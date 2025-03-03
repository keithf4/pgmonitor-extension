CREATE FUNCTION @extschema@.pgbackrest_info()
    RETURNS SETOF @extschema@.pgbackrest_info
    LANGUAGE plpgsql
    SET search_path TO pg_catalog, pg_temp
AS $function$
DECLARE

v_gather_timestamp      timestamptz;
v_system_identifier     bigint;

BEGIN
-- Get pgBackRest info in JSON format

-- TODO See if the shell script can be further pulled into this function more and maybe get rid of it

IF pg_catalog.pg_is_in_recovery() = 'f' THEN

    -- Ensure table is empty
    DELETE FROM @extschema@.pgbackrest_info;

    SELECT system_identifier into v_system_identifier FROM pg_control_system();

    -- Copy data into the table directory from the pgBackRest into command
    EXECUTE format( $cmd$ COPY @extschema@.pgbackrest_info (config_file, data) FROM program '/usr/bin/pgbackrest-info.sh %s' WITH (format text,DELIMITER '|') $cmd$, v_system_identifier::text );

END IF;

RETURN QUERY SELECT * FROM @extschema@.pgbackrest_info;

IF NOT FOUND THEN
    RAISE EXCEPTION 'No backups being returned from pgbackrest info command';
END IF;

END
$function$;


