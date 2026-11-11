--
-- PostgreSQL database dump
--

-- Dumped from database version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)
-- Dumped by pg_dump version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: check_favorite_recipe_access(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_favorite_recipe_access() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM recipes
               WHERE id = NEW.recipe_id
                 AND author_id IS NOT NULL AND author_id <> NEW.user_id) THEN
        RAISE EXCEPTION 'рецепт % — чужой личный рецепт', NEW.recipe_id;
    END IF;
    RETURN NEW;
END $$;


--
-- Name: check_no_cook_methods(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_no_cook_methods() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (SELECT no_cook FROM recipes WHERE id = NEW.recipe_id) THEN
    IF NEW.method_id <> 4 THEN
      RAISE EXCEPTION 'no_cook рецепт % не может иметь method_id=%',
        NEW.recipe_id, NEW.method_id;
    END IF;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: check_recipe_no_cook_flip(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_recipe_no_cook_flip() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.no_cook AND EXISTS (
       SELECT 1 FROM recipe_cooking_methods
       WHERE recipe_id = NEW.id AND method_id <> 4) THEN
    RAISE EXCEPTION 'нельзя сделать рецепт % no_cook: есть method_id<>4', NEW.id;
  END IF;
  RETURN NEW;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: allergens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.allergens (
    id integer NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    CONSTRAINT allergens_code_check CHECK ((code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT allergens_name_check CHECK (((name <> ''::text) AND (name = btrim(name))))
);


--
-- Name: allergens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.allergens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: allergens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.allergens_id_seq OWNED BY public.allergens.id;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id integer NOT NULL,
    name text NOT NULL,
    CONSTRAINT categories_name_check CHECK (((name <> ''::text) AND (name = btrim(name))))
);


--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: cooking_methods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cooking_methods (
    id integer NOT NULL,
    name text NOT NULL,
    CONSTRAINT cooking_methods_name_check CHECK (((name <> ''::text) AND (name = btrim(name))))
);


--
-- Name: cooking_methods_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cooking_methods_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cooking_methods_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cooking_methods_id_seq OWNED BY public.cooking_methods.id;


--
-- Name: diet_excluded_allergens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.diet_excluded_allergens (
    diet_id integer NOT NULL,
    allergen_id integer NOT NULL
);


--
-- Name: diet_excluded_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.diet_excluded_categories (
    diet_id integer NOT NULL,
    category_id integer NOT NULL
);


--
-- Name: diet_excluded_methods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.diet_excluded_methods (
    diet_id integer NOT NULL,
    method_id integer NOT NULL
);


--
-- Name: diets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.diets (
    id integer NOT NULL,
    kind text NOT NULL,
    name text NOT NULL,
    description text,
    CONSTRAINT diets_kind_check CHECK ((kind = ANY (ARRAY['diet'::text, 'pevzner'::text]))),
    CONSTRAINT diets_name_check CHECK (((name <> ''::text) AND (name = btrim(name))))
);


--
-- Name: diets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.diets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: diets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.diets_id_seq OWNED BY public.diets.id;


--
-- Name: favorite_ingredients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favorite_ingredients (
    user_id integer NOT NULL,
    ingredient_id integer NOT NULL,
    added_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: favorite_recipes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favorite_recipes (
    user_id integer NOT NULL,
    recipe_id integer NOT NULL,
    added_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ingredient_aliases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingredient_aliases (
    ingredient_id integer NOT NULL,
    alias text NOT NULL,
    CONSTRAINT ingredient_aliases_alias_check CHECK (((alias <> ''::text) AND (alias = btrim(alias))))
);


--
-- Name: ingredient_allergens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingredient_allergens (
    ingredient_id integer NOT NULL,
    allergen_id integer NOT NULL
);


--
-- Name: ingredient_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingredient_categories (
    ingredient_id integer NOT NULL,
    category_id integer NOT NULL
);


--
-- Name: ingredients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingredients (
    id integer NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    is_staple boolean DEFAULT false NOT NULL,
    display_unit text DEFAULT 'g'::text NOT NULL,
    grams_per_piece numeric(8,2),
    kcal numeric(7,2) NOT NULL,
    protein numeric(6,2) NOT NULL,
    fat numeric(6,2) NOT NULL,
    carbs numeric(6,2) NOT NULL,
    package_g numeric(8,2) NOT NULL,
    package_price numeric(10,2) NOT NULL,
    CONSTRAINT ingredients_carbs_check CHECK (((carbs >= (0)::numeric) AND (carbs <= (100)::numeric))),
    CONSTRAINT ingredients_check CHECK ((((protein + fat) + carbs) <= (100)::numeric)),
    CONSTRAINT ingredients_check1 CHECK (((display_unit <> 'pcs'::text) OR (grams_per_piece IS NOT NULL))),
    CONSTRAINT ingredients_code_check CHECK ((code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT ingredients_display_unit_check CHECK ((display_unit = ANY (ARRAY['g'::text, 'ml'::text, 'pcs'::text]))),
    CONSTRAINT ingredients_fat_check CHECK (((fat >= (0)::numeric) AND (fat <= (100)::numeric))),
    CONSTRAINT ingredients_grams_per_piece_check CHECK ((grams_per_piece > (0)::numeric)),
    CONSTRAINT ingredients_kcal_check CHECK (((kcal >= (0)::numeric) AND (kcal <= (900)::numeric))),
    CONSTRAINT ingredients_name_check CHECK (((name <> ''::text) AND (name = btrim(name)))),
    CONSTRAINT ingredients_package_g_check CHECK ((package_g > (0)::numeric)),
    CONSTRAINT ingredients_package_price_check CHECK ((package_price >= (0)::numeric)),
    CONSTRAINT ingredients_protein_check CHECK (((protein >= (0)::numeric) AND (protein <= (100)::numeric)))
);


--
-- Name: ingredients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ingredients_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ingredients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ingredients_id_seq OWNED BY public.ingredients.id;


--
-- Name: recipe_ingredients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recipe_ingredients (
    recipe_id integer NOT NULL,
    ingredient_id integer NOT NULL,
    qty_g numeric(8,2),
    is_optional boolean DEFAULT false NOT NULL,
    CONSTRAINT recipe_ingredients_qty_g_check CHECK (((qty_g > (0)::numeric) OR (qty_g IS NULL))),
    CONSTRAINT recipe_ingredients_required_has_qty CHECK ((is_optional OR (qty_g IS NOT NULL)))
);


--
-- Name: recipe_allergens; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.recipe_allergens AS
 SELECT DISTINCT ri.recipe_id,
    ia.allergen_id
   FROM (public.recipe_ingredients ri
     JOIN public.ingredient_allergens ia USING (ingredient_id))
  WHERE (NOT ri.is_optional);


--
-- Name: recipe_categories; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.recipe_categories AS
 SELECT DISTINCT ri.recipe_id,
    ic.category_id
   FROM (public.recipe_ingredients ri
     JOIN public.ingredient_categories ic USING (ingredient_id))
  WHERE (NOT ri.is_optional);


--
-- Name: recipe_cooking_methods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recipe_cooking_methods (
    recipe_id integer NOT NULL,
    method_id integer NOT NULL
);


--
-- Name: recipes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recipes (
    id integer NOT NULL,
    title text NOT NULL,
    description text,
    servings integer NOT NULL,
    cook_time_min integer NOT NULL,
    needs_microwave boolean DEFAULT false NOT NULL,
    needs_stove boolean DEFAULT false NOT NULL,
    needs_oven boolean DEFAULT false NOT NULL,
    image_url text,
    author_id integer,
    no_cook boolean DEFAULT false NOT NULL,
    CONSTRAINT recipes_cook_time_min_check CHECK ((cook_time_min >= 0)),
    CONSTRAINT recipes_no_cook_no_equipment CHECK (((NOT no_cook) OR ((NOT needs_stove) AND (NOT needs_oven) AND (NOT needs_microwave)))),
    CONSTRAINT recipes_servings_check CHECK ((servings > 0)),
    CONSTRAINT recipes_title_check CHECK (((title <> ''::text) AND (title = btrim(title))))
);


--
-- Name: recipe_nutrition; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.recipe_nutrition AS
 SELECT r.id AS recipe_id,
    round((sum(((i.kcal * ri.qty_g) / (100)::numeric)) / (r.servings)::numeric), 1) AS kcal,
    round((sum(((i.protein * ri.qty_g) / (100)::numeric)) / (r.servings)::numeric), 1) AS protein,
    round((sum(((i.fat * ri.qty_g) / (100)::numeric)) / (r.servings)::numeric), 1) AS fat,
    round((sum(((i.carbs * ri.qty_g) / (100)::numeric)) / (r.servings)::numeric), 1) AS carbs,
    ((count(ri.recipe_id) > 0) AND (count(*) FILTER (WHERE ((ri.recipe_id IS NOT NULL) AND (ri.qty_g IS NULL))) = 0)) AS complete
   FROM ((public.recipes r
     LEFT JOIN public.recipe_ingredients ri ON (((ri.recipe_id = r.id) AND (NOT ri.is_optional))))
     LEFT JOIN public.ingredients i ON ((i.id = ri.ingredient_id)))
  GROUP BY r.id, r.servings;


--
-- Name: recipe_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recipe_steps (
    recipe_id integer NOT NULL,
    step_no integer NOT NULL,
    instruction text NOT NULL,
    duration_min integer,
    CONSTRAINT recipe_steps_duration_min_check CHECK ((duration_min > 0)),
    CONSTRAINT recipe_steps_instruction_check CHECK ((btrim(instruction) <> ''::text)),
    CONSTRAINT recipe_steps_step_no_check CHECK ((step_no > 0))
);


--
-- Name: recipes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recipes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recipes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recipes_id_seq OWNED BY public.recipes.id;


--
-- Name: user_diets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_diets (
    user_id integer NOT NULL,
    diet_id integer NOT NULL,
    diet_kind text DEFAULT 'diet'::text NOT NULL,
    CONSTRAINT user_diets_diet_kind_check CHECK ((diet_kind = 'diet'::text))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    login public.citext NOT NULL,
    password_hash text NOT NULL,
    pevzner_diet_id integer,
    pevzner_kind text DEFAULT 'pevzner'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT users_login_check CHECK ((login OPERATOR(public.~) '^[A-Za-z0-9_.-]{3,32}$'::public.citext)),
    CONSTRAINT users_pevzner_kind_check CHECK ((pevzner_kind = 'pevzner'::text))
);


--
-- Name: user_all_diets; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.user_all_diets AS
 SELECT user_diets.user_id,
    user_diets.diet_id
   FROM public.user_diets
UNION
 SELECT users.id AS user_id,
    users.pevzner_diet_id AS diet_id
   FROM public.users
  WHERE (users.pevzner_diet_id IS NOT NULL);


--
-- Name: user_allergens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_allergens (
    user_id integer NOT NULL,
    allergen_id integer NOT NULL
);


--
-- Name: user_pantry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_pantry (
    user_id integer NOT NULL,
    ingredient_id integer NOT NULL,
    qty_g numeric(8,2),
    CONSTRAINT user_pantry_qty_g_check CHECK ((qty_g >= (0)::numeric))
);


--
-- Name: user_recipe_visibility; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.user_recipe_visibility AS
 WITH flags AS (
         SELECT u.id AS user_id,
            r.id AS recipe_id,
            COALESCE(( SELECT array_agg(DISTINCT a.name ORDER BY a.name) AS array_agg
                   FROM ((public.recipe_allergens ra
                     JOIN public.user_allergens ua ON ((ua.allergen_id = ra.allergen_id)))
                     JOIN public.allergens a ON ((a.id = ra.allergen_id)))
                  WHERE ((ra.recipe_id = r.id) AND (ua.user_id = u.id))), '{}'::text[]) AS user_allergens_in_dish,
            COALESCE(( SELECT array_agg(DISTINCT d.name ORDER BY d.name) AS array_agg
                   FROM (public.user_all_diets ud
                     JOIN public.diets d ON ((d.id = ud.diet_id)))
                  WHERE ((ud.user_id = u.id) AND ((EXISTS ( SELECT 1
                           FROM (public.recipe_categories rc
                             JOIN public.diet_excluded_categories x ON ((x.category_id = rc.category_id)))
                          WHERE ((rc.recipe_id = r.id) AND (x.diet_id = d.id)))) OR (EXISTS ( SELECT 1
                           FROM (public.recipe_allergens ra
                             JOIN public.diet_excluded_allergens x ON ((x.allergen_id = ra.allergen_id)))
                          WHERE ((ra.recipe_id = r.id) AND (x.diet_id = d.id)))) OR (EXISTS ( SELECT 1
                           FROM (public.recipe_cooking_methods rm
                             JOIN public.diet_excluded_methods x ON ((x.method_id = rm.method_id)))
                          WHERE ((rm.recipe_id = r.id) AND (x.diet_id = d.id))))))), '{}'::text[]) AS violated_diets,
            COALESCE(( SELECT array_agg(DISTINCT i.name ORDER BY i.name) AS array_agg
                   FROM (public.recipe_ingredients ri
                     JOIN public.ingredients i ON ((i.id = ri.ingredient_id)))
                  WHERE ((ri.recipe_id = r.id) AND ri.is_optional AND ((EXISTS ( SELECT 1
                           FROM (public.ingredient_allergens ia
                             JOIN public.user_allergens ua ON ((ua.allergen_id = ia.allergen_id)))
                          WHERE ((ia.ingredient_id = i.id) AND (ua.user_id = u.id)))) OR (EXISTS ( SELECT 1
                           FROM ((public.ingredient_categories ic
                             JOIN public.diet_excluded_categories x ON ((x.category_id = ic.category_id)))
                             JOIN public.user_all_diets ud ON ((ud.diet_id = x.diet_id)))
                          WHERE ((ic.ingredient_id = i.id) AND (ud.user_id = u.id)))) OR (EXISTS ( SELECT 1
                           FROM ((public.ingredient_allergens ia
                             JOIN public.diet_excluded_allergens x ON ((x.allergen_id = ia.allergen_id)))
                             JOIN public.user_all_diets ud ON ((ud.diet_id = x.diet_id)))
                          WHERE ((ia.ingredient_id = i.id) AND (ud.user_id = u.id))))))), '{}'::text[]) AS skip_optional
           FROM (public.users u
             CROSS JOIN public.recipes r)
          WHERE ((r.author_id IS NULL) OR (r.author_id = u.id))
        )
 SELECT user_id,
    recipe_id,
    user_allergens_in_dish,
    violated_diets,
    skip_optional,
    ((cardinality(user_allergens_in_dish) > 0) OR (cardinality(violated_diets) > 0)) AS is_hidden
   FROM flags f;


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: allergens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.allergens ALTER COLUMN id SET DEFAULT nextval('public.allergens_id_seq'::regclass);


--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: cooking_methods id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cooking_methods ALTER COLUMN id SET DEFAULT nextval('public.cooking_methods_id_seq'::regclass);


--
-- Name: diets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diets ALTER COLUMN id SET DEFAULT nextval('public.diets_id_seq'::regclass);


--
-- Name: ingredients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredients ALTER COLUMN id SET DEFAULT nextval('public.ingredients_id_seq'::regclass);


--
-- Name: recipes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipes ALTER COLUMN id SET DEFAULT nextval('public.recipes_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: allergens allergens_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.allergens
    ADD CONSTRAINT allergens_code_key UNIQUE (code);


--
-- Name: allergens allergens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.allergens
    ADD CONSTRAINT allergens_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: cooking_methods cooking_methods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cooking_methods
    ADD CONSTRAINT cooking_methods_pkey PRIMARY KEY (id);


--
-- Name: diet_excluded_allergens diet_excluded_allergens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_allergens
    ADD CONSTRAINT diet_excluded_allergens_pkey PRIMARY KEY (diet_id, allergen_id);


--
-- Name: diet_excluded_categories diet_excluded_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_categories
    ADD CONSTRAINT diet_excluded_categories_pkey PRIMARY KEY (diet_id, category_id);


--
-- Name: diet_excluded_methods diet_excluded_methods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_methods
    ADD CONSTRAINT diet_excluded_methods_pkey PRIMARY KEY (diet_id, method_id);


--
-- Name: diets diets_id_kind_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diets
    ADD CONSTRAINT diets_id_kind_key UNIQUE (id, kind);


--
-- Name: diets diets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diets
    ADD CONSTRAINT diets_pkey PRIMARY KEY (id);


--
-- Name: favorite_ingredients favorite_ingredients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_ingredients
    ADD CONSTRAINT favorite_ingredients_pkey PRIMARY KEY (user_id, ingredient_id);


--
-- Name: favorite_recipes favorite_recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_recipes
    ADD CONSTRAINT favorite_recipes_pkey PRIMARY KEY (user_id, recipe_id);


--
-- Name: ingredient_aliases ingredient_aliases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_aliases
    ADD CONSTRAINT ingredient_aliases_pkey PRIMARY KEY (ingredient_id, alias);


--
-- Name: ingredient_allergens ingredient_allergens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_allergens
    ADD CONSTRAINT ingredient_allergens_pkey PRIMARY KEY (ingredient_id, allergen_id);


--
-- Name: ingredient_categories ingredient_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_categories
    ADD CONSTRAINT ingredient_categories_pkey PRIMARY KEY (ingredient_id, category_id);


--
-- Name: ingredients ingredients_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredients
    ADD CONSTRAINT ingredients_code_key UNIQUE (code);


--
-- Name: ingredients ingredients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredients
    ADD CONSTRAINT ingredients_pkey PRIMARY KEY (id);


--
-- Name: recipe_cooking_methods recipe_cooking_methods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_cooking_methods
    ADD CONSTRAINT recipe_cooking_methods_pkey PRIMARY KEY (recipe_id, method_id);


--
-- Name: recipe_ingredients recipe_ingredients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_ingredients
    ADD CONSTRAINT recipe_ingredients_pkey PRIMARY KEY (recipe_id, ingredient_id);


--
-- Name: recipe_steps recipe_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_steps
    ADD CONSTRAINT recipe_steps_pkey PRIMARY KEY (recipe_id, step_no);


--
-- Name: recipes recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipes
    ADD CONSTRAINT recipes_pkey PRIMARY KEY (id);


--
-- Name: user_allergens user_allergens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_allergens
    ADD CONSTRAINT user_allergens_pkey PRIMARY KEY (user_id, allergen_id);


--
-- Name: user_diets user_diets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_diets
    ADD CONSTRAINT user_diets_pkey PRIMARY KEY (user_id, diet_id);


--
-- Name: user_pantry user_pantry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_pantry
    ADD CONSTRAINT user_pantry_pkey PRIMARY KEY (user_id, ingredient_id);


--
-- Name: users users_login_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_login_key UNIQUE (login);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: allergens_name_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX allergens_name_uq ON public.allergens USING btree (lower(name));


--
-- Name: categories_name_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX categories_name_uq ON public.categories USING btree (lower(name));


--
-- Name: cooking_methods_name_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cooking_methods_name_uq ON public.cooking_methods USING btree (lower(name));


--
-- Name: diets_name_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX diets_name_uq ON public.diets USING btree (lower(name));


--
-- Name: favorite_ingredients_ing_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX favorite_ingredients_ing_idx ON public.favorite_ingredients USING btree (ingredient_id);


--
-- Name: favorite_recipes_recipe_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX favorite_recipes_recipe_idx ON public.favorite_recipes USING btree (recipe_id);


--
-- Name: ingredient_aliases_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ingredient_aliases_uq ON public.ingredient_aliases USING btree (ingredient_id, lower(alias));


--
-- Name: ingredients_name_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ingredients_name_uq ON public.ingredients USING btree (lower(name));


--
-- Name: recipe_cooking_methods_method_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recipe_cooking_methods_method_idx ON public.recipe_cooking_methods USING btree (method_id);


--
-- Name: recipe_ingredients_ingr_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recipe_ingredients_ingr_idx ON public.recipe_ingredients USING btree (ingredient_id);


--
-- Name: recipes_author_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recipes_author_idx ON public.recipes USING btree (author_id);


--
-- Name: recipes_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recipes_time_idx ON public.recipes USING btree (cook_time_min);


--
-- Name: user_allergens_allergen_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_allergens_allergen_idx ON public.user_allergens USING btree (allergen_id);


--
-- Name: favorite_recipes favorite_recipes_access; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER favorite_recipes_access BEFORE INSERT OR UPDATE ON public.favorite_recipes FOR EACH ROW EXECUTE FUNCTION public.check_favorite_recipe_access();


--
-- Name: recipe_cooking_methods recipe_cooking_methods_no_cook; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recipe_cooking_methods_no_cook BEFORE INSERT OR UPDATE ON public.recipe_cooking_methods FOR EACH ROW EXECUTE FUNCTION public.check_no_cook_methods();


--
-- Name: recipes recipes_no_cook_flip; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recipes_no_cook_flip BEFORE UPDATE OF no_cook ON public.recipes FOR EACH ROW EXECUTE FUNCTION public.check_recipe_no_cook_flip();


--
-- Name: diet_excluded_allergens diet_excluded_allergens_allergen_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_allergens
    ADD CONSTRAINT diet_excluded_allergens_allergen_id_fkey FOREIGN KEY (allergen_id) REFERENCES public.allergens(id) ON DELETE CASCADE;


--
-- Name: diet_excluded_allergens diet_excluded_allergens_diet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_allergens
    ADD CONSTRAINT diet_excluded_allergens_diet_id_fkey FOREIGN KEY (diet_id) REFERENCES public.diets(id) ON DELETE CASCADE;


--
-- Name: diet_excluded_categories diet_excluded_categories_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_categories
    ADD CONSTRAINT diet_excluded_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;


--
-- Name: diet_excluded_categories diet_excluded_categories_diet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_categories
    ADD CONSTRAINT diet_excluded_categories_diet_id_fkey FOREIGN KEY (diet_id) REFERENCES public.diets(id) ON DELETE CASCADE;


--
-- Name: diet_excluded_methods diet_excluded_methods_diet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_methods
    ADD CONSTRAINT diet_excluded_methods_diet_id_fkey FOREIGN KEY (diet_id) REFERENCES public.diets(id) ON DELETE CASCADE;


--
-- Name: diet_excluded_methods diet_excluded_methods_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diet_excluded_methods
    ADD CONSTRAINT diet_excluded_methods_method_id_fkey FOREIGN KEY (method_id) REFERENCES public.cooking_methods(id) ON DELETE CASCADE;


--
-- Name: favorite_ingredients favorite_ingredients_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_ingredients
    ADD CONSTRAINT favorite_ingredients_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id) ON DELETE CASCADE;


--
-- Name: favorite_ingredients favorite_ingredients_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_ingredients
    ADD CONSTRAINT favorite_ingredients_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: favorite_recipes favorite_recipes_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_recipes
    ADD CONSTRAINT favorite_recipes_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.recipes(id) ON DELETE CASCADE;


--
-- Name: favorite_recipes favorite_recipes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_recipes
    ADD CONSTRAINT favorite_recipes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: ingredient_aliases ingredient_aliases_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_aliases
    ADD CONSTRAINT ingredient_aliases_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id) ON DELETE CASCADE;


--
-- Name: ingredient_allergens ingredient_allergens_allergen_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_allergens
    ADD CONSTRAINT ingredient_allergens_allergen_id_fkey FOREIGN KEY (allergen_id) REFERENCES public.allergens(id) ON DELETE CASCADE;


--
-- Name: ingredient_allergens ingredient_allergens_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_allergens
    ADD CONSTRAINT ingredient_allergens_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id) ON DELETE CASCADE;


--
-- Name: ingredient_categories ingredient_categories_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_categories
    ADD CONSTRAINT ingredient_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;


--
-- Name: ingredient_categories ingredient_categories_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_categories
    ADD CONSTRAINT ingredient_categories_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id) ON DELETE CASCADE;


--
-- Name: recipe_cooking_methods recipe_cooking_methods_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_cooking_methods
    ADD CONSTRAINT recipe_cooking_methods_method_id_fkey FOREIGN KEY (method_id) REFERENCES public.cooking_methods(id) ON DELETE RESTRICT;


--
-- Name: recipe_cooking_methods recipe_cooking_methods_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_cooking_methods
    ADD CONSTRAINT recipe_cooking_methods_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.recipes(id) ON DELETE CASCADE;


--
-- Name: recipe_ingredients recipe_ingredients_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_ingredients
    ADD CONSTRAINT recipe_ingredients_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id) ON DELETE RESTRICT;


--
-- Name: recipe_ingredients recipe_ingredients_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_ingredients
    ADD CONSTRAINT recipe_ingredients_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.recipes(id) ON DELETE CASCADE;


--
-- Name: recipe_steps recipe_steps_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_steps
    ADD CONSTRAINT recipe_steps_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.recipes(id) ON DELETE CASCADE;


--
-- Name: recipes recipes_author_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipes
    ADD CONSTRAINT recipes_author_fk FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_allergens user_allergens_allergen_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_allergens
    ADD CONSTRAINT user_allergens_allergen_id_fkey FOREIGN KEY (allergen_id) REFERENCES public.allergens(id) ON DELETE CASCADE;


--
-- Name: user_allergens user_allergens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_allergens
    ADD CONSTRAINT user_allergens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_diets user_diets_diet_id_diet_kind_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_diets
    ADD CONSTRAINT user_diets_diet_id_diet_kind_fkey FOREIGN KEY (diet_id, diet_kind) REFERENCES public.diets(id, kind) ON DELETE CASCADE;


--
-- Name: user_diets user_diets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_diets
    ADD CONSTRAINT user_diets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_pantry user_pantry_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_pantry
    ADD CONSTRAINT user_pantry_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id) ON DELETE CASCADE;


--
-- Name: user_pantry user_pantry_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_pantry
    ADD CONSTRAINT user_pantry_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_pevzner_diet_id_pevzner_kind_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pevzner_diet_id_pevzner_kind_fkey FOREIGN KEY (pevzner_diet_id, pevzner_kind) REFERENCES public.diets(id, kind) ON DELETE SET NULL (pevzner_diet_id);


--
-- PostgreSQL database dump complete
--

-- Server accounts, sessions and persistent API state (001_server_state).
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
