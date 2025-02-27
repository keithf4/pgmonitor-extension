CREATE MATERIALIZED VIEW @extschema@.ccp_pg_settings_checksum AS
    SELECT @extschema@.pg_settings_checksum() AS status;
CREATE UNIQUE INDEX ccp_pg_settings_checksum_idx ON @extschema@.ccp_pg_settings_checksum (status);

INSERT INTO @extschema@.metric_matviews (
    view_name
    , run_interval
    , scope )
VALUES (
   'ccp_pg_settings_checksum'
    , '5 minutes'::interval
    , 'global')
ON CONFLICT DO NOTHING;


