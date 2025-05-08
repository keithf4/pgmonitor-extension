
DROP VIEW @extschema@.pg_settings_hash;
DROP FUNCTION @extschema@.pg_settings_checksum(text);
DROP FUNCTION @extschema@.pg_settings_checksum_set_valid();
DROP MATERIALIZED VIEW @extschema@.ccp_pg_settings_checksum;
DELETE FROM @extschema@.metric_matviews WHERE view_name = 'ccp_pg_settings_checksum';
DROP TABLE @extschema@.pg_settings_checksum;

