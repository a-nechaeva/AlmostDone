package com.example.mobile_android.data.local

import androidx.room.*

@Entity(tableName = "pantry")
data class PantryEntity(
    @PrimaryKey val ingredientId: String,
    val amount: Double?,
    val unit: String?,
)

@Entity(tableName = "favorites", primaryKeys = ["itemId", "ingredient"])
data class FavoriteEntity(val itemId: String, val ingredient: Boolean)

@Entity(tableName = "recipe_plan")
data class PlanEntity(@PrimaryKey val recipeId: String, val servings: Int)

@Entity(tableName = "manual_purchases")
data class ManualPurchaseEntity(
    @PrimaryKey val ingredientId: String,
    val amount: Double,
    val unit: String,
)

@Entity(tableName = "checked_purchases")
data class CheckedPurchaseEntity(@PrimaryKey val ingredientId: String)

@Entity(tableName = "metadata")
data class MetadataEntity(@PrimaryKey val key: String, val value: String)

@Dao
interface HouseholdDao {
    @Query("SELECT * FROM pantry ORDER BY ingredientId") suspend fun pantry(): List<PantryEntity>

    @Query("SELECT * FROM favorites") suspend fun favorites(): List<FavoriteEntity>

    @Query("SELECT * FROM recipe_plan ORDER BY recipeId") suspend fun plan(): List<PlanEntity>

    @Query("SELECT * FROM manual_purchases ORDER BY ingredientId")
    suspend fun manual(): List<ManualPurchaseEntity>

    @Query("SELECT * FROM checked_purchases") suspend fun checked(): List<CheckedPurchaseEntity>

    @Query("SELECT value FROM metadata WHERE `key` = :key")
    suspend fun metadata(key: String): String?

    @Upsert suspend fun savePantry(row: PantryEntity)

    @Query("DELETE FROM pantry WHERE ingredientId = :id") suspend fun removePantry(id: String)

    /** Полная замена зеркала серверных запасов (источник истины — сервер). */
    @Query("DELETE FROM pantry") suspend fun clearPantry()

    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun addFavorite(row: FavoriteEntity)

    @Query("DELETE FROM favorites WHERE itemId = :id AND ingredient = :ingredient")
    suspend fun removeFavorite(id: String, ingredient: Boolean)

    /** Полная замена зеркала серверного избранного. */
    @Query("DELETE FROM favorites") suspend fun clearFavorites()

    @Upsert suspend fun savePlan(row: PlanEntity)

    @Query("DELETE FROM recipe_plan WHERE recipeId = :id") suspend fun removePlan(id: String)

    @Query("DELETE FROM recipe_plan") suspend fun clearPlan()

    @Upsert suspend fun saveManual(row: ManualPurchaseEntity)

    @Query("DELETE FROM manual_purchases WHERE ingredientId = :id")
    suspend fun removeManual(id: String)

    @Query("DELETE FROM manual_purchases") suspend fun clearManual()

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun addChecked(row: CheckedPurchaseEntity)

    @Query("DELETE FROM checked_purchases WHERE ingredientId = :id")
    suspend fun removeChecked(id: String)

    @Query("DELETE FROM checked_purchases") suspend fun clearChecked()

    @Upsert suspend fun saveMetadata(row: MetadataEntity)
}

@Database(
    entities =
        [
            PantryEntity::class,
            FavoriteEntity::class,
            PlanEntity::class,
            ManualPurchaseEntity::class,
            CheckedPurchaseEntity::class,
            MetadataEntity::class,
        ],
    version = 1,
    exportSchema = true,
)
abstract class HouseholdDatabase : RoomDatabase() {
    abstract fun householdDao(): HouseholdDao
}
