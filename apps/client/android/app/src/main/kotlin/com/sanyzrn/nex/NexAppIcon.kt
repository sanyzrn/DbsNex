package com.sanyzrn.nex

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * Which launcher icon Nex shows, chosen in Settings → Appearance → Theme.
 *
 * Android has no API for changing an app's icon. What it has is
 * `activity-alias`: the manifest declares one alias of [MainActivity] per
 * icon, each carrying the launcher intent filter and its own icon, and only
 * one of them is enabled. Switching enables the new alias *before* disabling
 * the old one, so there is never a moment with no launcher entry at all.
 *
 * The ids are the ones the Dart side uses; the class names are the aliases'
 * names in AndroidManifest.xml.
 */
object NexAppIcon {
    private val aliases = linkedMapOf(
        "default" to "com.sanyzrn.nex.IconDefault",
        "alt1" to "com.sanyzrn.nex.IconAlt1",
        "alt2" to "com.sanyzrn.nex.IconAlt2",
        "alt3" to "com.sanyzrn.nex.IconAlt3",
        "alt4" to "com.sanyzrn.nex.IconAlt4",
        "alt5" to "com.sanyzrn.nex.IconAlt5",
    )

    private fun component(context: Context, alias: String) =
        ComponentName(context.packageName, alias)

    fun current(context: Context): String {
        val pm = context.packageManager
        for ((id, alias) in aliases) {
            val state = pm.getComponentEnabledSetting(component(context, alias))
            val enabled = when (state) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> id == "default"
                else -> false
            }
            if (enabled) return id
        }
        return "default"
    }

    /** False for an id this build does not know. */
    fun set(context: Context, id: String): Boolean {
        val target = aliases[id] ?: return false
        val pm = context.packageManager
        pm.setComponentEnabledSetting(
            component(context, target),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for ((other, alias) in aliases) {
            if (other == id) continue
            pm.setComponentEnabledSetting(
                component(context, alias),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        return true
    }
}
