package com.sanyzrn.nex

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import java.util.UUID

object NexPrivateClipboard {
    fun copy(context: Context, text: String) {
        val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val marker = "Nex-private-${UUID.randomUUID()}"
        val clip = ClipData.newPlainText(marker, text)
        clip.description.extras = PersistableBundle().apply {
            putBoolean("android.content.extra.IS_SENSITIVE", true)
        }
        manager.setPrimaryClip(clip)
        Handler(Looper.getMainLooper()).postDelayed({
            runCatching {
                // Never erase a later copy belonging to the user or another app.
                if (manager.primaryClipDescription?.label?.toString() == marker) {
                    if (Build.VERSION.SDK_INT >= 28) manager.clearPrimaryClip()
                    else manager.setPrimaryClip(ClipData.newPlainText("", ""))
                }
            }
        }, 30_000)
    }
}
