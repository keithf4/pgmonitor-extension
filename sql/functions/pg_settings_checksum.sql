/*
 * Can't just do a raw check for the hash value since Prometheus only records numeric values for alerts
 * If checksum function returns 0, then NO settings have changed
 * If checksum function returns 1, then something has changed since last known valid state
 * For replicas, logging past settings is not possible to compare what may have changed
 * For replicas, by default, it is expected that its settings will match the primary
 * For replicas, if the pg_settings or pg_hba.conf are necessarily different from the primary, a known good hash of that replica's
    settings can be sent as an argument to the relevant checksum function. Views are provided to easily obtain the hash values used by this monitoring tool.
 * If any known hash parameters are passed to the checksum functions, note that it will override any past hash values stored in the log table when doing comparisons and completely re-evaluate the entire state. This is true even if done on a primary where the current state will then also be logged for comparison if it differs from the given hash.
 */

/**** These hash views are required to exist before the associated functions can be created  ****/
CREATE VIEW @extschema@.pg_settings_hash AS
    WITH settings_ordered_list AS (
        SELECT name
            , COALESCE(setting, '<<NULL>>') AS setting
        FROM pg_catalog.pg_settings
        ORDER BY name, setting)
    SELECT md5(string_agg(name||setting, ',')) AS md5_hash
        , string_agg(name||setting, ',') AS settings_string
    FROM settings_ordered_list;

CREATE FUNCTION @extschema@.pg_settings_checksum(p_known_settings_hash text DEFAULT NULL)
    RETURNS smallint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO pg_catalog, pg_temp
AS $function$
DECLARE

v_is_in_recovery        boolean;
v_settings_hash         text;
v_settings_hash_old     text;
v_settings_match        smallint := 0;
v_settings_string       text;
v_settings_string_old   text;
v_valid                 smallint;

BEGIN

SELECT pg_is_in_recovery() INTO v_is_in_recovery;

SELECT md5_hash
    , settings_string
INTO v_settings_hash
    , v_settings_string
FROM @extschema@.pg_settings_hash;

SELECT settings_hash_generated, valid
INTO v_settings_hash_old, v_valid
FROM @extschema@.pg_settings_checksum
ORDER BY created_at DESC LIMIT 1;

IF p_known_settings_hash IS NOT NULL THEN
    v_settings_hash_old := p_known_settings_hash;
    -- Do not base validity on the stored value if manual hash is given.
    v_valid := 0;
END IF;

IF (v_settings_hash_old IS NOT NULL) THEN

    IF (v_settings_hash != v_settings_hash_old) THEN

        v_valid := 1;

        IF v_is_in_recovery = false THEN
            INSERT INTO @extschema@.pg_settings_checksum (
                    settings_hash_generated
                    , settings_hash_known_provided
                    , settings_string
                    , valid)
            VALUES (
                    v_settings_hash
                    , p_known_settings_hash
                    , v_settings_string
                    , v_valid);
        END IF;
    END IF;

ELSE

    v_valid := 0;
    IF v_is_in_recovery = false THEN
        INSERT INTO @extschema@.pg_settings_checksum (
                settings_hash_generated
                , settings_hash_known_provided
                , settings_string
                , valid)
        VALUES (v_settings_hash
                , p_known_settings_hash
                , v_settings_string
                , v_valid);
    END IF;

END IF;

RETURN v_valid;

END
$function$;
