set arraysize 5000 rowprefetch 2 serveroutput on
whenever sqlerror continue

undefine key_cols_list
var v_rp_keycols char(1024)
var v_sc_keycols char(1024)
declare
    v_str  varchar2(1024) := '';
    n      number := 1;
    cursor c1 is
      SELECT cc.column_name as col1
      FROM  sys.dba_constraints@&&DBLINK_NAME c
           ,sys.dba_cons_columns@&&DBLINK_NAME cc
      WHERE 1=1
        AND c.owner=Upper('&&SC_OWNER') and c.constraint_type='P' AND c.table_name=Upper('&&SC_NAME')
        AND cc.owner=c.owner and cc.constraint_name=c.constraint_name AND c.table_name=cc.table_name
      ORDER BY cc.position asc
     ;
begin
    for i in c1
    loop
        if n = 1 then v_str := i.col1; else v_str := v_str||','||i.col1; end if;
--        dbms_output.put_line(n||' '||:v_sc_keycols);
        n := n + 1;
    end loop;
    :v_sc_keycols:=v_str;
end;
/

begin
      SELECT listagg(cc.column_name, ',') as col1
      into :v_rp_keycols      
      FROM  sys.dba_constraints c
           ,sys.dba_cons_columns cc
      WHERE 1=1
        AND c.owner=Upper('&&RP_OWNER') and c.constraint_type='P' AND c.table_name=Upper('&&RP_NAME')
        AND cc.owner=c.owner and cc.constraint_name=c.constraint_name AND c.table_name=cc.table_name
      ORDER BY cc.position asc
     ;
end;
/

var v_flag char(1)
begin
    dbms_output.put_line('Source-side  key-cols: '||:v_sc_keycols);
    dbms_output.put_line('Replica-side key-cols: '||:v_rp_keycols);

    if :v_rp_keycols = :v_sc_keycols then
       dbms_output.put_line('PK-keys exist on both-sides, and have the same structure');
       dbms_output.put_line('Trying to create local table and pk, see sql-session details, module=''&&session_module'' ');
       :v_flag := 'Y';
    else
       dbms_output.put_line('PK-keys are different or doesn''t exists on one or both-sides');
       dbms_output.put_line('If you want to localize source table at this stage: do it in your own way');
       dbms_output.put_line('Or skip it, probably, up to step 3a');
       :v_flag := 'N';
    end if;
end;
/

set timing on
declare
    v_lc_owner   varchar2(30) := upper('&&V_C_OWNER');
    v_lc_name    varchar2(128) := upper('&&LOCAL_TEMP_COPY');
    v_pk_name    varchar2(128) := upper('&&LOCAL_TEMP_COPY_PK_NAME');
    v_sc_owner   varchar2(30) := upper('&&SC_OWNER');
    v_sc_name    varchar2(30) := upper('&&SC_NAME');
    v_db_link    varchar2(30) := '&&DBLINK_NAME';
    v_comp_mode  varchar2(64) := lower('&&compress_mode');

    v_ts               varchar2(30) := '';
    v_allcols          varchar2(4000);
    v_str              varchar2(4000);
    n                  number := 1;
    v_scn              varchar2(16);
    cursor c1(p_towner in varchar2, p_tname in varchar2) is
 SELECT t.*
 FROM sys.dba_tab_cols@&&DBLINK_NAME t
 WHERE t.owner=upper(p_towner) AND t.table_name=upper(p_tname)
ORDER BY t.column_name
;

begin
    if :v_flag = 'Y' then
       begin
           execute immediate 'drop table &&V_C_OWNER..&&LOCAL_TEMP_COPY purge';
           dbms_output.put_line('Table &&V_C_OWNER..&&LOCAL_TEMP_COPY dropped successfully');
       exception when others then null;
       end;
   
       select distinct tablespace_name as v_target_obj_ts
       into v_ts
       from sys.dba_segments
       where 1=1
         and segment_type='TABLE' and owner=upper('&&RP_OWNER') and segment_name=upper('&&RP_NAME')
       fetch first 1 rows only
       ;
       dbms_output.put_line('TS: '||v_ts);
     
       select current_scn||'' as col1 into v_scn from v$database@&&DBLINK_NAME;
       dbms_output.put_line('SCN: '||v_scn);

       if v_comp_mode in ('compress', 'row store compress advanced', 'row store compress basic') then
           dbms_output.put_line('Compress mode: '||v_comp_mode);
       else
           dbms_output.put_line('Empty or unexpected value for compress mode: '||v_comp_mode);
           v_comp_mode:='none';
           dbms_output.put_line('CTAS is going to be executed without compression of newly created table');
       end if;

       for i in c1('&&SC_OWNER', '&&SC_NAME')
       loop
           if i.data_type in ( 'VARCHAR2','NVARCHAR2','NUMBER','FLOAT','DATE','BINARY_FLOAT','BINARY_DOUBLE','TIMESTAMP','TIMESTAMP WITH TIME ZONE','TIMESTAMP WITH LOCAL TIME ZONE','INTERVAL YEAR TO MONTH','INTERVAL DAY TO SECOND','RAW','CHAR','NCHAR' )
              and i.hidden_column != 'YES'
              and i.virtual_column != 'YES'
           then
              if n = 1 then v_allcols:=i.column_name; else v_allcols:=v_allcols||','||i.column_name; end if;
              n := n + 1;
           end if;
       end loop;
       dbms_output.put_line('Source-columns for CTAS: '||v_allcols);
       v_str :=                 'create table '||v_lc_owner||'.'||v_lc_name||' tablespace '||v_ts;
       if v_comp_mode != 'none' then
          v_str := v_str||chr(10)||v_comp_mode;
       end if;
       v_str := v_str||chr(10)||'as select ';
       v_str := v_str||chr(10)||v_allcols;
       v_str := v_str||chr(10)||'from '||v_sc_owner||'.'||v_sc_name||'@'||v_db_link||' as of scn  '||v_scn||' t';
       dbms_output.put_line( v_str );
       dbms_application_info.set_module('DBMS_COMPARISON', 'CTAS');
       execute immediate v_str;

       v_str:='alter table '||v_lc_owner||'.'||v_lc_name||' add constraint '||v_pk_name||' primary key ('||:v_sc_keycols||') using index tablespace '||v_ts;
       dbms_output.put_line( v_str );
       dbms_application_info.set_module('DBMS_COMPARISON', 'PK');
       execute immediate v_str;

       dbms_output.put_line('Source table localized as '||v_lc_owner||'.'||v_lc_name);
       dbms_output.put_line('Please do the following sqlplus-statements to configure work of next scripts with local-copy:');
       dbms_output.put_line('DEFINE SC_OWNER        = "'||v_lc_owner||'"');
       dbms_output.put_line('DEFINE SC_NAME         = "'||v_lc_name||'"');
       dbms_output.put_line('DEFINE DBLINK_NAME     = "&&localdblink"');
       dbms_output.put_line('DEFINE');
    end if;
end;
/

set timing off
