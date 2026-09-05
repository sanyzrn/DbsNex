package com.sanyzrn.nex

import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/**
 * The window a share arrives through — and deliberately not a window anyone
 * sees.
 *
 * Sharing into Nex used to open Nex: a launch screen over whatever app the
 * person was actually using, a timeline they did not ask for, and a back
 * gesture to get out of it. For a notes app that is the wrong trade. Sharing
 * something is a sentence you finish somewhere else; it should cost a moment
 * and leave you where you were.
 *
 * So the share has its own Activity with a translucent theme and no starting
 * window. The Flutter engine still boots — it is what owns the library and
 * writes the note — but it never paints: `NexBootstrapHost` draws nothing at
 * all once the platform tells it this is the silent window, and the Dart side
 * closes this Activity as soon as the capture is done, with a toast saying
 * what happened.
 *
 * Everything else is [MainActivity]'s, inherited whole: the same channel, the
 * same intent handling, the same copy-on-demand. The only differences are
 * that this one is see-through and that it shuts itself.
 */
class ShareActivity : MainActivity() {
    /**
     * Without this the engine paints an opaque surface and the translucent
     * theme buys nothing — a blank rectangle over the sharing app instead of
     * a splash over it.
     */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override val closesAfterShare = true
}
