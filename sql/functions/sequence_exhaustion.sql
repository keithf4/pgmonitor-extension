CREATE FUNCTION @extschema@.sequence_exhaustion (p_percent integer DEFAULT 75, OUT count bigint)
    LANGUAGE sql SECURITY DEFINER STABLE
    SET search_path TO pg_catalog, pg_temp
AS $function$

/*
 * Returns count of sequences that have used up the % value given via the p_percent parameter (default 75%)
 */

SELECT count(*) AS count
FROM (
     SELECT CEIL((s.max_value-min_value::NUMERIC+1)/s.increment_by::NUMERIC) AS slots
        , CEIL((COALESCE(s.last_value,s.min_value)-s.min_value::NUMERIC+1)/s.increment_by::NUMERIC) AS used
    FROM pg_catalog.pg_sequences s
) x
WHERE (ROUND(used/slots*100)::int) > p_percent;

$function$;


