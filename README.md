<p align="center">
  <img src="logo.png" alt="FluentEditor" width="150"/>
</p>

<h1 align="center">Fluent Editor</h1>

<p align="center">
  <a href="https://flutter.dev">
    <img src="https://img.shields.io/badge/Flutter-3.11.4+-blue?logo=flutter" alt="Flutter Version">
  </a>
  <a href="https://github.com/exusr/fluent-editor/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License">
  </a>
  <a href="https://github.com/exusr/fluent-editor/releases">
    <img src="https://img.shields.io/badge/version-1.1.0-orange" alt="Version">
  </a>
  <a href="https://exusr.github.io/fluent-editor/">
    <img src="https://img.shields.io/badge/demo-live-brightgreen" alt="Live Demo">
  </a>
  <a href="https://github.com/sponsors/exusr">
    <img src="https://img.shields.io/badge/GitHub%20Sponsors-Sponsor%20%E2%9D%A4-brightgreen" alt="GitHub Sponsors">
  </a>
  <a href="https://www.producthunt.com/products/fluent-editor">
    <img src="https://img.shields.io/badge/Product%20Hunt-Vote-orange?logo=producthunt" alt="Product Hunt">
  </a>
</p>

A powerful and feature-rich word processor for Flutter applications, inspired by nature 🍃.

## Features

- **Rich Text Editing**: Bold, italic, underline, strikethrough, superscript, subscript, small caps
- **Paragraph Styles**: Headings (H1–H6), normal text, paragraph formatting
- **Lists**: Ordered and unordered lists with nested sublists and checkboxes
- **Tables**: Create and edit tables with cell spanning (colspan/rowspan)
- **Images**: Insert and resize images with inline and block positioning
- **Links**: Insert and manage hyperlinks
- **Colors**: Text color and highlight color support
- **Alignment**: Left, center, right, and justify text alignment
- **Export**: Export to DOCX, ODT, PDF, HTML, Markdown, and plain text
- **Import**: Import from DOCX, ODT, HTML, and Markdown
- **Undo/Redo**: Full undo/redo history with intelligent action grouping
- **Selection**: Mouse and keyboard selection support
- **Word Count**: Real-time word and character count
- **Clipboard**: Cut, copy, and paste with formatting support
- **Plugin System**: Extensible architecture for custom functionality

## Tested On

- **Web**: Chrome
- **Windows**: Windows 11
- **Linux**: Ubuntu, Debian, Fedora
- **macOS**: macOS 13+
- **iOS**: iOS 15+
- **Android**: Android 12+

## Plugins

| Plugin | Description |
|--------|-------------|
| [`fluent_editor_comments`](../fluent-editor-comments/) | Comments and annotations plugin — anchor comments to text ranges, reply, resolve, and manage discussion threads. |
| [`fluent_editor_review`](../fluent-editor-review/) | Track Changes / Review plugin — captures additions and deletions as reviewable suggestions with accept/reject workflow. |
| [`fluent_editor_character_map`](../fluent-editor-character-map/) | Special character grid, math symbols, and emoji picker. |

## Getting Started

Add Fluent Editor to your `pubspec.yaml`:

```yaml
dependencies:
  fluent_editor:
    git:
      url: https://github.com/exusr/fluent-editor.git
```

## Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:fluent_editor/fluent_editor.dart';

class MyEditor extends StatefulWidget {
  @override
  State<MyEditor> createState() => _MyEditorState();
}

class _MyEditorState extends State<MyEditor> {
  late final FluentDocument _document;

  @override
  void initState() {
    super.initState();
    _document = FluentDocument();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FluentEditor(
        document: _document,
        toolbarMode: FluentToolbarMode.fixed,
        labels: const FluentEditorLabels(), // English defaults
      ),
    );
  }
}
```

## Usage with Plugins

Fluent Editor uses a **plugin architecture** where external libraries register themselves through the `FluentEditorPlugin` API. The core editor has **zero dependencies** on any plugin library.

### Comments + Review (Track Changes)

```dart
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor_comments/fluent_editor_comments.dart';
import 'package:fluent_editor_review/fluent_editor_review.dart';

class EditorWithPlugins extends StatefulWidget {
  @override
  State<EditorWithPlugins> createState() => _EditorWithPluginsState();
}

class _EditorWithPluginsState extends State<EditorWithPlugins> {
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
    return FluentEditor(
      document: _document,
      plugins: [
        // Comments plugin — adds comment highlights and context menu actions
        FluentCommentPlugin(provider: _commentProvider),
        // Review plugin — adds Editing/Review mode toggle to the toolbar
        FluentSuggestionPlugin(controller: _suggestionController),
      ],
      // Bubble toolbar actions (e.g. "Add comment" on text selection)
      bubbleActions: [
        CommentBubbleAction(
          document: _document,
          provider: _commentProvider,
        ),
      ],
    );
  }
}
```

### Unified Sidebar

When both plugins are registered, the editor automatically merges comments and suggestions into a **single unified sidebar** (`FluentUnifiedSidebar`). Items are displayed in document order and scroll-synced with the text:

```dart
FluentEditor(
  document: _document,
  plugins: [
    FluentCommentPlugin(provider: _commentProvider),
    FluentSuggestionPlugin(controller: _suggestionController),
  ],
  // The sidebar is automatically resolved from registered plugins.
);
```

### Localization

All UI labels are localizable. The core editor uses `FluentEditorLabels`, and each plugin uses its own labels class that falls back to the core labels:

```dart
FluentEditor(
  document: _document,
  labels: FluentEditorLabels(
    file: 'Archivo',
    edit: 'Editar',
    insert: 'Insertar',
    format: 'Formato',
    sidebarTitle: 'Actividades y Revisiones',
    emptySidebarMessage: 'No hay comentarios ni sugerencias.',
  ),
  plugins: [
    FluentCommentPlugin(
      provider: _commentProvider,
      labels: FluentCommentLabels(
        addCommentLabel: 'Añadir comentario',
        resolveButton: 'Resolver',
      ),
    ),
    FluentSuggestionPlugin(
      controller: _suggestionController,
      labels: SuggestionLabels(
        editingMode: 'Edición',
        suggestingMode: 'Revisión',
        additionLabel: 'Adición',
        deletionLabel: 'Eliminación',
      ),
    ),
  ],
);
```

## Creating a Document Programmatically

```dart
final document = FluentDocument();

// Add a heading
final heading = Paragraph()
  ..styleName = 'heading1'
  ..fragments = [Fragment('Annual Report')];
document.content.nodes.add(heading);

// Add a formatted paragraph
final p = Paragraph()
  ..fragments = [
    Fragment('This is '),
    Fragment('bold text')..bold = true,
    Fragment(' and '),
    Fragment('italic text.')..italic = true,
  ];
document.content.nodes.add(p);

// Add a list
final listItem1 = ListItem(bulletType: 'ordered', indexList: [1])
  ..children = [Paragraph()..fragments = [Fragment('First item')]];
final listItem2 = ListItem(bulletType: 'ordered', indexList: [2])
  ..children = [Paragraph()..fragments = [Fragment('Second item')]];
final list = FluentList(listType: 'ordered')
  ..items = [listItem1, listItem2];
document.content.nodes.add(list);

// Add a 2×2 table
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
document.content.nodes.add(table);

// Add an image
final image = FluentImage(src: 'https://example.com/image.png')
  ..width = 300
  ..height = 200;
document.content.nodes.add(image);

// Add a link inside a paragraph
final link = Link(url: 'https://example.com')
  ..fragments = [Fragment('Click here')];
final linkParagraph = Paragraph()
  ..fragments = [Fragment('Visit '), link, Fragment(' for more info')];
document.content.nodes.add(linkParagraph);

// Add a horizontal rule
document.content.nodes.add(HorizontalRule());
```

## Plugin System

The plugin API allows external libraries to extend Fluent Editor without introducing compile-time coupling. See [DOCUMENTATION.md](DOCUMENTATION.md) for the full API reference.

### Creating a Custom Plugin

```dart
import 'package:fluent_editor/plugins/plugin_api.dart';

class MyPlugin extends FluentEditorPlugin {
  @override
  String get id => 'com.example.my_plugin';

  @override
  String get version => '1.0.0';

  // Register custom toolbar buttons
  @override
  List<FluentUiContribution> get ui => [
    FluentUiContribution(
      id: 'my_plugin.toolbar_button',
      location: FluentPluginUiLocation.toolbar,
      order: 5,
      builder: (context, document) => IconButton(
        icon: const Icon(Icons.star),
        onPressed: () { /* custom action */ },
      ),
    ),
  ];

  // Intercept text operations (return true = handled)
  @override
  bool onInsertCharacter(String character, FluentDocument document) => false;

  @override
  bool onBackspace(FluentDocument document, {bool ctrl = false, bool lineStart = false}) => false;

  // Contribute sidebar items
  @override
  List<FluentSidebarItem> buildSidebarItems(BuildContext context, FluentDocument document) => [];

  // Lifecycle hooks
  @override
  void attach(FluentPluginContext context) { /* called on registration */ }

  @override
  void detach(FluentPluginContext context) { /* called on disposal */ }
}
```

## Working with Selection

```dart
final cursor = document.cursor;

if (cursor.isCollapsed) {
  print('Cursor at ${cursor.anchorId}:${cursor.anchorOffset}');
} else {
  print('Selection from ${cursor.anchorId}:${cursor.anchorOffset} '
      'to ${cursor.focusId}:${cursor.focusOffset}');
}

// Move the cursor
cursor.moveTo(fragmentId, offset);

// Extend selection
cursor.focusTo(targetFragmentId, targetOffset);
```

## Additional Information

### Documentation

For detailed technical documentation, see [DOCUMENTATION.md](DOCUMENTATION.md).

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

### Issues

If you find any bugs or have feature requests, please open an issue on GitHub.
