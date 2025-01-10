
-- TODO preserve privileges

DROP MATERIALIZED VIEW @extschema@.ccp_table_size;

CREATE FUNCTION @extschema@.ccp_replication_slots() RETURNS TABLE
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

ELSE

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
    FROM @extschema@.ccp_replication_slots();


CREATE MATERIALIZED VIEW @extschema@.ccp_table_size AS
    SELECT current_database() as dbname
    , n.nspname as schemaname
    , c.relname
    , pg_total_relation_size(c.oid) as bytes
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE NOT pg_is_other_temp_schema(n.oid)
    AND relkind IN ('r', 'm', 'f');

