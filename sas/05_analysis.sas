options validvarname=any;
libname mylib "/home/u64501602/ISS173_FinalProject";

/*------------------------------------------------------------------
  TECHNIQUE 1: PROC FORMAT
  Custom category bins so raw numeric scores read as business labels
------------------------------------------------------------------*/
proc format;
    /* Bin churn risk score into tiers for reporting */
    value risktier
        0   - 39  = "Low Risk"
        40  - 69  = "Medium Risk"
        70  - 100 = "High Risk";

    /* Bin tenure into lifecycle stages */
    value tenuregrp
        0   - 6   = "New (0-6 mo)"
        7   - 24  = "Growing (7-24 mo)"
        25  - 48  = "Established (25-48 mo)"
        49  - high = "Loyal (49+ mo)";
run;

/*------------------------------------------------------------------
  TECHNIQUE 2: PROC FREQ
  Frequency tables & cross-tabulations, using the custom formats
  above to make the output business-readable
------------------------------------------------------------------*/
title "Stage 5: Churn Distribution by Risk Tier";
proc freq data=mylib.telco_final;
    format 'Churn Score'n risktier.;
    tables 'Churn Score'n * 'Churn Label'n / nocol norow nopercent;
run;
title;

title "Stage 5: Churn by Contract Type and Internet Type";
proc freq data=mylib.telco_final;
    tables Contract * 'Churn Label'n
           'Internet Type'n * 'Churn Label'n / nocol nopercent;
run;
title;

title "Stage 5: Top Churn Reasons Among Month-to-Month Customers";
proc freq data=mylib.telco_final order=freq;
    where 'Churn Label'n = "YES";
    tables 'Churn Category'n / nocum;
run;
title;

/*------------------------------------------------------------------
  TECHNIQUE 3: PROC MEANS
  Group aggregation of the KPIs built in Stage 4, split by segment
------------------------------------------------------------------*/
title "Stage 5: KPI Summary by Risk Tier";
proc means data=mylib.telco_final n mean min max maxdec=2;
    class 'Churn Score'n;
    format 'Churn Score'n risktier.;
    var Avg_Monthly_Revenue Risk_Adjusted_CLTV Projected_12Month_Revenue;
run;
title;

title "Stage 5: KPI Summary by Contract Type";
proc means data=mylib.telco_final n mean std maxdec=2;
    class Contract;
    var 'Monthly Charge'n Revenue_Per_GB Refund_Rate_Pct;
run;
title;

/*------------------------------------------------------------------
  TECHNIQUE 4: PROC SGPLOT
  Visual representation - bar chart and histogram
------------------------------------------------------------------*/
title "Stage 5: Churn Rate by Contract Type";
proc sgplot data=mylib.telco_final;
    vbar Contract / group='Churn Label'n groupdisplay=cluster
                    stat=percent;
    yaxis label="Percent of Customers";
    xaxis label="Contract Type";
run;
title;

title "Stage 5: Distribution of Risk-Adjusted CLTV";
proc sgplot data=mylib.telco_final;
    histogram Risk_Adjusted_CLTV / fillattrs=(color=steelblue) binwidth=250;
    density Risk_Adjusted_CLTV;
    xaxis label="Risk-Adjusted Customer Lifetime Value";
run;
title;

title "Stage 5: Monthly Charge vs Projected 12-Month Revenue";
proc sgplot data=mylib.telco_final;
    scatter x='Monthly Charge'n y=Projected_12Month_Revenue /
            group='Churn Label'n transparency=0.4;
    reg x='Monthly Charge'n y=Projected_12Month_Revenue / nomarkers lineattrs=(color=red);
    xaxis label="Current Monthly Charge";
    yaxis label="Projected 12-Month Revenue";
run;
title;

/*------------------------------------------------------------------
  TECHNIQUE 5 (bonus): PROC UNIVARIATE
  Detailed distribution analysis of the key revenue projection KPI
------------------------------------------------------------------*/
title "Stage 5: Distribution Analysis - Projected 12-Month Revenue";
proc univariate data=mylib.telco_final;
    var Projected_12Month_Revenue;
    histogram / normal;
    inset mean std skewness kurtosis / position=ne;
run;
title;