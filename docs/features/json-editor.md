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
