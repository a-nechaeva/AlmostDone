package com.example.mobile_android.ui

import com.example.mobile_android.domain.QuantityUnit
import org.junit.Assert.*
import org.junit.Test

class FormattersTest {
    @Test
    fun decimalCommaIsAcceptedWithoutRoundingMoney() {
        assertEquals(23050L, parseMoney("230,50"))
        assertNull(parseMoney("230,501"))
        assertNull(parseMoney("-1"))
    }

    @Test
    fun invalidOrInfiniteQuantitiesAreRejected() {
        assertNull(parseQuantity("NaN", QuantityUnit.GRAM))
        assertNull(parseQuantity("Infinity", QuantityUnit.GRAM))
        assertNull(parseQuantity("-1", QuantityUnit.GRAM))
        assertEquals(0.5, parseQuantity("0,5", QuantityUnit.PIECE)!!.value, 0.0)
    }
}
