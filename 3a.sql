set arraysize 5000 serveroutput on
whenever sqlerror continue

undefine LOCAL_TEMP_COPY
define LOCAL_TEMP_COPY="COMPARISON_COPY_OF_SOURCE_TABLE"

undefine LOCAL_TEMP_COPY_PK_NAME
define   LOCAL_TEMP_COPY_PK_NAME="&&LOCAL_TEMP_COPY._PK"
undefine LOCAL_TEMP_COPY_PK_IDX_NAME
define LOCAL_TEMP_COPY_PK_IDX_NAME="&&LOCAL_TEMP_COPY._PK"


undefine key_cols_list
set termout off
column key_cols_list new_value key_cols_list noprint
select listagg(t.column_name, ',') as key_cols_list
from sys.DBA_COMPARISON_COLUMNS t
WHERE 1=1
  AND t.owner=Upper('&&v_c_owner') AND t.comparison_name=Upper('&&v_c_name')
  AND t.index_column = 'Y'
ORDER BY t.column_position asc
;
set termout on

Prompt
Prompt would you like to localize &&SC_OWNER..&&SC_NAME@&&DBLINK_NAME as &&V_C_OWNER..&&LOCAL_TEMP_COPY ?
Prompt It will try to create (if do not exists) it locally as &&LOCAL_TEMP_COPY in ts &&V_TARGET_OBJ_TS
Prompt The following pk will be created: &&LOCAL_TEMP_COPY_PK_NAME on &&key_cols_list 
undefine v_accept
accept v_answer char prompt '> next step is performing actual comparison; Press [yY] to proceed, or any others to skip: '

declare
    v_answer     varchar2(30) := nvl( upper('&&v_answer'), 'N');
    v_lc_owner   varchar2(30) := upper('&&V_C_OWNER');
    v_lc_name    varchar2(128) := upper('&&LOCAL_TEMP_COPY');
    n            number;
begin
    if v_answer != 'Y' then
        dbms_output.put_line('You prefered not to create local copy');
    else
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
    end if;
end;
/

undefine v_scn
set termout off
column v_scn new_value v_scn noprint
select current_scn||'' as v_scn from v$database@&&DBLINK_NAME;
set termout on

declare
   v_answer     varchar2(30) := nvl( upper('&&v_answer'), 'N');
begin
   if v_answer = 'Y' then
      dbms_output.put_line('Creating local table');  
   end if;
end;
/

declare
    v_answer     varchar2(30) := nvl( upper('&&v_answer'), 'N');
    v_lc_owner   varchar2(30) := upper('&&V_C_OWNER');
    v_lc_name    varchar2(128) := upper('&&LOCAL_TEMP_COPY');
    v_ts         varchar2(30) := upper('&&V_TARGET_OBJ_TS');
    v_sc_owner   varchar2(30) := upper('&&SC_OWNER');
    v_sc_name    varchar2(30) := upper('&&SC_NAME');
    v_db_link    varchar2(30) := '&&DBLINK_NAME';
    n            number;
    v_str        varchar2(4000) := '';
    v_scn        varchar2(30) := '&&v_scn';
    v_aux        varchar2(4000) := '';
    v_cols       varchar2(1024) := '';
    v_count      number;
    v_src_cols   varchar2(4000);

    cursor c1 is
    select *
    from sys.DBA_COMPARISON_COLUMNS t
    WHERE 1=1
      AND t.owner=Upper('&&v_c_owner') AND t.comparison_name=Upper('&&v_c_name')
      AND t.index_column = 'Y'
    ORDER BY t.column_position asc
    ;

    cursor c2 is
    select *
    from sys.DBA_COMPARISON_COLUMNS t
    WHERE 1=1
      AND t.owner=Upper('&&v_c_owner') AND t.comparison_name=Upper('&&v_c_name')
    ORDER BY t.column_position asc
    ;

begin
    if v_answer = 'Y' then
       v_count:=0;
       v_cols:='';
       for i in c1
       loop
           if v_count = 0 then
               v_cols := 't.'||i.column_name;
           else
               v_cols := v_cols||',t.'||i.column_name;
           end if;
           v_count:=v_count+1;
       end loop;
       -- dbms_output.put_line('v_count: '||v_count);
       if v_count=1 then
          v_aux:='i.index_value';
       else
          n:=1;
          for i in c1
          loop
              if n = 1 then
                 v_aux := 'regexp_substr(i.index_value,''[^,]+'', 1, '||n||') AS k'||n;
              else
                 v_aux := v_aux||chr(10)||',regexp_substr(i.index_value,''[^,]+'', 1, '||n||') AS k'||n;
              end if;
              n := n + 1;
          end loop;   
       end if;
    
       n:=1;
       for i in c2   --bacause source-table can has hidden key column(s)
       loop
           if n=1 then
              v_src_cols:='t.'||i.column_name;
           else
              v_src_cols:=v_src_cols||',t.'||i.column_name;
           end if;
           n:=n+1;
       end loop;

       v_str :=                 'create table '||v_lc_owner||'.'||v_lc_name||' tablespace '||v_ts;
       v_str := v_str||chr(10)||'as select /*+ driving_site(t)*/ ';
       v_str := v_str||chr(10)||v_src_cols;
       v_str := v_str||chr(10)||'from '||v_sc_owner||'.'||v_sc_name||'@'||v_db_link||' as of scn  '||v_scn||' t';
       v_str := v_str||chr(10)||'   where ('||v_cols||') in (';
       v_str := v_str||chr(10)||'select '||v_aux||' from sys.DBA_COMPARISON_ROW_DIF i';
       v_str := v_str||chr(10)||'where i.owner=Upper(''&&v_c_owner'') and i.comparison_name=Upper(''&&v_c_name'')';
       v_str := v_str||chr(10)||'   )';
       dbms_output.put_line( v_str );
       execute immediate v_str;
    end if;
end;
/

declare
   v_answer     varchar2(30) := nvl( upper('&&v_answer'), 'N');
begin
   if v_answer = 'Y' then
      dbms_output.put_line('Making pk');
   end if;
end;
/

declare
    v_answer     varchar2(30) := nvl( upper('&&v_answer'), 'N');
    v_lc_owner   varchar2(30) := upper('&&V_C_OWNER');
    v_lc_name    varchar2(128) := upper('&&LOCAL_TEMP_COPY');
    v_pk_name    varchar2(128) := upper('&&LOCAL_TEMP_COPY_PK_NAME');
    v_key_cols   varchar2(1024) := upper('&&KEY_COLS_LIST');
    v_ts         varchar2(30) := upper('&&V_TARGET_OBJ_TS');
    n            number;
    v_str        varchar2(4000) := '';
    v_dop        integer := nvl(to_number( upper('&&v_dop') ), 1);
begin
   if v_answer = 'Y' then
      dbms_output.put_line('DOP is: '||v_dop);
      if v_dop = 1 then
      --v_str := 'create unique index '||v_lc_owner||'.'||v_pk_name||' on '||v_lc_owner||'.'||v_lc_name||'('||v_key_cols||') parallel 8 ';
          v_str := 'alter table '||v_lc_owner||'.'||v_lc_name||' add constraint '||v_pk_name||' primary key ('||v_key_cols||') using index tablespace '||v_ts;
          dbms_output.put_line(v_str);
          execute immediate v_str;
      else
          v_str := 'create unique index '||v_lc_owner||'.'||v_pk_name||' on '||v_lc_owner||'.'||v_lc_name||'('||v_key_cols||') parallel '||v_dop||' tablespace '||v_ts;
          dbms_output.put_line(v_str);
          execute immediate v_str;
          v_str := 'alter table '||v_lc_owner||'.'||v_lc_name||' add constraint '||v_pk_name||' primary key ('||v_key_cols||') using index '||v_lc_owner||'.'||v_pk_name||' enable';
          dbms_output.put_line(v_str);
          execute immediate v_str;
          v_str := 'alter index '||v_lc_owner||'.'||v_pk_name||' noparallel';
          dbms_output.put_line(v_str);
          execute immediate v_str;
      end if;
      execute immediate 'select count('||v_key_cols||') from '||v_lc_owner||'.'||v_lc_name into n;
      dbms_output.put_line('Table '||v_lc_owner||'.'||v_lc_name||' has '||n||' rows');
   end if;
end;
/

Prompt done
