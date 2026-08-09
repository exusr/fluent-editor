# Fluent Editor Documentation 🍃

**Fluent Editor** is a powerful and feature-rich word processor for Flutter applications, designed to provide a rich text editing experience across all Flutter-supported platforms (Web, Windows, Linux, macOS, iOS, Android).

---

## Table of Contents

1. [Overview & Features](#1-overview--features)
2. [Installation & Setup](#2-installation--setup)
3. [Data Model Architecture](#3-data-model-architecture)
   - [FluentDocument & Node Structure](#fluentdocument--node-structure)
   - [Supported Content Nodes](#supported-content-nodes)
   - [Cursor & Selection Management](#cursor--selection-management)
   - [Undo / Redo System](#undo--redo-system)
4. [UI Components & Toolbar](#4-ui-components--toolbar)
   - [FluentEditor Widget](#fluenteditor-widget)
   - [Toolbar Modes](#toolbar-modes)
   - [Localization & Translations](#localization--translations)
5. [Document Import & Export](#5-document-import--export)
   - [Export Formats (DOCX, ODT, PDF, HTML, TXT)](#export-formats)
   - [Import Formats (DOCX, ODT, HTML, Markdown)](#import-formats)
6. [Plugin System & Extensions](#6-plugin-system--extensions)
   - [Plugin Architecture](#plugin-architecture)
   - [FluentEditorPlugin API](#fluenteditorplugin-api)
   - [Plugin Hooks Reference](#plugin-hooks-reference)
   - [Sidebar Items](#sidebar-items)
   - [Creating a Custom Plugin](#creating-a-custom-plugin)
7. [Ecosystem Plugins](#7-ecosystem-plugins)
   - [Comments Plugin](#comments-plugin)
   - [Review Plugin (Track Changes)](#review-plugin-track-changes)
   - [Character Map Plugin](#character-map-plugin)
8. [Full Integration Example](#8-full-integration-example)
9. [Testing & Code Quality](#9-testing--code-quality)

---

## 1. Overview & Features

Fluent Editor provides a comprehensive document editing engine similar to modern word processors (such as Microsoft Word, LibreOffice Writer, or Google Docs), while retaining the performance and customizability of a native Flutter component.

### Key Features
- **Rich Text Formatting**: Bold, italic, underline, strikethrough, highlight, text color, custom fonts, superscript, subscript, small caps.
- **Paragraph Styles & Headings**: Headings (H1–H6), normal text, block formatting, and alignment (left, center, right, justify).
- **Nested Lists**: Ordered and unordered lists with support for nesting levels and checkboxes.
- **Advanced Tables**: Create and edit tables with custom cell formatting, cell spanning (colspan/rowspan), column/row resize, and border styling.
- **Image Support**: Insert, resize, and align inline or block images.
- **Hyperlinks**: Insert and manage interactive URLs.
- **Real-Time Word Count**: Live word and character counter.
- **Clipboard Integration**: Cut, copy, and paste with full rich-text formatting preservation.
- **Revision History**: Intelligent Undo/Redo system based on atomic actions with automatic coalescing.
- **Plugin System**: Decoupled, extensible architecture where external libraries register through abstract hooks with zero compile-time coupling to the core.

---

## 2. Installation & Setup

### Environment Requirements
- **Dart SDK**: `>= 3.8.0`
- **Flutter**: `>= 3.24.0`

### Adding Dependencies
Add `fluent_editor` to your `pubspec.yaml`:

```yaml
dependencies:
  fluent_editor:
    git:
      url: https://github.com/exusr/fluent-editor.git
```

Or for local development:

```yaml
dependencies:
  fluent_editor:
    path: ../fluent-editor
```

---

## 3. Data Model Architecture

Fluent Editor strictly separates the document state (`FluentDocument`), model mutation logic, and UI rendering components (`FluentDocumentWidget`).

```
+-------------------------------------------------------+
|                    FluentDocument                     |
|                                                       |
|  +--------------------+      +---------------------+  |
|  |     Content        |      |       Cursor        |  |
|  | (List of Nodes)    |      | (Anchor & Focus)    |  |
|  +--------------------+      +---------------------+  |
|                                                       |
|  +--------------------+      +---------------------+  |
|  | UndoRedoManager    |      | FluentPluginRegistry|  |
|  +--------------------+      +---------------------+  |
+-------------------------------------------------------+
```

### FluentDocument & Node Structure

A `FluentDocument` represents the Abstract Syntax Tree (AST) of a document. It consists of a hierarchy of `FNode` objects, each representing a block or inline element.

### Supported Content Nodes

| Node | Description | Children |
|------|-------------|----------|
| `Paragraph` | Block of text containing styled fragments | `List<Fragment>` |
| `Fragment` | Contiguous character sequence with identical styles | — (leaf) |
| `Link` | Inline container wrapping text with a URL | `List<Fragment>` |
| `FluentTable` | Table structure | `List<FluentRow>` |
| `FluentRow` | Table row | `List<FluentCell>` |
| `FluentCell` | Table cell with optional colspan/rowspan | `List<Paragraph>` |
| `FluentList` | Ordered or unordered list | `List<ListItem>` |
| `ListItem` | List entry with bullet type and nesting level | `List<Paragraph>` |
| `FluentImage` | Image element (URL or base64) | — (atomic) |
| `HorizontalRule` | Block-level horizontal line divider | — (atomic) |

### Cursor & Selection Management

Text selection is managed via the `Cursor` class:
- **`anchorId` & `anchorOffset`**: Identifies the fragment ID and offset where selection started.
- **`focusId` & `focusOffset`**: Identifies where the selection head currently resides.
- **`isCollapsed`**: Boolean indicating whether selection is a single caret or a text range.

```dart
final cursor = document.cursor;

if (cursor.isCollapsed) {
  print('Cursor at ${cursor.anchorId}:${cursor.anchorOffset}');
} else {
  print('Selection from ${cursor.anchorId}:${cursor.anchorOffset} '
      'to ${cursor.focusId}:${cursor.focusOffset}');
}
```

### Undo / Redo System

Every mutation on `FluentDocument` is recorded in `UndoRedoManager`:
- Short typing actions are coalesced to prevent history fragmentation.
- Undo and Redo can be triggered programmatically via `document.undo()` or `document.redo()`.

---

## 4. UI Components & Toolbar

### FluentEditor Widget

The primary widget for embedding the editor in a Flutter UI:

```dart
import 'package:flutter/material.dart';
import 'package:fluent_editor/fluent_editor.dart';

class EditorPage extends StatefulWidget {
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final FluentDocument _document;

  @override
  void initState() {
    super.initState();
    _document = FluentDocument();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fluent Editor')),
      body: FluentEditor(
        document: _document,
        toolbarMode: FluentToolbarMode.fixed,
      ),
    );
  }
}
```

### Toolbar Modes

The `toolbarMode` property supports multiple layouts:
- **`FluentToolbarMode.fixed`**: Top-anchored primary toolbar.
- **`FluentToolbarMode.bubble`**: Floating context toolbar appearing above active text selection.
- **`FluentToolbarMode.none`**: Hides default toolbars for fully custom UI implementations.

### Localization & Translations

`FluentEditorLabels` enables complete UI localization. All default values are in **English**.

```dart
FluentEditor(
  document: _document,
  labels: FluentEditorLabels(
    file: 'Archivo',
    edit: 'Editar',
    insert: 'Insertar',
    format: 'Formato',
    sidebarTitle: 'Actividades y Revisiones',
    emptySidebarMessage: 'No hay comentarios ni sugerencias en el documento.',
  ),
)
```

Plugin libraries inherit labels from `FluentEditorLabels` via the document but also accept their own dedicated labels classes (`FluentCommentLabels`, `SuggestionLabels`) for more granular control.

---

## 5. Document Import & Export

Fluent Editor includes built-in converters in `lib/services/`:

### Export Formats
- **DOCX**: Native Microsoft Word (.docx) export retaining tables, styles, and formatting (`DocxExporter`).
- **ODT**: OpenDocument Text (.odt) format compatible with LibreOffice / OpenOffice (`OdtExporter`).
- **PDF**: Print-ready PDF documents with native font embedding (`ExportService`).
- **HTML & TXT**: Clean HTML markup or plain unformatted text.

```dart
import 'package:fluent_editor/services/export_service.dart';

// Export to PDF
final pdfBytes = await ExportService.exportToPdf(document);

// Export to DOCX
final docxBytes = await ExportService.exportToDocx(document);
```

### Import Formats
- `ImportDocxService`: Import `.docx` files.
- `ImportOdtService`: Import `.odt` files.
- `ImportHtmlService`: Parse HTML snippets or full documents.
- `ImportMarkdownService`: Convert Markdown syntax to document nodes.

---

## 6. Plugin System & Extensions

### Plugin Architecture

Fluent Editor's plugin system is designed around **complete decoupling**: the core editor has **zero compile-time dependencies** on any plugin library. Plugins communicate with the editor exclusively through:

1. **Abstract hooks** defined in `FluentEditorPlugin` (intercepting operations)
2. **Plugin registry** (`FluentPluginRegistry`) for registration and discovery
3. **Sidebar items** (`FluentSidebarItem`) for contributing UI cards

```
┌──────────────────────┐     ┌──────────────────────┐     ┌───────────────────────┐
│  fluent_editor       │     │ fluent_editor_       │     │ fluent_editor_        │
│  (core)              │     │ comments             │     │ review                │
│                      │     │                      │     │                       │
│  FluentEditorPlugin  │◄────│ FluentCommentPlugin  │     │ FluentSuggestionPlugin│
│  (abstract)          │     │ (implements)         │     │ (implements)          │
│                      │     │                      │     │                       │
│  FluentPluginRegistry│     │ FluentCommentProvider│     │ FluentSuggestion-     │
│                      │     │                      │     │ Controller            │
│  FluentUnifiedSidebar│     │ FluentCommentCard    │     │ FluentSuggestionCard  │
└──────────────────────┘     └──────────────────────┘     └───────────────────────┘
```

### FluentEditorPlugin API

Every plugin extends the `FluentEditorPlugin` abstract class:

```dart
abstract class FluentEditorPlugin {
  String get id;
  String get version;
  int get apiVersion => fluentPluginApiVersion;

  // Registration
  List<FluentPluginDependency> get dependencies => const [];
  List<FluentNodeDefinition<FNode>> get nodes => const [];
  List<FluentCommand> get commands => const [];
  List<FluentUiContribution> get ui => const [];
  List<FluentFormatContribution> get formats => const [];
  RenderStyleHook? get styleHook => null;

  // Sidebar
  List<FluentSidebarItem> buildSidebarItems(BuildContext context, FluentDocument document) => const [];

  // Lifecycle
  void attach(FluentPluginContext context) {}
  void detach(FluentPluginContext context) {}

  // Operation hooks (return true = handled, core editor skips default behavior)
  bool onInsertCharacter(String character, FluentDocument document) => false;
  bool onInsertText(String text, FluentDocument document) => false;
  bool onInsertNode(FluentDocument document, String nodeType, Map<String, dynamic> options) => false;
  bool onImeCompositionCommit(String text, FluentDocument document) => false;
  bool onBackspace(FluentDocument document, {bool ctrl = false, bool lineStart = false}) => false;
  bool onDelete(FluentDocument document, {bool ctrl = false}) => false;
  bool onDeleteNode(FluentDocument document, FNode node) => false;
  bool onEnter(FluentDocument document) => false;
  bool onTab(FluentDocument document, {required bool isShiftPressed}) => false;
  bool onReplaceSelection(String character, FluentDocument document) => false;

  // Table operation hooks
  bool onInsertTableRow(FluentDocument document, FluentTable table, int index) => false;
  bool onDeleteTableRow(FluentDocument document, FluentTable table, int index) => false;
  bool onInsertTableColumn(FluentDocument document, FluentTable table, int index) => false;
  bool onDeleteTableColumn(FluentDocument document, FluentTable table, int index) => false;
  bool onIncreaseTableRowspan(FluentDocument document, FluentTable table, FluentCell cell) => false;
  bool onDecreaseTableRowspan(FluentDocument document, FluentTable table, FluentCell cell) => false;
  bool onIncreaseTableColspan(FluentDocument document, FluentTable table, FluentCell cell) => false;
  bool onDecreaseTableColspan(FluentDocument document, FluentTable table, FluentCell cell) => false;
  bool onColumnResize(FluentDocument document, FluentTable table, int colIdx, double oldWidth, double newWidth) => false;
  bool onRowResize(FluentDocument document, FluentTable table, FluentRow row, double oldHeight, double newHeight) => false;

  // Notification hooks
  void onTextMutation(String paragraphId, int fromOffset, int delta) {}
  void onSaveState(FluentDocument document, String description) {}
  void onCommitSaveState(FluentDocument document, {SaveStateResult result = SaveStateResult.created}) {}
  void onUndo(FluentDocument document) {}
  void onRedo(FluentDocument document) {}

  // Query hooks
  bool isColumnResized(FluentDocument document, FluentTable table, int colIdx) => false;
  bool isRowResized(FluentDocument document, FluentTable table, FluentRow row) => false;
  bool isFormattingDisabled(FluentDocument document) => false;
  bool get isSuggestionMode => false;
}
```

### Plugin Hooks Reference

| Hook Category | Hooks | Return Semantics |
|---|---|---|
| **Text Operations** | `onInsertCharacter`, `onInsertText`, `onImeCompositionCommit`, `onReplaceSelection` | `true` = handled, skip default |
| **Deletion** | `onBackspace`, `onDelete`, `onDeleteNode` | `true` = handled, skip default |
| **Structure** | `onEnter`, `onTab`, `onInsertNode` | `true` = handled, skip default |
| **Table Operations** | `onInsertTableRow`, `onDeleteTableRow`, `onInsertTableColumn`, `onDeleteTableColumn` | `true` = handled, skip default |
| **Cell Spanning** | `onIncreaseTableRowspan`, `onDecreaseTableRowspan`, `onIncreaseTableColspan`, `onDecreaseTableColspan` | `true` = handled, skip default |
| **Resize** | `onColumnResize`, `onRowResize` | `true` = handled, skip default |
| **Notifications** | `onTextMutation`, `onSaveState`, `onCommitSaveState`, `onUndo`, `onRedo` | `void` — observation only |
| **Queries** | `isColumnResized`, `isRowResized`, `isFormattingDisabled`, `isSuggestionMode` | Boolean state query |

### Sidebar Items

Plugins contribute sidebar cards by returning `FluentSidebarItem` from `buildSidebarItems()`:

```dart
class FluentSidebarItem {
  final String id;            // Unique identifier
  final String nodeId;        // Document node this item is anchored to
  final DateTime createdAt;   // Creation timestamp (for ordering)
  final FluentSidebarItemCategory category;  // comment, suggestion, other
  final double estimatedHeight;
  final Widget widget;        // The card widget to render
}
```

Items from all registered plugins are merged into a single `FluentUnifiedSidebar` that displays comments and suggestions together in document order, with 1:1 scroll synchronization with the editor.

### Creating a Custom Plugin

```dart
import 'package:fluent_editor/plugins/plugin_api.dart';

class WordCountPlugin extends FluentEditorPlugin {
  int _wordCount = 0;

  @override
  String get id => 'com.example.word_count';

  @override
  String get version => '1.0.0';

  @override
  List<FluentUiContribution> get ui => [
    FluentUiContribution(
      id: 'word_count.status',
      location: FluentPluginUiLocation.toolbar,
      order: 99,
      builder: (context, document) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('$_wordCount words'),
      ),
    ),
  ];

  @override
  void onTextMutation(String paragraphId, int fromOffset, int delta) {
    // Recalculate word count on every text change
  }
}
```

---

## 7. Ecosystem Plugins

### Comments Plugin

**Package**: `fluent_editor_comments`

Provides inline comments anchored to text ranges with threaded replies and resolve/unresolve workflow.

See [`fluent_editor_comments/README.md`](../fluent-editor-comments/README.md) for full documentation.

```dart
FluentEditor(
  document: document,
  plugins: [
    FluentCommentPlugin(provider: commentProvider),
  ],
  bubbleActions: [
    CommentBubbleAction(document: document, provider: commentProvider),
  ],
);
```

### Review Plugin (Track Changes)

**Package**: `fluent_editor_review`

Provides a complete Track Changes workflow with Editing/Review mode toggle, visual markers for additions (green) and deletions (red strikethrough), and accept/reject actions.

See [`fluent_editor_review/README.md`](../fluent-editor-review/README.md) for full documentation.

```dart
FluentEditor(
  document: document,
  plugins: [
    FluentSuggestionPlugin(controller: suggestionController),
  ],
);
```

### Character Map Plugin

**Package**: `fluent_editor_character_map`

Adds a special character grid, math symbols, and emoji picker to the toolbar.

```dart
FluentEditor(
  document: document,
  plugins: [
    FluentCharacterMapPlugin(),
  ],
);
```

---

## 8. Full Integration Example

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor_comments/fluent_editor_comments.dart';
import 'package:fluent_editor_review/fluent_editor_review.dart';
import 'package:fluent_editor_character_map/fluent_editor_character_map.dart';

class FullEditorPage extends StatefulWidget {
  @override
  State<FullEditorPage> createState() => _FullEditorPageState();
}

class _FullEditorPageState extends State<FullEditorPage> {
  late final FluentDocument _document;
  final _commentProvider = FluentCommentProvider();
  final _suggestionController = FluentSuggestionController();

  @override
  void initState() {
    super.initState();
    _document = FluentDocument();
    _document.commentProvider = _commentProvider;
  }

  @override
  void dispose() {
    _commentProvider.dispose();
    _suggestionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fluent Editor')),
      body: FluentEditor(
        document: _document,
        toolbarMode: FluentToolbarMode.fixed,
        labels: const FluentEditorLabels(), // English defaults
        plugins: [
          // Character map: special characters and emoji
          FluentCharacterMapPlugin(),
          // Comments: inline annotations with replies
          FluentCommentPlugin(provider: _commentProvider),
          // Review: track changes with accept/reject
          FluentSuggestionPlugin(controller: _suggestionController),
        ],
        bubbleActions: [
          CommentBubbleAction(
            document: _document,
            provider: _commentProvider,
          ),
        ],
        // Sidebar is auto-resolved from plugins — shows comments + suggestions
        // in a single unified view, scroll-synced with the document.
      ),
    );
  }
}
```

---

## 9. Testing & Code Quality

Execute unit tests and static analysis:

```bash
# Run linter
flutter analyze

# Run test suite
flutter test
```

### Test Coverage

| Package | Tests | Status |
|---------|-------|--------|
| `fluent_editor` | 379 | ✅ All passing |
| `fluent_editor_review` | 83 | ✅ All passing |
| `fluent_editor_comments` | — | ✅ Static analysis clean |

---

*Updated for Fluent Editor version 1.0.7+*
