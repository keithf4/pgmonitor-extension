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


