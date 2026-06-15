import 'package:fluent_editor/factories.dart';

/// Service for importing Markdown into FluentEditor nodes.
class ImportMarkdownService {
  Root importFromMarkdown(String md) {
    try {
      final lines = md.split('\n');
      final nodes = <FNode>[];
      int i = 0;

      while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Horizontal rule
      if (RegExp(r'^(---|\*\*\*|___)\s*$').hasMatch(trimmed)) {
        nodes.add(HorizontalRule());
        i++;
        continue;
      }

      // Heading
      if (trimmed.startsWith('#')) {
        final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
        if (match != null) {
          final level = match.group(1)!.length;
          final text = match.group(2)!;
          nodes.add(Paragraph(
            text: '',
            styleName: 'heading$level',
          )..fragments = _parseInline(text));
          i++;
          continue;
        }
      }

      // Blockquote
      if (trimmed.startsWith('>')) {
        final buffer = StringBuffer();
        while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
          buffer.writeln(lines[i].trimLeft().substring(1).trimLeft());
          i++;
        }
        nodes.add(Paragraph(
          text: '',
          styleName: 'quote',
        )..fragments = _parseInline(buffer.toString().trim()));
        continue;
      }

      // Code block
      if (trimmed.startsWith('```')) {
        i++;
        final buffer = StringBuffer();
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buffer.writeln(lines[i]);
          i++;
        }
        i++;
        nodes.add(Paragraph(
          text: '',
          styleName: 'code',
        )..fragments = [Fragment(buffer.toString().trimRight())]);
        continue;
      }

      // Table
      if (line.trim().startsWith('|')) {
        final table = _parseTable(lines, i);
        if (table != null) {
          nodes.add(table.node);
          i = table.nextIndex;
          continue;
        }
      }

      // Checkbox list
      if (RegExp(r'^(\s*)-\s\[[ x~]\]\s').hasMatch(line)) {
        final list = _parseCheckboxList(lines, i);
        nodes.add(list.node);
        i = list.nextIndex;
        continue;
      }

      // Unordered list
      if (RegExp(r'^(\s*)[-*+]\s').hasMatch(line)) {
        final list = _parseList(lines, i, 'bullet');
        nodes.add(list.node);
        i = list.nextIndex;
        continue;
      }

      // Ordered list
      if (RegExp(r'^(\s*)\d+\.\s').hasMatch(line)) {
        final list = _parseList(lines, i, 'ordered');
        nodes.add(list.node);
        i = list.nextIndex;
        continue;
      }

      // Regular paragraph
      final buffer = StringBuffer();
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        buffer.write(lines[i].trim());
        if (i < lines.length - 1 && lines[i + 1].trim().isNotEmpty) {
          buffer.write(' ');
        }
        i++;
      }
      nodes.add(Paragraph(text: '')..fragments = _parseInline(buffer.toString()));
    }

      return Root(nodes: nodes.isEmpty ? [Paragraph(text: '')] : nodes);
    } catch (e) {
      // Gracefully return a document with the error as a paragraph
      return Root(nodes: [Paragraph(text: 'Import error: $e')]);
    }
  }

  ({FluentTable node, int nextIndex})? _parseTable(List<String> lines, int start) {
    final rows = <FluentRow>[];
    int i = start;
    while (i < lines.length && lines[i].trim().startsWith('|')) {
      final row = _parseTableRow(lines[i]);
      if (row != null) rows.add(row);
      i++;
    }
    // Skip separator line if present
    if (rows.length >= 2) {
      final secondCells = rows[1].cells;
      final isSep = secondCells.every((c) {
        final text = c.children.whereType<Paragraph>().map((p) => p.text).join().trim();
        return RegExp(r'^-+\s*$').hasMatch(text) || text.isEmpty;
      });
      if (isSep) rows.removeAt(1);
    }
    if (rows.isEmpty) return null;
    return (node: FluentTable(rows: rows), nextIndex: i);
  }

  FluentRow? _parseTableRow(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|')) return null;
    final parts = trimmed
        .substring(1)
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    final cells = parts.map((text) {
      return FluentCell(
        children: [Paragraph(text: '')..fragments = _parseInline(text)],
      );
    }).toList();
    return FluentRow(cells: cells);
  }

  ({FluentList node, int nextIndex}) _parseList(List<String> lines, int start, String listType) {
    final items = <ListItem>[];
    int i = start;
    final baseIndent = _leadingSpaces(lines[i]);

    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      final currentIndent = _leadingSpaces(line);
      if (currentIndent < baseIndent) break;

      final bulletMatch = RegExp(r'^(\s*)(?:[-*+]|\d+\.)\s+(.*)$').firstMatch(line);
      if (bulletMatch == null) break;

      // Verify bullet type matches expected list type (prevent cross-list consumption)
      final lineIsOrdered = RegExp(r'^(\s*)\d+\.(\s|$)').hasMatch(line);
      if ((listType == 'ordered' && !lineIsOrdered) || (listType == 'bullet' && lineIsOrdered)) {
        break;
      }

      final text = bulletMatch.group(2)!;
      final children = <FNode>[Paragraph(text: '')..fragments = _parseInline(text)];
      i++;

      // Check for sub-lists or continuation lines
      while (i < lines.length) {
        final nextLine = lines[i];
        if (nextLine.trim().isEmpty) {
          i++;
          continue;
        }
        final nextIndent = _leadingSpaces(nextLine);
        if (nextIndent > baseIndent) {
          if (RegExp(r'^(\s*)(?:[-*+]|\d+\.)\s').hasMatch(nextLine)) {
            final isOrdered = RegExp(r'^(\s*)\d+\.\s').hasMatch(nextLine);
            final subList = _parseList(lines, i, isOrdered ? 'ordered' : 'bullet');
            children.add(subList.node);
            i = subList.nextIndex;
          } else {
            children.add(Paragraph(text: '')..fragments = _parseInline(nextLine.trimLeft()));
            i++;
          }
        } else {
          break;
        }
      }

      final bulletType = listType == 'ordered' ? 'ordered' : 'bullet';
      final index = listType == 'ordered' ? items.length + 1 : 1;
      items.add(ListItem(
        bulletType: bulletType,
        indexList: [index],
        children: children,
      ));
    }

    final list = FluentList(listType: listType);
    list.items.addAll(items);
    return (node: list, nextIndex: i);
  }

  ({FluentList node, int nextIndex}) _parseCheckboxList(List<String> lines, int start) {
    final items = <ListItem>[];
    int i = start;
    final baseIndent = _leadingSpaces(lines[i]);

    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      final currentIndent = _leadingSpaces(line);
      if (currentIndent < baseIndent) break;

      final match = RegExp(r'^(\s*)-\s\[([ x~])\]\s+(.*)$').firstMatch(line);
      if (match == null) break;

      final checked = match.group(2);
      final text = match.group(3)!;
      final bulletType = switch (checked) {
        'x' => 'checkbox-checked',
        '~' => 'checkbox-crossed',
        _ => 'checkbox-unchecked',
      };

      items.add(ListItem(
        bulletType: bulletType,
        indexList: [1],
        children: [Paragraph(text: '')..fragments = _parseInline(text)],
      ));
      i++;
    }

    final list = FluentList(listType: 'bullet');
    list.items.addAll(items);
    return (node: list, nextIndex: i);
  }

  int _leadingSpaces(String s) {
    int count = 0;
    for (final ch in s.runes) {
      if (ch == 32) count++;
      else break;
    }
    return count;
  }

  List<Fragment> _parseInline(String text) {
    final fragments = <Fragment>[];
    int i = 0;

    while (i < text.length) {
      // Image ![alt](src)
      final imgMatch = RegExp(r'!\[([^\]]*)\]\(([^)]*)\)').matchAsPrefix(text, i);
      if (imgMatch != null) {
        fragments.add(FluentImage(imgMatch.group(2)!));
        i = imgMatch.end;
        continue;
      }

      // Link [text](url)
      final linkMatch = RegExp(r'\[([^\]]*)\]\(([^)]*)\)').matchAsPrefix(text, i);
      if (linkMatch != null) {
        final linkText = linkMatch.group(1)!;
        fragments.addAll(_parseInline(linkText));
        i = linkMatch.end;
        continue;
      }

      // Bold **text**
      if (text.startsWith('**', i)) {
        final end = text.indexOf('**', i + 2);
        if (end != -1) {
          final inner = text.substring(i + 2, end);
          fragments.addAll(_parseInline(inner).map((f) {
            final newStyles = <String>[...(f.styles ?? []), 'bold'];
            return Fragment(f.text, styles: newStyles);
          }));
          i = end + 2;
          continue;
        }
      }

      // Italic *text* (not **)
      if (text.startsWith('*', i) && (i + 1 >= text.length || text[i + 1] != '*')) {
        final end = text.indexOf('*', i + 1);
        if (end != -1) {
          final inner = text.substring(i + 1, end);
          fragments.addAll(_parseInline(inner).map((f) {
            final newStyles = <String>[...(f.styles ?? []), 'italic'];
            return Fragment(f.text, styles: newStyles);
          }));
          i = end + 1;
          continue;
        }
      }

      // Strikethrough ~~text~~
      if (text.startsWith('~~', i)) {
        final end = text.indexOf('~~', i + 2);
        if (end != -1) {
          final inner = text.substring(i + 2, end);
          fragments.addAll(_parseInline(inner).map((f) {
            final newStyles = <String>[...(f.styles ?? []), 'strikethrough'];
            return Fragment(f.text, styles: newStyles);
          }));
          i = end + 2;
          continue;
        }
      }

      // Plain text — find next special char (*, ~, !, [)
      int nextSpecial = text.length;
      for (final ch in ['*', '~', '!', '[']) {
        final pos = text.indexOf(ch, i + 1);
        if (pos != -1 && pos < nextSpecial) nextSpecial = pos;
      }
      final end = nextSpecial == text.length ? text.length : nextSpecial;
      if (end > i) {
        fragments.add(Fragment(text.substring(i, end)));
      }
      i = end;
    }

    return fragments;
  }
}
