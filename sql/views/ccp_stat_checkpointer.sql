CREATE VIEW @extschema@.ccp_stat_checkpointer AS
    SELECT
        num_timed
        , num_requested
        , write_time
        , sync_time
        , buffers_written
    FROM @extschema@.ccp_stat_checkpointer_func();

INSERT INTO @extschema@.metric_views (
    view_name
    , matview_source
    , scope )
VALUES (
   'ccp_stat_checkpointer'
    , false
    , 'global')
ON CONFLICT DO NOTHING;

