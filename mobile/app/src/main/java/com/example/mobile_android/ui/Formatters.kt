package com.example.mobile_android.ui

import com.example.mobile_android.domain.*
import java.math.BigDecimal

fun number(value: Double): String =
    BigDecimal.valueOf(value).stripTrailingZeros().toPlainString().replace('.', ',')

fun quantityLabel(value: Quantity?): String =
    value?.let { "${number(it.value)} ${it.unit.label}" } ?: "Количество неизвестно"

fun money(value: Long?): String =
    value?.let {
        "${BigDecimal.valueOf(it, 2).stripTrailingZeros().toPlainString().replace('.', ',')} ₽"
    } ?: "Нет оценки"

fun parseMoney(value: String): Long? =
    runCatching {
            BigDecimal(value.trim().replace(',', '.')).movePointRight(2).longValueExact().takeIf {
                it in 0..100000000
            }
        }
        .getOrNull()

fun parseQuantity(value: String, unit: QuantityUnit): Quantity? {
    val amount = value.trim().replace(',', '.').toDoubleOrNull() ?: return null
    return runCatching { Quantity(amount, unit) }.getOrNull()
}
