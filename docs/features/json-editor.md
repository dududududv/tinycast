# JSON editor

JSON Editor is a built-in `PaletteScreen` rendered inside Tinycast's existing floating palette. It
edits UTF-8 JSON source directly: TextKit 2 owns selection, Undo/Redo, Find and marked text, while
Tinycast adds line numbers, syntax colours and validation without opening another editor window.

## Invariants

- `JSONEditorEngine` stays Foundation-only. Validation, transformation and syntax tokenization are pure
  and compiled verbatim by `json-editor-test`.
- The displayed string is the document. Formatting replaces that source through `NSTextView`, so the
  operation participates in the editor's Undo stack.
- Validation is debounced and runs off-main. A result carries the source revision it analyzed, so an
  older parse can never overwrite the status of newer text.
- A file becomes clean only after the exact source written to disk is still current when the write
  finishes. Editing during a save leaves the document marked as changed.
- Leaving or hiding the palette retains the draft. New and Open never discard an edited document
  without Tinycast's own confirmation.
- The TextKit scroll view clips at its AppKit boundary, so its ruler cannot draw
  through the status row or the palette footer after a resize or reactivation.

## Structure

| File | Role |
| --- | --- |
| `Model/JSONEditorEngine.swift` | validation, pretty/minified output, issue positions and syntax tokens |
| `Service/JSONFileService.swift` | UTF-8 reads and atomic writes |
| `UI/JSONEditorCoordinator.swift` | palette entry, file panels, transformations and confirmations |
| `UI/JSONEditorScreen.swift` | palette rows, footer action and the ⌘K action menu |
| `UI/JSONSourceEditor.swift` | the narrow TextKit 2 bridge and syntax application |
| `UI/JSONLineNumberRulerView.swift` | scrolling line numbers and click-to-select-line behavior |
| `UI/JSONEditorView.swift` | inline controls, source surface and status rows |

The editor is owned by `AppCore` and reached through `JSONEditorCoordinator`. The launcher command
switches `PaletteMode` to `.jsonEditor`; the coordinator remains the single long-lived owner so a
click-away or Pop to Root transition cannot lose an unsaved draft.

The toolbar offers a session-retained line-wrap toggle. The ruler uses text-system positions rather
than fixed line heights, including when a source line wraps. Invalid input exposes the parser's
message inline and a button to locate the issue. Typing an opening brace or bracket outside a string
inserts its partner; Return preserves indentation and expands an empty pair with two-space indentation.
Marked-text composition retains native behavior. A background transformation applies only
to the exact document revision it started with, so subsequent edits cannot be overwritten.

Plain-text paste prepares the resulting document and formats valid JSON off-main before inserting it
as one undoable edit. Invalid JSON is inserted unchanged for correction. Marked-text composition stays
native. Documents above 128,000 UTF-8 bytes skip full syntax tokenization and show a simplified-highlight
status; validation and formatting remain available. Line starts are rebuilt on source edits, then
cursor and ruler lookups use binary search. Ruler drawing has a bounded visible-line pass.
The top text inset always anchors ruler drawing to line one; hit testing starts inside the text area.
Counts are updated only on source edits, not on cursor movement. Syntax colours use distinct blue keys, green
strings, purple numbers and orange keywords with appearance-aware tokens.

The toolbar search button and Command-F open TextKit's find bar inside the editor scroll view rather
than a separate find panel. Command-G and Shift-Command-G navigate matches. Escape from the source
editor closes an open find bar before dismissing the palette. Large-text mode still supports Find.
