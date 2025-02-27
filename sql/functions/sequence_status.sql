CREATE FUNCTION @extschema@.sequence_status() RETURNS TABLE (sequence_name text, last_value bigint, slots numeric, used numeric, percent int, cycle boolean, numleft numeric, table_usage text)
    LANGUAGE sql SECURITY DEFINER STABLE
    SET search_path TO pg_catalog, pg_temp
AS $function$

/*
 * Provide detailed status information of sequences in the current database
 */

WITH default_value_sequences AS (
    -- Get sequences defined as default values with related table
    -- Note this subquery can be locked/hung by DDL that affects tables with sequences.
    --  Use @extschema@.sequence_exhaustion() to actually monitor for sequences running out
    SELECT s.seqrelid, c.oid
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_attrdef ad on (ad.adrelid,ad.adnum) = (a.attrelid,a.attnum)
    JOIN pg_catalog.pg_class c on a.attrelid = c.oid
    JOIN pg_catalog.pg_sequence s ON s.seqrelid = regexp_replace(pg_get_expr(ad.adbin,ad.adrelid), $re$^nextval\('(.+?)'::regclass\)$$re$, $re$\1$re$)::regclass
    WHERE (pg_get_expr(ad.adbin,ad.adrelid)) ~ '^nextval\('
), dep_sequences AS (
    -- Get sequences set as dependencies with related tables (identities)
    SELECT s.seqrelid, c.oid
    FROM pg_catalog.pg_sequence s
    JOIN pg_catalog.pg_depend d ON s.seqrelid = d.objid
    JOIN pg_catalog.pg_class c ON d.refobjid = c.oid
    UNION
    SELECT seqrelid, oid FROM default_value_sequences
), all_sequences AS (
    -- Get any remaining sequences
    SELECT s.seqrelid AS sequence_oid, ds.oid AS table_oid
    FROM pg_catalog.pg_sequence s
    LEFT JOIN dep_sequences ds ON s.seqrelid = ds.seqrelid
)
SELECT sequence_name
    , last_value
    , slots
    , used
    , ROUND(used/slots*100)::int AS percent
    , cycle
    , CASE WHEN slots < used THEN 0 ELSE slots - used END AS numleft
    , table_usage
FROM (
     SELECT format('%I.%I',s.schemaname, s.sequencename)::text AS sequence_name
        , COALESCE(s.last_value,s.min_value) AS last_value
        , s.cycle
        , CEIL((s.max_value-min_value::NUMERIC+1)/s.increment_by::NUMERIC) AS slots
        , CEIL((COALESCE(s.last_value,s.min_value)-s.min_value::NUMERIC+1)/s.increment_by::NUMERIC) AS used
        , string_agg(a.table_oid::regclass::text, ', ') AS table_usage
    FROM pg_catalog.pg_sequences s
    JOIN all_sequences a ON (format('%I.%I', s.schemaname, s.sequencename))::regclass = a.sequence_oid
    GROUP BY 1,2,3,4,5
) x
ORDER BY ROUND(used/slots*100) DESC

$function$;


