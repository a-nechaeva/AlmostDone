package com.example.mobile_android.data.model

enum class DietTag(val title: String) {
    VEGETARIAN("Вегетарианское"),
    VEGAN("Веганское"),
    GLUTEN_FREE("Без глютена"),
    LACTOSE_FREE("Без лактозы"),
    DIABETES_FRIENDLY("Подходит при диабете"),
}

enum class CookingMethod(val title: String) {
    MICROWAVE("Микроволновка"),
    STOVE("Плита"),
    OVEN("Духовка"),
    NO_COOK("Без готовки"),
}

object Allergens {
    val ALL = listOf("Глютен", "Лактоза", "Орехи", "Яйца", "Рыба", "Морепродукты", "Соя", "Мёд")
}