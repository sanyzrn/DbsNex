package com.sanyzrn.nex

/** Only explicitly selected words; a styled CharSequence becomes plain text. */
internal fun selectedTextForCapture(action: String?, selected: CharSequence?): String? {
    if (action != "android.intent.action.PROCESS_TEXT") return null
    return selected?.toString()?.takeIf { it.isNotBlank() }
}
