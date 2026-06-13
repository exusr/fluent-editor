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
    <img src="https://img.shields.io/badge/version-1.0.2-orange" alt="Version">
  </a>
  <a href="https://exusr.github.io/fluent-editor/">
    <img src="https://img.shields.io/badge/demo-live-brightgreen" alt="Live Demo">
  </a>
</p>

A powerful and feature-rich rich word processor for Flutter applications, inspired by nature 🍃.

## Features

- **Rich Text Editing**: Support for bold, italic, underline, strikethrough, and more
- **Paragraph Styles**: Headings, normal text, and paragraph formatting
- **Lists**: Ordered and unordered lists with nested sublists
- **Tables**: Create and edit tables with cell spanning
- **Images**: Insert and resize images with inline and block positioning
- **Links**: Insert and manage hyperlinks
- **Colors**: Text color and highlight color support
- **Alignment**: Left, center, right, and justify text alignment
- **Export**: Export to DOCX, ODT, and PDF formats
- **Undo/Redo**: Full undo/redo history with intelligent action grouping
- **Selection**: Mouse and keyboard selection support
- **Word Count**: Real-time word and character count
- **Clipboard**: Cut, copy, and paste with formatting support

## Tested On

- **Web**: Chrome
- **Windows**: Windows 11
- **Linux**: Ubuntu, Debian, Fedora
- **macOS**: macOS 13+
- **iOS**: iOS 15+
- **Android**: Android 12+

## Plugins

- **fluent_editor_spellcheck** — Hunspell-based spell-check plugin with isolate-backed checking, and multi-language support. (WIP)
- **fluent_editor_comments** - Comments and annotations plugin. (WIP)
- **fluent_editor_review** - Review plugin for track changes and comments. (WIP)

## Getting Started

Add Fluent Editor to your `pubspec.yaml`:

```yaml
dependencies:
  fluent_editor:
    git:
      url: https://github.com/exusr/fluent-editor.git
```

## Usage

```dart
import 'package:fluent_editor/fluent_editor.dart';

class MyEditor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FluentEditor(
      document: FluentDocument(),
      labels: FluentEditorLabels( //translate labels
        file: 'File',
        edit: 'Edit',
        insert: 'Insert',
        format: 'Format',
      ),
    );
  }
}
```

### Creating a Document

```dart
final document = FluentDocument();

// Add a paragraph
final paragraph = Paragraph()
  ..fragments = [Fragment('Hello, World!')];
document.content.nodes.add(paragraph);

// Add a heading
final heading = Paragraph()
  ..styleName = 'heading1'
  ..fragments = [Fragment('Title')];
document.content.nodes.add(heading);

// Add a list
final listItem1 = ListItem(bulletType: 'ordered', indexList: [1])
  ..children = [Paragraph()..fragments = [Fragment('First item')]];
final listItem2 = ListItem(bulletType: 'ordered', indexList: [2])
  ..children = [Paragraph()..fragments = [Fragment('Second item')]];
final list = FluentList(listType: 'ordered')
  ..items = [listItem1, listItem2];
document.content.nodes.add(list);

// Add an image
final image = FluentImage(src: 'https://example.com/image.png')
  ..width = 300
  ..height = 200;
document.content.nodes.add(image);

// Add a table
final cell1 = FluentCell()..fragments = [Fragment('Cell 1')];
final cell2 = FluentCell()..fragments = [Fragment('Cell 2')];
final row = FluentRow()..cells = [cell1, cell2];
final table = FluentTable()..rows = [row];
document.content.nodes.add(table);

// Add a link
final link = Link(url: 'https://example.com')
  ..fragments = [Fragment('Click here')];
final linkParagraph = Paragraph()
  ..fragments = [Fragment('Visit '), link, Fragment(' for more info')];
document.content.nodes.add(linkParagraph);

// Add a horizontal line
final hr = HorizontalRule();
document.content.nodes.add(hr);
```

### Working with Selection

```dart
// Get the current cursor position
final cursor = document.cursor;
final fragmentId = cursor.anchorId;
final offset = cursor.anchorOffset;

// Check if there's a selection
if (cursor.isCollapsed) {
  // Cursor is collapsed (no selection)
  print('Cursor at $fragmentId:$offset');
} else {
  // There's a selection
  print('Selection from ${cursor.anchorId}:${cursor.anchorOffset} to ${cursor.focusId}:${cursor.focusOffset}');
}

// Move the cursor (collapses selection)
cursor.moveTo(fragmentId, offset);

// Extend selection (creates or updates selection)
cursor.focusTo(targetFragmentId, targetOffset);

// Get selection offsets for a specific fragment
final paragraph = document.content.nodes.first as Paragraph;
final fragment = paragraph.fragments.first;
final selectionOffsets = cursor.getOffsets(paragraph, fragment);
if (selectionOffsets.$1 != -1) {
  print('Selection in fragment: ${selectionOffsets.$1} to ${selectionOffsets.$2}');
}
```

## Additional Information

### Documentation

For more detailed documentation and examples, see the `/example` folder.

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### License

This project is licensed under the MIT License - see the LICENSE file for details.

### Issues

If you find any bugs or have feature requests, please open an issue on GitHub.
