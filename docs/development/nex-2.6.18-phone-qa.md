# Nex 2.6.18 — Phone verification

This release applies the reviewed visual + motion audit on the 2.6.17 baseline. Manual QA is required before merging and tagging.

1. **Upgrade safety** — install over 2.6.17; verify notes, attachments, tags, reminders, vault, and preferences are intact. Do not uninstall the existing app.
2. **Themes & legibility** — inspect Light, Dark, Night, and System. Verify vault card faces, banner action labels, urgent fire marker, module hues, switches, tag counts, and badge text.
3. **Persian + RTL** — review long Persian notes, mixed Persian/English cards, attachment badges, and recurring counters. Check clipping at different text scales and densities.
4. **Motion accessibility** — with Android *Remove animations* enabled, open/close sheets, swipe back, visit camera, onboarding, and AI/chat. No disruptive transitions or spinning progress indicators should continue.
5. **Default motion** — turn *Remove animations* off; camera shutter, navigation, onboarding, filter chips, reminder bell, card fold/unfold, and words review should still animate smoothly.
6. **Haptics** — check checklist row vs completed checklist, reminders (manual wheel and quick presets), switches, assistant button, camera shutter, successful notice, and failure notice; ensure no duplicate vibrations.
7. **Timeline performance** — populate the mixed-media library (short notes, long notes, Markdown, photos and links); scroll, expand/collapse date groups, filter tags, and open/close details without stutter.
8. **Regression** — create, edit and delete a note with Undo; open a reminder from notification; import a file; backup and restore in a safe test environment. Ensure the store build's update policy stays unchanged.

If any test fails, keep the PR unmerged and document the device, Android version, theme, language, reproduction steps, and screenshot/logs.

## Audit scope
This patch addresses 14 visual and 14 motion findings; larger structural refactors explicitly excluded by the source audit are not included. The baseline application revision is `85fcb427`.
