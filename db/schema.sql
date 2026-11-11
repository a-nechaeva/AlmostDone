CREATE EXTENSION IF NOT EXISTS citext;    -- регистронезависимый логин

-- 1. Справочники
-- Аллергены
CREATE TABLE allergens (
    id   SERIAL PRIMARY KEY,
    code TEXT UNIQUE NOT NULL CHECK (code ~ '^[a-z][a-z0-9_]*$'), 
    name TEXT NOT NULL CHECK (name <> '' AND name = btrim(name))  
);
CREATE UNIQUE INDEX allergens_name_uq ON allergens (lower(name));
 
-- Категории продуктов
CREATE TABLE categories (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL CHECK (name <> '' AND name = btrim(name))
);
CREATE UNIQUE INDEX categories_name_uq ON categories (lower(name));
 
-- Способы приготовления
CREATE TABLE cooking_methods (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL CHECK (name <> '' AND name = btrim(name))
);
CREATE UNIQUE INDEX cooking_methods_name_uq ON cooking_methods (lower(name));
 
-- Диеты
CREATE TABLE diets (
    id          SERIAL PRIMARY KEY,
    kind        TEXT NOT NULL CHECK (kind IN ('diet', 'pevzner')),
    name        TEXT NOT NULL CHECK (name <> '' AND name = btrim(name)),
    description TEXT,
    UNIQUE (id, kind)                        
);
CREATE UNIQUE INDEX diets_name_uq ON diets (lower(name));
 
-- Ограничения диеты
CREATE TABLE diet_excluded_categories (
    diet_id     INT REFERENCES diets(id)      ON DELETE CASCADE,
    category_id INT REFERENCES categories(id) ON DELETE CASCADE,
    PRIMARY KEY (diet_id, category_id)
);
 
-- Запрещённые способы приготовления
CREATE TABLE diet_excluded_methods (
    diet_id   INT REFERENCES diets(id)           ON DELETE CASCADE,
    method_id INT REFERENCES cooking_methods(id) ON DELETE CASCADE,
    PRIMARY KEY (diet_id, method_id)
);

-- Запрещённые аллергены: диета без глютена запрещает аллерген глютен
CREATE TABLE diet_excluded_allergens (
    diet_id     INT REFERENCES diets(id)     ON DELETE CASCADE,
    allergen_id INT REFERENCES allergens(id) ON DELETE CASCADE,
    PRIMARY KEY (diet_id, allergen_id)
);
 
-- 2. Ингредиенты
CREATE TABLE ingredients (
    id              SERIAL PRIMARY KEY,
    code            TEXT UNIQUE NOT NULL CHECK (code ~ '^[a-z][a-z0-9_]*$'), 
    name            TEXT NOT NULL CHECK (name <> '' AND name = btrim(name)), 
    is_staple       BOOLEAN NOT NULL DEFAULT false,  -- соль, вода, масло есть всегда
    display_unit    TEXT NOT NULL DEFAULT 'g' CHECK (display_unit IN ('g', 'ml', 'pcs')),
    grams_per_piece NUMERIC(8,2) CHECK (grams_per_piece > 0),  -- для штучных
    -- КБЖУ на 100 г
    kcal            NUMERIC(7,2) NOT NULL CHECK (kcal    BETWEEN 0 AND 900), 
    protein         NUMERIC(6,2) NOT NULL CHECK (protein BETWEEN 0 AND 100),
    fat             NUMERIC(6,2) NOT NULL CHECK (fat     BETWEEN 0 AND 100),
    carbs           NUMERIC(6,2) NOT NULL CHECK (carbs   BETWEEN 0 AND 100),
    -- средняя цена упаковки в магазине
    package_g       NUMERIC(8,2)  NOT NULL CHECK (package_g > 0),
    package_price   NUMERIC(10,2) NOT NULL CHECK (package_price >= 0),
    CHECK (protein + fat + carbs <= 100),                          
    CHECK (display_unit <> 'pcs' OR grams_per_piece IS NOT NULL)    -- штучному нужна масса штуки
);
CREATE UNIQUE INDEX ingredients_name_uq ON ingredients (lower(name));  
 
-- Синонимы 
CREATE TABLE ingredient_aliases (
    ingredient_id INT REFERENCES ingredients(id) ON DELETE CASCADE,
    alias         TEXT NOT NULL CHECK (alias <> '' AND alias = btrim(alias)),
    PRIMARY KEY (ingredient_id, alias)
);
CREATE UNIQUE INDEX ingredient_aliases_uq ON ingredient_aliases (ingredient_id, lower(alias));
 
CREATE TABLE ingredient_allergens (
    ingredient_id INT REFERENCES ingredients(id) ON DELETE CASCADE,
    allergen_id   INT REFERENCES allergens(id)   ON DELETE CASCADE,
    PRIMARY KEY (ingredient_id, allergen_id)
);
 
CREATE TABLE ingredient_categories (
    ingredient_id INT REFERENCES ingredients(id) ON DELETE CASCADE,
    category_id   INT REFERENCES categories(id)  ON DELETE CASCADE,
    PRIMARY KEY (ingredient_id, category_id)
);
 
-- 3. Рецепты
CREATE TABLE recipes (
    id              SERIAL PRIMARY KEY,
    title           TEXT NOT NULL CHECK (title <> '' AND title = btrim(title)),
    description     TEXT,
    servings        INT  NOT NULL CHECK (servings > 0),
    cook_time_min   INT  NOT NULL CHECK (cook_time_min >= 0),
    needs_microwave BOOLEAN NOT NULL DEFAULT false,
    needs_stove     BOOLEAN NOT NULL DEFAULT false,
    needs_oven      BOOLEAN NOT NULL DEFAULT false,
    no_cook         BOOLEAN NOT NULL DEFAULT false,
    image_url       TEXT,
    author_id       INT              -- NULL = базовый рецепт (видят все), иначе личный рецепт автора
);
CREATE INDEX recipes_time_idx   ON recipes (cook_time_min);
CREATE INDEX recipes_author_idx ON recipes (author_id);
 
CREATE TABLE recipe_cooking_methods (
    recipe_id INT REFERENCES recipes(id)         ON DELETE CASCADE,
    method_id INT REFERENCES cooking_methods(id) ON DELETE RESTRICT,
    PRIMARY KEY (recipe_id, method_id)
);
 
CREATE TABLE recipe_ingredients (
    recipe_id     INT REFERENCES recipes(id)     ON DELETE CASCADE,
    ingredient_id INT REFERENCES ingredients(id) ON DELETE RESTRICT,
    qty_g         NUMERIC(8,2) CHECK (qty_g > 0),
    is_optional   BOOLEAN NOT NULL DEFAULT false,   -- по вкусу: не докупаем, не скрываем из-за него блюдо, не считаем в КБЖУ
    PRIMARY KEY (recipe_id, ingredient_id)
);
CREATE INDEX recipe_ingredients_ingr_idx ON recipe_ingredients (ingredient_id);
 
CREATE TABLE recipe_steps (
    recipe_id    INT REFERENCES recipes(id) ON DELETE CASCADE,
    step_no      INT NOT NULL CHECK (step_no > 0),
    instruction  TEXT NOT NULL CHECK (btrim(instruction) <> ''),
    duration_min INT CHECK (duration_min > 0),
    PRIMARY KEY (recipe_id, step_no)
);
 
-- 4. Пользователь
CREATE TABLE users (
    id              SERIAL PRIMARY KEY,
    login           CITEXT UNIQUE NOT NULL CHECK (login ~ '^[A-Za-z0-9_.-]{3,32}$'), 
    password_hash   TEXT NOT NULL,      
    pevzner_diet_id INT,
    pevzner_kind    TEXT NOT NULL DEFAULT 'pevzner' CHECK (pevzner_kind = 'pevzner'),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (pevzner_diet_id, pevzner_kind) REFERENCES diets(id, kind)
        ON DELETE SET NULL (pevzner_diet_id)
);
 
ALTER TABLE recipes ADD CONSTRAINT recipes_author_fk
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE;
 
CREATE TABLE user_allergens (
    user_id     INT REFERENCES users(id)     ON DELETE CASCADE,
    allergen_id INT REFERENCES allergens(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, allergen_id)
);
 
CREATE TABLE user_diets (
    user_id   INT REFERENCES users(id) ON DELETE CASCADE,
    diet_id   INT NOT NULL,
    diet_kind TEXT NOT NULL DEFAULT 'diet' CHECK (diet_kind = 'diet'),
    PRIMARY KEY (user_id, diet_id),
    FOREIGN KEY (diet_id, diet_kind) REFERENCES diets(id, kind) ON DELETE CASCADE
);
 
CREATE TABLE user_pantry (
    user_id       INT REFERENCES users(id)       ON DELETE CASCADE,
    ingredient_id INT REFERENCES ingredients(id) ON DELETE CASCADE,
    qty_g         NUMERIC(8,2) CHECK (qty_g >= 0),
    PRIMARY KEY (user_id, ingredient_id)
);
 
CREATE TABLE favorite_recipes (
    user_id   INT REFERENCES users(id)   ON DELETE CASCADE,
    recipe_id INT REFERENCES recipes(id) ON DELETE CASCADE,
    added_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, recipe_id)
);

CREATE FUNCTION check_favorite_recipe_access() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM recipes
               WHERE id = NEW.recipe_id
                 AND author_id IS NOT NULL AND author_id <> NEW.user_id) THEN
        RAISE EXCEPTION 'рецепт % — чужой личный рецепт', NEW.recipe_id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER favorite_recipes_access BEFORE INSERT OR UPDATE ON favorite_recipes
    FOR EACH ROW EXECUTE FUNCTION check_favorite_recipe_access();
 
CREATE TABLE favorite_ingredients (
    user_id       INT REFERENCES users(id)       ON DELETE CASCADE,
    ingredient_id INT REFERENCES ingredients(id) ON DELETE CASCADE,
    added_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, ingredient_id)
);
 
-- 5. Представления: метрики блюда
CREATE VIEW recipe_nutrition AS
SELECT r.id AS recipe_id,
       ROUND(SUM(i.kcal    * ri.qty_g / 100) / r.servings, 1) AS kcal,
       ROUND(SUM(i.protein * ri.qty_g / 100) / r.servings, 1) AS protein,
       ROUND(SUM(i.fat     * ri.qty_g / 100) / r.servings, 1) AS fat,
       ROUND(SUM(i.carbs   * ri.qty_g / 100) / r.servings, 1) AS carbs
FROM recipes r
JOIN recipe_ingredients ri ON ri.recipe_id = r.id
JOIN ingredients i         ON i.id = ri.ingredient_id
WHERE NOT ri.is_optional
GROUP BY r.id, r.servings;

CREATE VIEW recipe_allergens AS
SELECT DISTINCT ri.recipe_id, ia.allergen_id
FROM recipe_ingredients ri
JOIN ingredient_allergens ia USING (ingredient_id)
WHERE NOT ri.is_optional;

CREATE VIEW recipe_categories AS
SELECT DISTINCT ri.recipe_id, ic.category_id
FROM recipe_ingredients ri
JOIN ingredient_categories ic USING (ingredient_id)
WHERE NOT ri.is_optional;
 
CREATE VIEW user_all_diets AS
SELECT user_id, diet_id FROM user_diets
UNION
SELECT id, pevzner_diet_id FROM users WHERE pevzner_diet_id IS NOT NULL;
 
CREATE VIEW user_recipe_visibility AS
WITH flags AS (
    SELECT u.id AS user_id, r.id AS recipe_id,
           COALESCE((SELECT array_agg(DISTINCT a.name ORDER BY a.name)
                     FROM recipe_allergens ra
                     JOIN user_allergens ua ON ua.allergen_id = ra.allergen_id
                     JOIN allergens a       ON a.id = ra.allergen_id
                     WHERE ra.recipe_id = r.id AND ua.user_id = u.id),
                    '{}') AS user_allergens_in_dish,
           COALESCE((SELECT array_agg(DISTINCT d.name ORDER BY d.name)
                     FROM user_all_diets ud
                     JOIN diets d ON d.id = ud.diet_id
                     WHERE ud.user_id = u.id
                       AND (EXISTS (SELECT 1 FROM recipe_categories rc
                                    JOIN diet_excluded_categories x ON x.category_id = rc.category_id
                                    WHERE rc.recipe_id = r.id AND x.diet_id = d.id)
                         OR EXISTS (SELECT 1 FROM recipe_allergens ra
                                    JOIN diet_excluded_allergens x ON x.allergen_id = ra.allergen_id
                                    WHERE ra.recipe_id = r.id AND x.diet_id = d.id)
                         OR EXISTS (SELECT 1 FROM recipe_cooking_methods rm
                                    JOIN diet_excluded_methods x ON x.method_id = rm.method_id
                                    WHERE rm.recipe_id = r.id AND x.diet_id = d.id))),
                    '{}') AS violated_diets,
           COALESCE((SELECT array_agg(DISTINCT i.name ORDER BY i.name)
                     FROM recipe_ingredients ri
                     JOIN ingredients i ON i.id = ri.ingredient_id
                     WHERE ri.recipe_id = r.id AND ri.is_optional
                       AND (EXISTS (SELECT 1 FROM ingredient_allergens ia
                                    JOIN user_allergens ua ON ua.allergen_id = ia.allergen_id
                                    WHERE ia.ingredient_id = i.id AND ua.user_id = u.id)
                         OR EXISTS (SELECT 1 FROM ingredient_categories ic
                                    JOIN diet_excluded_categories x ON x.category_id = ic.category_id
                                    JOIN user_all_diets ud ON ud.diet_id = x.diet_id
                                    WHERE ic.ingredient_id = i.id AND ud.user_id = u.id)
                         OR EXISTS (SELECT 1 FROM ingredient_allergens ia
                                    JOIN diet_excluded_allergens x ON x.allergen_id = ia.allergen_id
                                    JOIN user_all_diets ud ON ud.diet_id = x.diet_id
                                    WHERE ia.ingredient_id = i.id AND ud.user_id = u.id))),
                    '{}') AS skip_optional
    FROM users u CROSS JOIN recipes r
    WHERE r.author_id IS NULL OR r.author_id = u.id
)
SELECT f.*,
       (cardinality(user_allergens_in_dish) > 0
        OR cardinality(violated_diets) > 0) AS is_hidden
FROM flags f;
-- 6. Server accounts, sessions and persistent API state (001_server_state).
BEGIN;
SET LOCAL search_path = public, pg_catalog;

CREATE TABLE api_schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Provider subject is opaque and case-sensitive. Never store OAuth tokens here.
CREATE TABLE user_identities (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider ~ '^[a-z][a-z0-9_]*$'),
    provider_subject TEXT NOT NULL CHECK (provider_subject <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_subject)
);
CREATE INDEX user_identities_user_idx ON user_identities (user_id);

-- One session is one login; all token rotations belong to the same session.
-- UUIDs are generated by the application, without extra PostgreSQL extensions.
CREATE TABLE auth_sessions (
    id UUID PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    CHECK (expires_at > created_at),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX auth_sessions_user_idx ON auth_sessions (user_id);
CREATE INDEX auth_sessions_expiry_idx ON auth_sessions (expires_at);

-- One row per issued pair. Retain used refresh hashes until the session expires
-- so reuse can revoke the whole session, including its newest tokens.
CREATE TABLE auth_tokens (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES auth_sessions(id) ON DELETE CASCADE,
    access_token_hash TEXT NOT NULL UNIQUE CHECK (access_token_hash ~ '^[0-9a-f]{64}$'),
    refresh_token_hash TEXT NOT NULL UNIQUE CHECK (refresh_token_hash ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    access_expires_at TIMESTAMPTZ NOT NULL,
    refresh_expires_at TIMESTAMPTZ NOT NULL,
    refresh_used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    CHECK (access_expires_at > created_at),
    -- Access may outlive refresh near the session's absolute refresh deadline.
    CONSTRAINT auth_tokens_refresh_lifetime_check CHECK (refresh_expires_at > created_at),
    CHECK (refresh_used_at IS NULL OR refresh_used_at >= created_at),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX auth_tokens_session_idx ON auth_tokens (session_id);
CREATE INDEX auth_tokens_expiry_idx ON auth_tokens (refresh_expires_at);

-- Existing SQL tables remain the source of truth for pantry, diets and favorites.
-- pantry_display preserves original API units/amounts alongside user_pantry.qty_g.
CREATE TABLE user_api_state (
    user_id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    state_version BIGINT NOT NULL DEFAULT 0 CHECK (state_version >= 0),
    diabetes BOOLEAN NOT NULL DEFAULT false,
    pantry_display JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(pantry_display) = 'object'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Detect changes to domain tables made by other SQL clients.
    state_hash TEXT CHECK (state_hash IS NULL OR state_hash ~ '^[0-9a-f]{64}$')
);
INSERT INTO user_api_state (user_id) SELECT id FROM users;

-- Store the existing Result representation (data and version).
-- The application must write this row in the SAME transaction as the mutation.
CREATE TABLE api_idempotency (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scope TEXT NOT NULL CHECK (scope <> ''),
    idempotency_key TEXT NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
    request_hash TEXT NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
    result JSONB NOT NULL CHECK (jsonb_typeof(result) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, scope, idempotency_key),
    CHECK (expires_at > created_at)
);
CREATE INDEX api_idempotency_expiry_idx ON api_idempotency (expires_at);

-- JSON representations of short-lived resources, never images or raw tokens.
-- The application is responsible for serializing engine models to JSON.
CREATE TABLE api_resources (
    id UUID PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('snapshot', 'cursor', 'recognition')),
    body JSONB NOT NULL CHECK (jsonb_typeof(body) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    CHECK (expires_at > created_at)
);
CREATE INDEX api_resources_user_idx ON api_resources (user_id, kind);
CREATE INDEX api_resources_expiry_idx ON api_resources (expires_at);

-- Independent of api_resources: deleting an expired recognition must not delete
-- its import marker. Record this together with the pantry mutation.
CREATE TABLE recognition_imports (
    recognition_id UUID PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    operation_id UUID NOT NULL UNIQUE,
    imported_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX recognition_imports_user_idx ON recognition_imports (user_id);

INSERT INTO api_schema_migrations (version) VALUES ('001_server_state');
COMMIT;
