## 1.0.7

* Added native IME composition support with preedit text isolation for CJK input (iOS, macOS, Windows, Android, web)
* Added IME buffer sync mirroring fragment text in the platform buffer for autocorrect and predictive text context
* Added platform-specific IME candidate window positioning for macOS CJK keyboards with caret rect tracking
* Added grapheme-aware text handling for emoji and surrogate pairs using the `characters` package for accurate grapheme cluster detection
* Added CJK-aware zero-width space (ZWS) caret stop filtering — ZWS between two CJK characters is skipped during cursor navigation
* Added ZWS-aware backspace deletion — backspace skips invisible ZWS and deletes the visible character; ZWS in empty table cells is preserved
* Added table cell preservation — empty table cells retain at least one fragment (ZWS) to remain navigable after backspace
* Added empty paragraph minimum height rendering so empty paragraphs and table cells remain clickable
* Added `getFragmentAtPosition` fallback for empty paragraphs so taps place the cursor correctly in empty cells
* Added web platform IME positioning with fragment-scoped transform, font sync, and delta range validation to prevent surrogate-pair corruption
* Added Windows IME buffer sync and grapheme-safe spell correction
* Added Android delta-based text operations with fragment-scoped buffer persistence for autocorrect context
* Added macOS Cmd+Backspace to delete to line start with platform-specific modifier mapping
* Added ArrowKeyRepeater support for macOS/iOS physical keyboards with backspace/delete/undo repeat support
* Added image resize mode with double-tap activation preventing selection/scroll interference during resize
* Added selective list index recalculation for affected nodes only to avoid full document tree walk
* Added undo/redo manager improvements for IME composition actions
* Fixed arrow key navigation to jump between top-level nodes when no line above/below exists
* Fixed arrow key navigation to collapse selection at edges and prevent duplicate handling
* Fixed scroll-to-cursor to use measured item heights instead of fixed estimate
* Fixed backspace to remove empty fragments and clean up empty Links and style wrappers that block navigation
* Fixed mobile-web gesture detection to distinguish tap/scroll/drag and prevent keyboard interference during scrolling
* Fixed web IME composition state corruption by tracking full synced text and setting composition flag before selection clearing
* Fixed iOS virtual keyboard backspace for empty paragraphs and fragment-start cursor positions with zero-width placeholder workaround
* Fixed IME buffer race conditions by syncing to new fragment after Enter and trusting document cursor position for backspace
* Fixed macOS IME commit to remove old preedit before applying final text to prevent ghost fragments
* Fixed structural change grace period to prevent platform echo duplication during paragraph splits on iOS/macOS

## 1.0.6

* Fixed `Unsupported operation: Platform._operatingSystem` error on web 

## 1.0.5

platform — `dart:io` `Platform` checks are now guarded with `kIsWeb`
* Fixed HTML import losing spaces around links — whitespace is now preserved by buffering consecutive text nodes before collapsing
* Fixed ODT import always assigning index 1 to ordered list items — now correctly increments item indices (1, 2, 3...)
* Fixed HTML import creating phantom empty paragraphs inside list items caused by trailing whitespace after `</ul>`/`</ol>`
* Fixed HTML import parsing of `<img>` tags, inline styles (`fontSize`, `color`), list indentation, and `listType` for `<ul>` elements
* Fixed ODT/DOCX import compilation errors related to `FluentCell` and `FluentImage` constructor usage
* Fixed type-checking order in export services — `Link` nodes are now correctly handled before `Paragraph`/`Fragment` checks
* Fixed HTML import `<a>` tag reconstruction preserving URL and inner text
* Fixed HTML import ordered list type detection from actual XML structure instead of style name string matching
* Various other bugfixes and stability improvements across import/export services
* Performance optimization

## 1.0.4

* Fixed keyboard not appearing after text selection on mobile web - now shows keyboard when drag selection ends

## 1.0.3

* Improved mobile web keyboard support - enabled hidden TextField for web browsers on mobile devices

## 1.0.2

* Fixed selection rendering when crossing multiple logical nodes during ctrl+shift+arrow (word selection)
* Added Linux-specific workaround for key repeat events to ensure selection highlights update in real-time during key hold

## 1.0.1

* Fixed cursor initialization to point to first paragraph in empty documents
* Improved modifier key tracking during key repeat events

## 1.0.0

* Initial release of FluentEditor
* Rich text editing with bold, italic, underline, strikethrough
* Paragraph styles (headings, normal text, code and quote)
* Ordered and unordered lists with nested sublists
* Tables with cell spanning support
* Image insertion and resizing (inline and block positioning)
* Hyperlink management
* Text color and highlight color support
* Text alignment (left, center, right, justify)
* Export to DOCX, ODT, and PDF formats
* Undo/Redo with intelligent action grouping
* Mouse and keyboard selection support
* Word count and character count
* Cut, copy, and paste with formatting support
* Precise cursor navigation with caret stops
* Localization support with FluentEditorLabels
