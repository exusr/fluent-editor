import 'package:flutter/widgets.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';

/// Abstract base class for rendering style hooks.
///
/// Allows plugins or document settings to hook into the paragraph and node
/// rendering pipeline to dynamically transform text styles (e.g. suggestions,
/// spellcheck errors, comments, custom text highlights).
abstract class RenderStyleHook {
  const RenderStyleHook();

  /// Returns true if this hook should handle or transform styles for [fragment].
  bool appliesTo(List<String>? styles, Fragment fragment);

  /// Resolves and returns the transformed [TextStyle] for [fragment].
  TextStyle resolveStyle(
    TextStyle baseStyle, {
    required bool isDark,
    required Fragment fragment,
    required List<String> styles,
    required FluentDocument? document,
  });

  /// Builds overlay widgets for Widget-rendered nodes (e.g. [FluentImage]).
  List<Widget> buildNodeOverlayWidgets(
    FNode node, {
    required BuildContext context,
    required FluentDocument document,
  }) =>
      const [];

  /// Resolves background tint, line color, and border for [HorizontalRule].
  ({Color? bgTint, Color? hrColor, Border? border})? resolveHrStyle(
    HorizontalRule node, {
    BuildContext? context,
    required FluentDocument document,
    required bool isSelected,
  }) =>
      null;

  /// Resolves background color for painting [FluentCell] canvas in tables.
  Color? resolveCellBackgroundColor(
    FluentCell cell, {
    BuildContext? context,
    required FluentDocument document,
    required bool isResized,
  }) =>
      null;
}

/// A lightweight, functional implementation of [RenderStyleHook].
class CustomStyleHook extends RenderStyleHook {
  final bool Function(List<String>? styles, Fragment fragment) appliesToPredicate;
  final TextStyle Function(
    TextStyle baseStyle, {
    required bool isDark,
    required Fragment fragment,
    required List<String> styles,
    required FluentDocument? document,
  }) resolver;

  const CustomStyleHook({
    required this.appliesToPredicate,
    required this.resolver,
  });

  @override
  bool appliesTo(List<String>? styles, Fragment fragment) {
    return appliesToPredicate(styles, fragment);
  }

  @override
  TextStyle resolveStyle(
    TextStyle baseStyle, {
    required bool isDark,
    required Fragment fragment,
    required List<String> styles,
    required FluentDocument? document,
  }) {
    return resolver(
      baseStyle,
      isDark: isDark,
      fragment: fragment,
      styles: styles,
      document: document,
    );
  }
}
