set newp none pagesize 0 linesize 1024 appinfo DBMS_COMPARISON verify off linesize 1024 serveroutput on echo off feedback off
set history on
DEFINE _EDITOR = vi
whenever sqlerror exit failure

column v_c_owner new_value v_c_owner noprint;
select SYS_CONTEXT ('USERENV', 'SESSION_USER') as v_c_owner from dual;

undefine sc_owner
undefine sc_name
undefine rp_owner
undefine rp_name
undefine dblink_name
undefine v_c_name
undefine v_dirname
undefine v_dirpath
undefine v_dop
undefine local_temp_copy
undefine local_temp_copy_pk_name
undefine local_temp_copy_pk_idx_name
undefine localdblink
undefine compress_mode
undefine session_module
var v_flag char(1)

define sc_owner="SM"
define sc_name="SUPPORT_EXPEDITION"
define rp_owner="R_LM_157"
define rp_name="SUPPORT_EXPEDITION"
define dblink_name="LMPROD.WORLD"
define v_c_name="&&rp_owner._&&rp_name"
define v_dirname="GGATEEXP"
define v_dop=1
define compress_mode="none"
define localdblink="LOCALDB.WORLD"
define LOCAL_TEMP_COPY="COMPARISON_COPY_OF_SOURCE_TABLE"
define LOCAL_TEMP_COPY_PK_NAME="&&LOCAL_TEMP_COPY._PK"
define LOCAL_TEMP_COPY_PK_IDX_NAME="&&LOCAL_TEMP_COPY._PK"
define session_module="DBMS_COMPARISON"
column v_dirpath new_value v_dirpath noprint
select directory_path as v_dirpath from sys.dba_directories where directory_name=upper('&&v_dirname');

declare
    v    number;
begin
    execute immediate 'select count(*) from dual@&&dblink_name' into v;
    dbms_output.put_line('Ok: db-link &&dblink_name works');
exception
 when others then raise_application_error(-20001, 'Error: can not work through db-link &&dblink_name');
end;
/

set termout off
select 1 as col1 from &&sc_owner..&&sc_name@&&dblink_name fetch first 1 rows only;
set termout on
Prompt Ok &&sc_owner..&&sc_name@&&dblink_name exists

undefine v_src_object_size
set termout off
column v_src_object_size new_value v_src_object_size noprint
select round( sum(bytes)/1024/1024, 2) as v_src_object_size
from sys.dba_segments@&&dblink_name
where 1=1
  and segment_type='TABLE'
  and owner=upper('&&sc_owner') and segment_name=upper('&&sc_name')
;
set termout on

set termout off
select 1 as col1 from &&rp_owner..&&rp_name fetch first 1 rows only;
set termout on
Prompt Ok &&rp_owner..&&rp_name exists

undefine v_target_obj_ts
set termout off
column v_target_obj_ts new_value v_target_obj_ts noprint
select listagg(tablespace_name, ',') as v_target_obj_ts
from sys.dba_segments
where 1=1
  and segment_type='TABLE'
  and owner=upper('&&RP_OWNER') and segment_name=upper('&&RP_NAME')
;
set termout on

declare
    f1 utl_file.file_type;
begin
     f1 := UTL_FILE.FOPEN('&&v_dirname','repair.sql','w'); 
     utl_file.fclose(f1);
     dbms_output.put_line('Ok, it looks like &&v_dirname (&&v_dirpath) is write-accessible for &&v_c_owner');
exception
 when others then dbms_output.put_line('Error: can not work with directory-object &&v_dirname ');
                  raise;
end;
/

declare
    v    number;
begin
    select count(*)
    into v
    from sys.DBA_COMPARISON t
    WHERE 1=1 
      AND t.owner=upper('&&v_c_owner') AND t.comparison_name=upper('&&v_c_name');

    if v>0 then
        raise_application_error(-20001, 'Error: comparison with name &&v_c_owner..&&v_c_name already exists; Delete it first;');
    else
        dbms_output.put_line('Ok: there is no comparison with name: &&v_c_owner..&&v_c_name');
    end if;
end;
/

declare
    v  number;
begin
    select count(*)
    into v
    from sys.dba_db_links t
    where t.owner=Upper('&&v_c_owner') and t.db_link=upper('&&localdblink');

    if v!=1 then
        raise_application_error(-20001, 'Error: db-link &&localdblink doesn''t exist; It''s supposed to be db-link which pointed to this schema in this db;');
    else
        dbms_output.put_line('Ok: there is db-link &&localdblink');
    end if;
end;
/

spool session.log replace
set appinfo &&session_module
Prompt summary:
Prompt source table:.......................&&sc_owner..&&sc_name@&&dblink_name
Prompt source table size, Mb:..............&&v_src_object_size
Prompt replica table:......................&&rp_owner..&&rp_name
Prompt replica ts(es) name(s):.............&&v_target_obj_ts
Prompt comparison name is supposed to be:..&&v_c_name
Prompt directory object name is:...........&&v_dirname
Prompt directory path is:..................&&v_dirpath
Prompt dop:................................&&v_dop
Prompt compress_mode:......................&&compress_mode
Prompt local db-link name:.................&&localdblink
accept v_answer char prompt '>Would you like to continue? '


