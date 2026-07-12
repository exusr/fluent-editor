import 'package:characters/characters.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

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

  /// Collects leaf fragments within the selection range of [node],
  /// skipping FluentImage leaves.
  static List<Fragment> collectLeavesInRange(SelectedNode node) {
    final leaves = collectLeafFragments(node.container as FNode);
    final result = <Fragment>[];
    bool inRange = false;
    for (final leaf in leaves) {
      if (leaf.id == node.startFragment.id) inRange = true;
      if (inRange && leaf is! FluentImage) result.add(leaf);
      if (leaf.id == node.endFragment.id) inRange = false;
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

  /// Applies the document's pending styles to an existing fragment in-place.
  static void applyPendingStyles(FluentDocument document, Fragment frag) {
    frag
      ..fontFamily = document.pendingFontFamily
      ..fontSize = document.pendingFontSize
      ..styles = List.from(document.pendingStyles)
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
      fragment.text = safeSubstring(fragment.text, 0, offset) +
          text +
          safeSubstring(fragment.text, offset);
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
      fragment.text = safeSubstring(fragment.text, count);
    } else if (offset + count == fragment.text.length) {
      fragment.text = safeSubstring(fragment.text, 0, offset);
    } else {
      fragment.text =
          safeSubstring(fragment.text, 0, offset) + safeSubstring(fragment.text, offset + count);
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
    final leftText = safeSubstring(fragment.text, 0, offset);
    final rightText = safeSubstring(fragment.text, offset);
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

  /// Safely extracts a substring, adjusting indices to avoid cutting through
  /// UTF-16 surrogate pairs (e.g., emoji). If [end] is not provided, extracts
  /// from [start] to the end of the string.
  static String safeSubstring(String s, int start, [int? end]) {
    if (s.isEmpty) return s;
    final adjustedStart = adjustIndex(s, start.clamp(0, s.length));
    final adjustedEnd = end != null ? adjustIndex(s, end.clamp(0, s.length)) : s.length;
    if (adjustedStart >= adjustedEnd) return '';
    return s.substring(adjustedStart, adjustedEnd);
  }

  /// Adjusts an index to avoid cutting through a grapheme cluster
  /// (e.g., emoji surrogate pairs, CJK variation selectors, combining marks).
  /// If the index falls inside a multi-code-unit grapheme cluster, moves it
  /// back to the start of that cluster.
  static int adjustIndex(String s, int index) {
    if (index <= 0 || index >= s.length) return index;
    final prev = s.codeUnitAt(index - 1);
    final curr = s.codeUnitAt(index);
    if (prev >= 0xD800 && prev <= 0xDBFF && curr >= 0xDC00 && curr <= 0xDFFF) {
      return index - 1;
    }
    return _snapToGraphemeStart(s, index);
  }

  /// Calculates the previous grapheme cluster offset in a string.
  /// Returns the start offset of the grapheme cluster that ends at
  /// [currentOffset], handling surrogate pairs, CJK variation selectors,
  /// combining marks, and ZWJ sequences correctly.
  static int getPreviousGraphemeOffset(String s, int currentOffset) {
    if (currentOffset <= 0) return 0;
    if (currentOffset > s.length) return s.length;
    int pos = 0;
    for (final grapheme in s.characters) {
      final nextPos = pos + grapheme.length;
      if (nextPos >= currentOffset) {
        return pos;
      }
      pos = nextPos;
    }
    return currentOffset - 1;
  }

  /// Calculates the number of UTF-16 code units to delete starting from [offset]
  /// to delete one complete grapheme cluster. Returns 1 for regular characters,
  /// 2 for surrogate pairs (emoji), and potentially more for complex clusters
  /// (e.g., CJK + variation selector, ZWJ sequences).
  static int getGraphemeLengthAt(String s, int offset) {
    if (offset < 0 || offset >= s.length) return 1;
    int pos = 0;
    for (final grapheme in s.characters) {
      if (pos == offset) {
        return grapheme.length;
      }
      pos += grapheme.length;
      if (pos > offset) {
        return pos - offset;
      }
    }
    return 1;
  }

  /// Snaps [index] back to the start of the grapheme cluster it falls into.
  /// If [index] is already at a cluster boundary, it is returned unchanged.
  static int _snapToGraphemeStart(String s, int index) {
    int pos = 0;
    for (final grapheme in s.characters) {
      final nextPos = pos + grapheme.length;
      if (index > pos && index < nextPos) {
        return pos;
      }
      if (index == nextPos) {
        return index;
      }
      pos = nextPos;
    }
    return index;
  }

  /// Returns the grapheme offset before [offset], skipping a ZWS character
  /// if the fragment has visible content (so backspace deletes the visible
  /// character, not the invisible marker). If the fragment is all-ZWS,
  /// the original offset is returned (preserve original behavior).
  static int getPreviousGraphemeOffsetSkippingZWS(String text, int offset) {
    int newOffset = getPreviousGraphemeOffset(text, offset);
    if (newOffset >= 0 && newOffset < text.length &&
        text.codeUnitAt(newOffset) == 0x200B &&
        text.replaceAll('\u200B', '').isNotEmpty) {
      final skipOffset = getPreviousGraphemeOffset(text, newOffset);
      if (skipOffset < newOffset) newOffset = skipOffset;
    }
    return newOffset;
  }
}
