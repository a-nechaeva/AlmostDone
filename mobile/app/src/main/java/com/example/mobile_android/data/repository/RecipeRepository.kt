package com.example.mobile_android.data.repository

import com.example.mobile_android.data.model.Ingredient
import com.example.mobile_android.data.model.Recipe
import com.example.mobile_android.data.model.RecipeIngredient
import com.example.mobile_android.data.model.RecipeMetrics
import com.example.mobile_android.data.model.CookingMethod
import com.example.mobile_android.data.model.DietTag

object RecipeRepository {

    // Заглушка: позже сюда встанет Room/JSON с базой 100 рецептов и 150+ ингредиентов
    val ingredients: List<Ingredient> = listOf(
        Ingredient("i1", "Овсянка", 380.0, 12.0, 6.0, 60.0, 40.0, setOf("Глютен")),
        Ingredient("i2", "Банан", 90.0, 1.0, 0.5, 21.0, 120.0),
        Ingredient("i3", "Молоко", 60.0, 3.0, 3.2, 4.7, 70.0, setOf("Лактоза")),
        Ingredient("i4", "Яйцо куриное", 155.0, 13.0, 11.0, 1.1, 130.0, setOf("Яйца")),
        Ingredient("i5", "Творог 5%", 120.0, 17.0, 5.0, 3.0, 350.0, setOf("Лактоза")),
        Ingredient("i6", "Грецкий орех", 650.0, 15.0, 65.0, 14.0, 800.0, setOf("Орехи")),
        Ingredient("i7", "Мёд", 330.0, 0.8, 0.0, 82.0, 600.0, setOf("Мёд")),
        Ingredient("i8", "Куриная грудка", 165.0, 31.0, 3.6, 0.0, 450.0),
    )

    val recipes: List<Recipe> = listOf(
        Recipe(
            id = "r1",
            title = "Овсяная каша с бананом",
            ingredients = listOf(
                RecipeIngredient("i1", 80.0),
                RecipeIngredient("i3", 200.0),
                RecipeIngredient("i2", 100.0),
            ),
            steps = listOf("Залить овсянку молоком", "Варить 5 минут", "Добавить нарезанный банан"),
            timeMinutes = 15,
            portions = 1,
            tags = setOf(DietTag.VEGETARIAN),
            methods = setOf(CookingMethod.STOVE, CookingMethod.MICROWAVE),
            warnings = listOf("Содержит глютен и лактозу"),
        ),
        Recipe(
            id = "r2",
            title = "Творожная запеканка",
            ingredients = listOf(
                RecipeIngredient("i5", 400.0),
                RecipeIngredient("i4", 100.0),
                RecipeIngredient("i7", 30.0),
            ),
            steps = listOf("Смешать творог, яйцо и мёд", "Запекать 35 минут при 180°C"),
            timeMinutes = 45,
            portions = 2,
            methods = setOf(CookingMethod.OVEN),
            warnings = listOf("Содержит лактозу и яйца"),
        ),
        Recipe(
            id = "r3",
            title = "Салат с бананом, орехами и мёдом",
            ingredients = listOf(
                RecipeIngredient("i2", 150.0),
                RecipeIngredient("i6", 30.0),
                RecipeIngredient("i7", 20.0),
            ),
            steps = listOf("Нарезать банан", "Посыпать орехами", "Полить мёдом"),
            timeMinutes = 5,
            portions = 1,
            tags = setOf(DietTag.VEGETARIAN, DietTag.GLUTEN_FREE),
            methods = setOf(CookingMethod.NO_COOK),
            warnings = listOf("Орехи и мёд — сильные аллергены", "Высокая сахарная нагрузка"),
        ),
    )

    fun ingredientById(id: String): Ingredient? = ingredients.find { it.id == id }
    fun recipeById(id: String): Recipe? = recipes.find { it.id == id }

    fun metrics(recipe: Recipe): RecipeMetrics {
        var cost = 0.0; var kcal = 0.0; var p = 0.0; var f = 0.0; var c = 0.0
        val allergens = mutableSetOf<String>()
        recipe.ingredients.forEach { ri ->
            ingredientById(ri.ingredientId)?.let { ing ->
                val k = ri.grams / 100.0
                cost += ing.pricePer100g * k
                kcal += ing.kcalPer100g * k
                p += ing.proteinPer100g * k
                f += ing.fatPer100g * k
                c += ing.carbPer100g * k
                allergens += ing.allergens
            }
        }
        return RecipeMetrics(cost, kcal, p, f, c, allergens)
    }
}