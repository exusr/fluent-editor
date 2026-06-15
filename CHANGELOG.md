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
