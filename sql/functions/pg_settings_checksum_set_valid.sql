CREATE FUNCTION @extschema@.pg_settings_checksum_set_valid() RETURNS smallint
    LANGUAGE sql
AS $function$
/*
 * This function provides quick, clear interface for resetting the checksum monitor to treat the currently detected configuration as valid after alerting on a change. Note that configuration history will be cleared.
 */
TRUNCATE @extschema@.pg_settings_checksum;

SELECT @extschema@.pg_settings_checksum();

$function$;

