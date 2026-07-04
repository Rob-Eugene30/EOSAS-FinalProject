/*==========================================================
  CS401 / ISS173 FINAL PROJECT - TELCO CUSTOMER PIPELINE
==========================================================*/

options validvarname=any;
libname mylib "/home/u64501631/ISS173-CM15_Activities_Dequiñon";

/*==========================================================
  STAGE 01 - DATA INGESTION
==========================================================*/

/* Import raw customer data from CSV source */
proc import
    datafile="/home/u64501631/ISS173-CM15_Activities_Dequiñon/telco.csv"
    out=mylib.telco_raw
    dbms=csv
    replace;
    guessingrows=max;
    getnames=yes;
run;

/*==========================================================
  STAGE 02 - DATA CLEANUP
==========================================================*/

data mylib.telco_clean;
    set mylib.telco_raw;

    /* 1. Remove unnecessary spaces and standardize casing */
    'Customer ID'n = compress(strip('Customer ID'n), "-");

    Gender  = propcase(strip(Gender));
    Country = propcase(strip(Country));
    State   = propcase(strip(State));
    City    = propcase(strip(City));

    Offer    = propcase(strip(Offer));
    Contract = propcase(strip(Contract));

    'Payment Method'n = propcase(strip('Payment Method'n));
    'Customer Status'n = propcase(strip('Customer Status'n));

    'Churn Label'n    = upcase(strip('Churn Label'n));
    'Churn Category'n = propcase(strip('Churn Category'n));
    'Churn Reason'n   = propcase(strip('Churn Reason'n));

    /* 2. Handle missing values */
    if missing(Offer) then Offer = "None";
    if missing('Churn Category'n) then 'Churn Category'n = "Not Applicable";
    if missing('Churn Reason'n) then 'Churn Reason'n = "Not Applicable";

    /* 3. Mask sensitive information (Customer ID) */
    length Masked_ID $20;
    Masked_ID = cats("XXXX", substr('Customer ID'n, length('Customer ID'n) - 3));

    /* 4. Remove unnecessary columns */
    drop Latitude Longitude Population;

run;

/*==========================================================
  STAGE 03 - DATA TRANSFORMATION
==========================================================*/

/* Split cleaned data into profile and billing subsets */
data customer_profile;
    set mylib.telco_clean;
    keep Masked_ID Gender Age 'Under 30'n 'Senior Citizen'n Married Dependents
         'Number of Dependents'n Country State City 'Zip Code'n Quarter
         'Referred a Friend'n 'Number of Referrals'n 'Tenure in Months'n
         Contract 'Payment Method'n 'Paperless Billing'n;
run;

data customer_billing;
    set mylib.telco_clean;
    keep Masked_ID Offer 'Phone Service'n 'Avg Monthly Long Distance Charges'n
         'Multiple Lines'n 'Internet Service'n 'Internet Type'n
         'Avg Monthly GB Download'n 'Online Security'n 'Online Backup'n
         'Device Protection Plan'n 'Premium Tech Support'n 'Streaming TV'n
         'Streaming Movies'n 'Streaming Music'n 'Unlimited Data'n
         'Monthly Charge'n 'Total Charges'n 'Total Refunds'n
         'Total Extra Data Charges'n 'Total Long Distance Charges'n
         'Total Revenue'n 'Satisfaction Score'n 'Customer Status'n
         'Churn Label'n 'Churn Score'n CLTV 'Churn Category'n 'Churn Reason'n;
run;

/* Sort both subsets prior to merge */
proc sort data=customer_profile;
    by Masked_ID;
run;

proc sort data=customer_billing;
    by Masked_ID;
run;

/* Merge profile and billing data - IN= tracks join coverage */
data mylib.telco_merged;
    merge customer_profile (in=inProfile)
          customer_billing (in=inBilling);
    by Masked_ID;

    if inProfile and inBilling then Match_Status = "Matched";
    else if inProfile then Match_Status = "Profile Only";
    else Match_Status = "Billing Only";

    if inProfile and inBilling;   /* inner join: keep matched records only */
run;

/* Validation: confirm the join produced a clean 1:1 match */
title "Stage 3 Check: Join Integrity";
proc freq data=mylib.telco_merged;
    tables Match_Status;
run;
title;

/* Filter to target population: active month-to-month customers with revenue */
data mylib.telco_target;
    set mylib.telco_merged;
    where 'Total Revenue'n > 0 and Contract = "Month-To-Month";

    /* Row-level filter using IF: drop zero-tenure signups */
    if 'Tenure in Months'n = 0 then delete;

    drop Match_Status;
run;

title "Stage 3 Output: Filtered Row Count";
proc sql;
    select count(*) as Month_to_Month_Customers
    from mylib.telco_target;
quit;
title;

/*==========================================================
  STAGE 04 - CALCULATIONS
==========================================================*/

/* Derive KPIs and run a 12-month forward revenue projection */
data mylib.telco_calculated;
    set mylib.telco_target;

    /* KPI: average revenue earned per month of tenure */
    if 'Tenure in Months'n > 0 then
        Avg_Monthly_Revenue = round('Total Revenue'n / 'Tenure in Months'n, 0.01);
    else
        Avg_Monthly_Revenue = 'Monthly Charge'n;

    /* KPI: revenue earned per GB of data used */
    if 'Avg Monthly GB Download'n > 0 then
        Revenue_Per_GB = round('Monthly Charge'n / 'Avg Monthly GB Download'n, 0.01);
    else
        Revenue_Per_GB = .;

    /* KPI: refunds as a percentage of total charges */
    if 'Total Charges'n > 0 then
        Refund_Rate_Pct = round(('Total Refunds'n / 'Total Charges'n) * 100, 0.01);
    else
        Refund_Rate_Pct = 0;

    /* KPI: risk-adjusted lifetime value, discounted by churn probability */
    Risk_Adjusted_CLTV = round(CLTV * (1 - ('Churn Score'n / 100)), 1);

    /* 12-month forward revenue projection using ARRAY and DO loop.
       Compounds monthly growth and discounts for churn risk each period. */
    array Proj_M{12} Proj_M1-Proj_M12;

    Monthly_Growth_Rate = 0.02;                   /* assumed 2% monthly upsell growth  */
    Monthly_Churn_Decay = 'Churn Score'n / 1000;   /* higher churn score = faster decay */

    Proj_M{1} = 'Monthly Charge'n;
    do i = 2 to 12;
        Proj_M{i} = Proj_M{i-1} * (1 + Monthly_Growth_Rate) * (1 - Monthly_Churn_Decay);
    end;

    Projected_12Month_Revenue = round(sum(of Proj_M1-Proj_M12), 0.01);

    drop i;
run;

/* Running totals across customers using RETAIN */
data mylib.telco_final;
    set mylib.telco_calculated;
    by Masked_ID;

    retain Cumulative_Projected_Revenue 0;
    retain Customer_Sequence_No 0;

    Cumulative_Projected_Revenue + Projected_12Month_Revenue;  /* sum statement, works with RETAIN */
    Customer_Sequence_No + 1;
run;

/* Validation: preview calculated fields */
title "Stage 4 Check: Calculated Fields Preview";
proc print data=mylib.telco_final(obs=10);
    var Masked_ID 'Monthly Charge'n Avg_Monthly_Revenue Revenue_Per_GB
        Refund_Rate_Pct Risk_Adjusted_CLTV Projected_12Month_Revenue
        Cumulative_Projected_Revenue Customer_Sequence_No;
run;
title;

/* Validation: summary statistics of new KPIs */
title "Stage 4 Check: Summary Statistics of New KPIs";
proc means data=mylib.telco_final n mean min max maxdec=2;
    var Avg_Monthly_Revenue Revenue_Per_GB Refund_Rate_Pct
        Risk_Adjusted_CLTV Projected_12Month_Revenue;
run;
title;

/*==========================================================
  STAGE 05 - SAS TECHNIQUES
==========================================================*/

/* TECHNIQUE 1: PROC FORMAT - custom category bins for reporting */
proc format;
    /* Bin churn risk score into tiers */
    value risktier
        0   - 39  = "Low Risk"
        40  - 69  = "Medium Risk"
        70  - 100 = "High Risk";

    /* Bin tenure into lifecycle stages */
    value tenuregrp
        0   - 6    = "New (0-6 mo)"
        7   - 24   = "Growing (7-24 mo)"
        25  - 48   = "Established (25-48 mo)"
        49  - high = "Loyal (49+ mo)";
run;

/* TECHNIQUE 2: PROC FREQ - frequency tables using custom formats */
title "Churn Distribution by Risk Tier";
proc freq data=mylib.telco_final;
    format 'Churn Score'n risktier.;
    tables 'Churn Score'n * 'Churn Label'n / nocol norow nopercent;
run;
title;

title "Churn by Contract Type and Internet Type";
proc freq data=mylib.telco_final;
    tables Contract * 'Churn Label'n
           'Internet Type'n * 'Churn Label'n / nocol nopercent;
run;
title;

title "Top Churn Reasons Among Month-to-Month Customers";
proc freq data=mylib.telco_final order=freq;
    where 'Churn Label'n = "YES";
    tables 'Churn Category'n / nocum;
run;
title;

/* TECHNIQUE 3: PROC MEANS - KPI aggregation by segment */
title "KPI Summary by Risk Tier";
proc means data=mylib.telco_final n mean min max maxdec=2;
    class 'Churn Score'n;
    format 'Churn Score'n risktier.;
    var Avg_Monthly_Revenue Risk_Adjusted_CLTV Projected_12Month_Revenue;
run;
title;

title "KPI Summary by Contract Type";
proc means data=mylib.telco_final n mean std maxdec=2;
    class Contract;
    var 'Monthly Charge'n Revenue_Per_GB Refund_Rate_Pct;
run;
title;

/* TECHNIQUE 4: PROC SGPLOT - visual analysis */
title "Churn Rate by Contract Type";
proc sgplot data=mylib.telco_final;
    vbar Contract / group='Churn Label'n groupdisplay=cluster
                    stat=percent;
    yaxis label="Percent of Customers";
    xaxis label="Contract Type";
run;
title;

title "Distribution of Risk-Adjusted CLTV";
proc sgplot data=mylib.telco_final;
    histogram Risk_Adjusted_CLTV / fillattrs=(color=steelblue) binwidth=250;
    density Risk_Adjusted_CLTV;
    xaxis label="Risk-Adjusted Customer Lifetime Value";
run;
title;

title "Monthly Charge vs Projected 12-Month Revenue";
proc sgplot data=mylib.telco_final;
    scatter x='Monthly Charge'n y=Projected_12Month_Revenue /
            group='Churn Label'n transparency=0.4;
    reg x='Monthly Charge'n y=Projected_12Month_Revenue / nomarkers lineattrs=(color=red);
    xaxis label="Current Monthly Charge";
    yaxis label="Projected 12-Month Revenue";
run;
title;

/* TECHNIQUE 5 (bonus): PROC UNIVARIATE - detailed distribution analysis */
title "Distribution Analysis - Projected 12-Month Revenue";
proc univariate data=mylib.telco_final;
    var Projected_12Month_Revenue;
    histogram / normal;
    inset mean std skewness kurtosis / position=ne;
run;
title;

/*==========================================================
  PARAMETERIZED PIPELINE MACRO
  Wraps Stages 01-05. Stage 06 to be added once specified.
==========================================================*/

%macro RunPipeline(
    libpath=,           /* folder containing telco.csv and used as the SAS library */
    csvfile=,           /* full path to the source CSV file */
    contract=,          /* contract type to filter on in Stage 03, e.g. Month-To-Month */
    minimum_revenue=,   /* minimum Total Revenue threshold in Stage 03 */
    growth_rate=,        /* monthly upsell growth rate used in Stage 04 projection */
    risk_threshold=      /* churn score cutoff (0-100) marking the start of High Risk in Stage 05 */
);

options validvarname=any;
libname mylib "&libpath.";

/*==========================================================
  STAGE 01 - DATA INGESTION
==========================================================*/
proc import
    datafile="&csvfile."
    out=mylib.telco_raw
    dbms=csv
    replace;
    guessingrows=max;
    getnames=yes;
run;

/*==========================================================
  STAGE 02 - DATA CLEANUP
==========================================================*/
data mylib.telco_clean;
    set mylib.telco_raw;

    'Customer ID'n = compress(strip('Customer ID'n), "-");

    Gender  = propcase(strip(Gender));
    Country = propcase(strip(Country));
    State   = propcase(strip(State));
    City    = propcase(strip(City));

    Offer    = propcase(strip(Offer));
    Contract = propcase(strip(Contract));

    'Payment Method'n = propcase(strip('Payment Method'n));
    'Customer Status'n = propcase(strip('Customer Status'n));

    'Churn Label'n    = upcase(strip('Churn Label'n));
    'Churn Category'n = propcase(strip('Churn Category'n));
    'Churn Reason'n   = propcase(strip('Churn Reason'n));

    if missing(Offer) then Offer = "None";
    if missing('Churn Category'n) then 'Churn Category'n = "Not Applicable";
    if missing('Churn Reason'n) then 'Churn Reason'n = "Not Applicable";

    length Masked_ID $20;
    Masked_ID = cats("XXXX", substr('Customer ID'n, length('Customer ID'n) - 3));

    drop Latitude Longitude Population;

run;

/*==========================================================
  STAGE 03 - DATA TRANSFORMATION
==========================================================*/
data customer_profile;
    set mylib.telco_clean;
    keep Masked_ID Gender Age 'Under 30'n 'Senior Citizen'n Married Dependents
         'Number of Dependents'n Country State City 'Zip Code'n Quarter
         'Referred a Friend'n 'Number of Referrals'n 'Tenure in Months'n
         Contract 'Payment Method'n 'Paperless Billing'n;
run;

data customer_billing;
    set mylib.telco_clean;
    keep Masked_ID Offer 'Phone Service'n 'Avg Monthly Long Distance Charges'n
         'Multiple Lines'n 'Internet Service'n 'Internet Type'n
         'Avg Monthly GB Download'n 'Online Security'n 'Online Backup'n
         'Device Protection Plan'n 'Premium Tech Support'n 'Streaming TV'n
         'Streaming Movies'n 'Streaming Music'n 'Unlimited Data'n
         'Monthly Charge'n 'Total Charges'n 'Total Refunds'n
         'Total Extra Data Charges'n 'Total Long Distance Charges'n
         'Total Revenue'n 'Satisfaction Score'n 'Customer Status'n
         'Churn Label'n 'Churn Score'n CLTV 'Churn Category'n 'Churn Reason'n;
run;

proc sort data=customer_profile;
    by Masked_ID;
run;

proc sort data=customer_billing;
    by Masked_ID;
run;

data mylib.telco_merged;
    merge customer_profile (in=inProfile)
          customer_billing (in=inBilling);
    by Masked_ID;

    if inProfile and inBilling then Match_Status = "Matched";
    else if inProfile then Match_Status = "Profile Only";
    else Match_Status = "Billing Only";

    if inProfile and inBilling;
run;

title "Stage 3 Check: Join Integrity";
proc freq data=mylib.telco_merged;
    tables Match_Status;
run;
title;

data mylib.telco_target;
    set mylib.telco_merged;
    where 'Total Revenue'n > &minimum_revenue. and Contract = "&contract.";

    if 'Tenure in Months'n = 0 then delete;

    drop Match_Status;
run;

title "Stage 3 Output: Filtered Row Count";
proc sql;
    select count(*) as Filtered_Customers
    from mylib.telco_target;
quit;
title;

/*==========================================================
  STAGE 04 - CALCULATIONS
==========================================================*/
data mylib.telco_calculated;
    set mylib.telco_target;

    if 'Tenure in Months'n > 0 then
        Avg_Monthly_Revenue = round('Total Revenue'n / 'Tenure in Months'n, 0.01);
    else
        Avg_Monthly_Revenue = 'Monthly Charge'n;

    if 'Avg Monthly GB Download'n > 0 then
        Revenue_Per_GB = round('Monthly Charge'n / 'Avg Monthly GB Download'n, 0.01);
    else
        Revenue_Per_GB = .;

    if 'Total Charges'n > 0 then
        Refund_Rate_Pct = round(('Total Refunds'n / 'Total Charges'n) * 100, 0.01);
    else
        Refund_Rate_Pct = 0;

    Risk_Adjusted_CLTV = round(CLTV * (1 - ('Churn Score'n / 100)), 1);

    array Proj_M{12} Proj_M1-Proj_M12;

    Monthly_Growth_Rate = &growth_rate.;
    Monthly_Churn_Decay = 'Churn Score'n / 1000;

    Proj_M{1} = 'Monthly Charge'n;
    do i = 2 to 12;
        Proj_M{i} = Proj_M{i-1} * (1 + Monthly_Growth_Rate) * (1 - Monthly_Churn_Decay);
    end;

    Projected_12Month_Revenue = round(sum(of Proj_M1-Proj_M12), 0.01);

    drop i;
run;

data mylib.telco_final;
    set mylib.telco_calculated;
    by Masked_ID;

    retain Cumulative_Projected_Revenue 0;
    retain Customer_Sequence_No 0;

    Cumulative_Projected_Revenue + Projected_12Month_Revenue;
    Customer_Sequence_No + 1;
run;

title "Stage 4 Check: Calculated Fields Preview";
proc print data=mylib.telco_final(obs=10);
    var Masked_ID 'Monthly Charge'n Avg_Monthly_Revenue Revenue_Per_GB
        Refund_Rate_Pct Risk_Adjusted_CLTV Projected_12Month_Revenue
        Cumulative_Projected_Revenue Customer_Sequence_No;
run;
title;

title "Stage 4 Check: Summary Statistics of New KPIs";
proc means data=mylib.telco_final n mean min max maxdec=2;
    var Avg_Monthly_Revenue Revenue_Per_GB Refund_Rate_Pct
        Risk_Adjusted_CLTV Projected_12Month_Revenue;
run;
title;

/*==========================================================
  STAGE 05 - SAS TECHNIQUES
==========================================================*/
proc format;
    value risktier
        0 - <&risk_threshold.   = "Low/Medium Risk"
        &risk_threshold. - 100  = "High Risk";

    value tenuregrp
        0   - 6    = "New (0-6 mo)"
        7   - 24   = "Growing (7-24 mo)"
        25  - 48   = "Established (25-48 mo)"
        49  - high = "Loyal (49+ mo)";
run;

title "Churn Distribution by Risk Tier";
proc freq data=mylib.telco_final;
    format 'Churn Score'n risktier.;
    tables 'Churn Score'n * 'Churn Label'n / nocol norow nopercent;
run;
title;

title "Churn by Contract Type and Internet Type";
proc freq data=mylib.telco_final;
    tables Contract * 'Churn Label'n
           'Internet Type'n * 'Churn Label'n / nocol nopercent;
run;
title;

title "Top Churn Reasons Among Filtered Customers";
proc freq data=mylib.telco_final order=freq;
    where 'Churn Label'n = "YES";
    tables 'Churn Category'n / nocum;
run;
title;

title "KPI Summary by Risk Tier";
proc means data=mylib.telco_final n mean min max maxdec=2;
    class 'Churn Score'n;
    format 'Churn Score'n risktier.;
    var Avg_Monthly_Revenue Risk_Adjusted_CLTV Projected_12Month_Revenue;
run;
title;

title "KPI Summary by Contract Type";
proc means data=mylib.telco_final n mean std maxdec=2;
    class Contract;
    var 'Monthly Charge'n Revenue_Per_GB Refund_Rate_Pct;
run;
title;

title "Churn Rate by Contract Type";
proc sgplot data=mylib.telco_final;
    vbar Contract / group='Churn Label'n groupdisplay=cluster
                    stat=percent;
    yaxis label="Percent of Customers";
    xaxis label="Contract Type";
run;
title;

title "Distribution of Risk-Adjusted CLTV";
proc sgplot data=mylib.telco_final;
    histogram Risk_Adjusted_CLTV / fillattrs=(color=steelblue) binwidth=250;
    density Risk_Adjusted_CLTV;
    xaxis label="Risk-Adjusted Customer Lifetime Value";
run;
title;

title "Monthly Charge vs Projected 12-Month Revenue";
proc sgplot data=mylib.telco_final;
    scatter x='Monthly Charge'n y=Projected_12Month_Revenue /
            group='Churn Label'n transparency=0.4;
    reg x='Monthly Charge'n y=Projected_12Month_Revenue / nomarkers lineattrs=(color=red);
    xaxis label="Current Monthly Charge";
    yaxis label="Projected 12-Month Revenue";
run;
title;

title "Distribution Analysis - Projected 12-Month Revenue";
proc univariate data=mylib.telco_final;
    var Projected_12Month_Revenue;
    histogram / normal;
    inset mean std skewness kurtosis / position=ne;
run;
title;

%mend RunPipeline;

/*==========================================================
  MACRO CALL
==========================================================*/
%RunPipeline(
    libpath=/home/YOUR_USERNAME/ISS173_FinalProject,
    csvfile=/home/YOUR_USERNAME/ISS173_FinalProject/telco.csv,
    contract=Month-To-Month,
    minimum_revenue=0,
    growth_rate=0.02,
    risk_threshold=70
);