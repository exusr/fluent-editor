import 'package:flutter/material.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/renderers/style_hook.dart';

/// Function signature to resolve text styling for addition or deletion suggestions.
typedef SuggestionTextStyleResolver = TextStyle Function(
  TextStyle baseStyle, {
  required bool isDark,
  Fragment? fragment,
});

/// Hook configuration for suggestion addition and deletion styles.
class SuggestionStyleHook extends RenderStyleHook {
  /// Style tag string for suggested additions (default: 'suggestion_addition').
  final String additionTag;

  /// Style tag string for suggested deletions (default: 'suggestion_deletion').
  final String deletionTag;

  /// Style tag string for strikethrough (default: 'strikethrough').
  final String strikethroughTag;

  /// Resolver hook for suggested addition text styling.
  final SuggestionTextStyleResolver additionStyleResolver;

  /// Resolver hook for suggested deletion text styling.
  final SuggestionTextStyleResolver deletionStyleResolver;

  /// Custom addition background color override (optional).
  final Color? additionBackgroundColor;

  /// Custom deletion background color override (optional).
  final Color? deletionBackgroundColor;

  /// Custom addition highlight color override (optional).
  final Color? additionColor;

  /// Custom deletion highlight color override (optional).
  final Color? deletionColor;

  const SuggestionStyleHook({
    this.additionTag = 'suggestion_addition',
    this.deletionTag = 'suggestion_deletion',
    this.strikethroughTag = 'strikethrough',
    this.additionStyleResolver = defaultAdditionStyleResolver,
    this.deletionStyleResolver = defaultDeletionStyleResolver,
    this.additionBackgroundColor,
    this.deletionBackgroundColor,
    this.additionColor,
    this.deletionColor,
  });

  @override
  bool appliesTo(List<String>? styles, Fragment fragment) {
    return styles?.contains(additionTag) == true || styles?.contains(deletionTag) == true;
  }

  @override
  TextStyle resolveStyle(
    TextStyle baseStyle, {
    required bool isDark,
    required Fragment fragment,
    required List<String> styles,
    required FluentDocument? document,
  }) {
    if (styles.contains(additionTag)) {
      return additionStyleResolver(baseStyle, isDark: isDark, fragment: fragment);
    }
    if (styles.contains(deletionTag)) {
      return deletionStyleResolver(baseStyle, isDark: isDark, fragment: fragment);
    }
    return baseStyle;
  }

  @override
  List<Widget> buildNodeOverlayWidgets(
    FNode node, {
    required BuildContext context,
    required FluentDocument document,
  }) {
    if (node is FluentImage) {
      final isDel = node.styles?.contains(deletionTag) == true;
      final isAdd = node.styles?.contains(additionTag) == true;
      if (isDel) {
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  ColoredBox(
                    color: Colors.red.withValues(alpha: 0.35),
                    child: const SizedBox.expand(),
                  ),
                  Center(
                    child: Container(
                      height: 4,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];
      }
      if (isAdd) {
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.green, width: 3),
                ),
              ),
            ),
          ),
        ];
      }
    }
    if (node is HorizontalRule) {
      if (node.styles?.contains(deletionTag) == true) {
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ];
      }
    }
    return const [];
  }

  @override
  ({Color? bgTint, Color? hrColor, Border? border})? resolveHrStyle(
    HorizontalRule node, {
    BuildContext? context,
    required FluentDocument document,
    required bool isSelected,
  }) {
    final isDel = node.styles?.contains(deletionTag) == true;
    final isAdd = node.styles?.contains(additionTag) == true;

    final bgTint = isDel
        ? const Color(0x40F44336)
        : (isAdd
            ? const Color(0x404CAF50)
            : (isSelected && context != null
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                : null));

    final hrColor = isDel
        ? const Color(0xFFEF5350)
        : (isAdd
            ? const Color(0xFF66BB6A)
            : null);

    final border = isDel
        ? Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.5), width: 1)
        : (isAdd
            ? Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.5), width: 1)
            : null);

    return (bgTint: bgTint, hrColor: hrColor, border: border);
  }

  @override
  Color? resolveCellBackgroundColor(
    FluentCell cell, {
    BuildContext? context,
    required FluentDocument document,
    required bool isResized,
  }) {
    bool isAdditionCell = false;
    bool isDeletionCell = false;

    for (final c in cell.children) {
      if (c is Paragraph) {
        for (final f in c.fragments) {
          if (f is Fragment) {
            if (f.styles?.contains(additionTag) == true) isAdditionCell = true;
            if (f.styles?.contains(deletionTag) == true) isDeletionCell = true;
          }
        }
      }
    }

    if (isAdditionCell || isResized) {
      return const Color(0x354CAF50);
    } else if (isDeletionCell) {
      return const Color(0x35F44336);
    }
    return null;
  }

  /// Default addition style resolver hook.
  static TextStyle defaultAdditionStyleResolver(
    TextStyle baseStyle, {
    required bool isDark,
    Fragment? fragment,
  }) {
    final addBg = isDark ? const Color(0x3581C784) : const Color(0x354CAF50);
    return baseStyle.copyWith(backgroundColor: addBg);
  }

  /// Default deletion style resolver hook.
  static TextStyle defaultDeletionStyleResolver(
    TextStyle baseStyle, {
    required bool isDark,
    Fragment? fragment,
  }) {
    final delBg = isDark ? const Color(0x35EF9A9A) : const Color(0x35F44336);
    final delLineColor = isDark ? const Color(0xFFEF5350) : const Color(0xFFE53935);

    final decs = <TextDecoration>[];
    if (baseStyle.decoration != null && baseStyle.decoration != TextDecoration.none) {
      decs.add(baseStyle.decoration!);
    }
    decs.add(TextDecoration.lineThrough);

    return baseStyle.copyWith(
      backgroundColor: delBg,
      decoration: TextDecoration.combine(decs),
      decorationColor: delLineColor,
      decorationStyle: TextDecorationStyle.solid,
    );
  }

  /// Apply addition style tag to [styles].
  void applyAddition(List<String> styles) {
    if (!styles.contains(additionTag)) {
      styles.add(additionTag);
    }
    styles.remove(deletionTag);
  }

  /// Apply deletion style tag to [styles].
  void applyDeletion(List<String> styles) {
    if (!styles.contains(deletionTag)) {
      styles.add(deletionTag);
    }
    if (!styles.contains(strikethroughTag)) {
      styles.add(strikethroughTag);
    }
    styles.remove(additionTag);
  }

  /// Remove suggestion style tags from [styles].
  void removeSuggestionStyles(List<String> styles) {
    styles.remove(additionTag);
    styles.remove(deletionTag);
  }
}
