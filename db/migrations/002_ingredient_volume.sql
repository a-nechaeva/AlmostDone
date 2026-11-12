-- Nullable density supports ml without assuming that every food has water density.
ALTER TABLE public.ingredients ADD COLUMN grams_per_ml numeric(8,4)
    CHECK (grams_per_ml > 0 AND grams_per_ml < 'Infinity'::numeric);
COMMENT ON COLUMN public.ingredients.grams_per_ml IS
    'Mass in grams per ml; NULL means volume conversion is not supported.';

-- Approximate food-composition densities, FAO/INFOODS v2 (2012), pp. 7, 9, 12.
-- https://www.fao.org/4/ap815e/ap815e.pdf
-- Existing recipe/pack masses and display units are unchanged.
UPDATE public.ingredients AS i SET grams_per_ml = d.grams_per_ml
FROM (VALUES
    ('ing_94735c5d0f98f9bb', 0.92),
    ('ing_69f91741a4c2027f', 1.03),
    ('ing_14a4780585e50d6a', 0.918),
    ('ing_dd786d8ed9d32aff', 0.923),
    ('ing_db84ea5b310b4ac9', 0.96),
    ('ing_816ad581c21510bf', 0.918),
    ('ing_0611a1b7ac680b4a', 1)
) AS d(code, grams_per_ml) WHERE i.code = d.code;
