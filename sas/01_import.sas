options validvarname=any;

/* Create Permanent Library */

libname mylib "/home/u64510891/ISS173_FinalProject";

/* Import Dataset */

proc import
    datafile="/home/u64510891/ISS173_FinalProject/telco.csv"
    out=mylib.telco_raw
    dbms=csv
    replace;
    guessingrows=max;
    getnames=yes;
run;

/* Verify Variable Names */

title "Dataset Structure";

proc contents data=mylib.telco_raw;
run;

/* Preview Dataset */

title "First 10 Records";

proc print data=mylib.telco_raw(obs=10);
run;

title;