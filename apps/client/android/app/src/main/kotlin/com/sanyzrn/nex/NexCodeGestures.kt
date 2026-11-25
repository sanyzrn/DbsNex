package com.sanyzrn.nex

/**
 * One typed character's correction in a code field.
 *
 * [start] is the character the person typed; [replacement] is what takes its
 * place (the same character, a pair, or nothing when a closer is typed over
 * its twin), and [caret] is where the caret belongs afterwards.
 */
internal data class CodeGesture(
    val start: Int,
    val replacement: String,
    val caret: Int,
)

/**
 * The native editor's half of `NexCodeInputFormatter`: what a single typed
 * character should become in a code field.
 *
 * This is the same rule as the Dart formatter, and it is a pure function on
 * purpose — no Android classes, no editor — so it can be run on the JVM
 * (`NexCodeGesturesTest`) instead of only being hoped for on a device. The
 * caller passes the text and caret before the change and after it; anything
 * that is not exactly one character inserted at a collapsed caret comes back
 * as `null` and is left alone.
 *
 * The rules:
 *
 * * Enter keeps the indentation of the line it came from;
 * * a closing bracket or quote typed over its own twin steps past it instead
 *   of writing a second one;
 * * an opening bracket or an unescaped quote writes its partner and leaves
 *   the caret between them.
 */
internal fun nexCodeGesture(
    before: String,
    beforeStart: Int,
    beforeEnd: Int,
    after: String,
    afterStart: Int,
    afterEnd: Int,
): CodeGesture? {
    // A selection, a missing caret, or a caret that is not a caret.
    if (beforeStart != beforeEnd || beforeStart < 0) return null
    if (after.length != before.length + 1) return null
    val start = beforeStart
    if (start >= after.length) return null
    if (afterStart != start + 1 || afterEnd != start + 1) return null
    // Exactly one character, at the caret, with nothing else touched. A paste,
    // an autocorrect, a composition that rewrote several characters and a
    // change from Dart all fail here.
    if (after.substring(0, start) != before.substring(0, start)) return null
    if (after.substring(start + 1) != before.substring(start)) return null

    val input = after[start]
    val beforeChar = if (start == 0) NONE else before[start - 1]
    val afterChar = if (start < before.length) before[start] else NONE
    var replacement = input.toString()
    var caret = start + 1
    when {
        input == '\n' -> {
            val lineStart = if (start == 0) 0 else before.lastIndexOf('\n', start - 1) + 1
            var indentEnd = lineStart
            while (indentEnd < start &&
                (before[indentEnd] == ' ' || before[indentEnd] == '\t')
            ) {
                indentEnd++
            }
            val indent = before.substring(lineStart, indentEnd)
            // Text that came from Windows or a paste keeps its CRLF; a file
            // must not end up with both kinds of line ending.
            val newline = if (before.contains("\r\n")) "\r\n" else "\n"
            replacement = "$newline$indent"
            caret = start + replacement.length
        }
        input in CLOSERS && afterChar == input && beforeChar != '\\' -> {
            // The closer is already there: step over it.
            replacement = ""
            caret = start + 1
        }
        input in OPENERS -> {
            val partner = when (input) {
                '(' -> ')'
                '[' -> ']'
                '{' -> '}'
                else -> input
            }
            val quote = input == partner
            val afterWord = beforeChar.isLetterOrDigit() ||
                beforeChar == '_' ||
                beforeChar == '\\'
            val nextIsFree = afterChar == NONE ||
                afterChar.isWhitespace() ||
                afterChar in PAIR_FOLLOWERS
            if (!(quote && afterWord) && nextIsFree) {
                replacement = "$input$partner"
                caret = start + 1
            }
        }
    }
    if (replacement == input.toString() && caret == start + 1) return null
    return CodeGesture(start, replacement, caret)
}

/** Stands in for "there is no character here". */
private const val NONE = '\u0000'

private const val OPENERS = "([{\"'"
private const val CLOSERS = ")]}\"'"

/** What may follow a character for a quote beside it to be paired. */
private const val PAIR_FOLLOWERS = ")]}>,;:"
