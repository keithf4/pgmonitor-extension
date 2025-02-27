CREATE VIEW @extschema@.ccp_replication_slots AS
    SELECT slot_name
        , active
        , retained_bytes
        , database
        , slot_type
        , conflicting
        , failover
        , synced
    FROM @extschema@.ccp_replication_slots_func();

INSERT INTO @extschema@.metric_views (
    view_name
    , matview_source
    , scope )
VALUES (
   'ccp_replication_slots'
    , false
    , 'global')
ON CONFLICT DO NOTHING;


