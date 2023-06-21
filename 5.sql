Prompt
Prompt > try to delete comparison &&v_c_name
Prompt > In case it hangs too long, see if it does delete from SYS.COMPARISON_ROW_DIF$
Prompt > And, if so: cancel script execution, check size of SYS.COMPARISON_ROW_DIF$ and truncate it if it big enough (say >64Mb)
Prompt > Then run this script again, on order to delete comparison and aux-table

declare
    v_comparison_name      varchar2(30) := '&&v_c_name';
begin
   DBMS_COMPARISON.DROP_COMPARISON( comparison_name=>v_comparison_name);
end;
/

Prompt
Prompt > Comparison information:
select t.owner, t.comparison_name, t.schema_name||'.'||t.object_name as rep_name, t.remote_schema_name||'.'||t.remote_object_name as sc_name
       ,t.dblink_name
from sys.DBA_COMPARISON t
WHERE 1=1
  AND t.owner=upper('&&v_c_owner') AND t.comparison_name=upper('&&v_c_name')
;

declare
    v_lc_owner   varchar2(30) := upper('&&V_C_OWNER');
    v_lc_name    varchar2(128) := upper('&&LOCAL_TEMP_COPY');
    n            number;
begin
        dbms_output.put_line('Check if table '||v_lc_owner||'.'||v_lc_name||'  exists');
        select count(*)
        into n
        from sys.dba_tables
        where owner=v_lc_owner and table_name=v_lc_name
        ;
        if n = 1 then
            dbms_output.put_line('Table '||v_lc_owner||'.'||v_lc_name||'  exists. Try to drop it');
            execute immediate 'drop table '||v_lc_owner||'.'||v_lc_name||' purge';
            dbms_output.put_line('Table '||v_lc_owner||'.'||v_lc_name||' dropped');
        else
            dbms_output.put_line('Table '||v_lc_owner||'.'||v_lc_name||' does not exist.');
        end if;
end;
/

