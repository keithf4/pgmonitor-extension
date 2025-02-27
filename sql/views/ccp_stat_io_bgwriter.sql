CREATE VIEW @extschema@.ccp_stat_io_bgwriter AS
    SELECT
        writes
        , fsyncs
    FROM @extschema@.ccp_stat_io_bgwriter_func();

INSERT INTO @extschema@.metric_views (
    view_name
    , matview_source
    , scope )
VALUES (
   'ccp_stat_io_bgwriter'
    , false
    , 'global')
ON CONFLICT DO NOTHING;


