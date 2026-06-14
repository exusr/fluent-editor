// editor_utils.dart — updated version
//
// Contains: buildFNodeWidget, insertCharacterInFragment, loadSystemFonts,
// normalizeFontFamily. Dead code (findRecursive, pruneEmpty,
// replaceFragmentsRangeWithNode, insertNodeAtFragment) removed.

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluent_editor/widgets/nodes/fluent_fragment_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_hr_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_image_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_link_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_list_item_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_list_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_cell_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_paragraph_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_table_widget.dart';
import 'package:flutter/widgets.dart';

// ─── buildFNodeWidget ────────────────────────────────────────────────
// Unchanged: stable keys via document.getKeyForNode.

Widget buildFNodeWidget(FNode node, FluentDocument document,
    {int anchorOffset = -1, int focusOffset = -1}) {
  return switch (node) {
    HorizontalRule() => FluentHrWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    FluentImage() => FluentImageWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    FluentCell() => FluentCellWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    FluentTable() => FluentTableWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    FluentList() => FluentListWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    ListItem() => FluentListItemWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    Link() => FluentLinkWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    Paragraph() => FluentParagraphWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    Fragment() => FluentFragmentWidget(
        key: document.getKeyForNode(node.id),
        node: node,
        anchorOffset: anchorOffset,
        focusOffset: focusOffset),
    _ => throw Exception('Node type not supported: ${node.runtimeType}'),
  };
}

// ─── insertCharacterInFragment ───────────────────────────────────────
// Delegates to FragmentOperations.insertTextInFragment().

bool insertCharacterInFragment(String character, Fragment fragment, int offset) =>
    FragmentOperations.insertTextInFragment(fragment, offset, character);

// ─── loadSystemFonts ─────────────────────────────────────────────────
// On Linux queries fc-list to get the real names of installed fonts.
// On other OS falls back to a hardcoded list of the most common ones.

Future<List<String>> loadSystemFonts() async {
  if (kIsWeb) return [];
  if (Platform.isLinux) {
    try {
      final result = await Process.run('fc-list', [':', 'family']);
      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        final families = <String>{};
        for (final line in stdout.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final mainFamily = trimmed.split(',').first.trim();
          if (mainFamily.isNotEmpty) families.add(mainFamily);
        }
        return families.toList()..sort();
      }
    } catch (e) {
      // ignore: fc-list not available
    }
  }
  return _fallbackFonts;
}

const _fallbackFonts = <String>[
  'DejaVu Sans', 'Cantarell', 'Helvetica', 'Liberation Sans',
  'Lucida Grande', 'Noto Sans', 'Roboto', 'Segoe UI', 'Tahoma',
  'Trebuchet MS', 'Ubuntu', 'Verdana', 'Book Antiqua', 'Garamond',
  'Georgia', 'Liberation Serif', 'Noto Serif', 'Palatino',
  'Times New Roman', 'Andale Mono', 'Consolas', 'Courier New',
  'Courier', 'DejaVu Sans Mono', 'Liberation Mono', 'Lucida Console',
  'Monaco', 'Ubuntu Mono',
];

/// Normalizes a font family name, mapping generic/legacy families to our bundled default.
String normalizeFontFamily(String? fontFamily) {
  if (fontFamily == null || fontFamily.isEmpty) return 'DejaVu Sans';
  final lower = fontFamily.toLowerCase();
  if (lower == 'sans-serif' || lower == 'arial' || lower == 'helvetica') {
    return 'DejaVu Sans';
  }
  return fontFamily;
}