package com.sanyzrn.nex

import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.fonts.Font
import android.graphics.fonts.FontFamily
import android.os.Build
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.ActionMode
import android.view.Gravity
import android.view.KeyEvent
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * The editor behind `NexTextField` (ADR-037): Android's own `EditText`, so a
 * note in two languages is laid out the way the platform lays it out —
 * direction and alignment decided per paragraph by its first strong letter,
 * with the system's caret, handles, magnifier and selection menu.
 *
 * Flutter's editor gives a whole field one direction. A Persian note with an
 * English line put that line's full stop on the wrong end, and the caret and
 * handles followed the same scrambled order. This is the editor Telegram and
 * every other app built on Android's own text view uses, which is why they do
 * not have that problem.
 *
 * The Dart side owns the text: every change here is sent over this view's
 * channel (`nex/edit_text/<id>`) and written into the field's controller, and
 * a change made there — an AI rewrite, a format, a cleared composer — comes
 * back as `setValue`. The protocol is documented on `_NativeField` in
 * nex_text_field.dart.
 */
class NexEditTextFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        NexEditTextView(context, messenger, viewId, (args as? Map<*, *>) ?: emptyMap<Any, Any>())

    companion object {
        const val VIEW_TYPE = "nex/edit_text"

        /**
         * Reads the editor's fonts off the main thread, ahead of the first
         * editor: Vazirmatn is the largest file the app ships, and reading it
         * the moment Edit was tapped held the sheet's opening up behind it.
         */
        fun warmUp(context: Context) {
            val app = context.applicationContext
            Thread({ runCatching { NexEditTextView.typeface(app) } }, "nex-edit-text-fonts").start()
        }
    }
}

/** An `EditText` that says when its selection moves, and can take Copy. */
private class NexEditText(context: Context) : EditText(context) {
    var onSelection: ((Int, Int) -> Unit)? = null

    /** Given Copy (false) or Cut (true); true when it took care of it. */
    var onCopy: ((Boolean) -> Boolean)? = null

    /**
     * The keyboard's Enter key sends instead of starting a new line. The
     * field stays multi-line either way — a single-line input type would
     * also draw every line break in the text as a space.
     */
    var enterSends = false

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
        val connection = super.onCreateInputConnection(outAttrs)
        if (enterSends) {
            outAttrs.imeOptions = outAttrs.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION.inv()
        }
        return connection
    }

    // Copy and Cut from the selection menu and from a keyboard's Ctrl+C both
    // arrive here.
    override fun onTextContextMenuItem(id: Int): Boolean {
        if (id == android.R.id.copy || id == android.R.id.cut) {
            if (onCopy?.invoke(id == android.R.id.cut) == true) return true
        }
        return super.onTextContextMenuItem(id)
    }

    override fun onSelectionChanged(selStart: Int, selEnd: Int) {
        super.onSelectionChanged(selStart, selEnd)
        onSelection?.invoke(selStart, selEnd)
    }
}

private class NexEditTextView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    args: Map<*, *>,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "nex/edit_text/$id")
    private val edit = NexEditText(context)
    private val density = context.resources.displayMetrics.density

    /** True while a value from Dart is written in, so it is not sent back. */
    private var applying = false
    private var lastHeight = -1f
    private var minLines = 1
    private var maxLines = 0
    private var expands = false
    private var imeAction = "newline"
    private var formats: List<Pair<String, String>> = emptyList()

    /** Copy and Cut go to Dart's private clipboard; Share is not offered. */
    private var privateCopy = false

    /**
     * While a model holds the note: the text stays selectable and copyable,
     * but nothing typed, pasted or cut changes it. A filter rather than
     * taking the key listener away, which would also make the text
     * unselectable and reset the input type.
     */
    private var readOnly = false
    private val readOnlyFilter = InputFilter { _, _, _, dest, dstart, dend ->
        if (!readOnly || applying) null else dest.subSequence(dstart, dend)
    }

    init {
        channel.setMethodCallHandler(this)
        edit.background = null
        edit.setPadding(0, 0, 0, 0)
        edit.includeFontPadding = false
        // The point of the whole class. Each paragraph takes its direction
        // from its own first strong letter, and `ALIGN_NORMAL` — what gravity
        // START means for a paragraph — puts it against that paragraph's own
        // start: an English line left, a Persian one right, in one note.
        edit.gravity = Gravity.TOP or Gravity.START
        edit.textAlignment = View.TEXT_ALIGNMENT_GRAVITY
        edit.textDirection = View.TEXT_DIRECTION_FIRST_STRONG
        edit.typeface = typeface(context)
        edit.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI
        configure(args)
        val text = args["text"] as? String ?: ""
        applying = true
        edit.setText(text)
        select(args["start"] as? Int, args["end"] as? Int)
        applying = false

        edit.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (!applying) {
                    channel.invokeMethod(
                        "changed",
                        mapOf(
                            "text" to (s?.toString() ?: ""),
                            "start" to edit.selectionStart,
                            "end" to edit.selectionEnd,
                        ),
                    )
                }
                edit.post { reportHeight() }
            }
        })
        edit.onSelection = { start, end ->
            if (!applying) {
                channel.invokeMethod("selection", mapOf("start" to start, "end" to end))
            }
        }
        edit.onCopy = { cut ->
            if (!privateCopy || edit.selectionStart == edit.selectionEnd) {
                false
            } else {
                channel.invokeMethod(
                    "copy",
                    mapOf(
                        "start" to min(edit.selectionStart, edit.selectionEnd),
                        "end" to max(edit.selectionStart, edit.selectionEnd),
                        "cut" to cut,
                    ),
                )
                // The menu closes as it would after an ordinary copy.
                edit.setSelection(max(edit.selectionStart, edit.selectionEnd))
                true
            }
        }
        edit.setOnFocusChangeListener { _, focused ->
            channel.invokeMethod("focus", mapOf("focused" to focused))
        }
        edit.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_NULL || imeAction == "newline") {
                false
            } else {
                channel.invokeMethod("submit", null)
                true
            }
        }
        // A hardware keyboard's Enter, where the field sends: the same as the
        // on-screen key, with Shift+Enter still starting a new line.
        edit.setOnKeyListener { _, keyCode, event ->
            val enter = keyCode == KeyEvent.KEYCODE_ENTER || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER
            if (!enter || !edit.enterSends || event.isShiftPressed) {
                false
            } else {
                if (event.action == KeyEvent.ACTION_DOWN) channel.invokeMethod("submit", null)
                true
            }
        }
        edit.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> reportHeight() }
        edit.customSelectionActionModeCallback = selectionMenu(withFormats = true)
        edit.customInsertionActionModeCallback = selectionMenu(withFormats = false)
        if (args["autofocus"] == true) {
            edit.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) {
                    edit.removeOnAttachStateChangeListener(this)
                    edit.post { focus() }
                }

                override fun onViewDetachedFromWindow(v: View) {}
            })
        }
    }

    override fun getView(): View = edit

    override fun dispose() {
        channel.setMethodCallHandler(null)
        edit.onSelection = null
        edit.onCopy = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setValue" -> {
                val text = call.argument<String>("text") ?: ""
                applying = true
                try {
                    if (edit.text.toString() != text) edit.setText(text)
                    select(call.argument<Int>("start"), call.argument<Int>("end"))
                } finally {
                    applying = false
                }
                edit.post { reportHeight() }
                result.success(null)
            }
            "update" -> {
                (call.arguments as? Map<*, *>)?.let { configure(it) }
                edit.post { reportHeight() }
                result.success(null)
            }
            "focus" -> {
                focus()
                result.success(null)
            }
            "unfocus" -> {
                if (edit.hasFocus()) {
                    edit.clearFocus()
                    keyboard()?.hideSoftInputFromWindow(edit.windowToken, 0)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun keyboard(): InputMethodManager? =
        edit.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager

    /** Focus and the keyboard; asked once more if the first ask was early. */
    private fun focus() {
        edit.requestFocus()
        keyboard()?.showSoftInput(edit, InputMethodManager.SHOW_IMPLICIT)
        edit.postDelayed({
            val imm = keyboard()
            if (edit.hasFocus() && imm != null && !imm.isActive(edit)) {
                imm.showSoftInput(edit, InputMethodManager.SHOW_IMPLICIT)
            }
        }, 150)
    }

    private fun select(start: Int?, end: Int?) {
        val length = edit.text.length
        val s = (start ?: length).coerceIn(0, length)
        val e = (end ?: s).coerceIn(0, length)
        edit.setSelection(s, e)
    }

    private fun configure(args: Map<*, *>) {
        edit.layoutDirection =
            if (args["rtl"] == true) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        (args["fontSize"] as? Number)?.let {
            edit.setTextSize(TypedValue.COMPLEX_UNIT_DIP, it.toFloat())
        }
        val fontSize = (args["fontSize"] as? Number)?.toFloat() ?: 16f
        (args["lineHeight"] as? Number)?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                edit.lineHeight = (fontSize * it.toFloat() * density).toInt()
            }
        }
        (args["letterSpacing"] as? Number)?.let { edit.letterSpacing = it.toFloat() / fontSize }
        (args["textColor"] as? Number)?.let { edit.setTextColor(it.toInt()) }
        (args["hintColor"] as? Number)?.let { edit.setHintTextColor(it.toInt()) }
        (args["selectionColor"] as? Number)?.let { edit.highlightColor = it.toInt() }
        (args["accentColor"] as? Number)?.let { tint(it.toInt()) }
        edit.hint = args["hint"] as? String

        imeAction = args["imeAction"] as? String ?: "newline"
        var type = when (args["keyboard"]) {
            "number" -> InputType.TYPE_CLASS_NUMBER
            "phone" -> InputType.TYPE_CLASS_PHONE
            "email" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
            "url" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            else -> InputType.TYPE_CLASS_TEXT
        }
        if (type and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT) {
            type = type or when (args["capitalization"]) {
                "sentences" -> InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
                "words" -> InputType.TYPE_TEXT_FLAG_CAP_WORDS
                "characters" -> InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
                else -> 0
            }
            if (args["autocorrect"] != false) type = type or InputType.TYPE_TEXT_FLAG_AUTO_CORRECT
            if (args["suggestions"] == false) type = type or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            type = type or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        }
        if (edit.inputType != type) edit.inputType = type
        edit.enterSends = imeAction != "newline"
        var options = EditorInfo.IME_FLAG_NO_EXTRACT_UI or when (imeAction) {
            "send" -> EditorInfo.IME_ACTION_SEND
            "done" -> EditorInfo.IME_ACTION_DONE
            "search" -> EditorInfo.IME_ACTION_SEARCH
            "go" -> EditorInfo.IME_ACTION_GO
            "next" -> EditorInfo.IME_ACTION_NEXT
            else -> EditorInfo.IME_ACTION_NONE
        }
        if (args["incognito"] == true) options = options or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        edit.imeOptions = options

        expands = args["expands"] == true
        minLines = (args["minLines"] as? Number)?.toInt() ?: 1
        maxLines = (args["maxLines"] as? Number)?.toInt() ?: 0
        edit.setHorizontallyScrolling(false)
        edit.minLines = if (expands) 0 else max(minLines, 1)
        edit.maxLines = if (expands || maxLines <= 0) Int.MAX_VALUE else maxLines
        edit.isVerticalScrollBarEnabled = true

        val enabled = args["enabled"] != false
        if (edit.isEnabled != enabled) edit.isEnabled = enabled
        readOnly = args["readOnly"] == true
        edit.showSoftInputOnFocus = !readOnly

        val maxLength = (args["maxLength"] as? Number)?.toInt() ?: 0
        edit.filters = if (maxLength > 0) {
            arrayOf(readOnlyFilter, InputFilter.LengthFilter(maxLength))
        } else {
            arrayOf(readOnlyFilter)
        }

        privateCopy = args["privateCopy"] == true
        formats = (args["formats"] as? List<*>)?.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val formatId = map["id"] as? String ?: return@mapNotNull null
            val label = map["label"] as? String ?: return@mapNotNull null
            formatId to label
        } ?: emptyList()
    }

    /** The caret and both selection handles in the app's accent. */
    private fun tint(color: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        edit.textCursorDrawable = GradientDrawable().apply {
            setColor(color)
            setSize((2 * density).toInt(), 0)
        }
        edit.textSelectHandle?.setTint(color)
        edit.textSelectHandleLeft?.setTint(color)
        edit.textSelectHandleRight?.setTint(color)
    }

    /**
     * The selection menu: the platform's own commands, this app's formatting
     * after them, and nothing other apps put there — the rule
     * `nexOwnMenuItems` keeps for Flutter's menus.
     */
    private fun selectionMenu(withFormats: Boolean) = object : ActionMode.Callback {
        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
            if (withFormats) {
                formats.forEachIndexed { index, (_, label) ->
                    menu.add(Menu.NONE, FORMAT_BASE + index, 200 + index, label)
                }
            }
            return true
        }

        override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
            for (index in 0 until menu.size()) {
                val item = menu.getItem(index)
                if (item.intent?.action == Intent.ACTION_PROCESS_TEXT) item.isVisible = false
                if (privateCopy && item.itemId == android.R.id.shareText) item.isVisible = false
            }
            return true
        }

        override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
            val index = item.itemId - FORMAT_BASE
            if (index < 0 || index >= formats.size) return false
            channel.invokeMethod(
                "format",
                mapOf(
                    "id" to formats[index].first,
                    "start" to edit.selectionStart,
                    "end" to edit.selectionEnd,
                ),
            )
            mode.finish()
            return true
        }

        override fun onDestroyActionMode(mode: ActionMode) {}
    }

    /**
     * How tall the field wants to be, in Flutter's logical pixels: its text,
     * held between its minimum and maximum lines. Flutter sizes the view to
     * it; past the maximum the editor scrolls inside itself.
     */
    private fun reportHeight() {
        if (expands) return
        val layout = edit.layout ?: return
        val count = max(layout.lineCount, 1)
        val shown = min(count, if (maxLines > 0) maxLines else Int.MAX_VALUE)
        var px = layout.getLineTop(shown).toFloat()
        if (count < minLines) px += (minLines - count) * edit.lineHeight
        px += edit.compoundPaddingTop + edit.compoundPaddingBottom
        val height = px / density
        if (abs(height - lastHeight) < 0.5f) return
        lastHeight = height
        channel.invokeMethod("height", mapOf("height" to height.toDouble()))
    }

    companion object {
        private const val FORMAT_BASE = 0x4E0000

        @Volatile
        private var cachedTypeface: Typeface? = null

        /**
         * Inter for Latin with Vazirmatn behind it, the families the rest of
         * the app draws text in, read from the Flutter assets that already
         * ship them.
         */
        fun typeface(context: Context): Typeface {
            cachedTypeface?.let { return it }
            val loader = FlutterInjector.instance().flutterLoader()
            val inter = loader.getLookupKeyForAsset("assets/fonts/Inter-subset.ttf")
            val vazir = loader.getLookupKeyForAsset("assets/fonts/VazirmatnVariable.ttf")
            val made = runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    Typeface.CustomFallbackBuilder(
                        FontFamily.Builder(Font.Builder(context.assets, inter).build()).build(),
                    )
                        .addCustomFallback(
                            FontFamily.Builder(
                                Font.Builder(context.assets, vazir)
                                    .setFontVariationSettings("'wght' 400")
                                    .build(),
                            ).build(),
                        )
                        .setSystemFallback("sans-serif")
                        .build()
                } else {
                    Typeface.createFromAsset(context.assets, vazir)
                }
            }.getOrDefault(Typeface.DEFAULT)
            cachedTypeface = made
            return made
        }
    }
}
