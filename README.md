# repair_replica
Scripts for repairing replica-table

It's a dbms_comparison-based workaround aimed at automation process of repairing of a replica-table;
Place this bunch of sql-scripts to db-side, where you want to sync your outdated replica;

Of course you have to have db-link, from this db, to db where source-table lives;

Write necessary meta-data into define-statements in `1.sql`
And execute sql-scripts, in order, which is implied by their names;
That is: `1.sql`, then `2.sql`, and so on;

Execution of `1a.sql` is optional; The script is intended for localizing source-table before any other activities;
It utilizes CTAS command to localize source-table thoght db-link with help of flashback-query;
If the script is executed and it localizes source-table successfully then `3a.sql` shouldn't and wouldn't be executed;
Pay attention to substitution variable `compress_mode` it might be used in CTAS if it setted intentionally to one of proper values;

Execution of script `3a.sql` is optional, and if you want to execute this one - it is supposed to be done after `3.sql`;
`3a.sql` makes local copy of source-table, that is - it localizes data of source-table near, in the same db, where replicat lives;
It might be very profitable in terms of saving time cost which is made by executions of dml-statement of repair script - they can work with localy placed data, not with remoute db, through db-link;

A bit of information related to `dbms_comparison` mechanic;
It saves and stores metadata about source and replica tables row-divergences in table `SYS.COMPARISON_ROW_DIF$`, in `SYSAUX` tablespace;
So according to aims of use of `SYS.COMPARISON_ROW_DIF$` - this table tend to be fragmented and tend to grow quite rapidly;

Dropping and/or purging data of used and non-actual comparisons tend to work very slowly, when this table is big enough and fragmented;MOS note `2089484.1` says that you're able to just truncate this tablem with drop-storage option, in order to defragment it;
