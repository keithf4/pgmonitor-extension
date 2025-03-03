CREATE VIEW @extschema@.ccp_postmaster_uptime AS
    SELECT extract(epoch from (clock_timestamp() - pg_postmaster_start_time() )) AS seconds;

INSERT INTO @extschema@.metric_views (
    view_name
    , matview_source
    , scope )
VALUES (
   'ccp_postmaster_uptime'
    , false
    , 'global')
ON CONFLICT DO NOTHING;


