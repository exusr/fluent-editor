// editor_utils.dart — updated version
//
// CHANGES compared to previous version:
//  - findRecursive: now delegates to findNode() of node_operations (fix FluentList/Table)
//  - insertCharacterInFragment: delegates to insertTextInFragment()
//  - pruneEmpty: delegates to pruneEmptyContainers()
//  - All widget imports remain unchanged
//  - Existing public signatures remain identical for compatibility

import 'package:fluent_editor/core/types.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluent_editor/utils/string_utils.dart';
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
import 'dart:io';

// ─── findRecursive ───────────────────────────────────────────────────
// Delegates to findNode() which correctly traverses FluentList, FluentTable
// and all other types. The signature remains identical for compatibility.

FNode? findRecursive(FNode node, bool Function(FNode) test) =>
    findNode(node, test);

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

// ─── pruneEmpty ──────────────────────────────────────────────────────
// Delegates to pruneEmptyContainers() of node_operations.

void pruneEmpty(FNode node, Root root) =>
    pruneEmptyContainers(node, root);

// ─── insertCharacterInFragment ───────────────────────────────────────
// Delegates to FragmentOperations.insertTextInFragment().

bool insertCharacterInFragment(String character, Fragment fragment, int offset) =>
    FragmentOperations.insertTextInFragment(fragment, offset, character);

// ─── replaceFragmentsRangeWithNode ───────────────────────────────────
// Unchanged: complex logic that uses tree_utils internally.

bool replaceFragmentsRangeWithNode(
    List<FragmentRange> fragmentRanges, FNode newNode, FluentDocument document) {
  if (fragmentRanges.length == 1) {
    insertNodeAtFragment(
      fragmentRanges[0].fragment as Fragment,
      fragmentRanges[0].parent as Paragraph,
      fragmentRanges[0].offset,
      fragmentRanges[0].focus,
      newNode,
    );
    return true;
  } else if (fragmentRanges.length > 1) {
    for (final fragmentRange in fragmentRanges) {
      if (fragmentRange.offset == 0 &&
          fragmentRange.focus ==
              (fragmentRange.fragment as Fragment).text.length) {
        (fragmentRange.parent as Paragraph)
            .fragments
            .remove(fragmentRange.fragment);
        pruneEmptyContainers(fragmentRange.parent, document.content);
      } else if (fragmentRange.offset > 0 &&
          fragmentRange.focus ==
              (fragmentRange.fragment as Fragment).text.length) {
        final (leftText, rightText) = splitStringAt(
            (fragmentRange.fragment as Fragment).text, fragmentRange.offset);
        (fragmentRange.fragment as Fragment).text = leftText;
        final newFragment = copyFrom(fragmentRange.fragment) as Fragment;
        newFragment.text = rightText;
        (fragmentRange.parent as Paragraph).fragments.insert(
            (fragmentRange.parent as Paragraph)
                    .fragments
                    .indexOf(fragmentRange.fragment) +
                1,
            newNode);
      } else if (fragmentRange.offset == 0 &&
          fragmentRange.focus <
              (fragmentRange.fragment as Fragment).text.length) {
        final (_, rightText) = splitStringAt(
            (fragmentRange.fragment as Fragment).text, fragmentRange.focus);
        (fragmentRange.fragment as Fragment).text = rightText;
      }
    }
    return true;
  }
  return false;
}

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

// ─── insertNodeAtFragment ────────────────────────────────────────────
// Unchanged.

bool insertNodeAtFragment(
    Fragment fragment, Paragraph parent, int offset, int focus, FNode newNode) {
  final index = parent.fragments.indexOf(fragment);
  if (offset == 0 && focus == 0) {
    parent.fragments.insert(index, newNode);
    return true;
  }
  if (offset == fragment.text.length && focus == fragment.text.length) {
    parent.fragments.add(newNode);
    return true;
  }
  if (offset > 0 && offset < fragment.text.length &&
      focus > 0 && focus < fragment.text.length) {
    final (leftText, rightText) = splitStringAt(fragment.text, offset);
    fragment.text = leftText;
    final newFragment = copyFrom(fragment) as Fragment;
    newFragment.text = rightText;
    parent.fragments.insert(index + 1, newNode);
    parent.fragments.insert(index + 2, newFragment);
    return true;
  }
  return false;
}

/// Normalizes a font family name, mapping generic/legacy families to our bundled default.
String normalizeFontFamily(String? fontFamily) {
  if (fontFamily == null || fontFamily.isEmpty) return 'DejaVu Sans';
  final lower = fontFamily.toLowerCase();
  if (lower == 'sans-serif' || lower == 'arial' || lower == 'helvetica') {
    return 'DejaVu Sans';
  }
  return fontFamily;
}