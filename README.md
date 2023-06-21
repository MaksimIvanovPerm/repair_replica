# repair_replica
Scripts for repairing replica-table

It's a dbms_comparison-based workaround aimed at automation process of repairing of a replica-table;
Place this bunch of sql-scripts to db-side, where you want to sync your outdated replica;

Of course you have to have db-link, from this db, to db where source-table lives;

Write necessary meta-data into define-statements in `1.sql`
And execute sql-scripts, in order, which is implied by their names;
That is: `1.sql`, then `2.sql`, and so on;

Execution of script `3a.sql` is optional, and if you want to execute it is supposed to be done after `3.sql`
`3a.sql` makes local copy of source-table, tha is - it localizes data of source-table near, in the same db, where replicat lives;
It might be very profitable in terms of saving time cost which make by executions of dml-statement of repair script - they can work with localy placed data, not with remoute db, through db-link;



