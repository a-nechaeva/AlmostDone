-- The three trigger functions looked tables up through the caller's search_path.
-- pg_dump writes data with an empty search_path, so a data-only dump of this
-- database could not be restored: COPY into recipe_cooking_methods fired
-- check_no_cook_methods() and failed with "relation "recipes" does not exist".
-- The functions now carry their own search_path. A function that is absent is skipped.
DO $$
DECLARE
    signature text;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.check_favorite_recipe_access()',
        'public.check_no_cook_methods()',
        'public.check_recipe_no_cook_flip()'
    ] LOOP
        IF to_regprocedure(signature) IS NOT NULL THEN
            EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_catalog', signature);
        END IF;
    END LOOP;
END;
$$;
