undefine v_answer

  Prompt >Replica-side key info
  column ctype heading "ctype" format A1
  column cname heading "cnamr" format A30
  column col_name heading "col_name" format A30
  column col_position heading "col_pos" format  99
  
  SELECT  c.constraint_type as ctype
         ,c.constraint_name as cname
         ,cc.column_name as col_name
         ,cc.position as col_position
  FROM sys.dba_constraints c, sys.dba_cons_columns cc
  WHERE 1=1
    AND c.owner=Upper('&&rp_owner')
    AND c.constraint_type IN ('P', 'U')
    AND c.table_name=Upper('&&rp_name')
    AND c.owner=cc.owner AND c.constraint_name=cc.constraint_name AND c.table_name=cc.table_name
  ORDER BY c.constraint_name, cc.position asc
  ;

  Prompt >Source-side key info:
  SELECT  c.constraint_type as ctype
         ,c.constraint_name as cname
         ,cc.column_name as col_name
         ,cc.position as col_position
  FROM sys.dba_constraints@&&DBLINK_NAME c, sys.dba_cons_columns@&&DBLINK_NAME cc
  WHERE 1=1
    AND c.owner=Upper('&&SC_OWNER')
    AND c.constraint_type IN ('P', 'U')
    AND c.table_name=Upper('&&SC_NAME')
    AND c.owner=cc.owner AND c.constraint_name=cc.constraint_name AND c.table_name=cc.table_name
  ORDER BY c.constraint_name, cc.position asc
  ;

Prompt > See information above carefully;
Prompt > If both sides of replicated pair have PK, with the same amount and order of columns in it: just continue to the following step
Prompt > Otherwise you have to choose and set here name of unique-index which is used by gg-replicat as actual key
Prompt > If necessery: type the name of that unique-index or just press enter to skip and continue
accept v_answer char prompt '>Please type name of key, which is used by this replication pair: '

Prompt
Prompt see sql-session with module='DBMS_COMPARISON' and action='creating comparison'
declare
 v_comparison_name      varchar2(128) := '&&v_c_name';
 v_rep_owner            varchar2(30) := upper('&&rp_owner');
 v_rep_table            varchar2(30) := upper('&&rp_name');
 v_dblink               varchar2(30) := '&&dblink_name';
 v_srs_owner            varchar2(30) := upper('&&sc_owner');
 v_srs_table            varchar2(30) := upper('&&sc_name');
 v_indexname            varchar2(30) := '&&v_answer';
 v_column_list          varchar2(4000) := '';
 v1                     number;

 cursor c1(p_towner in varchar2, p_tname in varchar2) is
 SELECT t.*
 FROM sys.dba_tab_cols t
 WHERE t.owner=upper(p_towner) AND t.table_name=upper(p_tname)  
ORDER BY t.column_name
;

BEGIN
  
  v1 := 1;
  for i in c1(v_rep_owner, v_rep_table)
  loop
      if     i.column_name NOT IN ('ROW_SCN')
         and i.data_type in ( 'VARCHAR2','NVARCHAR2','NUMBER','FLOAT','DATE','BINARY_FLOAT','BINARY_DOUBLE','TIMESTAMP','TIMESTAMP WITH TIME ZONE','TIMESTAMP WITH LOCAL TIME ZONE','INTERVAL YEAR TO MONTH','INTERVAL DAY TO SECOND','RAW','CHAR','NCHAR' )
         and i.hidden_column != 'YES' 
         and i.virtual_column != 'YES'
      then
          if v1 = 1 then v_column_list := i.column_name; else v_column_list := v_column_list||', '||i.column_name; end if;
          v1 := v1 + 1;
      else
          dbms_output.put_line('skip column: '||i.column_name);
      end if;
  end loop;
  dbms_output.put_line(v_column_list);

  dbms_application_info.set_module('DBMS_COMPARISON', 'creating comparison'); 
  if v_indexname is not null then
     dbms_output.put_line('v_indexname: '||v_indexname);
     DBMS_COMPARISON.CREATE_COMPARISON(
    comparison_name => v_comparison_name
   ,schema_name     => v_rep_owner
   ,object_name     => v_rep_table
   ,dblink_name     => v_dblink
   ,index_name      => v_indexname
   ,remote_schema_name=>v_srs_owner
   ,remote_object_name=>v_srs_table
   ,scan_mode=>DBMS_COMPARISON.CMP_SCAN_MODE_FULL
   ,column_list=>v_column_list);
  else
     dbms_output.put_line('Without explicitly setted key-index name');
     DBMS_COMPARISON.CREATE_COMPARISON(
    comparison_name => v_comparison_name
   ,schema_name     => v_rep_owner
   ,object_name     => v_rep_table
   ,dblink_name     => v_dblink
   ,remote_schema_name=>v_srs_owner
   ,remote_object_name=>v_srs_table
   ,scan_mode=>DBMS_COMPARISON.CMP_SCAN_MODE_FULL
   ,column_list=>v_column_list);
  end if;

END;
/

column owner format a10
column comparison_name format a30
column rep_name format a30
column sc_name format a30
column dblink_name format a30

Prompt
Prompt > Comparison information:
select t.owner, t.comparison_name, t.schema_name||'.'||t.object_name as rep_name, t.remote_schema_name||'.'||t.remote_object_name as sc_name
       ,t.dblink_name
from sys.DBA_COMPARISON t
WHERE 1=1
  AND t.owner=upper('&&v_c_owner') AND t.comparison_name=upper('&&v_c_name')
;

Prompt
Prompt > Columns which will be processed in the comparison:
select comparison_name||' '||column_name||' '||column_position||' '||index_column as col1
from sys.DBA_COMPARISON_COLUMNS t
WHERE 1=1
  AND t.owner=upper('&&v_c_owner') AND t.comparison_name=upper('&&v_c_name')
ORDER BY t.column_position asc
;
