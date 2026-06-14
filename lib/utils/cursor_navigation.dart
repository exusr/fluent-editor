// cursor_navigation.dart
//
// PURE AND TESTABLE module for cursor navigation with arrow keys.
//
// KEY CONCEPTS:
//
// 1. CaretStop: a position reachable by the cursor.
//    Identified by (fragmentId, localOffset). The stream of stops is ordered
//    according to the logical order (reading) of the document.
//
// 2. LogicalLine: a "logical line" of the document, i.e. the first ancestor
//    Paragraph/ListItem/FluentCell (NOT Link, which is inline-transparent).
//    Each stop belongs to only one LogicalLine.
//
// 3. preferredX: x coordinate in pixels of the caret, used for Up/Down.
//    Replaces the old "preferredColumn" (stop index) which caused slippage
//    on proportional fonts. It is -1.0 when it needs to be recalculated.
//
// DECIDED BEHAVIORS:
// - FluentImage = atomic: 2 stops (before and after), never on the internal ZWS.
// - Link = transparent: the cursor traverses it like normal text.
// - Arrow Down on last paragraph: go to end of document.
// - Arrow Up on first paragraph: go to start of document.

import 'package:fluent_editor/factories.dart';

// ─── Coordinate resolver type ─────────────────────────────────

/// Callback injected by the rendering layer.
/// Translates a CaretStop into its global x coordinate (logical pixels).
/// Provided by ParagraphRegistry.resolveCaretX.
typedef CaretXResolver = double Function(CaretStop stop);

typedef CaretYResolver = double Function(CaretStop stop);

// ─── Models ─────────────────────────────────────────────────────────

/// A position reachable by the cursor in the document.
class CaretStop {
  final String fragmentId;
  final int offset;

  const CaretStop(this.fragmentId, this.offset);

  @override
  bool operator ==(Object other) =>
      other is CaretStop &&
      other.fragmentId == fragmentId &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(fragmentId, offset);

  @override
  String toString() => 'CaretStop($fragmentId:$offset)';
}

/// Represents a "logical line" of the document.
class LogicalLine {
  final InlineContainerNode node;
  final List<CaretStop> stops;

  const LogicalLine({required this.node, required this.stops});

  int get length => stops.length;
  int indexOf(CaretStop stop) => stops.indexOf(stop);
}

// ─── Navigation result ────────────────────────────────────

/// Result of a cursor movement.
/// [position] is the new position (null = no movement possible).
/// [preferredX] is the x coordinate to preserve for subsequent Up/Down.
///   - Left/Right: always ignored by the caller (reset to -1.0).
///   - Up/Down: preserved unchanged during vertical sequences.
class NavigationResult {
  final CaretStop? position;

  /// X coordinate in logical pixels to preserve for the next Up/Down.
  /// Equals 0.0 for Left/Right results (the caller ignores it).
  final double preferredX;

  const NavigationResult({required this.position, required this.preferredX});

  static const NavigationResult none = NavigationResult(
    position: null,
    preferredX: 0.0,
  );
}

// ─── Building CaretStop ─────────────────────────────────────

/// Generates the flat list of ALL CaretStop in the document, in reading
/// order. This is the "rail" on which Left/Right move.
List<CaretStop> buildAllStops(Root root) {
  final out = <CaretStop>[];
  for (final node in root.nodes) {
    _collectStopsRecursive(node, out);
  }
  return out;
}

/// Descends the tree with the same structure as _collectLogicalLines,
/// ensuring that the order of stops is identical to the order of LogicalLine.
void _collectStopsRecursive(FNode node, List<CaretStop> out) {
  if (node is HorizontalRule) {
    out.add(CaretStop(node.id, 0));
    out.add(CaretStop(node.id, 1));
    return;
  }

  if (node is FluentTable) {
    for (final row in node.getChildren()) {
      for (final cell in row.getChildren()) {
        _collectStopsRecursive(cell, out);
      }
    }
    return;
  }

  if (node is FluentList) {
    for (final item in node.getChildren()) {
      _collectStopsRecursive(item, out);
    }
    return;
  }

  if (node is ListItem) {
    // ListItem is just a wrapper: delegates to children (Paragraph, FluentList, etc.)
    // Each Paragraph child becomes a standalone line; sublists
    // descend recursively. This way LogicalLine.node always coincides
    // with a "leaf" InlineContainerNode (Paragraph/Cell), aligned with
    // findLogicalContainer.
    for (final child in node.children) {
      _collectStopsRecursive(child, out);
    }
    return;
  }

  // Paragraph, FluentCell: linear leaf
  _collectStopsInLine(node, out);
}

/// Returns all LogicalLines of the document, in reading order.
List<LogicalLine> buildAllLogicalLines(Root root) {
  final out = <LogicalLine>[];
  for (final node in root.nodes) {
    _collectLogicalLines(node, out);
  }
  return out;
}

void _collectLogicalLines(FNode node, List<LogicalLine> out) {
  if (node is HorizontalRule) {
    // HR is atomic: produces a LogicalLine with its own 2 stops.
    // Does not implement InlineContainerNode, so we handle it explicitly.
    final stops = [CaretStop(node.id, 0), CaretStop(node.id, 1)];
    // We use a fake wrapper — but HR implements InlineContainerNode.
    out.add(LogicalLine(node: node as InlineContainerNode, stops: stops));
    return;
  }

  if (node is FluentTable) {
    for (final row in node.getChildren()) {
      for (final cell in row.getChildren()) {
        _collectLogicalLines(cell, out);
      }
    }
    return;
  }

  if (node is FluentList) {
    for (final item in node.getChildren()) {
      _collectLogicalLines(item, out);
    }
    return;
  }

  if (node is ListItem) {
    // ListItem does not produce its own LogicalLine: delegates to children.
    for (final child in node.children) {
      _collectLogicalLines(child, out);
    }
    return;
  }

  if (node is InlineContainerNode) {
    final stops = <CaretStop>[];
    _collectStopsInLine(node, stops);
    if (stops.isNotEmpty) {
      out.add(LogicalLine(node: node as InlineContainerNode, stops: stops));
    }
  }
}

/// Removes Fragments with empty text that are not the only child of a
/// container. If the container has a single empty child, it is kept.
List<FNode> _filterEmptyFragments(List<FNode> raw) {
  if (raw.length <= 1) return raw;
  return raw.where((c) => !(c is Fragment && c.text.isEmpty)).toList();
}

/// Collects the stops of a single LogicalLine (without descending into sublists).
void _collectStopsInLine(FNode node, List<CaretStop> out) {
  if (node is FluentImage || node is HorizontalRule) {
    out.add(CaretStop(node.id, 0));
    out.add(CaretStop(node.id, 1));
    return;
  }

  if (node is Fragment && node is! InlineContainerNode) {
    final len = node.text.length;
    if (len == 0) {
      // empty fragment: a single stop at the beginning (= end), so the cursor
      // can enter a cell with a single empty fragment
      out.add(CaretStop(node.id, 0));
      return;
    }
    for (int i = 0; i <= len; i++) {
      out.add(CaretStop(node.id, i));
    }
    return;
  }

  if (node is Link) {
    final rawChildren = node.getChildren()
        .where((c) => c is! FluentList && c is! FluentCell)
        .toList();
    final children = _filterEmptyFragments(rawChildren);
    if (children.isEmpty && rawChildren.isNotEmpty) {
      out.add(CaretStop((rawChildren.first as Fragment).id, 0));
      return;
    }
    for (int ci = 0; ci < children.length; ci++) {
      final child = children[ci];
      final nextChild = ci + 1 < children.length ? children[ci + 1] : null;
      final prevChild = ci > 0 ? children[ci - 1] : null;

      final afterImage     = prevChild is FluentImage;
      final beforeImage    = nextChild is FluentImage;
      final beforeFragment = nextChild is Fragment && nextChild is! InlineContainerNode;

      if (child is Fragment && child is! InlineContainerNode && child.text.isNotEmpty) {
        final len = child.text.length;
        final startI = afterImage ? 1 : 0;
        final endI   = (beforeImage || beforeFragment) ? len - 1 : len;
        for (int i = startI; i <= endI; i++) {
          out.add(CaretStop(child.id, i));
        }
      } else {
        _collectStopsInLine(child, out);
      }
    }
    return;
  }

  if (node is InlineContainerNode) {
    final rawChildren = (node as InlineContainerNode).getChildren()
        .where((c) => c is! FluentList && c is! FluentCell)
        .toList();
    final children = _filterEmptyFragments(rawChildren);
    if (children.isEmpty && rawChildren.isNotEmpty) {
      out.add(CaretStop((rawChildren.first as Fragment).id, 0));
      return;
    }
    for (int ci = 0; ci < children.length; ci++) {
      final child = children[ci];
      final nextChild = ci + 1 < children.length ? children[ci + 1] : null;
      final prevChild = ci > 0 ? children[ci - 1] : null;

      if (child is FluentList) continue; // sublists = separate LogicalLine

      final afterLink    = prevChild is Link;
      final afterImage   = prevChild is FluentImage;
      final beforeLink   = nextChild is Link;
      final beforeImage  = nextChild is FluentImage;
      final beforeFragment = nextChild is Fragment && nextChild is! InlineContainerNode;

      if (child is Fragment && child is! InlineContainerNode && child.text.isNotEmpty) {
        final len = child.text.length;
        final startI = (afterLink || afterImage) ? 1 : 0;
        final endI   = (beforeLink || beforeImage || beforeFragment) ? len - 1 : len;
        for (int i = startI; i <= endI; i++) {
          out.add(CaretStop(child.id, i));
        }
      } else {
        _collectStopsInLine(child, out);
      }
    }
  }
}

// ─── Lookup helpers ──────────────────────────────────────────────────

int findStopIndex(List<CaretStop> stops, String fragmentId, int offset) {
  for (int i = 0; i < stops.length; i++) {
    final s = stops[i];
    if (s.fragmentId == fragmentId && s.offset == offset) return i;
  }
  int bestIdx = -1;
  int bestDist = 1 << 30;
  for (int i = 0; i < stops.length; i++) {
    final s = stops[i];
    if (s.fragmentId == fragmentId) {
      final d = (s.offset - offset).abs();
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
  }
  return bestIdx;
}

({int lineIndex, int stopIndexInLine})? findLineForStop(
  List<LogicalLine> lines,
  CaretStop stop,
) {
  for (int i = 0; i < lines.length; i++) {
    final idx = lines[i].indexOf(stop);
    if (idx >= 0) return (lineIndex: i, stopIndexInLine: idx);
  }
  return null;
}

int _findStopIndexInLines(
  List<LogicalLine> lines,
  String fragmentId,
  int offset,
) {
  final allStops = lines.expand((l) => l.stops).toList();
  for (int i = 0; i < allStops.length; i++) {
    if (allStops[i].fragmentId == fragmentId && allStops[i].offset == offset) {
      return i;
    }
  }
  return -1;
}

// ─── Horizontal navigation ─────────────────────────────────────────
// Left/Right don't use the resolver: the caller always resets preferredX to -1.0.

NavigationResult moveLeft(Root root, CaretStop current, {List<CaretStop>? stops}) {
  final stops_ = stops ?? buildAllStops(root);
  int idx = findStopIndex(stops_, current.fragmentId, current.offset);

  if (idx < 0) {
    final lines = buildAllLogicalLines(root);
    idx = _findStopIndexInLines(lines, current.fragmentId, current.offset);
    if (idx <= 0) return NavigationResult.none;
    final stopsFromLines = lines.expand((l) => l.stops).toList();
    final newStop = stopsFromLines[idx - 1];
    return NavigationResult(position: newStop, preferredX: 0.0);
  }

  if (idx <= 0) return NavigationResult.none;
  final newStop = stops_[idx - 1];
  return NavigationResult(position: newStop, preferredX: 0.0);
}

NavigationResult moveRight(Root root, CaretStop current, {List<CaretStop>? stops}) {
  final stops_ = stops ?? buildAllStops(root);
  int idx = findStopIndex(stops_, current.fragmentId, current.offset);

  if (idx < 0) {
    final lines = buildAllLogicalLines(root);
    idx = _findStopIndexInLines(lines, current.fragmentId, current.offset);
    if (idx < 0) return NavigationResult.none;
    final stopsFromLines = lines.expand((l) => l.stops).toList();
    if (idx >= stopsFromLines.length - 1) return NavigationResult.none;
    final newStop = stopsFromLines[idx + 1];
    return NavigationResult(position: newStop, preferredX: 0.0);
  }

  if (idx >= stops_.length - 1) return NavigationResult.none;
  final newStop = stops_[idx + 1];
  return NavigationResult(position: newStop, preferredX: 0.0);
}

const double _kLineYTolerance = 2.0;

// ─── Vertical navigation ───────────────────────────────────────────

/// Moves the cursor up by one LogicalLine.
/// [preferredX] is the x coordinate in pixels to maintain.
/// If it's -1.0, it's calculated from the current position via [resolveX].
NavigationResult moveUp(
  Root root,
  CaretStop current,
  double preferredX,
  CaretXResolver resolveX,
  CaretYResolver resolveY, { // ← new
  List<CaretStop>? stops,
}) {
  final stops_ = stops ?? buildAllStops(root);
  if (stops_.isEmpty) return NavigationResult.none;

  final x = preferredX >= 0.0 ? preferredX : resolveX(current);
  final currentY = resolveY(current);

  // Find the highest y that is strictly above the current line
  double? targetY;
  for (final stop in stops_) {
    final y = resolveY(stop);
    if (y < currentY - _kLineYTolerance) {
      if (targetY == null || y > targetY) targetY = y;
    }
  }

  // No line above: go to the first stop of the document
  if (targetY == null) {
    final first = stops_.first;
    if (first == current) return NavigationResult.none;
    return NavigationResult(position: first, preferredX: x);
  }

  // Among the stops on the target line, take the one with closest x
  final lineStops = stops_
      .where((s) => (resolveY(s) - targetY!).abs() <= _kLineYTolerance)
      .toList();

  final best = _stopNearestX(lineStops, x, resolveX);
  return NavigationResult(position: best, preferredX: x);
}

/// Moves the cursor down by one LogicalLine.
NavigationResult moveDown(
  Root root,
  CaretStop current,
  double preferredX,
  CaretXResolver resolveX,
  CaretYResolver resolveY, { // ← new
  List<CaretStop>? stops,
}) {
  final stops_ = stops ?? buildAllStops(root);
  if (stops_.isEmpty) return NavigationResult.none;

  final x = preferredX >= 0.0 ? preferredX : resolveX(current);
  final currentY = resolveY(current);

  // Find the lowest y that is strictly below the current line
  double? targetY;
  for (final stop in stops_) {
    final y = resolveY(stop);
    if (y > currentY + _kLineYTolerance) {
      if (targetY == null || y < targetY) targetY = y;
    }
  }

  // No line below: go to the last stop of the document
  if (targetY == null) {
    final last = stops_.last;
    if (last == current) return NavigationResult.none;
    return NavigationResult(position: last, preferredX: x);
  }

  final lineStops = stops_
      .where((s) => (resolveY(s) - targetY!).abs() <= _kLineYTolerance)
      .toList();

  final best = _stopNearestX(lineStops, x, resolveX);
  return NavigationResult(position: best, preferredX: x);
}

// ─── Helpers for visual column ─────────────────────────────────────

/// Finds the stop in [line] whose x coordinate (from [resolveX]) is closest
/// to [preferredX]. Automatic clamp if the line is empty.
CaretStop _stopNearestX(
  List<CaretStop> stops,
  double preferredX,
  CaretXResolver resolveX,
) {
  if (stops.isEmpty) throw StateError('Empty stop list');
  CaretStop best = stops.first;
  double bestDist = (resolveX(best) - preferredX).abs();
  for (final stop in stops.skip(1)) {
    final dist = (resolveX(stop) - preferredX).abs();
    if (dist < bestDist) {
      bestDist = dist;
      best = stop;
    }
  }
  return best;
}

Map<String, Fragment> _buildFragmentCache(Root root) {
  final cache = <String, Fragment>{};
  void visit(FNode node) {
    if (node is Fragment && node is! InlineContainerNode) {
      cache[node.id] = node;
      return;
    }
    if (node is FluentTable) {
      for (final row in node.getChildren()) {
        for (final cell in row.getChildren()) {
          visit(cell);
        }
      }
      return;
    }
    if (node is FluentList) {
      for (final child in node.getChildren()) {
        visit(child);
      }
      return;
    }
    if (node is InlineContainerNode) {
      for (final child in (node as InlineContainerNode).getChildren()) {
        visit(child);
      }
    }
  }
  for (final node in root.nodes) {
    visit(node);
  }
  return cache;
}

bool _isWordChar(String ch) =>
    RegExp(r'[a-zA-Z0-9_\u00C0-\u024F]').hasMatch(ch);

bool _isSpaceChar(String ch) => ch == ' ' || ch == '\t' || ch == '\n';

List<int> _buildStopLineIndex(
    List<CaretStop> stops, List<LogicalLine> lines) {
  final posOf = <CaretStop, int>{};
  for (int i = 0; i < stops.length; i++) {
    posOf[stops[i]] = i;
  }

  final result = List<int>.filled(stops.length, -1);
  for (int li = 0; li < lines.length; li++) {
    for (final stop in lines[li].stops) {
      final i = posOf[stop];
      if (i != null) result[i] = li;
    }
  }
  return result;
}

NavigationResult moveWordRight(Root root, CaretStop current, {List<CaretStop>? stops}) {
  final stops_ = stops ?? buildAllStops(root);
  int idx = findStopIndex(stops_, current.fragmentId, current.offset);
  if (idx < 0 || idx >= stops_.length - 1) return NavigationResult.none;

  final cache = _buildFragmentCache(root);
  final lineIdx = _buildStopLineIndex(stops_, buildAllLogicalLines(root));
  String? ch(int i) => _charRight(stops_, i, cache, lineIdx);

  final startChar = ch(idx);

  if (startChar == null) return NavigationResult.none; // end of document

  if (_isSpaceChar(startChar)) {
    // On space or line boundary: skip separators, then skip the word
    while (idx < stops_.length - 1 && _isSpaceChar(ch(idx) ?? '')) {
      idx++;
    }
    while (idx < stops_.length - 1) {
      final c = ch(idx);
      if (c == null || !_isWordChar(c)) break;
      idx++;
    }
  } else if (_isWordChar(startChar)) {
    // Inside a word: go to the end
    while (idx < stops_.length - 1) {
      final c = ch(idx);
      if (c == null || !_isWordChar(c)) break;
      idx++;
    }
  } else {
    // Punctuation: skip the sequence
    while (idx < stops_.length - 1) {
      final c = ch(idx);
      if (c == null || _isWordChar(c) || _isSpaceChar(c)) break;
      idx++;
    }
  }

  return NavigationResult(position: stops_[idx], preferredX: 0.0);
}

NavigationResult moveWordLeft(Root root, CaretStop current, {List<CaretStop>? stops}) {
  final stops_ = stops ?? buildAllStops(root);
  int idx = findStopIndex(stops_, current.fragmentId, current.offset);
  if (idx < 0 || idx <= 0) return NavigationResult.none;

  final cache = _buildFragmentCache(root);
  final lineIdx = _buildStopLineIndex(stops_, buildAllLogicalLines(root));
  String? ch(int i) => _charLeft(stops_, i, cache, lineIdx);

  final startChar = ch(idx);

  if (startChar == null) return NavigationResult.none;

  if (_isSpaceChar(startChar)) {
    while (idx > 0 && _isSpaceChar(ch(idx) ?? '')) {
      idx--;
    }
    while (idx > 0) {
      final c = ch(idx);
      if (c == null || !_isWordChar(c)) break;
      idx--;
    }
  } else if (_isWordChar(startChar)) {
    while (idx > 0) {
      final c = ch(idx);
      if (c == null || !_isWordChar(c)) break;
      idx--;
    }
  } else {
    while (idx > 0) {
      final c = ch(idx);
      if (c == null || _isWordChar(c) || _isSpaceChar(c)) break;
      idx--;
    }
  }

  return NavigationResult(position: stops_[idx], preferredX: 0.0);
}
const String _kLineBoundary = '\n';

String? _charRight(
  List<CaretStop> stops,
  int startIdx,
  Map<String, Fragment> cache,
  List<int> lineIndex,
) {
  final targetLine = lineIndex[startIdx];
  int i = startIdx;
  while (i < stops.length) {
    final curLine = lineIndex[i];
    if (curLine != targetLine) return _kLineBoundary; // different line = '\n'
    final stop = stops[i];
    final frag = cache[stop.fragmentId];
    if (frag == null) return _kLineBoundary; // FluentImage = boundary
    if (stop.offset < frag.text.length) return frag.text[stop.offset];
    i++; // end of fragment: look at the next stop on the same line
  }
  return null; // end of document
}

/// Character to the left of [startIdx].
/// Mirror of _charRight.
String? _charLeft(
  List<CaretStop> stops,
  int startIdx,
  Map<String, Fragment> cache,
  List<int> lineIndex,
) {
  if (startIdx <= 0) return null;
  final targetLine = lineIndex[startIdx];
  int i = startIdx - 1;
  while (i >= 0) {
    final curLine = lineIndex[i];
    if (curLine != targetLine) return _kLineBoundary;
    final stop = stops[i];
    final frag = cache[stop.fragmentId];
    if (frag == null) return _kLineBoundary;
    if (stop.offset < frag.text.length) return frag.text[stop.offset];
    i--; // end of fragment: continue backward on the same line
  }
  return null;
}

// ─── Line navigation (Home/End) ─────────────────────────────────────

/// Moves the cursor to the start of the current logical line.
NavigationResult moveToLineStart(
  Root root,
  CaretStop current,
) {
  final lines = buildAllLogicalLines(root);
  final lineInfo = findLineForStop(lines, current);
  if (lineInfo == null) return NavigationResult.none;

  final line = lines[lineInfo.lineIndex];
  if (line.stops.isEmpty) return NavigationResult.none;

  final firstStop = line.stops.first;
  if (firstStop == current) return NavigationResult.none;

  return NavigationResult(position: firstStop, preferredX: 0.0);
}

/// Moves the cursor to the end of the current logical line.
NavigationResult moveToLineEnd(
  Root root,
  CaretStop current,
) {
  final lines = buildAllLogicalLines(root);
  final lineInfo = findLineForStop(lines, current);
  if (lineInfo == null) return NavigationResult.none;

  final line = lines[lineInfo.lineIndex];
  if (line.stops.isEmpty) return NavigationResult.none;

  final lastStop = line.stops.last;
  if (lastStop == current) return NavigationResult.none;

  return NavigationResult(position: lastStop, preferredX: 0.0);
}

// ─── Page navigation (Page Up/Down) ───────────────────────────────────

/// Moves the cursor up by approximately 10-15 logical lines.
NavigationResult movePageUp(
  Root root,
  CaretStop current,
  double preferredX,
  CaretXResolver resolveX,
  CaretYResolver resolveY,
) {
  final lines = buildAllLogicalLines(root);
  final lineInfo = findLineForStop(lines, current);
  if (lineInfo == null) return NavigationResult.none;

  final currentLineIndex = lineInfo.lineIndex;
  final targetLineIndex = (currentLineIndex - 10).clamp(0, lines.length - 1);

  if (targetLineIndex == currentLineIndex) {
    // Already at or near the top, go to document start
    final stops = buildAllStops(root);
    if (stops.isEmpty) return NavigationResult.none;
    final firstStop = stops.first;
    if (firstStop == current) return NavigationResult.none;
    return NavigationResult(position: firstStop, preferredX: preferredX);
  }

  final targetLine = lines[targetLineIndex];
  if (targetLine.stops.isEmpty) return NavigationResult.none;

  final x = preferredX >= 0.0 ? preferredX : resolveX(current);
  final best = _stopNearestX(targetLine.stops, x, resolveX);

  return NavigationResult(position: best, preferredX: x);
}

/// Moves the cursor down by approximately 10-15 logical lines.
NavigationResult movePageDown(
  Root root,
  CaretStop current,
  double preferredX,
  CaretXResolver resolveX,
  CaretYResolver resolveY,
) {
  final lines = buildAllLogicalLines(root);
  final lineInfo = findLineForStop(lines, current);
  if (lineInfo == null) return NavigationResult.none;

  final currentLineIndex = lineInfo.lineIndex;
  final targetLineIndex = (currentLineIndex + 10).clamp(0, lines.length - 1);

  if (targetLineIndex == currentLineIndex) {
    // Already at or near the bottom, go to document end
    final stops = buildAllStops(root);
    if (stops.isEmpty) return NavigationResult.none;
    final lastStop = stops.last;
    if (lastStop == current) return NavigationResult.none;
    return NavigationResult(position: lastStop, preferredX: preferredX);
  }

  final targetLine = lines[targetLineIndex];
  if (targetLine.stops.isEmpty) return NavigationResult.none;

  final x = preferredX >= 0.0 ? preferredX : resolveX(current);
  final best = _stopNearestX(targetLine.stops, x, resolveX);

  return NavigationResult(position: best, preferredX: x);
}
