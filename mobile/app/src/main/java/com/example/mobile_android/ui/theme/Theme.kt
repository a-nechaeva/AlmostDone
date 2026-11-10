package com.example.mobile_android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

private val Light =
    lightColorScheme(
        primary = Color(0xFFB64C35),
        onPrimary = Color.White,
        primaryContainer = Color(0xFFFAE5DC),
        onPrimaryContainer = Color(0xFF9B3F2C),
        secondary = Color(0xFF9B3F2C),
        onSecondary = Color.White,
        secondaryContainer = Color(0xFFFAE5DC),
        onSecondaryContainer = Color(0xFF9B3F2C),
        tertiary = Color(0xFF34694B),
        onTertiary = Color.White,
        tertiaryContainer = Color(0xFFE7F1E8),
        onTertiaryContainer = Color(0xFF234E34),
        background = Color(0xFFF8F7F4),
        onBackground = Color(0xFF20201E),
        surface = Color.White,
        onSurface = Color(0xFF20201E),
        surfaceVariant = Color(0xFFEEECE7),
        onSurfaceVariant = Color(0xFF6C6B66),
        outline = Color(0xFF7D8178),
        outlineVariant = Color(0xFFE8E5DF),
        error = Color(0xFFA7352D),
        onError = Color.White,
    )
private val Dark =
    darkColorScheme(
        primary = Color(0xFFFFB49F),
        onPrimary = Color(0xFF3D160C),
        primaryContainer = Color(0xFF633026),
        onPrimaryContainer = Color(0xFFFFDACF),
        secondary = Color(0xFFFFB49F),
        onSecondary = Color(0xFF3D160C),
        secondaryContainer = Color(0xFF633026),
        onSecondaryContainer = Color(0xFFFFDACF),
        tertiary = Color(0xFFADC6AA),
        onTertiary = Color(0xFF183822),
        tertiaryContainer = Color(0xFF234E34),
        onTertiaryContainer = Color(0xFFE7F1E8),
        background = Color(0xFF171815),
        onBackground = Color(0xFFEAE7DE),
        surface = Color(0xFF23241F),
        onSurface = Color(0xFFEAE7DE),
        surfaceVariant = Color(0xFF34352E),
        onSurfaceVariant = Color(0xFFC9C7BB),
        outline = Color(0xFFA6A99F),
        outlineVariant = Color(0xFF494A42),
        error = Color(0xFFFFB4AB),
        onError = Color(0xFF690005),
    )

@Composable
fun AlmostReadyTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) Dark else Light,
        typography = Typography(),
        shapes =
            Shapes(
                small = RoundedCornerShape(16.dp),
                medium = RoundedCornerShape(22.dp),
                large = RoundedCornerShape(28.dp),
            ),
        content = content,
    )
}
