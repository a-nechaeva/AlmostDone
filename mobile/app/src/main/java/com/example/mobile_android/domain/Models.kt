package com.example.mobile_android.domain

import kotlin.math.ceil

enum class QuantityUnit(val label: String) {
    GRAM("г"),
    MILLILITER("мл"),
    PIECE("шт."),
}

data class Quantity(val value: Double, val unit: QuantityUnit) {
    init {
        require(value.isFinite() && value >= 0 && value <= 1_000_000) {
            "Количество должно быть от 0 до 1 000 000."
        }
    }
}

data class PackageOffer(val quantity: Quantity, val priceKopecks: Long) {
    init {
        require(quantity.value > 0 && priceKopecks >= 0)
    }
}

enum class Allergen(val label: String) {
    MILK("Молоко"),
    EGGS("Яйца"),
    GLUTEN("Злаки с глютеном"),
    NUTS("Орехи"),
    FISH("Рыба"),
    SOY("Соя"),
}

enum class FoodType(val label: String) {
    ANY("Без предпочтений"),
    VEGETARIAN("Вегетарианское"),
    VEGAN("Веганское"),
}

enum class CookingMethod(val label: String) {
    STOVE("Плита"),
    OVEN("Духовка"),
    MICROWAVE("Микроволновка"),
    NO_COOK("Без готовки"),
}

data class FoodPreferences(
    val foodType: FoodType = FoodType.ANY,
    val excludedAllergens: Set<Allergen> = emptySet(),
    val glutenFree: Boolean = false,
    val lactoseFree: Boolean = false,
    val diabetes: Boolean = false,
    val dietTable: String = "",
)

data class DietaryFacts(
    val vegetarian: Boolean?,
    val vegan: Boolean?,
    val glutenFree: Boolean?,
    val lactoseFree: Boolean?,
)

data class Ingredient(
    val id: String,
    val name: String,
    val unit: QuantityUnit,
    val offer: PackageOffer? = null,
)

data class RecipeIngredient(val ingredientId: String, val quantity: Quantity)

data class Nutrition(val kcal: Int, val protein: Int, val fat: Int, val carbs: Int)

data class Recipe(
    val id: String,
    val title: String,
    val ingredients: List<RecipeIngredient>,
    val steps: List<String>,
    val minutes: Int,
    val servings: Int,
    val nutritionPerServing: Nutrition?,
    val allergens: Set<Allergen>,
    val allergenDataComplete: Boolean,
    val dietaryFacts: DietaryFacts,
    val methods: Set<CookingMethod>,
    val photo: String,
) {
    init {
        require(servings in 1..12 && minutes > 0 && ingredients.all { it.quantity.value > 0 })
    }
}

data class Catalog(val ingredients: List<Ingredient>, val recipes: List<Recipe>) {
    init {
        require(ingredients.map { it.id }.distinct().size == ingredients.size)
        require(recipes.map { it.id }.distinct().size == recipes.size)
    }

    fun ingredient(id: String): Ingredient? = ingredients.find { it.id == id }

    fun recipe(id: String): Recipe? = recipes.find { it.id == id }
}

data class PantryItem(val ingredientId: String, val quantity: Quantity?)

data class PlannedRecipe(val recipeId: String, val servings: Int)

data class ManualPurchase(val ingredientId: String, val quantity: Quantity)

data class Household(
    val pantry: List<PantryItem> = emptyList(),
    val favoriteRecipes: Set<String> = emptySet(),
    val favoriteIngredients: Set<String> = emptySet(),
    val plan: List<PlannedRecipe> = emptyList(),
    val manualPurchases: List<ManualPurchase> = emptyList(),
    val checkedPurchases: Set<String> = emptySet(),
)

enum class Suitability {
    ALLOWED,
    HIDDEN,
    UNKNOWN,
}

data class DietaryAssessment(val status: Suitability, val reasons: List<String>)

data class Shortage(val ingredientId: String, val quantity: Quantity?)

data class RecipeMatch(
    val recipe: Recipe,
    val servings: Int,
    val missing: List<Shortage>,
    val uncertainQuantityIds: Set<String>,
    val purchaseKopecks: Long?,
    val dietary: DietaryAssessment,
) {
    val ready: Boolean
        get() = missing.isEmpty() && uncertainQuantityIds.isEmpty()
}

data class ShoppingLine(
    val ingredientId: String,
    val required: Quantity?,
    val buyQuantity: Quantity?,
    val priceKopecks: Long?,
    val checked: Boolean,
)

data class ShoppingQuote(val lines: List<ShoppingLine>) {
    val totalKopecks: Long?
        get() = sumMoney(lines.map { it.priceKopecks })
}

data class PurchaseSuggestion(
    val ingredient: Ingredient,
    val quantity: Quantity,
    val priceKopecks: Long,
    val recipeIds: Set<String>,
)

fun quotePackage(shortage: Quantity?, offer: PackageOffer?): Pair<Quantity, Long>? {
    if (shortage == null || offer == null || shortage.unit != offer.quantity.unit) return null
    val packages = ceil(shortage.value / offer.quantity.value).toLong()
    val purchased = packages * offer.quantity.value
    if (purchased > 1_000_000) return null
    val total =
        runCatching { Math.multiplyExact(packages, offer.priceKopecks) }.getOrNull() ?: return null
    return Quantity(purchased, shortage.unit) to total
}

internal fun sumMoney(prices: List<Long?>): Long? {
    if (prices.any { it == null }) return null
    return runCatching { prices.fold(0L) { sum, value -> Math.addExact(sum, value!!) } }.getOrNull()
}
