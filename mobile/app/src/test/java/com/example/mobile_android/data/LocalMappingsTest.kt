package com.example.mobile_android.data

import com.example.mobile_android.data.local.*
import com.example.mobile_android.domain.*
import org.junit.Assert.*
import org.junit.Test

class LocalMappingsTest {
    @Test
    fun storedAmountAndUnitArePreserved() {
        assertEquals(
            PantryItem("milk", Quantity(250.0, QuantityUnit.MILLILITER)),
            PantryEntity("milk", 250.0, "MILLILITER").toDomain(),
        )
        assertEquals(
            ManualPurchase("eggs", Quantity(3.0, QuantityUnit.PIECE)),
            ManualPurchaseEntity("eggs", 3.0, "PIECE").toDomain(),
        )
    }

    @Test
    fun missingAmountOrUnitRemainsUnknown() {
        assertNull(PantryEntity("milk", null, "MILLILITER").toDomain().quantity)
        assertNull(PantryEntity("milk", 250.0, null).toDomain().quantity)
        assertNull(PantryEntity("milk", null, null).toDomain().quantity)
    }

    @Test
    fun zeroIsDifferentFromUnknown() {
        assertEquals(
            Quantity(0.0, QuantityUnit.GRAM),
            PantryEntity("salt", 0.0, "GRAM").toDomain().quantity,
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun invalidStoredUnitFailsInsteadOfGuessing() {
        PantryEntity("milk", 250.0, "LITRE").toDomain()
    }

    @Test(expected = IllegalArgumentException::class)
    fun invalidPurchaseAmountFailsInsteadOfBecomingZero() {
        ManualPurchaseEntity("eggs", -3.0, "PIECE").toDomain()
    }
}
