
options validvarname=any;
libname mylib "/home/u64501602/ISS173_FinalProject";


data mylib.telco_calculated;
    set mylib.telco_target;


    if 'Tenure in Months'n > 0 then
        Avg_Monthly_Revenue = round('Total Revenue'n / 'Tenure in Months'n, 0.01);
    else
        Avg_Monthly_Revenue = 'Monthly Charge'n;

    /* KPI: how much a customer pays per GB of data used */
    if 'Avg Monthly GB Download'n > 0 then
        Revenue_Per_GB = round('Monthly Charge'n / 'Avg Monthly GB Download'n, 0.01);
    else
        Revenue_Per_GB = .;

    /* Percentage KPI: refunds as a share of total charges */
    if 'Total Charges'n > 0 then
        Refund_Rate_Pct = round(('Total Refunds'n / 'Total Charges'n) * 100, 0.01);
    else
        Refund_Rate_Pct = 0;

    /* KPI: risk-adjusted lifetime value, discounted by churn probability */
    Risk_Adjusted_CLTV = round(CLTV * (1 - ('Churn Score'n / 100)), 1);

    /*------------------------------------------------------------
      4.2  Growth-rate / multi-period projection using a DO loop
           and an ARRAY: 12-month forward revenue simulation per
           customer, compounding monthly growth and discounting
           for churn risk each period.
    ------------------------------------------------------------*/
    array Proj_M{12} Proj_M1-Proj_M12;

    Monthly_Growth_Rate = 0.02;                  /* assumed 2% monthly upsell growth  */
    Monthly_Churn_Decay = 'Churn Score'n / 1000;  /* higher churn score = faster decay */

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

    Cumulative_Projected_Revenue + Projected_12Month_Revenue; /* sum statement, works with RETAIN */
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


