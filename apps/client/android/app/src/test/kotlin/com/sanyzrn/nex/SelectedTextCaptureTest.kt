package com.sanyzrn.nex

import org.junit.Assert.*
import org.junit.Test

class SelectedTextCaptureTest {
    private val action = "android.intent.action.PROCESS_TEXT"

    @Test fun preservesPersianEnglishParagraphsAndSpaces() {
        val selected = "  سلام Nex\nحالت چطوره؟\nhttps://example.test  "
        assertEquals(selected, selectedTextForCapture(action, selected))
    }

    @Test fun styledTextIsCopiedWithoutChangingTheSource() {
        val source = StringBuilder("سلام selected words")
        val saved = selectedTextForCapture(action, source)
        source.append(" changed later")
        assertEquals("سلام selected words", saved)
    }

    @Test fun missingOrBlankSelectionsAreIgnored() {
        for (text in listOf(null, "", " ", "\n\t")) {
            assertNull(selectedTextForCapture(action, text))
        }
    }

    @Test fun otherIntentActionsCannotTriggerTheSelectionPath() {
        for (other in listOf(null, "android.intent.action.SEND", "android.intent.action.VIEW")) {
            assertNull(selectedTextForCapture(other, "unselected words"))
        }
    }
}
