package com.sanyzrn.nex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The code gestures the Android editor applies itself (2.9.0, step 5).
 *
 * They were Dart-only until the capture box stopped swapping editors, and the
 * Kotlin half cannot be exercised by a widget test. The rule is therefore a
 * pure function — [nexCodeGesture] — and this is it on the JVM: the same
 * cases `NexCodeInputFormatter` is held to, so a real keyboard's input can be
 * checked on a build machine.
 *
 * Run with `./gradlew testDebugUnitTest`, or compile the two files with
 * `kotlinc` and run JUnit directly (see the 2.9.0 progress log).
 */
class NexCodeGesturesTest {

    /** One character typed at [caret]; the answer after it, or null. */
    private fun typed(
        before: String,
        caret: Int,
        input: String,
    ): Pair<String, Int>? {
        val after = before.substring(0, caret) + input + before.substring(caret)
        val gesture = nexCodeGesture(
            before = before,
            beforeStart = caret,
            beforeEnd = caret,
            after = after,
            afterStart = caret + input.length,
            afterEnd = caret + input.length,
        ) ?: return null
        assertEquals("the gesture starts at the typed character", caret, gesture.start)
        return after.replaceRange(
            gesture.start,
            gesture.start + 1,
            gesture.replacement,
        ) to gesture.caret
    }

    @Test
    fun `enter keeps the indentation of the line above`() {
        assertEquals("  print\n  " to 10, typed("  print", 7, "\n"))
        assertEquals("\tif (ok)\n\t" to 10, typed("\tif (ok)", 8, "\n"))
        // No indent to carry: the newline is the whole edit.
        assertNull(typed("x", 1, "\n"))
        // Text with Windows line endings keeps them.
        assertEquals("  a\r\n  b\r\n  " to 12, typed("  a\r\n  b", 8, "\n"))
    }

    @Test
    fun `enter on an empty line adds nothing`() {
        assertNull(typed("", 0, "\n"))
    }

    @Test
    fun `brackets and braces write their partner with the caret inside`() {
        assertEquals("print()" to 6, typed("print", 5, "("))
        assertEquals("()" to 1, typed("", 0, "("))
        assertEquals("[]" to 1, typed("", 0, "["))
        assertEquals("{}" to 1, typed("", 0, "{"))
        assertEquals("f(a)[]" to 5, typed("f(a)", 4, "["))
    }

    @Test
    fun `a quote pairs at a line start or before a closer`() {
        assertEquals("\"\"" to 1, typed("", 0, "\""))
        assertEquals("''" to 1, typed("", 0, "'"))
        assertEquals("f(\"\")" to 3, typed("f()", 2, "\""))
    }

    @Test
    fun `a quote after a word or an escape is left alone`() {
        assertNull(typed("ab", 2, "\""))
        assertNull(typed("don't", 4, "'"))
        assertNull(typed("\\\\", 1, "\""))
    }

    @Test
    fun `typing the closer that is already there steps over it`() {
        assertEquals("f()" to 3, typed("f()", 2, ")"))
        assertEquals("[]" to 2, typed("[]", 1, "]"))
        assertEquals("\"\"" to 2, typed("\"\"", 1, "\""))
    }

    @Test
    fun `a paste, a selection and an ordinary letter are left alone`() {
        assertNull(typed("", 0, "print(\"a\")"))
        assertNull(typed("x", 0, "xy"))
        assertEquals(null, typed("abc", 3, "d"))

        val before = "abc"
        val after = "a(c"
        assertNull(
            nexCodeGesture(before, 1, 2, after, 2, 2),
        )
    }

    @Test
    fun `a change from Dart is left alone`() {
        assertNull(
            nexCodeGesture(
                before = "if (x)",
                beforeStart = 6,
                beforeEnd = 6,
                after = "if (x) {\n}",
                afterStart = 11,
                afterEnd = 11,
            ),
        )
    }
}
