/*==========================================================
  CS401 / ISS173 FINAL PROJECT - TELCO CUSTOMER PIPELINE
  Team: Erin, William, Wax, Rob
==========================================================*/

options validvarname=any;

/*==========================================================
  PARAMETERIZED PIPELINE MACRO
==========================================================*/

%macro RunPipeline(
    libpath=,           /* folder containing telco.csv and used as the SAS library */
    csvfile=,           /* full path to the source CSV file */
    contract=,          /* contract type to filter on in Stage 03, e.g. Month-To-Month */
    minimum_revenue=,   /* minimum Total Revenue threshold in Stage 03 */
    growth_rate=,        /* monthly upsell growth rate used in Stage 04 projection */
    risk_threshold=      /* churn score cutoff (0-100) marking the start of High Risk in Stage 05 */
);

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

/* NOTE: source column "Avg Monthly Long Distance Charges" is 33 characters,
   exceeding SAS's 32-character variable name limit. PROC IMPORT auto-truncates
   it to "Avg Monthly Long Distance Charge" (32 chars, no trailing "s") - that
   truncated name is what actually exists in telco_clean and must be used here. */
data customer_billing;
    set mylib.telco_clean;
    keep Masked_ID Offer 'Phone Service'n 'Avg Monthly Long Distance Charge'n
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
    libpath=/home/u64501631/ISS173-CM15_Activities_Dequiñon,
    csvfile=/home/u64501631/ISS173-CM15_Activities_Dequiñon/telco.csv,
    contract=Month-To-Month,
    minimum_revenue=0,
    growth_rate=0.02,
    risk_threshold=70
);