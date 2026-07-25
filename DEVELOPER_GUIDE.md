# Developer Architecture Guide & Internals Reference — Fluent Editor 🍃

This document serves as the exhaustive technical developer guide for **Fluent Editor**. It covers internal data structures, rendering mathematics, event handler algorithms, and procedures for extending every layer of the package.

---

## Table of Contents

1. [Three-Tier Architecture & Data Flow](#1-three-tier-architecture--data-flow)
2. [Data Model & AST Deep Dive](#2-data-model--ast-deep-dive)
   - [Class Hierarchy (FNode, Node, Fragment)](#class-hierarchy-fnode-node-fragment)
   - [Complete JSON Schema Specification](#complete-json-schema-specification)
3. [Rendering Engine: RenderFluentParagraph & ParagraphRegistry](#3-rendering-engine-renderfluentparagraph--paragraphregistry)
   - [Fragment Position Tracking (_FragmentPosition)](#fragment-position-tracking-_fragmentposition)
   - [Virtualized Rendering & Caret Calculation at O(visible) Complexity](#virtualized-rendering--caret-calculation-at-ovisible-complexity)
   - [Hit Testing & Coordinate Mapping (x, y) <-> (fragmentId, offset)](#hit-testing--coordinate-mapping-x-y---fragmentid-offset)
   - [Inline WidgetSpans, Images, and IME Preedit Integration](#inline-widgetspans-images-and-ime-preedit-integration)
4. [Input Handling, Cursor, & Event Handler Algorithms](#4-input-handling-cursor--event-handler-algorithms)
   - [Selection Management & Normalization (Cursor & SelectionManager)](#selection-management--normalization-cursor--selectionmanager)
   - [Backspace Handling Algorithm (handle_backspace.dart)](#backspace-handling-algorithm-handle_backspacedart)
   - [Enter Handling & Paragraph Splitting Algorithm (handle_enter.dart)](#enter-handling--paragraph-splitting-algorithm-handle_enterdart)
   - [Vertical Navigation & preferredX Persistence (handle_arrow_key.dart)](#vertical-navigation--preferredx-persistence-handle_arrow_keydart)
   - [Multi-MIME Clipboard Integration (handle_clipboard.dart)](#multi-mime-clipboard-integration-handle_clipboarddart)
5. [Undo/Redo System & Atomic Transactions (DocumentDelta)](#5-undoredo-system--atomic-transactions-documentdelta)
6. [Exporter / Importer Architecture (DOCX, ODT, PDF, HTML)](#6-exporter--importer-architecture-docx-odt-pdf-html)
   - [OpenXML (DOCX) & OpenDocument (ODT) Generation](#openxml-docx--opendocument-odt-generation)
   - [PDF Layout Pagination & Canvas Painting](#pdf-layout-pagination--canvas-painting)
7. [Extending Fluent Editor & Custom Plugin Development](#7-extending-fluent-editor--custom-plugin-development)

---

## 1. Three-Tier Architecture & Data Flow

Fluent Editor enforces a strict decoupling between document state (`FluentDocument`), layout and rendering objects (`RenderFluentParagraph` and `ParagraphRegistry`), and Flutter UI widgets (`FluentEditor`, `FluentDocumentWidget`).

```
+-----------------------------------------------------------------------------------+
|                                  FLUTTER UI LAYER                                 |
|                                                                                   |
|   [FluentEditor]                                                                  |
|         |                                                                         |
|         v                                                                         |
|   [FluentDocumentWidget] ---> (Toolbar, Sidebars, Bubble Menu)                    |
|         |                                                                         |
|         v                                                                         |
|   [NodeWidgetBuilder]                                                             |
+-----------------------------------------------------------------------------------+
                                          |
                                          | (Build & Updates)
                                          v
+-----------------------------------------------------------------------------------+
|                                 RENDERING LAYER                                   |
|                                                                                   |
|   [RenderFluentParagraph] <=====================> [ParagraphRegistry]             |
|    - Single TextPainter per paragraph              - Visible Renders (Viewport)   |
|    - Inline WidgetSpans (Images)                   - Caret Global Coordinates     |
|    - IME Preedit Underline                         - Vertical Nearest Paragraph   |
+-----------------------------------------------------------------------------------+
                                          ^
                                          | (Synchronization)
                                          v
+-----------------------------------------------------------------------------------+
|                                  MODEL LAYER                                      |
|                                                                                   |
|   [FluentDocument]                                                                |
|    ├── Content (Tree of Nodes: Paragraph, Table, List, Image, HR)                 |
|    ├── Cursor (Anchor Stop & Focus Stop)                                          |
|    ├── UndoRedoManager (Stack of DocumentDelta with Coalescing)                   |
|    └── FluentPluginRegistry (Keyboard & Toolbar Hook Extensions)                  |
+-----------------------------------------------------------------------------------+
```

---

## 2. Data Model & AST Deep Dive

### Class Hierarchy

All document elements derive from the base interface `FNode` and its implementation `Node`:

- **`FNode`**: Fundamental interface providing a unique `id` (generated via `nanoid`).
- **`Node`**: Abstract base class for document nodes. Contains references to its `parent` node.
- **`ContainerNode`**: Abstract node capable of hosting child nodes (`children`).
- **`InlineContainerNode`**: Specialized container for inline text elements (e.g., `Paragraph`, `ListItem`, `FluentCell`).
- **`Paragraph`**: Represents a block of formatted text. Its children are `Fragment` instances or inline nodes like `Link`.
- **`Fragment`**: Represents a contiguous segment of text with atomic attributes (`bold`, `italic`, `underline`, `strikethrough`, `textColor`, `backgroundColor`, `fontFamily`, `fontSize`, `superscript`, `subscript`).
- **`FluentTable`**: Table node containing a list of `FluentRow` nodes, which contain `FluentCell` nodes.
- **`FluentList`**: Container for ordered or unordered lists, holding `ListItem` instances.
- **`FluentImage`**: Node representing graphics with `src`, `width`, `height`, and `alignment`.
- **`HorizontalRule`**: Non-text block node drawing a horizontal line divider.

### Complete JSON Schema Specification

All nodes are serializable and deserializable via JSON (`nodeFromJson` and `node.toJson()` in `lib/factories.dart`).

#### JSON Schema: Paragraph & Fragments
```json
{
  "id": "p_8923a1",
  "type": "paragraph",
  "styleName": "heading1",
  "textAlign": "left",
  "fragments": [
    {
      "id": "f_1092ab",
      "type": "fragment",
      "text": "Document Title",
      "bold": true,
      "fontSize": 24.0,
      "textColor": 4278190080
    }
  ]
}
```

#### JSON Schema: Table
```json
{
  "id": "tbl_4492a",
  "type": "table",
  "rows": [
    {
      "id": "row_11a",
      "cells": [
        {
          "id": "cell_1a",
          "colSpan": 1,
          "rowSpan": 1,
          "fragments": [
            { "id": "f_99a", "type": "fragment", "text": "Header" }
          ]
        }
      ]
    }
  ]
}
```

---

## 3. Rendering Engine: RenderFluentParagraph & ParagraphRegistry

Text rendering is driven by `RenderFluentParagraph` in `lib/renderers/render_paragraph.dart`, extending `RenderBox` and registering with `ParagraphRegistry`.

### Fragment Position Tracking (_FragmentPosition)

During `performLayout()`, `RenderFluentParagraph` builds a list of `_FragmentPosition`:

```dart
class _FragmentPosition {
  final String id;
  final int start;
  final int end;
  final bool isImage;

  int get textLength => end - start;
  bool contains(int offset) => offset >= start && offset < end;
  int toLocal(int globalOffset) => globalOffset - start;
  int toGlobal(int localOffset) => start + localOffset;
}
```

This maps individual `Fragment` local offsets to a single continuous text index evaluated by `TextPainter`.

### Virtualized Rendering & Caret Calculation at O(visible) Complexity

To prevent an $O(N)$ full-document scan during keypresses or cursor blinking:

1. **Viewport Notification**: As paragraph widgets enter the viewport via `ListView.builder`, they invoke `registry.markVisible(containerId)`.
2. **Selective Scan**: `ParagraphRegistry.resolveCaretX()` and `resolveCaretY()` inspect `_visibleContainerIds` first.

```dart
double resolveCaretX(CaretStop stop) {
  // 1. High-performance scan over visible viewport paragraphs (O(visible))
  for (final id in _visibleContainerIds) {
    final render = _renders[id];
    if (render != null) {
      final x = render.getCaretX(stop.fragmentId, stop.offset);
      if (x != null) return x;
    }
  }
  // 2. Fallback to off-screen renders only if unresolvable
  for (final render in _renders.values) {
    final x = render.getCaretX(stop.fragmentId, stop.offset);
    if (x != null) return x;
  }
  return 0.0;
}
```

### Hit Testing & Coordinate Mapping (x, y) <-> (fragmentId, offset)

Upon touch/click events:
1. `RenderFluentParagraph.hitTestSelf()` intercepts the event.
2. `getPositionForOffset(Offset localOffset)` calls `_painter.getPositionForOffset(localOffset)`.
3. The returned `TextPosition` provides the global paragraph offset.
4. `_fragmentPositionMap` maps the global offset back to the native `fragmentId` and local fragment offset.

### Inline WidgetSpans, Images, and IME Preedit Integration

- **Inline Images**: Images inside paragraphs are converted into `PlaceholderSpan` / `WidgetSpan` within `TextPainter`. `RenderFluentParagraph` lays out and paints child RenderBox objects (`collectInlineImages`) at placeholder dimensions.
- **IME Preedit**: During active IME text composition, `imePreeditText` is injected into `TextSpan` with a blue dashed underline (`TextDecoration.underline`).

---

## 4. Input Handling, Cursor, & Event Handler Algorithms

### Selection Management & Normalization (Cursor & SelectionManager)

The `Cursor` class models caret position or active range selection:
- **`anchorId` / `anchorOffset`**: Selection starting point.
- **`focusId` / `focusOffset`**: Current selection head.

`SelectionManager` normalizes ranges into ordered `(startStop, endStop)` tuples, regardless of forward or backward selection dragging.

### Backspace Handling Algorithm (handle_backspace.dart)

When `Backspace` is pressed:

1. **Active Range Selection (`!cursor.isCollapsed`)**:
   - Triggers `handleReplaceSelection(document, '')` to delete the selected range atomically.

2. **Caret at Fragment Offset 0 (`offset == 0`)**:
   - **`ListItem` Node**: Decreases list indentation (`indentLevel - 1`). If `indentLevel == 0`, converts `ListItem` into a standard `Paragraph`.
   - **Paragraph First Fragment**: If the current paragraph follows another paragraph, its contents are merged into the preceding paragraph. The current paragraph is removed from the AST.
   - **`FluentTable` / `FluentImage` Nodes**: If the preceding node is a block element, the cursor shifts or selects the element.

3. **Inline Text (`offset > 0`)**:
   - Deletes the preceding character using Unicode grapheme cluster ranges (`characters.getRange(offset - 1, offset)`).

### Enter Handling & Paragraph Splitting Algorithm (handle_enter.dart)

When `Enter` is pressed:

1. **Tables (`FluentCell`)**: Inserts a `\n` or creates a new cell paragraph.
2. **Lists (`ListItem`)**:
   - If the current `ListItem` is empty, pressing Enter exits the list and creates a normal paragraph below.
   - If populated, creates a new `ListItem` inheriting `bulletType` and indentation.
3. **Paragraphs (`Paragraph`)**:
   - Splits the `Paragraph` into two distinct nodes at the cursor position.
   - Fragments to the left remain in the original paragraph; fragments to the right transfer to the new paragraph.

### Vertical Navigation & preferredX Persistence (handle_arrow_key.dart)

During Up/Down arrow navigation:
- As the caret moves across lines of varying lengths, the editor records the initial horizontal coordinate (`preferredX`).
- On each line change, the editor selects the character closest to `preferredX`.
- Left/Right arrow movements reset `preferredX`.

### Multi-MIME Clipboard Integration (handle_clipboard.dart)

During Copy / Cut actions:
- Generates `text/plain`, `text/html`, and native JSON payloads (`application/fluent-editor-json`).
- During Paste, the editor checks payloads in order: Native JSON $\rightarrow$ HTML $\rightarrow$ Plain Text.

---

## 5. Undo/Redo System & Atomic Transactions (DocumentDelta)

Mutations generate a `DocumentDelta` object:

```dart
class DocumentDelta {
  final List<FNode> targetNodes;
  final DocumentDeltaType type;
  final Map<String, dynamic> beforeState;
  final Map<String, dynamic> afterState;
  final DateTime timestamp;
}
```

### Coalescing Algorithm

During continuous typing:
1. `UndoRedoManager` evaluates the timestamp delta.
2. If typing continues within a $1000\text{ ms}$ threshold in the same fragment, current mutations coalesce into the top `DocumentDelta` stack entry.

---

## 6. Exporter / Importer Architecture (DOCX, ODT, PDF, HTML)

### OpenXML (DOCX) & OpenDocument (ODT) Generation

- **DOCX (`DocxExporter`)**:
  - Builds an in-memory ZIP archive using package `archive`.
  - Generates OpenXML DOM structures: `<w:p>` (paragraphs), `<w:r>` (runs), `<w:rPr>` (run properties), and `<w:tbl>` (tables).
- **ODT (`OdtExporter`)**:
  - Generates OASIS OpenDocument `content.xml` translating paragraphs to `<text:p>` and lists to `<text:list>`.

### PDF Layout Pagination & Canvas Painting

`ExportService.exportToPdf()` uses `pdf/widgets.dart`:
- Converts `FluentDocument` AST into `pdf.Widget.Document` layout structures.
- Employs native font embedding via `pdf_font_provider.dart` for offline UTF-8 and special character rendering.

---

## 7. Extending Fluent Editor & Custom Plugin Development

Example of a custom plugin adding a keyboard shortcut (`Ctrl+Shift+S`) to insert a signature block:

```dart
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';
import 'package:flutter/services.dart';

class SignaturePlugin extends FluentEditorPlugin {
  @override
  String get id => 'signature_plugin';

  @override
  String get name => 'Signature & Quick Snippets Plugin';

  @override
  void initialize(FluentPluginRegistry registry) {}

  @override
  bool onKeyEvent(KeyEvent event, FluentDocument document) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyS &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      
      final p = Paragraph()
        ..fragments = [
          Fragment('Best regards,\n'),
          Fragment('Development Team')..bold = true,
        ];
      
      document.content.nodes.add(p);
      document.notifyListeners();
      return true; // Handled
    }
    return false;
  }
}
```

---

*Developer Architecture Guide — Fluent Editor v1.0.7+*
