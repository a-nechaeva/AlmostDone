package com.example.mobile_android.data.local

import com.example.mobile_android.domain.*

internal fun storedQuantity(value: Double?, unit: String?): Quantity? =
    if (value == null || unit == null) null else Quantity(value, QuantityUnit.valueOf(unit))

internal fun PantryEntity.toDomain() = PantryItem(ingredientId, storedQuantity(amount, unit))

internal fun ManualPurchaseEntity.toDomain() =
    ManualPurchase(ingredientId, Quantity(amount, QuantityUnit.valueOf(unit)))
