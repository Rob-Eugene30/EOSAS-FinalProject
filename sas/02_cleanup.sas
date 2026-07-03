options validvarname=any;

libname mylib "/home/u64510891/ISS173_FinalProject";

data mylib.telco_clean;

    set mylib.telco_raw;

    /* 1. Remove unnecessary spaces + standardize casing */

    'Customer ID'n = compress(strip('Customer ID'n), "-");

    Gender = propcase(strip(Gender));
    Country = propcase(strip(Country));
    State = propcase(strip(State));
    City = propcase(strip(City));

    Offer = propcase(strip(Offer));
    Contract = propcase(strip(Contract));

    'Payment Method'n = propcase(strip('Payment Method'n));

    'Customer Status'n = propcase(strip('Customer Status'n));

    'Churn Label'n = upcase(strip('Churn Label'n));
    'Churn Category'n = propcase(strip('Churn Category'n));
    'Churn Reason'n = propcase(strip('Churn Reason'n));

    /*====================================================
        2. Handle missing values
    ====================================================*/

    if missing(Offer) then Offer = "None";

    if missing('Churn Category'n) then
        'Churn Category'n = "Not Applicable";

    if missing('Churn Reason'n) then
        'Churn Reason'n = "Not Applicable";

    /* 3. Mask sensitive information (Customer ID) */

    length Masked_ID $20;

    Masked_ID =
        cats("XXXX",
             substr('Customer ID'n,
                    length('Customer ID'n)-3));

    /* 4. Remove unnecessary columns */

    drop Latitude Longitude Population;

run;

/* VERIFY OUTPUT */

title "Clean Dataset Structure";

proc contents data=mylib.telco_clean;
run;

title "Sample Clean Data";

proc print data=mylib.telco_clean(obs=10);
run;

title;