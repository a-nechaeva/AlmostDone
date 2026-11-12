-- Transactional invalidation: rolled-back writes must not invalidate snapshots.
CREATE TABLE public.catalog_revision (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    revision bigint NOT NULL DEFAULT 0
);
INSERT INTO public.catalog_revision(singleton, revision) VALUES (true, 0);

CREATE FUNCTION public.bump_catalog_revision() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
    UPDATE public.catalog_revision SET revision = revision + 1 WHERE singleton;
    -- Identical notifications coalesce per transaction; delivery follows COMMIT.
    PERFORM pg_catalog.pg_notify('almostdone_catalog_changed', '');
    RETURN NULL;
END;
$$;

-- Statement triggers also cover bulk imports, deletes and TRUNCATE.
DO $$
DECLARE
    relation_name text;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY[
        'ingredients', 'ingredient_aliases', 'ingredient_allergens', 'allergens',
        'recipes', 'recipe_ingredients', 'recipe_steps',
        'cooking_methods', 'recipe_cooking_methods'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER invalidate_catalog AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.%I '
            'FOR EACH STATEMENT EXECUTE FUNCTION public.bump_catalog_revision()', relation_name
        );
    END LOOP;
END;
$$;
