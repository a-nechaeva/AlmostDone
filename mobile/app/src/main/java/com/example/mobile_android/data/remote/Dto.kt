package com.example.mobile_android.data.remote

import com.example.mobile_android.domain.Allergen
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.FoodType
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import org.json.JSONArray
import org.json.JSONObject

/** Маппинг canonical ID справочника аллергенов сервера на модель Android. */
internal fun Allergen.toApiId(): String =
    when (this) {
        Allergen.MILK -> "milk"
        Allergen.EGGS -> "eggs"
        Allergen.GLUTEN -> "gluten"
        Allergen.NUTS -> "nuts"
        Allergen.PEANUTS -> "peanuts"
        Allergen.SESAME -> "sesame"
        Allergen.FISH -> "fish"
        Allergen.SOY -> "soy"
    }

internal fun allergenFromApiId(id: String): Allergen? =
    when (id) {
        "milk" -> Allergen.MILK
        "eggs" -> Allergen.EGGS
        "gluten" -> Allergen.GLUTEN
        "nuts" -> Allergen.NUTS
        "peanuts" -> Allergen.PEANUTS
        "sesame" -> Allergen.SESAME
        "fish" -> Allergen.FISH
        "soy" -> Allergen.SOY
        else -> null
    }

internal fun FoodType.toApiId(): String =
    when (this) {
        FoodType.ANY -> "any"
        FoodType.VEGETARIAN -> "vegetarian"
        FoodType.VEGAN -> "vegan"
    }

internal fun foodTypeFromApiId(id: String): FoodType =
    when (id) {
        "vegetarian" -> FoodType.VEGETARIAN
        "vegan" -> FoodType.VEGAN
        else -> FoodType.ANY
    }

internal fun QuantityUnit.toApiId(): String =
    when (this) {
        QuantityUnit.GRAM -> "g"
        QuantityUnit.MILLILITER -> "ml"
        QuantityUnit.PIECE -> "pcs"
    }

internal fun quantityUnitFromApiId(id: String): QuantityUnit? =
    when (id) {
        "g" -> QuantityUnit.GRAM
        "ml" -> QuantityUnit.MILLILITER
        "pcs" -> QuantityUnit.PIECE
        else -> null
    }

internal fun parseQuantity(json: JSONObject): Quantity? {
    val unit = quantityUnitFromApiId(json.optString("unit")) ?: return null
    val value = json.optDouble("value", Double.NaN)
    return runCatching { Quantity(value, unit) }.getOrNull()
}

internal fun quantityJson(quantity: Quantity) =
    JSONObject().put("value", quantity.value).put("unit", quantity.unit.toApiId())

/** Чтение `GET /me`: только preferences; имя и unsupported_restrictions Android пока не показывает. */
internal fun parseProfilePreferences(json: JSONObject): FoodPreferences {
    val p = json.getJSONObject("preferences")
    val allergens = p.optJSONArray("excluded_allergens") ?: JSONArray()
    return FoodPreferences(
        foodType = foodTypeFromApiId(p.optString("food_type")),
        excludedAllergens =
            buildSet {
                for (i in 0 until allergens.length()) {
                    allergenFromApiId(allergens.optString(i))?.let(::add)
                }
            },
        glutenFree = p.optBoolean("gluten_free"),
        lactoseFree = p.optBoolean("lactose_free"),
        diabetes = p.optBoolean("diabetes"),
        dietTable = if (p.isNull("diet_table_id")) "" else p.optString("diet_table_id"),
    )
}

/** Тело `PATCH /me`: полный черновик настроек. */
internal fun profileUpdateJson(preferences: FoodPreferences): JSONObject {
    val allergens = JSONArray()
    preferences.excludedAllergens.map(Allergen::toApiId).sorted().forEach(allergens::put)
    return JSONObject().put(
        "preferences",
        JSONObject()
            .put("food_type", preferences.foodType.toApiId())
            .put("excluded_allergens", allergens)
            .put("gluten_free", preferences.glutenFree)
            .put("lactose_free", preferences.lactoseFree)
            .put("diabetes", preferences.diabetes)
            .put(
                "diet_table_id",
                preferences.dietTable.trim().takeIf { it.isNotEmpty() } ?: JSONObject.NULL,
            ),
    )
}
