import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';

/// Utility functions for fragment operations.
class FragmentOperations {
  /// Recursively collects all leaf fragments in order.
  /// A leaf fragment is a Fragment that is not an InlineContainerNode.
  static List<Fragment> collectLeafFragments(FNode node) {
    final result = <Fragment>[];
    if (node is Fragment && node is! InlineContainerNode) {
      result.add(node);
    } else if (node is InlineContainerNode) {
      for (final child in (node as InlineContainerNode).getChildren()) {
        result.addAll(collectLeafFragments(child));
      }
    }
    return result;
  }

  /// Creates a new fragment with the same styles as the source fragment.
  /// If [text] is provided, uses that text; otherwise uses the source fragment's text.
  static Fragment cloneFragment(Fragment source, {String? text}) {
    return Fragment(text ?? source.text)
      ..styles = List.from(source.styles ?? [])
      ..fontFamily = source.fontFamily
      ..fontSize = source.fontSize
      ..color = source.color
      ..highlightColor = source.highlightColor;
  }

  /// Creates a new fragment with styles from the document's pending styles.
  /// Used when inserting new text at the cursor position.
  static Fragment createFragmentWithPendingStyles(FluentDocument document, String text) {
    return Fragment(text)
      ..styles = List.from(document.pendingStyles)
      ..fontFamily = document.pendingFontFamily
      ..fontSize = document.pendingFontSize
      ..color = document.pendingColor
      ..highlightColor = document.pendingHighlightColor;
  }

  /// Inserts [text] in [fragment] at [offset].
  /// Returns false if offset is out of range.
  /// Optimised edge cases (prepend / append) avoid temp substring allocations.
  static bool insertTextInFragment(Fragment fragment, int offset, String text) {
    if (offset < 0 || offset > fragment.text.length) return false;
    if (text.isEmpty) return true;
    if (offset == 0) {
      fragment.text = text + fragment.text;
    } else if (offset == fragment.text.length) {
      fragment.text = fragment.text + text;
    } else {
      fragment.text = fragment.text.substring(0, offset) +
          text +
          fragment.text.substring(offset);
    }
    return true;
  }

  /// Deletes [count] characters from [fragment] starting from [offset].
  /// Returns false if the range is invalid.
  /// Optimised edge cases avoid temp substring allocations.
  static bool deleteTextInFragment(Fragment fragment, int offset, {int count = 1}) {
    if (offset < 0 || offset + count > fragment.text.length) return false;
    if (count <= 0) return true;
    if (count == fragment.text.length) {
      fragment.text = '';
    } else if (offset == 0) {
      fragment.text = fragment.text.substring(count);
    } else if (offset + count == fragment.text.length) {
      fragment.text = fragment.text.substring(0, offset);
    } else {
      fragment.text =
          fragment.text.substring(0, offset) + fragment.text.substring(offset + count);
    }
    return true;
  }

  /// Splits [fragment] at [offset]: returns (left, right).
  /// The original fragment is mutated (becomes the left part).
  /// The right part is a new Fragment with the same style (cloneFragment).
  ///
  /// The caller is responsible for inserting [right] in the container.
  static ({Fragment left, Fragment right}) splitFragment(
      Fragment fragment, int offset) {
    assert(offset >= 0 && offset <= fragment.text.length);
    final leftText = fragment.text.substring(0, offset);
    final rightText = fragment.text.substring(offset);
    fragment.text = leftText;
    final right = cloneFragment(fragment);
    right.text = rightText;
    return (left: fragment, right: right);
  }

  /// Merges [next] into [fragment] (concatenates the text, then [next] must be
  /// removed from the container by the caller).
  static void mergeFragments(Fragment fragment, Fragment next) {
    fragment.text += next.text;
  }
}
