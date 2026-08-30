# JSON editor

JSON Editor is a built-in launcher command that opens a native, resizable document window. It edits
UTF-8 JSON source directly: TextKit 2 owns selection, Undo/Redo, Find and marked text, while Tinycast
adds line numbers, syntax colours and validation.

## Invariants

- `JSONEditorEngine` stays Foundation-only. Validation, transformation and syntax tokenization are pure
  and compiled verbatim by `json-editor-test`.
- The displayed string is the document. Formatting replaces that source through `NSTextView`, so the
  operation participates in the editor's Undo stack.
- Validation is debounced and runs off-main. A result carries the source revision it analyzed, so an
  older parse can never overwrite the status of newer text.
- A file becomes clean only after the exact source written to disk is still current when the write
  finishes. Editing during a save leaves the document marked as changed.
- New, Open and window close never discard an edited document without Tinycast's own confirmation.

## Structure

| File | Role |
| --- | --- |
| `Model/JSONEditorEngine.swift` | validation, pretty/minified output, issue positions and syntax tokens |
| `Service/JSONFileService.swift` | UTF-8 reads and atomic writes |
| `UI/JSONEditorCoordinator.swift` | window lifecycle, file panels, transformations and confirmations |
| `UI/JSONSourceEditor.swift` | the narrow TextKit 2 bridge and syntax application |
| `UI/JSONLineNumberRulerView.swift` | scrolling line numbers and click-to-select-line behavior |
| `UI/JSONEditorToolbarController.swift` | native macOS toolbar and document-edited state |

The editor is owned by `AppCore` and reached through `JSONEditorCoordinator`. The launcher command
hides the transient palette before opening the normal-level window. Closing tears down the window and
its SwiftUI/AppKit view tree; the coordinator remains the single long-lived owner.
