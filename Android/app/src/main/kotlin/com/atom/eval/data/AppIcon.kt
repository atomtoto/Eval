package com.atom.eval.data

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/** The launcher icon style of « Icône de l’app », as iOS AppIconChoice. */
enum class AppIconChoice(val key: String) { Lens("lens"), Point("point") }

/**
 * The launcher icon of the app, as iOS sets an alternate icon: the style (Lentille or
 * Point) follows the accent color, so the icon matches the app's tint. The styles are
 * the activity-alias icons of the manifest; enabling one disables the primary icon.
 */
object AppIcon {
    const val STORAGE_KEY = "eval.appIcon.v1"

    private val aliases = listOf(".MainActivityIconPoint", ".MainActivityIconBlue", ".MainActivityIconPointBlue")

    /** The alias of the icon for a style and an accent; null is the primary icon. */
    private fun alias(choice: AppIconChoice, accent: Accent): String? = when (choice to accent) {
        AppIconChoice.Lens to Accent.Orange -> null
        AppIconChoice.Point to Accent.Orange -> ".MainActivityIconPoint"
        AppIconChoice.Lens to Accent.Blue -> ".MainActivityIconBlue"
        AppIconChoice.Point to Accent.Blue -> ".MainActivityIconPointBlue"
        else -> null
    }

    /** The launcher resource that previews a style in an accent, for « Réglages ». */
    fun preview(choice: AppIconChoice, accent: Accent): Int = when (choice to accent) {
        AppIconChoice.Lens to Accent.Orange -> com.atom.eval.R.mipmap.ic_launcher
        AppIconChoice.Point to Accent.Orange -> com.atom.eval.R.mipmap.ic_launcher_point
        AppIconChoice.Lens to Accent.Blue -> com.atom.eval.R.mipmap.ic_launcher_blue
        AppIconChoice.Point to Accent.Blue -> com.atom.eval.R.mipmap.ic_launcher_point_blue
        else -> com.atom.eval.R.mipmap.ic_launcher
    }

    /** Gives the app the icon of the chosen style in the accent color, unless it already has it. */
    fun apply(context: Context, choice: AppIconChoice, accent: Accent) {
        val packageManager = context.packageManager
        val target = alias(choice, accent)
        for (alias in aliases) {
            packageManager.setComponentEnabledSetting(
                ComponentName(context, alias),
                if (alias == target) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        // The primary activity holds the launcher icon when no alias is chosen.
        packageManager.setComponentEnabledSetting(
            ComponentName(context, com.atom.eval.MainActivity::class.java.name),
            if (target == null) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
