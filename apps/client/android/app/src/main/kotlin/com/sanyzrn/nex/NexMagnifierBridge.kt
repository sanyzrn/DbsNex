package com.sanyzrn.nex

import android.os.Build
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityManager
import android.view.inspector.WindowInspector
import android.widget.EditText
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Experimental 2.0.6 adapter, not a new text editor or loupe implementation.
 * Android still lays out the text and handles every selection gesture; Flutter's
 * stock TextMagnifier draws the lens using the already-composited editor texture.
 * Geometry is sent only during a gesture. No pixels or text cross this channel.
 */
internal class NexMagnifierBridge(
    private val edit: EditText,
    private val send: (Map<String, Any>) -> Unit,
) {
    var enabled = false
        set(value) {
            field = value
            if (!value) stop()
        }
    private val density = edit.resources.displayMetrics.density
    private val accessibility = edit.context.getSystemService(android.content.Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
    private val hooked = mutableSetOf<View>()
    private var disposed = false
    private var directTouch = false
    private var longPressed = false
    private var handleTouch = false
    private var movingStart = false
    private var lastStart = -1
    private var lastEnd = -1
    private var touchX = 0f
    private var downX = 0f
    private var downY = 0f
    private var moved = false
    private var showing = false
    private val discover = Runnable { hookHandles() }

    private fun available() = enabled && !disposed && edit.isEnabled &&
        accessibility?.isTouchExplorationEnabled != true

    fun touch(event: MotionEvent, native: () -> Boolean): Boolean {
        if (!available()) return native()
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                hide()
                directTouch = true
                moved = false
                longPressed = false
                downX = event.x
                downY = event.y
            }
            MotionEvent.ACTION_MOVE -> moved = moved ||
                abs(event.x - downX) + abs(event.y - downY) > android.view.ViewConfiguration.get(edit.context).scaledTouchSlop
            MotionEvent.ACTION_POINTER_DOWN -> stopGesture()
        }
        touchX = event.x
        val result = nativeWithoutLoupe(native)
        when (event.actionMasked) {
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> stopGesture()
        }
        discoverHandles()
        return result
    }

    fun longPress() {
        if (!available() || !directTouch) return
        longPressed = true
        publish()
        discoverHandles()
    }

    fun selectionChanged(start: Int, end: Int) {
        movingStart = start != lastStart && end == lastEnd
        lastStart = start
        lastEnd = end
        if (handleTouch || (directTouch && (longPressed || moved))) publish()
        // Typing also moves selection; do not inspect windows on each keystroke.
        if (handleTouch || directTouch) discoverHandles()
    }

    fun discoverHandles() {
        if (!available() || !edit.hasFocus()) return
        edit.removeCallbacks(discover)
        edit.postDelayed(discover, 32)
    }

    /** Public API (29+). Only framework text handles of this focused window. */
    private fun hookHandles() {
        if (!available() || !edit.hasFocus() || Build.VERSION.SDK_INT < 29) return
        val token = edit.applicationWindowToken ?: return
        runCatching {
            WindowInspector.getGlobalWindowViews().filter { it.applicationWindowToken == token }
                .forEach { visit(it) }
        }
    }

    private fun visit(view: View) {
        val name = view.javaClass.name
        if (name == "android.widget.Editor\$InsertionHandleView" ||
            name == "android.widget.Editor\$SelectionHandleView") {
            if (!hooked.add(view)) return
            // Returning the native result preserves word snapping, auto-scroll,
            // RTL crossing rules, toolbar timing and handle lifetime.
            view.setOnTouchListener { handle, event ->
                if (!available() || !edit.hasFocus()) return@setOnTouchListener false
                val location = IntArray(2)
                edit.getLocationOnScreen(location)
                touchX = event.rawX - location[0]
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    handleTouch = true
                    movingStart = nearestStart(touchX, event.rawY - location[1])
                }
                val result = nativeWithoutLoupe { handle.onTouchEvent(event) }
                when (event.actionMasked) {
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> stopGesture()
                    else -> publish()
                }
                result
            }
        } else if (view is ViewGroup) {
            for (index in 0 until view.childCount) visit(view.getChildAt(index))
        }
    }

    private fun nearestStart(x: Float, y: Float): Boolean {
        val layout = edit.layout ?: return false
        fun distance(offset: Int): Float {
            val safe = offset.coerceIn(0, edit.text.length)
            val line = layout.getLineForOffset(safe)
            val cx = layout.getPrimaryHorizontal(safe) + edit.totalPaddingLeft - edit.scrollX
            val cy = layout.getLineBottom(line).toFloat() + edit.totalPaddingTop - edit.scrollY
            return (x - cx) * (x - cx) + (y - cy) * (y - cy)
        }
        return distance(edit.selectionStart) < distance(edit.selectionEnd)
    }

    /**
     * Android exposes no public switch for its editor loupe. AOSP's Editor
     * deliberately skips it for rotated views (checkForTransforms). An identity
     * 360-degree rotation during dispatch uses that guard, then restores the
     * original property before drawing. No reflection, private fields, global
     * renderer change or persistent transform. This workaround needs OEM tests.
     * If the view was already transformed, preserve its existing behavior.
     */
    private fun nativeWithoutLoupe(native: () -> Boolean): Boolean {
        if (!available() || edit.layout == null || edit.rotation != 0f) return native()
        edit.rotation = 360f
        return try { native() } finally { edit.rotation = 0f }
    }

    private fun publish() {
        if (!available() || !edit.hasFocus() || !edit.isAttachedToWindow) return
        val layout = edit.layout ?: return
        if (edit.width <= 0 || edit.height <= 0 || edit.text.isEmpty()) return
        val offset = (if (movingStart) edit.selectionStart else edit.selectionEnd)
            .coerceIn(0, edit.text.length)
        val line = layout.getLineForOffset(offset)
        val top = (layout.getLineTop(line) + edit.totalPaddingTop - edit.scrollY).toFloat()
        val bottom = (layout.getLineBottom(line) + edit.totalPaddingTop - edit.scrollY).toFloat()
        val x = layout.getPrimaryHorizontal(offset) + edit.totalPaddingLeft - edit.scrollX
        val left = min(layout.getLineLeft(line), layout.getLineRight(line)) + edit.totalPaddingLeft - edit.scrollX
        val right = max(layout.getLineLeft(line), layout.getLineRight(line)) + edit.totalPaddingLeft - edit.scrollX
        if (bottom <= 0 || top >= edit.height) { hide(); return }
        showing = true
        send(mapOf(
            "show" to true, "x" to touchX / density,
            "caretX" to x / density, "top" to top / density, "bottom" to bottom / density,
            "left" to left / density, "right" to right / density,
            "width" to edit.width / density, "height" to edit.height / density,
        ))
    }

    fun hide() {
        if (!showing) return
        showing = false
        send(mapOf("show" to false))
    }

    private fun stopGesture() {
        directTouch = false
        longPressed = false
        handleTouch = false
        moved = false
        hide()
    }

    fun stop() {
        stopGesture()
        edit.removeCallbacks(discover)
        hooked.forEach { it.setOnTouchListener(null) }
        hooked.clear()
    }

    fun dispose() { stop(); disposed = true }
}
