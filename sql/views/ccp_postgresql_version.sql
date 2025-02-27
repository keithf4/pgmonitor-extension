CREATE VIEW @extschema@.ccp_postgresql_version AS
    SELECT current_setting('server_version_num')::int AS current;

INSERT INTO @extschema@.metric_views (
    view_name
    , matview_source
    , scope )
VALUES (
   'ccp_postgresql_version'
    , false
    , 'global')
ON CONFLICT DO NOTHING;


