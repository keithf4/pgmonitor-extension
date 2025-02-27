
CREATE TEMP TABLE pgmonitor_preserve_privs_temp (statement text);

INSERT INTO pgmonitor_preserve_privs_temp
WITH aclstuff AS (                                                                                                             
    SELECT (aclexplode(relacl)).grantee AS grantee, (aclexplode(relacl)).privilege_type AS privilege_type 
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = 'ccp_table_size'
    AND n.nspname = '@extschema@') 
SELECT format('GRANT %s ON TABLE %I.%I TO %I;', string_agg(a.privilege_type, ','), '@extschema@', 'ccp_table_size',  r.rolname)
FROM pg_catalog.pg_roles r 
JOIN aclstuff a ON a.grantee = r.oid
WHERE r.rolname != 'PUBLIC'
GROUP BY rolname;

INSERT INTO pgmonitor_preserve_privs_temp
WITH aclstuff AS (                                                                                                             
    SELECT (aclexplode(relacl)).grantee AS grantee, (aclexplode(relacl)).privilege_type AS privilege_type 
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = 'ccp_database_size'
    AND n.nspname = '@extschema@') 
SELECT format('GRANT %s ON TABLE %I.%I TO %I;', string_agg(a.privilege_type, ','), '@extschema@', 'ccp_database_size',  r.rolname)
FROM pg_catalog.pg_roles r 
JOIN aclstuff a ON a.grantee = r.oid
WHERE r.rolname != 'PUBLIC'
GROUP BY rolname;

INSERT INTO pgmonitor_preserve_privs_temp
WITH aclstuff AS (                                                                                                             
    SELECT (aclexplode(relacl)).grantee AS grantee, (aclexplode(relacl)).privilege_type AS privilege_type 
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = 'ccp_stat_database'
    AND n.nspname = '@extschema@') 
SELECT format('GRANT %s ON TABLE %I.%I TO %I;', string_agg(a.privilege_type, ','), '@extschema@', 'ccp_stat_database',  r.rolname)
FROM pg_catalog.pg_roles r 
JOIN aclstuff a ON a.grantee = r.oid
WHERE r.rolname != 'PUBLIC'
GROUP BY rolname;

INSERT INTO pgmonitor_preserve_privs_temp
WITH aclstuff AS (                                                                                                             
    SELECT (aclexplode(relacl)).grantee AS grantee, (aclexplode(relacl)).privilege_type AS privilege_type 
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = 'ccp_pg_stat_statements_reset'
    AND n.nspname = '@extschema@') 
SELECT format('GRANT %s ON TABLE %I.%I TO %I;', string_agg(a.privilege_type, ','), '@extschema@', 'ccp_pg_stat_statements_reset',  r.rolname)
FROM pg_catalog.pg_roles r 
JOIN aclstuff a ON a.grantee = r.oid
WHERE r.rolname != 'PUBLIC'
GROUP BY rolname;

DROP MATERIALIZED VIEW @extschema@.ccp_table_size;
DROP MATERIALIZED VIEW @extschema@.ccp_database_size;
DROP MATERIALIZED VIEW @extschema@.ccp_stat_database;
ALTER FUNCTION @extschema@.ccp_stat_checkpointer() RENAME TO ccp_stat_checkpointer_func;
ALTER FUNCTION @extschema@.ccp_stat_io_bgwriter() RENAME TO ccp_stat_io_bgwriter_func;

/**** START CONFIG CHANGES ****/
-- convert matview to view
UPDATE @extschema@.metric_views SET materialized_view = false WHERE view_name = 'ccp_stat_database';
-- convert view to table refresh
WITH tablestuff AS (
    DELETE FROM @extschema@.metric_views WHERE view_name = 'ccp_pg_stat_statements_reset' RETURNING *
)
INSERT INTO metric_tables (table_schema
    , table_name
    , refresh_statement
    , run_interval
    , last_run
    , last_run_time
    , active
    , scope)
SELECT view_schema
    , view_name
    , 'SELECT pgmonitor_ext.pg_stat_statements_reset_info()'
    , run_interval
    , last_run
    , last_run_time
    , active
    , scope
FROM tablestuff;

CREATE TABLE @extschema@.metric_matviews (
    view_schema text NOT NULL DEFAULT '@extschema@'
    , view_name text NOT NULL
    , concurrent_refresh boolean NOT NULL DEFAULT true
    , run_interval interval NOT NULL DEFAULT '10 minutes'::interval
    , last_run timestamptz
    , last_run_time interval
    , active boolean NOT NULL DEFAULT true
    , scope text NOT NULL default 'global'
    , CONSTRAINT metric_matviews_pk PRIMARY KEY (view_schema, view_name)
    , CONSTRAINT metric_matviews_scope_ck CHECK (scope IN ('global', 'database'))
);
CREATE INDEX metric_matviews_active ON @extschema@.metric_matviews (active);
SELECT pg_catalog.pg_extension_config_dump('metric_matviews', '');
ALTER TABLE @extschema@.metric_matviews SET (
    autovacuum_analyze_scale_factor = 0
    , autovacuum_vacuum_scale_factor = 0
    , autovacuum_vacuum_threshold = 10
    , autovacuum_analyze_threshold = 10);

WITH matviews AS (
    DELETE FROM @extschema@.metric_views WHERE materialized_view = true RETURNING * )
INSERT INTO @extschema@.metric_matviews (view_schema, view_name, concurrent_refresh, run_interval, last_run, last_run_time, scope)
    SELECT m.view_schema, m.view_name, m.concurrent_refresh, m.run_interval, m.last_run, m.last_run_time, m.scope FROM matviews m;

DROP INDEX @extschema@.metric_views_active_matview;
CREATE INDEX metric_views_active ON @extschema@.metric_views (active);

ALTER TABLE @extschema@.metric_views RENAME COLUMN materialized_view TO matview_source;
ALTER TABLE @extschema@.metric_views ALTER COLUMN matview_source SET DEFAULT false;
ALTER TABLE @extschema@.metric_views DROP COLUMN concurrent_refresh;
ALTER TABLE @extschema@.metric_views DROP COLUMN run_interval;
ALTER TABLE @extschema@.metric_views DROP COLUMN last_run;
ALTER TABLE @extschema@.metric_views DROP COLUMN last_run_time;


CREATE OR REPLACE PROCEDURE @extschema@.refresh_metrics (p_object_schema text DEFAULT 'monitor', p_object_name text DEFAULT NULL)
    LANGUAGE plpgsql
    AS $$
DECLARE

v_adv_lock                      boolean;
v_loop_sql                      text;
v_refresh_statement             text;
v_refresh_sql                   text;
v_row                           record;
v_runtime                       interval;
v_start_runtime                 timestamptz;
v_stop_runtime                  timestamptz;

BEGIN

IF pg_catalog.pg_is_in_recovery() = TRUE THEN
    RAISE DEBUG 'Database instance in recovery mode. Exiting without view refresh';
    RETURN;
END IF;

v_adv_lock := pg_catalog.pg_try_advisory_lock(hashtext('pgmonitor refresh call'));
IF v_adv_lock = false THEN
    RAISE WARNING 'pgMonitor extension refresh already running or another session has not released its advisory lock. If you are seeing this warning repeatedly, try adjusting the interval that this procedure is called or check the runtime of refresh jobs for long runtimes.';
    RETURN;
END IF;

v_loop_sql := format('SELECT view_schema, view_name, concurrent_refresh
                        FROM @extschema@.metric_matviews
                        WHERE active
                        AND ( last_run IS NULL OR (CURRENT_TIMESTAMP - last_run) > run_interval )');

IF p_object_name IS NOT NULL THEN
    v_loop_sql := format('%s AND view_schema = %L AND view_name = %L', v_loop_sql, p_object_schema, p_object_name);
END IF;

FOR v_row IN EXECUTE v_loop_sql LOOP

    v_start_runtime := clock_timestamp();
    v_stop_runtime := NULL;

    v_refresh_sql := 'REFRESH MATERIALIZED VIEW ';
    IF v_row.concurrent_refresh THEN
        v_refresh_sql := v_refresh_sql || 'CONCURRENTLY ';
    END IF;
    v_refresh_sql := format('%s %I.%I', v_refresh_sql, v_row.view_schema, v_row.view_name);
    RAISE DEBUG 'pgmonitor view refresh: %', v_refresh_sql;
    EXECUTE v_refresh_sql;

    v_stop_runtime := clock_timestamp();
    v_runtime = v_stop_runtime - v_start_runtime;

    UPDATE @extschema@.metric_matviews
    SET last_run = CURRENT_TIMESTAMP, last_run_time = v_runtime
    WHERE view_schema = v_row.view_schema
    AND view_name = v_row.view_name;

    COMMIT;
END LOOP;

v_loop_sql := format('SELECT table_schema, table_name, refresh_statement
    FROM @extschema@.metric_tables
    WHERE active
    AND ( last_run IS NULL OR (CURRENT_TIMESTAMP - last_run) > run_interval )');

IF p_object_name IS NOT NULL THEN
    v_loop_sql := format('%s AND table_schema = %L AND table_name = %L', v_loop_sql, p_object_schema, p_object_name);
END IF;

FOR v_row IN EXECUTE v_loop_sql LOOP
    RAISE DEBUG 'pgmonitor table refresh: %', v_row.refresh_statement;

    v_start_runtime := clock_timestamp();
    v_stop_runtime := NULL;

    EXECUTE format(v_row.refresh_statement);

    v_stop_runtime := clock_timestamp();
    v_runtime = v_stop_runtime - v_start_runtime;

    UPDATE @extschema@.metric_tables
    SET last_run = CURRENT_TIMESTAMP, last_run_time = v_runtime
    WHERE table_schema = v_row.table_schema
    AND table_name = v_row.table_name;

    COMMIT;
END LOOP;

PERFORM pg_catalog.pg_advisory_unlock(hashtext('pgmonitor refresh call'));

END
$$;

/**** END CONFIG CHANGES ****/


/**** START ccp_database_size ****/

CREATE MATERIALIZED VIEW @extschema@.ccp_database_size_matview AS
    SELECT datname as dbname
    , pg_catalog.pg_database_size(datname) as bytes
    FROM pg_catalog.pg_database
    WHERE datistemplate = false;
CREATE UNIQUE INDEX ccp_database_size_matview_idx ON @extschema@.ccp_database_size_matview (dbname);

UPDATE @extschema@.metric_matviews SET view_name = 'ccp_database_size_matview' WHERE view_name = 'ccp_database_size';
-- Ensure the entry is there in case it somehow got deleted
INSERT INTO @extschema@.metric_matviews (
    view_name)
VALUES (
    'ccp_database_size_matview')
ON CONFLICT DO NOTHING;

CREATE FUNCTION @extschema@.ccp_database_size_view_choice() RETURNS TABLE
(
    dbname name
    , bytes bigint
)
    LANGUAGE plpgsql
AS $function$
DECLARE

v_matview   boolean;

BEGIN

SELECT matview_source 
INTO v_matview
FROM @extschema@.metric_views
WHERE view_name = 'ccp_database_size';

IF v_matview THEN

    RETURN QUERY SELECT m.dbname
    , m.bytes
    FROM @extschema@.ccp_database_size_matview m;

ELSE

    RETURN QUERY SELECT datname as dbname
    , pg_catalog.pg_database_size(datname) as bytes
    FROM pg_catalog.pg_database
    WHERE datistemplate = false;

END IF;

END
$function$;

CREATE VIEW @extschema@.ccp_database_size AS
    SELECT dbname
    , bytes
    FROM @extschema@.ccp_database_size_view_choice();

INSERT INTO @extschema@.metric_views (
    view_name
    , matview_source)
VALUES (
    'ccp_database_size'
    , true)
ON CONFLICT DO NOTHING;

/**** END ccp_database_size ****/


/**** START ccp_replication_slots ****/

CREATE FUNCTION @extschema@.ccp_replication_slots_func() RETURNS TABLE
(
    slot_name name
    , active int
    , retained_bytes numeric
    , database name
    , slot_type text
    , conflicting int
    , failover int
    , synced int
)
    LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN

IF current_setting('server_version_num')::int >= 170000 THEN

    RETURN QUERY
    SELECT s.slot_name
        , s.active::int
        , pg_wal_lsn_diff(CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_insert_lsn() END, s.restart_lsn) AS retained_bytes
        , s.database
        , s.slot_type
        , s.conflicting::int
        , s.failover::int
        , s.synced::int
    FROM pg_catalog.pg_replication_slots s;

ELSIF current_setting('server_version_num')::int >= 160000  AND current_setting('server_version_num')::int < 170000 THEN

    RETURN QUERY
    SELECT s.slot_name
        , s.active::int
        , pg_wal_lsn_diff(CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_insert_lsn() END, s.restart_lsn) AS retained_bytes
        , s.database
        , s.slot_type
        , s.conflicting::int
        , 0 AS failover
        , 0 AS synced
    FROM pg_catalog.pg_replication_slots s;

ELSE

    RETURN QUERY
    SELECT s.slot_name
        , s.active::int
        , pg_wal_lsn_diff(CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_insert_lsn() END, s.restart_lsn) AS retained_bytes
        , s.database
        , s.slot_type
        , 0 AS conflicting
        , 0 AS failover
        , 0 AS synced
    FROM pg_catalog.pg_replication_slots s;

END IF;

END
$function$;

CREATE OR REPLACE VIEW @extschema@.ccp_replication_slots AS
    SELECT slot_name
        , active
        , retained_bytes
        , database
        , slot_type
        , conflicting
        , failover
        , synced
    FROM @extschema@.ccp_replication_slots_func();

/**** END ccp_replication_slots ****/


/**** START ccp_stat_checkpointer ****/

CREATE OR REPLACE VIEW @extschema@.ccp_stat_checkpointer AS
    SELECT
        num_timed
        , num_requested
        , write_time
        , sync_time
        , buffers_written
    FROM @extschema@.ccp_stat_checkpointer_func();

/**** END ccp_stat_checkpointer ****/


/**** START ccp_stat_database ****/

CREATE VIEW @extschema@.ccp_stat_database AS
    SELECT s.datname AS dbname
    , s.xact_commit
    , s.xact_rollback
    , s.blks_read
    , s.blks_hit
    , s.tup_returned
    , s.tup_fetched
    , s.tup_inserted
    , s.tup_updated
    , s.tup_deleted
    , s.conflicts
    , s.temp_files
    , s.temp_bytes
    , s.deadlocks
    FROM pg_catalog.pg_stat_database s
    JOIN pg_catalog.pg_database d ON d.datname = s.datname
    WHERE d.datistemplate = false;

/**** END ccp_stat_database ****/


/**** START ccp_stat_io_bgwriter  ****/

CREATE OR REPLACE VIEW @extschema@.ccp_stat_io_bgwriter AS
    SELECT
        writes
        , fsyncs
    FROM @extschema@.ccp_stat_io_bgwriter_func();

/**** END ccp_stat_io_bgwriter  ****/

/**** START ccp_stat_user_tables  ****/

ALTER MATERIALIZED VIEW @extschema@.ccp_stat_user_tables RENAME TO ccp_stat_user_tables_matview;
ALTER INDEX @extschema@.ccp_user_tables_db_schema_relname_idx RENAME TO ccp_user_tables_matview_idx;

UPDATE @extschema@.metric_matviews SET view_name = 'ccp_stat_user_tables_matview' WHERE view_name = 'ccp_stat_user_tables';
-- Ensure the entry is there in case it somehow got deleted
INSERT INTO @extschema@.metric_matviews (
    view_name
)
VALUES (
    'ccp_stat_user_tables_matview'
)
ON CONFLICT DO NOTHING;


CREATE FUNCTION @extschema@.ccp_stat_user_tables_view_choice() RETURNS TABLE
(
    dbname name
    , schemaname name
    , relname name
    , seq_scan bigint
    , seq_tup_read bigint
    , idx_scan bigint
    , idx_tup_fetch bigint
    , n_tup_ins bigint
    , n_tup_upd bigint
    , n_tup_del bigint
    , n_tup_hot_upd bigint
    , n_tup_newpage_upd bigint
    , n_live_tup bigint
    , n_dead_tup bigint
    , vacuum_count bigint
    , autovacuum_count bigint
    , analyze_count bigint
    , autoanalyze_count bigint
)
    LANGUAGE plpgsql
AS $function$
DECLARE

v_matview   boolean;

BEGIN

SELECT matview_source 
INTO v_matview
FROM @extschema@.metric_views
WHERE view_name = 'ccp_stat_user_tables';

IF v_matview THEN

    RETURN QUERY SELECT
        s.dbname
        , s.schemaname
        , s.relname
        , s.seq_scan
        , s.seq_tup_read
        , s.idx_scan
        , s.idx_tup_fetch
        , s.n_tup_ins
        , s.n_tup_upd
        , s.n_tup_del
        , s.n_tup_hot_upd
        , s.n_tup_newpage_upd
        , s.n_live_tup
        , s.n_dead_tup
        , s.vacuum_count
        , s.autovacuum_count
        , s.analyze_count
        , s.autoanalyze_count
    FROM @extschema@.ccp_stat_user_tables_matview s;

ELSE

    RETURN QUERY SELECT
        current_database() as dbname
        , s.schemaname
        , s.relname
        , s.seq_scan
        , s.seq_tup_read
        , s.idx_scan
        , s.idx_tup_fetch
        , s.n_tup_ins
        , s.n_tup_upd
        , s.n_tup_del
        , s.n_tup_hot_upd
        , s.n_tup_newpage_upd
        , s.n_live_tup
        , s.n_dead_tup
        , s.vacuum_count
        , s.autovacuum_count
        , s.analyze_count
        , s.autoanalyze_count
    FROM @extschema@.ccp_stat_user_tables_func() s;

END IF; 

END
$function$;

CREATE VIEW @extschema@.ccp_stat_user_tables AS
    SELECT dbname
    , schemaname
    , relname
    , seq_scan
    , seq_tup_read
    , idx_scan
    , idx_tup_fetch
    , n_tup_ins
    , n_tup_upd
    , n_tup_del
    , n_tup_hot_upd
    , n_tup_newpage_upd
    , n_live_tup
    , n_dead_tup
    , vacuum_count
    , autovacuum_count
    , analyze_count
    , autoanalyze_count
    FROM @extschema@.ccp_stat_user_tables_view_choice();

INSERT INTO @extschema@.metric_views (
    view_name
)
VALUES (
    'ccp_stat_user_tables'
)
ON CONFLICT DO NOTHING;

/**** END ccp_stat_user_tables  ****/


/**** START ccp_table_size ****/

CREATE MATERIALIZED VIEW @extschema@.ccp_table_size_matview AS
    SELECT current_database() as dbname
    , n.nspname as schemaname
    , c.relname
    , pg_catalog.pg_total_relation_size(c.oid) as bytes
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE NOT pg_catalog.pg_is_other_temp_schema(n.oid)
    AND relkind IN ('r', 'm', 'f', 'p');
CREATE UNIQUE INDEX ccp_table_size_matview_idx ON @extschema@.ccp_table_size_matview (dbname, schemaname, relname);

UPDATE @extschema@.metric_matviews SET view_name = 'ccp_table_size_matview' WHERE view_name = 'ccp_table_size';
-- Ensure the entry is there in case it somehow got deleted
INSERT INTO @extschema@.metric_matviews (
    view_name
    , run_interval
    , scope)
VALUES (
    'ccp_table_size_matview'
    , '5 minutes'::interval
    , 'database')
ON CONFLICT DO NOTHING;


CREATE FUNCTION @extschema@.ccp_table_size_view_choice() RETURNS TABLE
(
    dbname name
    , schemaname name
    , relname name
    , bytes bigint
)
    LANGUAGE plpgsql
AS $function$
DECLARE

v_matview   boolean;

BEGIN

SELECT matview_source 
INTO v_matview
FROM @extschema@.metric_views
WHERE view_name = 'ccp_table_size';

IF v_matview THEN

    RETURN QUERY SELECT m.dbname
    , m.schemaname
    , m.relname
    , m.bytes
    FROM @extschema@.ccp_table_size_matview m;

ELSE

    RETURN QUERY SELECT current_database() as dbname
    , n.nspname as schemaname
    , c.relname
    , pg_catalog.pg_total_relation_size(c.oid) as bytes
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE NOT pg_is_other_temp_schema(n.oid)
    AND relkind IN ('r', 'm', 'f');

END IF;

END
$function$;

CREATE VIEW @extschema@.ccp_table_size AS
    SELECT dbname
    , schemaname
    , relname
    , bytes
    FROM @extschema@.ccp_table_size_view_choice();

INSERT INTO @extschema@.metric_views (
    view_name
    , matview_source)
VALUES (
    'ccp_table_size'
    , true)
ON CONFLICT DO NOTHING;

/**** END ccp_table_size ****/


CREATE OR REPLACE FUNCTION @extschema@.pg_stat_statements_reset_info()
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO pg_catalog, pg_temp
AS $function$
DECLARE

  v_reset_timestamp      timestamptz;
  v_reset_interval       interval;
  v_sql                  text;
  v_stat_schema          name;

BEGIN
-- ******** NOTE ********
-- This function must be owned by a superuser to work

-- Function to reset pg_stat_statements periodically
-- The run_interval stored in metric_tables for "ccp_pg_stat_statements_reset" is
--   what is used to determine how often this function resets the stats

  SELECT n.nspname INTO v_stat_schema
  FROM pg_catalog.pg_extension e
  JOIN pg_catalog.pg_namespace n ON e.extnamespace = n.oid
  WHERE e.extname = 'pg_stat_statements';

  IF v_stat_schema IS NULL THEN
    RAISE EXCEPTION 'Unable to find pg_stat_statements extension installed on this database';
  END IF;

  SELECT run_interval INTO v_reset_interval
  FROM @extschema@.metric_tables
  WHERE table_schema = '@extschema@'
  AND table_name = 'ccp_pg_stat_statements_reset';

  SELECT COALESCE(max(reset_time), '1970-01-01'::timestamptz) INTO v_reset_timestamp FROM @extschema@.pg_stat_statements_reset_info;

  IF ((CURRENT_TIMESTAMP - v_reset_timestamp) > v_reset_interval) THEN
      -- Ensure table is empty
      DELETE FROM @extschema@.pg_stat_statements_reset_info;
      v_sql := format('SELECT %I.pg_stat_statements_reset()', v_stat_schema);
      EXECUTE v_sql;
      INSERT INTO @extschema@.pg_stat_statements_reset_info(reset_time) values (CURRENT_TIMESTAMP);
  END IF;

  RETURN (SELECT extract(epoch from reset_time) FROM @extschema@.pg_stat_statements_reset_info);

END
$function$;


CREATE OR REPLACE FUNCTION @extschema@.pg_stat_statements_func() RETURNS TABLE
(
    "role" name
    , dbname name
    , queryid bigint
    , query text
    , calls bigint
    , total_exec_time double precision
    , max_exec_time double precision
    , mean_exec_time double precision
    , rows bigint
    , wal_records bigint
    , wal_fpi bigint
    , wal_bytes numeric
)
    LANGUAGE plpgsql
AS $function$
DECLARE

v_new_search_path               text;
v_old_search_path               text;
v_stat_schema                   text;

BEGIN
/*
 * Function interface to the pg_stat_statements contrib view to allow multi-version PG support
 *  Only columns that are used by pgMonitor metrics are returned
 */

SELECT current_setting('search_path') INTO v_old_search_path;
IF length(v_old_search_path) > 0 THEN
   v_new_search_path := '@extschema@,pg_temp,'||v_old_search_path;
ELSE
    v_new_search_path := '@extschema@,pg_temp';
END IF;
SELECT nspname INTO v_stat_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_stat_statements'::name AND e.extnamespace = n.oid;
IF v_stat_schema IS NOT NULL THEN
    v_new_search_path := format('%s,%s',v_stat_schema, v_new_search_path);
    EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_new_search_path, 'false');
ELSE
    RAISE EXCEPTION 'Unable to find pg_stat_statements extension installed on this database';
END IF;

IF current_setting('server_version_num')::int >= 130000 THEN
    RETURN QUERY SELECT
        pg_get_userbyid(s.userid) AS role
        , d.datname AS dbname
        , s.queryid
        , btrim(replace(left(s.query, 40), '\n', '')) AS query
        , s.calls
        , s.total_exec_time
        , s.max_exec_time
        , s.mean_exec_time
        , s.rows
        , s.wal_records
        , s.wal_fpi
        , s.wal_bytes
      FROM pg_stat_statements s
      JOIN pg_catalog.pg_database d ON d.oid = s.dbid;
ELSE
    RETURN QUERY SELECT
        pg_get_userbyid(s.userid) AS role
        , d.datname AS dbname
        , s.queryid
        , btrim(replace(left(s.query, 40), '\n', '')) AS query
        , s.calls
        , s.total_time AS total_exec_time
        , s.max_time AS max_exec_time
        , s.mean_time AS mean_exec_time
        , s.rows
        , 0::bigint AS wal_records
        , 0::bigint AS wal_fpi
        , 0::numeric AS wal_bytes
      FROM pg_stat_statements s
      JOIN pg_catalog.pg_database d ON d.oid = s.dbid;
END IF;

IF v_stat_schema IS NOT NULL THEN
    EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_old_search_path, 'false');
END IF;


END
$function$;


CREATE OR REPLACE FUNCTION @extschema@.refresh_metrics_legacy (p_object_schema text DEFAULT 'monitor', p_object_name text DEFAULT NULL)
    RETURNS void
    LANGUAGE plpgsql
    AS $function$
DECLARE

v_adv_lock                      boolean;
v_loop_sql                      text;
v_refresh_statement             text;
v_refresh_sql                   text;
v_row                           record;
v_runtime                       interval;
v_start_runtime                 timestamptz;
v_stop_runtime                  timestamptz;

BEGIN
/*
 * Function version of refresh_metrics() procedure for PG versions less than 14 that cannot be called via BGW
 */

IF pg_catalog.pg_is_in_recovery() = TRUE THEN
    RAISE DEBUG 'Database instance in recovery mode. Exiting without view refresh';
    RETURN;
END IF;

v_adv_lock := pg_catalog.pg_try_advisory_lock(hashtext('pgmonitor refresh call'));
IF v_adv_lock = false THEN
    RAISE WARNING 'pgMonitor extension refresh already running or another session has not released its advisory lock. If you are seeing this warning repeatedly, try adjusting the interval that this procedure is called or check the runtime of refresh jobs for long runtimes.';
    RETURN;
END IF;

v_loop_sql := format('SELECT view_schema, view_name, concurrent_refresh
                        FROM @extschema@.metric_matviews
                        WHERE active
                        AND ( last_run IS NULL OR (CURRENT_TIMESTAMP - last_run) > run_interval )');

IF p_object_name IS NOT NULL THEN
    v_loop_sql := format('%s AND view_schema = %L AND view_name = %L', v_loop_sql, p_object_schema, p_object_name);
END IF;


FOR v_row IN EXECUTE v_loop_sql LOOP

    v_start_runtime := clock_timestamp();
    v_stop_runtime := NULL;

    v_refresh_sql := 'REFRESH MATERIALIZED VIEW ';
    IF v_row.concurrent_refresh THEN
        v_refresh_sql := v_refresh_sql || 'CONCURRENTLY ';
    END IF;
    v_refresh_sql := format('%s %I.%I', v_refresh_sql, v_row.view_schema, v_row.view_name);
    RAISE DEBUG 'pgmonitor view refresh: %', v_refresh_sql;
    EXECUTE v_refresh_sql;

    v_stop_runtime := clock_timestamp();
    v_runtime = v_stop_runtime - v_start_runtime;

    UPDATE @extschema@.metric_views
    SET last_run = CURRENT_TIMESTAMP, last_run_time = v_runtime
    WHERE view_schema = v_row.view_schema
    AND view_name = v_row.view_name;

END LOOP;

v_loop_sql := format('SELECT table_schema, table_name, refresh_statement
    FROM @extschema@.metric_tables
    WHERE active
    AND ( last_run IS NULL OR (CURRENT_TIMESTAMP - last_run) > run_interval )');

IF p_object_name IS NOT NULL THEN
    v_loop_sql := format('%s AND table_schema = %L AND table_name = %L', v_loop_sql, p_object_schema, p_object_name);
END IF;

FOR v_row IN EXECUTE v_loop_sql LOOP
    RAISE DEBUG 'pgmonitor table refresh: %', v_row.refresh_statement;

    v_start_runtime := clock_timestamp();
    v_stop_runtime := NULL;

    EXECUTE format(v_row.refresh_statement);

    v_stop_runtime := clock_timestamp();
    v_runtime = v_stop_runtime - v_start_runtime;

    UPDATE @extschema@.metric_tables
    SET last_run = CURRENT_TIMESTAMP, last_run_time = v_runtime
    WHERE table_schema = v_row.table_schema
    AND table_name = v_row.table_name;

END LOOP;

PERFORM pg_catalog.pg_advisory_unlock(hashtext('pgmonitor refresh call'));

RETURN;
END
$function$;


-- Restore dropped object privileges
DO $$
DECLARE
v_row   record;
BEGIN
    FOR v_row IN SELECT statement FROM pgmonitor_preserve_privs_temp LOOP
        IF v_row.statement IS NOT NULL THEN
            EXECUTE v_row.statement;
        END IF;
    END LOOP;
END
$$;

DROP TABLE IF EXISTS pgmonitor_preserve_privs_temp;
