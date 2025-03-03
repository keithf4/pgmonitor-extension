CREATE MATERIALIZED VIEW @extschema@.ccp_database_size_matview AS
    SELECT datname as dbname
    , pg_catalog.pg_database_size(datname) as bytes
    FROM pg_catalog.pg_database
    WHERE datistemplate = false;
CREATE UNIQUE INDEX ccp_database_size_matview_idx ON @extschema@.ccp_database_size_matview (dbname);

INSERT INTO @extschema@.metric_matviews (
    view_name)
VALUES (
    'ccp_database_size_matview')
ON CONFLICT DO NOTHING;

