package com.example.mobile_android.data

import com.example.mobile_android.domain.*
import kotlinx.coroutines.flow.flowOf

class DemoCatalogRepository : CatalogRepository {
    override val catalog = flowOf(DemoCatalog.catalog)
}

object DemoCatalog {
    private fun offer(value: Double, unit: QuantityUnit, rubles: Int) =
        PackageOffer(Quantity(value, unit), rubles * 100L)

    private val g = QuantityUnit.GRAM
    private val ml = QuantityUnit.MILLILITER
    private val pcs = QuantityUnit.PIECE
    val catalog =
        Catalog(
            ingredients =
                listOf(
                    Ingredient("eggs", "Яйца", pcs, offer(10.0, pcs, 130)),
                    Ingredient("tomatoes", "Томаты", g, offer(500.0, g, 160)),
                    Ingredient("pasta", "Макароны", g, offer(450.0, g, 120)),
                    Ingredient("butter", "Сливочное масло", g, offer(180.0, g, 220)),
                    Ingredient("milk", "Молоко", ml, offer(1000.0, ml, 110)),
                    Ingredient("olive-oil", "Оливковое масло", ml, offer(500.0, ml, 500)),
                    Ingredient("salt", "Соль", g, offer(1000.0, g, 60)),
                    Ingredient("water", "Вода", ml, offer(1500.0, ml, 80)),
                    Ingredient("hard-cheese", "Твёрдый сыр", g, offer(200.0, g, 230)),
                    Ingredient("rice", "Рис", g),
                ),
            recipes =
                listOf(
                    Recipe(
                        "omelette",
                        "Омлет с томатами",
                        listOf(
                            RecipeIngredient("eggs", Quantity(2.0, pcs)),
                            RecipeIngredient("tomatoes", Quantity(100.0, g)),
                            RecipeIngredient("milk", Quantity(50.0, ml)),
                            RecipeIngredient("butter", Quantity(10.0, g)),
                        ),
                        listOf(
                            "Нарежьте томаты.",
                            "Взбейте яйца с молоком.",
                            "Растопите масло, добавьте томаты и яичную смесь.",
                            "Готовьте под крышкой до готовности.",
                        ),
                        15,
                        1,
                        Nutrition(290, 15, 22, 8),
                        setOf(Allergen.EGGS, Allergen.MILK),
                        true,
                        DietaryFacts(true, false, true, false),
                        setOf(CookingMethod.STOVE),
                        "omelette",
                    ),
                    Recipe(
                        "pasta",
                        "Паста с томатами",
                        listOf(
                            RecipeIngredient("pasta", Quantity(200.0, g)),
                            RecipeIngredient("tomatoes", Quantity(300.0, g)),
                            RecipeIngredient("olive-oil", Quantity(20.0, ml)),
                            RecipeIngredient("water", Quantity(1000.0, ml)),
                            RecipeIngredient("salt", Quantity(5.0, g)),
                        ),
                        listOf(
                            "Отварите макароны в подсоленной воде.",
                            "Нарежьте томаты и прогрейте с маслом.",
                            "Смешайте пасту с томатами и подавайте.",
                        ),
                        20,
                        2,
                        Nutrition(424, 13, 8, 75),
                        setOf(Allergen.GLUTEN),
                        true,
                        DietaryFacts(true, true, false, true),
                        setOf(CookingMethod.STOVE),
                        "pasta",
                    ),
                    Recipe(
                        "cheese",
                        "Паста с томатами и сыром",
                        listOf(
                            RecipeIngredient("pasta", Quantity(200.0, g)),
                            RecipeIngredient("tomatoes", Quantity(300.0, g)),
                            RecipeIngredient("olive-oil", Quantity(20.0, ml)),
                            RecipeIngredient("water", Quantity(1000.0, ml)),
                            RecipeIngredient("salt", Quantity(5.0, g)),
                            RecipeIngredient("hard-cheese", Quantity(80.0, g)),
                        ),
                        listOf(
                            "Отварите макароны в подсоленной воде.",
                            "Прогрейте томаты с маслом, смешайте с пастой.",
                            "Натрите сыр, добавьте к пасте и подавайте.",
                        ),
                        20,
                        2,
                        Nutrition(549, 21, 17, 78),
                        setOf(Allergen.GLUTEN, Allergen.MILK),
                        true,
                        DietaryFacts(null, false, false, false),
                        setOf(CookingMethod.STOVE),
                        "pasta",
                    ),
                    Recipe(
                        "cheeseEgg",
                        "Омлет с сыром",
                        listOf(
                            RecipeIngredient("eggs", Quantity(2.0, pcs)),
                            RecipeIngredient("milk", Quantity(50.0, ml)),
                            RecipeIngredient("butter", Quantity(10.0, g)),
                            RecipeIngredient("hard-cheese", Quantity(50.0, g)),
                        ),
                        listOf(
                            "Взбейте яйца с молоком.",
                            "Натрите сыр и добавьте к яйцам.",
                            "Растопите масло и готовьте омлет под крышкой до готовности.",
                        ),
                        15,
                        1,
                        Nutrition(443, 27, 35, 5),
                        setOf(Allergen.EGGS, Allergen.MILK),
                        true,
                        DietaryFacts(null, false, true, false),
                        setOf(CookingMethod.STOVE),
                        "omelette",
                    ),
                ),
        )
    val initialPantry =
        listOf(
            PantryItem("eggs", Quantity(4.0, pcs)),
            PantryItem("tomatoes", Quantity(500.0, g)),
            PantryItem("pasta", Quantity(400.0, g)),
            PantryItem("butter", Quantity(100.0, g)),
            PantryItem("milk", Quantity(500.0, ml)),
            PantryItem("olive-oil", Quantity(100.0, ml)),
            PantryItem("salt", Quantity(100.0, g)),
            PantryItem("water", Quantity(2000.0, ml)),
        )
}
