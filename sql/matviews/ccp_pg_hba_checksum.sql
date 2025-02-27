CREATE MATERIALIZED VIEW @extschema@.ccp_pg_hba_checksum AS
    SELECT @extschema@.pg_hba_checksum() AS status;
CREATE UNIQUE INDEX ccp_pg_hba_checksum_idx ON @extschema@.ccp_pg_hba_checksum (status);

INSERT INTO @extschema@.metric_matviews (
    view_name
    , run_interval
    , scope )
VALUES (
   'ccp_pg_hba_checksum'
    , '5 minutes'::interval
    , 'global')
ON CONFLICT DO NOTHING;


