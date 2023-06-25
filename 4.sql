undefine V_ANSWER
accept v_answer char prompt 'Is &&SC_OWNER..&&SC_NAME@&&DBLINK_NAME actually local table [yn]? '

DECLARE
    f1                 utl_file.file_type;
    TYPE               reckey_record IS RECORD (col_name VARCHAR2(30), col_type VARCHAR2(120));
    TYPE               reckey_type IS TABLE OF reckey_record index BY BINARY_INTEGER;
    n                  BINARY_INTEGER;
    v_pk               reckey_type;
    v_allcols          VARCHAR2(1024);
    v_nokeycols        VARCHAR2(4000);
    v_str              VARCHAR2(4000);
    v_aux              VARCHAR2(1024);
    v_commit_freq      NUMBER := 1000;
    v_commit_sttm      VARCHAR2(128) := 'commit write nowait batch;';
    v_count            NUMBER := 0;
    v_source           VARCHAR2(128);
    v_localized        varchar2(3) := nvl(upper('&&v_answer'), 'N');
    v_keypos           NUMBER;
    v_keyval           VARCHAR2(128);

    CURSOR c1 IS
    SELECT *
    FROM sys.DBA_COMPARISON_ROW_DIF t
    WHERE 1=1
      AND t.owner=Upper('&&v_c_owner') AND t.comparison_name=Upper('&&v_c_name')
    --fetch first 10 rows only
    ;

    CURSOR c2 IS
    select t.column_name 
    from sys.DBA_COMPARISON_COLUMNS t
    WHERE 1=1
      AND t.owner=Upper('&&v_c_owner') AND t.comparison_name=Upper('&&v_c_name')  AND t.index_column!='Y'
    ORDER BY t.column_position ASC
    ;

    CURSOR c3 IS
    select t.column_name 
    from sys.DBA_COMPARISON_COLUMNS t
    WHERE 1=1
      AND t.owner=Upper('&&v_c_owner') AND t.comparison_name=Upper('&&v_c_name')  AND t.index_column='Y'
    ORDER BY t.column_position ASC
    ;

    FUNCTION quote_if_it_char(p_datatype IN VARCHAR2, p_value IN varchar2) 
    RETURN VARCHAR2
    IS
    BEGIN
        IF Upper(p_datatype) IN ('CLOB', 'NCLOB', 'CHAR', 'VARCHAR2', 'NCHAR') THEN
            RETURN ''''||p_value||'''';
        ELSE
            RETURN p_value;
        END IF;
    END; 

BEGIN
/*
 1) key - can be compoid key, that is: no one column
 2) key-column(s) can be character-type column(s); So it should be quoted;
*/
    if v_localized = 'Y' then
        v_source := '&&V_C_OWNER..&&LOCAL_TEMP_COPY';
    else
        v_source := '&&sc_owner..&&sc_name@&&dblink_name';        
    end if;

    f1 := UTL_FILE.FOPEN('&&V_DIRNAME','repair.sql','w',4096);  

    UTL_FILE.PUT_LINE(f1, '/* record key structure info: ');
    n:=1;
    FOR i IN c3
    LOOP
        v_pk(n).col_name := i.column_name;
        SELECT t.data_type
        INTO v_pk(n).col_type 
        FROM sys.dba_tab_cols t
        WHERE 1=1
          AND t.owner=upper('&&rp_owner') AND t.table_name=Upper('&&rp_name') AND t.column_name=Upper(i.column_name)
        ;
        UTL_FILE.PUT_LINE(f1, v_pk(n).col_name||' '||v_pk(n).col_type);
        n := n + 1;
    END LOOP;
    UTL_FILE.PUT_LINE(f1, '*/');


    select listagg(t.column_name, ',') AS col1
    INTO v_allcols
    from sys.DBA_COMPARISON_COLUMNS t
    WHERE 1=1
      AND t.owner=Upper('&&v_c_owner') AND t.comparison_name=Upper('&&v_c_name')
    ORDER BY t.column_position ASC
    ;
    
    UTL_FILE.PUT_LINE(f1, '-- all columns list is: '||v_allcols);

    v_nokeycols:='';
    v_count := 0;
    FOR i IN c2
    LOOP
        IF v_count = 0 THEN
             v_nokeycols:=' r.'||i.column_name||'=s.'||i.column_name;
        ELSE
             v_nokeycols:=v_nokeycols||Chr(10)||',r.'||i.column_name||'=s.'||i.column_name;
        END IF;
        --Dbms_Output.put_line(v_count);
        v_count:=v_count+1;
    END LOOP;
    --Dbms_Output.put_line(v_nokeycols);
    UTL_FILE.PUT_LINE(f1, '/* no key columns list is:');
    UTL_FILE.PUT_LINE(f1, v_nokeycols);
    UTL_FILE.PUT_LINE(f1, '*/');

    UTL_FILE.PUT_LINE(f1, 'whenever sqlerror continue');
    UTL_FILE.PUT_LINE(f1, 'set echo off define off verify off serveroutput on timing off');
    UTL_FILE.PUT_LINE(f1, 'show user');
    UTL_FILE.PUT_LINE(f1, 'show con_name');
    UTL_FILE.PUT_LINE(f1, 'accept v_answer char prompt ''Would you like to continue? ''');
    UTL_FILE.PUT_LINE(f1, 'alter session set cursor_sharing=force;');

    UTL_FILE.PUT_LINE(f1, 'set termout off');
    UTL_FILE.PUT_LINE(f1, 'var t1 char(30)');
    UTL_FILE.PUT_LINE(f1, 'var t2 char(30)');
    UTL_FILE.PUT_LINE(f1, 'exec :t1:=to_char(sysdate,''yyyy.mm.dd hh24:mi:ss'');');
    UTL_FILE.PUT_LINE(f1, 'set termout on');

                                        
    v_count := 0;
    FOR i IN c1
    LOOP
        v_str := '';
        v_aux := '';
        v_keyval:='';
        v_keypos:=1;
        n:=v_pk.first;
        IF i.remote_rowid IS NULL AND i.local_rowid  IS NOT NULL THEN
              --rows which exist in replica only, they have to be deleted from replica
              v_str:='delete /* repair_sql */  from &&rp_owner..&&rp_name where ';
              WHILE n IS NOT NULL
              LOOP
                  v_keyval:=regexp_substr(i.index_value,'[^,]+', 1, v_keypos);
                  IF n = v_pk.first THEN
                      v_aux:=v_pk(n).col_name||'='||quote_if_it_char(v_pk(n).col_type, v_keyval);
                  ELSE
                      v_aux:=v_aux||' and '||v_pk(n).col_name||'='||quote_if_it_char(v_pk(n).col_type, v_keyval);
                  END IF;
                  n := v_pk.NEXT(n);
                  v_keypos := v_keypos + 1;
              END LOOP;
              v_str:=v_str||v_aux||';';
              UTL_FILE.PUT_LINE(f1, v_str);
              v_count := v_count + 1;
        ELSIF i.remote_rowid IS not NULL  AND i.local_rowid IS NULL THEN
              --rows which exist in source but no in replica, they have to be inserted into replica
              v_str := 'insert /* repair_sql */ into &&rp_owner..&&rp_name ('||v_allcols||')';
              UTL_FILE.PUT_LINE(f1, v_str);
              v_str := 'select '||v_allcols||' from '||v_source||' where ';
              WHILE n IS NOT NULL
              LOOP
                  v_keyval:=regexp_substr(i.index_value,'[^,]+', 1, v_keypos);
                  IF n = v_pk.first THEN
                      v_aux:=v_pk(n).col_name||'='||quote_if_it_char(v_pk(n).col_type, v_keyval);
                  ELSE
                      v_aux:=v_aux||' and '||v_pk(n).col_name||'='||quote_if_it_char(v_pk(n).col_type, v_keyval);
                  END IF;
                  n := v_pk.NEXT(n);
                  v_keypos:=v_keypos+1;
              END LOOP;
              v_str := v_str||v_aux||';';
              UTL_FILE.PUT_LINE(f1, v_str);
              v_count := v_count + 1;
        ELSIF i.remote_rowid IS not NULL  AND i.local_rowid IS NOT NULL THEN
              --rows which exist in source and in replica, they have to be updated in replica
              WHILE n IS NOT NULL
              LOOP
                  v_keyval:=regexp_substr(i.index_value,'[^,]+', 1, v_keypos);
                  IF n = v_pk.first THEN
                      v_aux:=v_pk(n).col_name||'='||quote_if_it_char(v_pk(n).col_type, v_keyval);
                  ELSE
                      v_aux:=v_aux||' and '||v_pk(n).col_name||'='||quote_if_it_char(v_pk(n).col_type, v_keyval);
                  END IF;
                  n := v_pk.NEXT(n);
                  v_keypos:=v_keypos+1;
              END LOOP;
              v_str:='merge /* repair_sql */ into &&rp_owner..&&rp_name r using ( select '||v_allcols||' from '||v_source||' where '||v_aux||' ) s';
              UTL_FILE.PUT_LINE(f1, v_str);

              v_aux:='';
              n:=v_pk.first;
              WHILE n IS NOT NULL
              LOOP
                  IF n = v_pk.first THEN
                      v_aux:='r.'||v_pk(n).col_name||'=s.'||v_pk(n).col_name;
                  ELSE
                      v_aux:=v_aux||' and r.'||v_pk(n).col_name||'=s.'||v_pk(n).col_name;
                  END IF;                  
                  n := v_pk.NEXT(n);
              END LOOP;
              v_str:='on ( '||v_aux||' ) when matched then update set ';
              UTL_FILE.PUT_LINE(f1, v_str);
              v_str:=v_nokeycols||';';
              UTL_FILE.PUT_LINE(f1, v_str);
              v_count := v_count + 1; 
        END IF;
        IF Mod(v_count, v_commit_freq)=0 THEN
            UTL_FILE.PUT_LINE(f1, v_commit_sttm);
            dbms_application_info.set_module('DBMS_COMPARISON', 'repair '||v_count); 
            UTL_FILE.PUT_LINE(f1, 'exec dbms_application_info.set_module(''DBMS_COMPARISON'', ''repair ''||'||v_count||');');
        END IF;
    END LOOP;

    IF v_count > 0 THEN 
       UTL_FILE.PUT_LINE(f1, v_commit_sttm);
    END IF;

    UTL_FILE.PUT_LINE(f1, 'set termout off');
    UTL_FILE.PUT_LINE(f1, 'exec :t2:=to_char(sysdate,''yyyy.mm.dd hh24:mi:ss'');');
    UTL_FILE.PUT_LINE(f1, 'select (24*3600)*( to_date(:t2, ''yyyy.mm.dd hh24:mi:ss'')-to_date(:t1, ''yyyy.mm.dd hh24:mi:ss'') ) as elatime from dual; ');
    UTL_FILE.PUT_LINE(f1, 'set termout on');
    UTL_FILE.PUT_LINE(f1, 'exec dbms_output.put_line(''Elapsed time (seconds): ''||round(( to_date(:t2, ''yyyy.mm.dd hh24:mi:ss'')-to_date(:t1, ''yyyy.mm.dd hh24:mi:ss'') )*24*3600, 2) );');
    utl_file.fclose(f1);

EXCEPTION
 WHEN OTHERS THEN utl_file.fclose_all;
END;
/

