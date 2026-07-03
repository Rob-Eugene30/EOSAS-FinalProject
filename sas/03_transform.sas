

options validvarname=any;
libname mylib "/home/u64501602/ISS173_FinalProject";



data customer_profile;
    set mylib.telco_clean;
    keep Masked_ID Gender Age 'Under 30'n 'Senior Citizen'n Married Dependents
         'Number of Dependents'n Country State City 'Zip Code'n Quarter
         'Referred a Friend'n 'Number of Referrals'n 'Tenure in Months'n
         Contract 'Payment Method'n 'Paperless Billing'n;
run;

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

/*----------------------------------------------------------------

       Only customers present in BOTH tables are kept.
----------------------------------------------------------------*/
data mylib.telco_merged;
    merge customer_profile (in=inProfile)
          customer_billing (in=inBilling);
    by Masked_ID;

    /* IN= tracking variables used to control the join type */
    if inProfile and inBilling then Match_Status = "Matched";
    else if inProfile then Match_Status = "Profile Only";
    else Match_Status = "Billing Only";

    if inProfile and inBilling;   /* inner join condition */
run;

/* Integrity check: confirm the join produced a clean 1:1 match */
title "Stage 3 Check: Join Integrity";
proc freq data=mylib.telco_merged;
    tables Match_Status;
run;
title;


data mylib.telco_target;
    set mylib.telco_merged;
    where 'Total Revenue'n > 0 and Contract = "Month-To-Month";

    /* Additional row-level filter using IF: drop zero-tenure signups */
    if 'Tenure in Months'n = 0 then delete;

    drop Match_Status;
run;

title "Stage 3 Output: Filtered Row Count";
proc sql;
    select count(*) as Month_to_Month_Customers
    from mylib.telco_target;
quit;
title;


