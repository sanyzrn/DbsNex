package com.sanyzrn.nex

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * The Quick Settings tile: one swipe down and a tap, from anywhere, into the
 * same capture sheet the home-screen Capture widget opens (W5.2).
 *
 * It carries no state — it is a button, not a switch — so it is always drawn
 * inactive and never toggles. On a locked phone it asks for the unlock first:
 * the capture sheet is the app, and the app is behind the lock screen like
 * everything else in it.
 */
class NexCaptureTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        // The app's language, not the phone's (LOC-03).
        val text = NexWidgetAppearance.localized(this)
        qsTile?.let {
            it.state = Tile.STATE_INACTIVE
            it.label = text.getString(R.string.tile_capture_label)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                it.subtitle = text.getString(R.string.tile_capture_subtitle)
            }
            it.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) unlockAndRun { open() } else open()
    }

    // The Intent overload is deprecated from API 34, where only a
    // PendingIntent is accepted; below 34 the PendingIntent overload does not
    // exist. Both open the same capture request.
    private fun open() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(NexWidgetActions.textCapture(this))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(NexWidgetActions.textCaptureIntent(this))
        }
    }
}
