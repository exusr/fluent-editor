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
   - [Creating a Custom Plugin](#creating-a-custom-plugin)
   - [Ecosystem Plugins (Comments, Character Map)](#ecosystem-plugins)
7. [Code Examples](#7-code-examples)
8. [Testing & Code Quality](#8-testing--code-quality)

---

## 1. Overview & Features

Fluent Editor provides a comprehensive document editing engine similar to modern word processors (such as Microsoft Word, LibreOffice Writer, or Google Docs), while retaining the performance and customizability of a native Flutter component.

### Key Features
- **Rich Text Formatting**: Bold, italic, underline, strikethrough, highlight, text color, and custom fonts.
- **Paragraph Styles & Headings**: Headings (H1-H6), normal text, block formatting, and alignment (left, center, right, justify).
- **Nested Lists**: Ordered and unordered lists with support for nesting levels.
- **Advanced Tables**: Create and edit tables with custom cell formatting, cell spanning (colspan/rowspan), and border styling.
- **Image Support**: Insert, resize, and align inline or block images.
- **Hyperlinks**: Insert and manage interactive URLs.
- **Real-Time Word Count**: Live word and character counter.
- **Clipboard Integration**: Cut, copy, and paste with full rich-text formatting preservation.
- **Revision History**: Intelligent Undo/Redo system based on atomic actions with automatic coalescing.

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

A `FluentDocument` represents the Abstract Syntax Tree (AST) of a document. It consists of a hierarchy of `Node` objects, each representing a block or inline element.

### Supported Content Nodes

1. **`Paragraph`**: Represents a paragraph of text. Contains a list of `Fragment` instances or inline elements like `Link`.
2. **`Fragment`**: Represents a contiguous sequence of characters sharing identical style attributes (bold, color, font, etc.).
3. **`FluentTable`**: A table composed of `FluentRow` nodes, which contain `FluentCell` nodes.
4. **`FluentList` & `ListItem`**: Ordered (numbered) or unordered (bulleted) list structures.
5. **`FluentImage`**: Image element with attributes for width, height, source URL/base64, and alignment.
6. **`HorizontalRule`**: Block-level horizontal line divider.
7. **`Link`**: Inline container wrapping text fragments with a target URL.

### Cursor & Selection Management

Text selection is managed via the `Cursor` class:
- **`anchorId` & `anchorOffset`**: Identifies the fragment ID and offset where selection started.
- **`focusId` & `focusOffset`**: Identifies where the selection head currently resides.
- **`isCollapsed`**: Boolean indicating whether selection is a single caret or a text range.

```dart
final cursor = document.cursor;

if (cursor.isCollapsed) {
  print('Cursor positioned at fragment ${cursor.anchorId}:${cursor.anchorOffset}');
} else {
  print('Selection from ${cursor.anchorId}:${cursor.anchorOffset} to ${cursor.focusId}:${cursor.focusOffset}');
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

`FluentEditorLabels` enables complete UI localization:

```dart
FluentEditor(
  document: _document,
  labels: FluentEditorLabels(
    file: 'File',
    edit: 'Edit',
    insert: 'Insert',
    format: 'Format',
  ),
)
```

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

### Creating a Custom Plugin

Extend `FluentEditorPlugin` to register keyboard handlers, toolbar items, or custom node renderers:

```dart
import 'package:fluent_editor/plugins/plugin_api.dart';

class MyCustomPlugin extends FluentEditorPlugin {
  @override
  String get id => 'my_custom_plugin';

  @override
  String get name => 'My Custom Plugin';

  @override
  void initialize(FluentPluginRegistry registry) {
    // Register custom handlers or commands
  }
}
```

### Ecosystem Plugins
- **`fluent_editor_comments`**: Margins annotations, inline comments, and discussion threads.
- **`fluent_editor_character_map`**: Special character grid, math symbols, and emoji picker.

---

## 7. Code Examples

### Constructing Complex Documents Programmatically

```dart
final doc = FluentDocument();

// Add Heading
final heading = Paragraph()
  ..styleName = 'heading1'
  ..fragments = [Fragment('Annual Report')];
doc.content.nodes.add(heading);

// Add Formatted Paragraph
final p = Paragraph()
  ..fragments = [
    Fragment('This is '),
    Fragment('bold text')..bold = true,
    Fragment(' and '),
    Fragment('italic text.')..italic = true,
  ];
doc.content.nodes.add(p);

// Add 2x2 Table
final table = FluentTable()
  ..rows = [
    FluentRow()
      ..cells = [
        FluentCell()..fragments = [Fragment('Header 1')],
        FluentCell()..fragments = [Fragment('Header 2')],
      ],
    FluentRow()
      ..cells = [
        FluentCell()..fragments = [Fragment('Data 1')],
        FluentCell()..fragments = [Fragment('Data 2')],
      ],
  ];
doc.content.nodes.add(table);
```

---

## 8. Testing & Code Quality

Execute unit tests and static analysis:

```bash
# Run linter
flutter analyze

# Run test suite
flutter test
```

---

*Updated for Fluent Editor version 1.0.7+*
