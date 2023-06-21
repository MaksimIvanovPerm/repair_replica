set arraysize 5000
undefine v_accept
accept v_answer char prompt '> next step is performing actual comparison; Press [yY] to proceed, or any others to skip: '
Prompt
Prompt see sql-session with module='DBMS_COMPARISON' and action='doing &&v_c_name'
 

DECLARE
  v_answer               varchar2(30) := upper('&&v_answer');
  v_comparison_name      varchar2(128) := '&&v_c_name';
  consistent             BOOLEAN;
  scan_info              DBMS_COMPARISON.COMPARISON_TYPE;
BEGIN
  if v_answer = 'Y' then
     dbms_output.put_line('Ok, do comparison');
     dbms_application_info.set_module('DBMS_COMPARISON', 'doing &&v_c_name');
     consistent := DBMS_COMPARISON.COMPARE(
                                            comparison_name => v_comparison_name
                                           ,scan_info       => scan_info
                                           ,perform_row_dif => TRUE
                                          );
     DBMS_OUTPUT.PUT_LINE('Scan ID: '||scan_info.scan_id);
     IF consistent=TRUE THEN
        DBMS_OUTPUT.PUT_LINE('No differences were found.');
     ELSE
        DBMS_OUTPUT.PUT_LINE('Differences were found.');
     END IF;
  else
     dbms_output.put_line('You prefered to skip doing comparison');
  end if; 
END;
/


Prompt
Prompt Below is summary about differences in rows;
Prompt That is: how many rows you have to update/delete/insert in &&rp_owner..&&rp_name in order to sync it with &&sc_owner..&&sc_name@&&dblink_name
Prompt If there are too many rows to update/insert (say >1000): 
Prompt then consider to localize (next step, you will be asked) of &&sc_owner..&&sc_name@&&dblink_name
Prompt for saving time by avoiding network trips to remote-side through db-link;

SELECT  CASE 
            WHEN diff_code = 3 THEN 'Updates: '||amount
            WHEN diff_code = 2 THEN 'Deletes: '||amount
            WHEN diff_code = 1 THEN 'Inserts: '||amount
        END AS diff_info
FROM (
SELECT diff_code, Count(*) AS amount
FROM (
SELECT  local_row*2+remote_row AS diff_code
FROM (
SELECT  CASE WHEN t.local_rowid  IS NOT NULL THEN 1 ELSE 0 END AS local_row 
       ,CASE WHEN t.remote_rowid IS NOT NULL THEN 1 ELSE 0 END AS remote_row       
FROM sys.DBA_COMPARISON_ROW_DIF t
WHERE 1=1
  AND t.owner=Upper('&&v_c_owner')
  AND t.comparison_name=Upper('&&v_c_name')
  )
   )
   GROUP BY diff_code
    )
;


