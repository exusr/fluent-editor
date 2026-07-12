import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';

/// Callback injected by the rendering layer.
/// Translates a CaretStop into its global x coordinate (logical pixels).
/// Provided by ParagraphRegistry.resolveCaretX.
typedef CaretXResolver = double Function(CaretStop stop);

typedef CaretYResolver = double Function(CaretStop stop);

/// Resolves a node id to its parent node id (O(1) when cached).
typedef ParentResolver = String? Function(String childId);

/// Resolves a fragment id to its logical container id (O(1) when cached).
typedef ContainerResolver = String? Function(String fragmentId);

/// Resolves a node/fragment id to its top-level index (O(1) when cached), or -1.
typedef TopLevelIndexResolver = int Function(String id);

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
    for (final child in node.children) {
      _collectStopsRecursive(child, out);
    }
    return;
  }

  if (node is FluentCell) {
    for (final child in node.getChildren()) {
      _collectStopsRecursive(child, out);
    }
    return;
  }

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
    final stops = [CaretStop(node.id, 0), CaretStop(node.id, 1)];
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
    for (final child in node.children) {
      _collectLogicalLines(child, out);
    }
    return;
  }

  if (node is FluentCell) {
    for (final child in node.getChildren()) {
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

/// Returns true if the code unit at [offset] in [text] is a zero-width
/// space (U+200B) that sits between two CJK characters. In that case the
/// ZWS should not produce a visible caret stop — the cursor should glide
/// from one CJK character to the next without stopping on the invisible
/// separator.
bool isZwsBetweenCjk(String text, int offset) {
  if (offset < 0 || offset >= text.length) return false;
  if (text.codeUnitAt(offset) != 0x200B) return false;
  int prev = offset - 1;
  if (prev < 0) return false;
  if ((text.codeUnitAt(prev) & 0xFC00) == 0xDC00) prev--;
  if (prev < 0) return false;
  int next = offset + 1;
  if (next >= text.length) return false;
  if ((text.codeUnitAt(next) & 0xFC00) == 0xD800) next++;
  if (next >= text.length) return false;
  return isCjk(text.codeUnitAt(prev)) && isCjk(text.codeUnitAt(next));
}

/// Returns true if [codeUnit] belongs to a CJK script
/// (Han, Hiragana, Katakana, Hangul).
bool isCjk(int codeUnit) {
  if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) return true;
  if (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) return true;
  if (codeUnit >= 0x20000 && codeUnit <= 0x2A6DF) return true;
  if (codeUnit >= 0x3040 && codeUnit <= 0x309F) return true;
  if (codeUnit >= 0x30A0 && codeUnit <= 0x30FF) return true;
  if (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF) return true;
  if (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) return true;
  return false;
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
      out.add(CaretStop(node.id, 0));
      return;
    }
    int i = 0;
    while (i <= len) {
      if (i > 0 && i < len && isZwsBetweenCjk(node.text, i)) {
        i++;
        continue;
      }
      out.add(CaretStop(node.id, i));
      if (i < len) {
        final graphemeLen = FragmentOperations.getGraphemeLengthAt(node.text, i);
        i += graphemeLen;
      } else {
        i++;
      }
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
        int i = startI;
        while (i <= endI) {
          if (i > 0 && i < len && isZwsBetweenCjk(child.text, i)) {
            i++;
            continue;
          }
          out.add(CaretStop(child.id, i));
          if (i < endI) {
            final graphemeLen = FragmentOperations.getGraphemeLengthAt(child.text, i);
            i += graphemeLen;
          } else {
            i++;
          }
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
        int i = startI;
        while (i <= endI) {
          if (i > 0 && i < len && isZwsBetweenCjk(child.text, i)) {
            i++;
            continue;
          }
          out.add(CaretStop(child.id, i));
          if (i < endI) {
            final graphemeLen = FragmentOperations.getGraphemeLengthAt(child.text, i);
            i += graphemeLen;
          } else {
            i++;
          }
        }
      } else {
        _collectStopsInLine(child, out);
      }
    }
  }
}

List<CaretStop>? _stopsRefForIndex;
Map<String, int>? _stopExactIndex;

int findStopIndex(List<CaretStop> stops, String fragmentId, int offset) {
  if (!identical(stops, _stopsRefForIndex)) {
    _stopsRefForIndex = stops;
    final m = <String, int>{};
    for (int i = 0; i < stops.length; i++) {
      m['${stops[i].fragmentId}\u0000${stops[i].offset}'] = i;
    }
    _stopExactIndex = m;
  }

  final exact = _stopExactIndex!['$fragmentId\u0000$offset'];
  if (exact != null) return exact;

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

// Cache for findLineForStop: maps stop identity to (lineIndex, stopIndexInLine)
// Keyed by lines list identity to invalidate when lines change.
List<LogicalLine>? _linesRefForLineIndex;
Map<CaretStop, ({int lineIndex, int stopIndexInLine})>? _stopToLineIndex;

// Cache for _findStopIndexInLines: hash map keyed by lines identity
List<LogicalLine>? _linesRefForFlatStops;
Map<String, int>? _cachedFlatStopIndex;

({int lineIndex, int stopIndexInLine})? findLineForStop(
  List<LogicalLine> lines,
  CaretStop stop,
) {
  if (!identical(lines, _linesRefForLineIndex)) {
    _linesRefForLineIndex = lines;
    final m = <CaretStop, ({int lineIndex, int stopIndexInLine})>{};
    for (int i = 0; i < lines.length; i++) {
      for (int j = 0; j < lines[i].stops.length; j++) {
        m[lines[i].stops[j]] = (lineIndex: i, stopIndexInLine: j);
      }
    }
    _stopToLineIndex = m;
  }

  return _stopToLineIndex?[stop];
}

int _findStopIndexInLines(
  List<LogicalLine> lines,
  String fragmentId,
  int offset,
) {
  if (!identical(lines, _linesRefForFlatStops)) {
    _linesRefForFlatStops = lines;
    final flat = lines.expand((l) => l.stops).toList(growable: false);
    final m = <String, int>{};
    for (int i = 0; i < flat.length; i++) {
      m['${flat[i].fragmentId}\u0000${flat[i].offset}'] = i;
    }
    _cachedFlatStopIndex = m;
  }
  return _cachedFlatStopIndex!['$fragmentId\u0000$offset'] ?? -1;
}

/// Returns the stop at [flatIndex] in the flattened lines list,
/// without allocating a new list.
CaretStop? _stopAtFlatIndex(List<LogicalLine> lines, int flatIndex) {
  int acc = 0;
  for (final line in lines) {
    if (flatIndex < acc + line.stops.length) {
      return line.stops[flatIndex - acc];
    }
    acc += line.stops.length;
  }
  return null;
}

NavigationResult moveLeft(Root root, CaretStop current, {
  List<CaretStop>? stops,
  List<LogicalLine>? cachedLines,
}) {
  final stops_ = stops ?? buildAllStops(root);
  int idx = findStopIndex(stops_, current.fragmentId, current.offset);

  if (idx < 0) {
    final lines = cachedLines ?? buildAllLogicalLines(root);
    idx = _findStopIndexInLines(lines, current.fragmentId, current.offset);
    if (idx <= 0) return NavigationResult.none;
    final newStop = _stopAtFlatIndex(lines, idx - 1);
    if (newStop == null) return NavigationResult.none;
    return NavigationResult(position: newStop, preferredX: 0.0);
  }

  if (idx <= 0) return NavigationResult.none;
  final newStop = stops_[idx - 1];
  return NavigationResult(position: newStop, preferredX: 0.0);
}

NavigationResult moveRight(Root root, CaretStop current, {
  List<CaretStop>? stops,
  List<LogicalLine>? cachedLines,
}) {
  final stops_ = stops ?? buildAllStops(root);
  int idx = findStopIndex(stops_, current.fragmentId, current.offset);

  if (idx < 0) {
    final lines = cachedLines ?? buildAllLogicalLines(root);
    idx = _findStopIndexInLines(lines, current.fragmentId, current.offset);
    if (idx < 0) return NavigationResult.none;
    final newStop = _stopAtFlatIndex(lines, idx + 1);
    if (newStop == null) return NavigationResult.none;
    return NavigationResult(position: newStop, preferredX: 0.0);
  }

  if (idx >= stops_.length - 1) return NavigationResult.none;
  final newStop = stops_[idx + 1];
  return NavigationResult(position: newStop, preferredX: 0.0);
}

const double _kLineYTolerance = 2.0;

/// Moves the cursor up by one LogicalLine.
/// [preferredX] is the x coordinate in pixels to maintain.
/// If it's -1.0, it's calculated from the current position via [resolveX].
/// [allStops] is the full document stop list used for cross-node fallback.
NavigationResult moveUp(
  Root root,
  CaretStop current,
  double preferredX,
  CaretXResolver resolveX,
  CaretYResolver resolveY, {
  List<CaretStop>? stops,
  List<CaretStop>? allStops,
  ParentResolver? parentResolver,
  ContainerResolver? containerResolver,
  TopLevelIndexResolver? topLevelIndexResolver,
}) {
  final stops_ = stops ?? buildAllStops(root);
  if (stops_.isEmpty) return NavigationResult.none;

  final yCache = <CaretStop, double>{};
  double cachedY(CaretStop s) => yCache[s] ??= resolveY(s);
  final xCache = <CaretStop, double>{};
  double cachedX(CaretStop s) => xCache[s] ??= resolveX(s);

  final x = preferredX >= 0.0 ? preferredX : cachedX(current);
  final currentY = cachedY(current);

  // Single-pass: find targetY, then find nearest-X stop on that line.
  double? targetY;
  for (final stop in stops_) {
    final y = cachedY(stop);
    if (y < currentY - _kLineYTolerance) {
      if (targetY == null || y > targetY) targetY = y;
    }
  }

  if (targetY == null) {
    final docStops = allStops ?? stops_;
    if (_isInFirstNode(root, current.fragmentId,
        parentResolver: parentResolver, containerResolver: containerResolver,
        topLevelIndexResolver: topLevelIndexResolver)) {
      final first = docStops.first;
      if (first == current) return NavigationResult.none;
      return NavigationResult(position: first, preferredX: x);
    }
    final currentNodeId = _findTopLevelNodeId(root, current.fragmentId,
        parentResolver: parentResolver, containerResolver: containerResolver,
        topLevelIndexResolver: topLevelIndexResolver);
    if (currentNodeId != null) {
      final currentNodeIdx = topLevelIndexResolver != null
          ? topLevelIndexResolver(currentNodeId)
          : root.nodes.indexWhere((n) => n.id == currentNodeId);
      for (int i = currentNodeIdx - 1; i >= 0; i--) {
        final prevNode = root.nodes[i];
        for (int j = docStops.length - 1; j >= 0; j--) {
          if (_stopBelongsToNode(docStops[j], prevNode, root, containerResolver: containerResolver, parentResolver: parentResolver, topLevelIndexResolver: topLevelIndexResolver)) {
            return NavigationResult(position: docStops[j], preferredX: x);
          }
        }
      }
    }
    final first = docStops.first;
    if (first == current) return NavigationResult.none;
    return NavigationResult(position: first, preferredX: x);
  }

  // Single-pass: find nearest-X stop on the target line without allocating.
  CaretStop? best;
  double bestDist = double.infinity;
  for (final stop in stops_) {
    if ((cachedY(stop) - targetY).abs() <= _kLineYTolerance) {
      final dist = (cachedX(stop) - x).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = stop;
      }
    }
  }
  if (best == null) return NavigationResult(position: current, preferredX: x);
  return NavigationResult(position: best, preferredX: x);
}

/// Moves the cursor down by one LogicalLine.
/// [allStops] is the full document stop list used for cross-node fallback.
NavigationResult moveDown(
  Root root,
  CaretStop current,
  double preferredX,
  CaretXResolver resolveX,
  CaretYResolver resolveY, {
  List<CaretStop>? stops,
  List<CaretStop>? allStops,
  ParentResolver? parentResolver,
  ContainerResolver? containerResolver,
  TopLevelIndexResolver? topLevelIndexResolver,
}) {
  final stops_ = stops ?? buildAllStops(root);
  if (stops_.isEmpty) return NavigationResult.none;

  final yCache = <CaretStop, double>{};
  double cachedY(CaretStop s) => yCache[s] ??= resolveY(s);
  final xCache = <CaretStop, double>{};
  double cachedX(CaretStop s) => xCache[s] ??= resolveX(s);

  final x = preferredX >= 0.0 ? preferredX : cachedX(current);
  final currentY = cachedY(current);

  double? targetY;
  for (final stop in stops_) {
    final y = cachedY(stop);
    if (y > currentY + _kLineYTolerance) {
      if (targetY == null || y < targetY) targetY = y;
    }
  }

  if (targetY == null) {
    final docStops = allStops ?? stops_;
    if (_isInLastNode(root, current.fragmentId,
        parentResolver: parentResolver, containerResolver: containerResolver,
        topLevelIndexResolver: topLevelIndexResolver)) {
      final last = docStops.last;
      if (last == current) return NavigationResult.none;
      return NavigationResult(position: last, preferredX: x);
    }
    final currentNodeId = _findTopLevelNodeId(root, current.fragmentId,
        parentResolver: parentResolver, containerResolver: containerResolver,
        topLevelIndexResolver: topLevelIndexResolver);
    if (currentNodeId != null) {
      final currentNodeIdx = topLevelIndexResolver != null
          ? topLevelIndexResolver(currentNodeId)
          : root.nodes.indexWhere((n) => n.id == currentNodeId);
      for (int i = currentNodeIdx + 1; i < root.nodes.length; i++) {
        final nextNode = root.nodes[i];
        for (final stop in docStops) {
          if (_stopBelongsToNode(stop, nextNode, root, containerResolver: containerResolver, parentResolver: parentResolver, topLevelIndexResolver: topLevelIndexResolver)) {
            return NavigationResult(position: stop, preferredX: x);
          }
        }
      }
    }
    final last = docStops.last;
    if (last == current) return NavigationResult.none;
    return NavigationResult(position: last, preferredX: x);
  }

  // Single-pass: find nearest-X stop on the target line without allocating.
  CaretStop? best;
  double bestDist = double.infinity;
  for (final stop in stops_) {
    if ((cachedY(stop) - targetY).abs() <= _kLineYTolerance) {
      final dist = (cachedX(stop) - x).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = stop;
      }
    }
  }
  if (best == null) return NavigationResult(position: current, preferredX: x);
  return NavigationResult(position: best, preferredX: x);
}

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

/// Returns true if [fragmentId] is inside [node] (recursively).
/// Uses O(1) cached resolvers when available, falls back to O(n) recursive scan.
bool _stopBelongsToNode(
  CaretStop stop,
  FNode node,
  Root root, {
  ContainerResolver? containerResolver,
  ParentResolver? parentResolver,
  TopLevelIndexResolver? topLevelIndexResolver,
}) {
  final fragmentId = stop.fragmentId;
  if (containerResolver != null && topLevelIndexResolver != null) {
    // O(1) path: resolve the stop's top-level node id and compare.
    final stopTopId = _findTopLevelNodeId(root,
        fragmentId,
        parentResolver: parentResolver,
        containerResolver: containerResolver,
        topLevelIndexResolver: topLevelIndexResolver);
    return stopTopId == node.id;
  }
  return _nodeContainsFragment(node, fragmentId);
}

/// Returns true if [fragmentId] is inside [node] (recursively).
bool _nodeContainsFragment(FNode node, String fragmentId) {
  if (node is Fragment && node.id == fragmentId) return true;
  if (node is FluentTable) {
    for (final row in node.getChildren()) {
      for (final cell in row.getChildren()) {
        if (_nodeContainsFragment(cell, fragmentId)) return true;
      }
    }
    return false;
  }
  if (node is FluentList) {
    for (final child in node.getChildren()) {
      if (_nodeContainsFragment(child, fragmentId)) return true;
    }
    return false;
  }
  if (node is InlineContainerNode) {
    for (final child in (node as InlineContainerNode).getChildren()) {
      if (_nodeContainsFragment(child, fragmentId)) return true;
    }
  }
  return false;
}

/// Returns the id of the top-level node in [root] that contains [fragmentId].
/// Uses [parentResolver] and [containerResolver] for O(1) lookups when provided;
/// falls back to O(n) tree traversal otherwise.
String? _findTopLevelNodeId(
  Root root,
  String fragmentId, {
  ParentResolver? parentResolver,
  ContainerResolver? containerResolver,
  TopLevelIndexResolver? topLevelIndexResolver,
}) {
  if (containerResolver != null) {
    final containerId = containerResolver(fragmentId);
    if (containerId == null) return null;
    // If the container is itself a top-level node, return it directly.
    if (topLevelIndexResolver != null) {
      if (topLevelIndexResolver(containerId) >= 0) return containerId;
    } else if (root.nodes.any((n) => n.id == containerId)) {
      return containerId;
    }
    String current = containerId;
    while (true) {
      final parent = parentResolver?.call(current);
      if (parent == null) return current;
      // If parent is a top-level node, return it.
      if (topLevelIndexResolver != null) {
        if (topLevelIndexResolver(parent) >= 0) return parent;
      } else if (root.nodes.any((n) => n.id == parent)) {
        return parent;
      }
      current = parent;
    }
  }
  final container = findLogicalContainer(root, fragmentId);
  if (container == null) return null;
  FNode node = container as FNode;
  while (true) {
    final parent = findParent(root, node);
    if (parent == null || parent is Root) return node.id;
    node = parent;
  }
}

/// True when the fragment belongs to the first top-level node of [root].
bool _isInFirstNode(
  Root root,
  String fragmentId, {
  ParentResolver? parentResolver,
  ContainerResolver? containerResolver,
  TopLevelIndexResolver? topLevelIndexResolver,
}) {
  if (root.nodes.isEmpty) return false;
  final id = _findTopLevelNodeId(root, fragmentId,
      parentResolver: parentResolver, containerResolver: containerResolver,
      topLevelIndexResolver: topLevelIndexResolver);
  return id != null && id == root.nodes.first.id;
}

/// True when the fragment belongs to the last top-level node of [root].
bool _isInLastNode(
  Root root,
  String fragmentId, {
  ParentResolver? parentResolver,
  ContainerResolver? containerResolver,
  TopLevelIndexResolver? topLevelIndexResolver,
}) {
  if (root.nodes.isEmpty) return false;
  final id = _findTopLevelNodeId(root, fragmentId,
      parentResolver: parentResolver, containerResolver: containerResolver,
      topLevelIndexResolver: topLevelIndexResolver);
  return id != null && id == root.nodes.last.id;
}

/// Pre-compiled RegExp for word-character detection.
/// Avoids creating a new RegExp object on every character check
/// during word navigation (CTRL+arrow), which could be 1000+
/// allocations per long word.
final _wordCharRe = RegExp(r'[a-zA-Z0-9_\u00C0-\u024F]');

bool _isWordChar(String ch) => _wordCharRe.hasMatch(ch);

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

List<CaretStop>? _wordCacheStopsRef;
Map<String, Fragment>? _wordFragCache;
List<int>? _wordLineIdx;

void _ensureWordCaches(
  Root root,
  List<CaretStop> stops, {
  List<LogicalLine>? cachedLines,
}) {
  if (identical(stops, _wordCacheStopsRef) &&
      _wordFragCache != null &&
      _wordLineIdx != null) {
    return;
  }
  _wordCacheStopsRef = stops;
  _wordFragCache = _buildFragmentCache(root);
  _wordLineIdx = _buildStopLineIndex(stops, cachedLines ?? buildAllLogicalLines(root));
}

NavigationResult moveWordRight(Root root, CaretStop current, {
  List<CaretStop>? stops,
  List<LogicalLine>? cachedLines,
}) {
  final stops_ = stops ?? buildAllStops(root);
  int idx = findStopIndex(stops_, current.fragmentId, current.offset);
  if (idx < 0 || idx >= stops_.length - 1) return NavigationResult.none;

  _ensureWordCaches(root, stops_, cachedLines: cachedLines);
  final cache = _wordFragCache!;
  final lineIdx = _wordLineIdx!;
  String? ch(int i) => _charRight(stops_, i, cache, lineIdx);

  final startChar = ch(idx);

  if (startChar == null) return NavigationResult.none;

  if (_isSpaceChar(startChar)) {
    while (idx < stops_.length - 1 && _isSpaceChar(ch(idx) ?? '')) {
      idx++;
    }
    while (idx < stops_.length - 1) {
      final c = ch(idx);
      if (c == null || !_isWordChar(c)) break;
      idx++;
    }
  } else if (_isWordChar(startChar)) {
    while (idx < stops_.length - 1) {
      final c = ch(idx);
      if (c == null || !_isWordChar(c)) break;
      idx++;
    }
  } else {
    while (idx < stops_.length - 1) {
      final c = ch(idx);
      if (c == null || _isWordChar(c) || _isSpaceChar(c)) break;
      idx++;
    }
  }

  return NavigationResult(position: stops_[idx], preferredX: 0.0);
}

NavigationResult moveWordLeft(Root root, CaretStop current, {
  List<CaretStop>? stops,
  List<LogicalLine>? cachedLines,
}) {
  final stops_ = stops ?? buildAllStops(root);
  int idx = findStopIndex(stops_, current.fragmentId, current.offset);
  if (idx < 0 || idx <= 0) return NavigationResult.none;

  _ensureWordCaches(root, stops_, cachedLines: cachedLines);
  final cache = _wordFragCache!;
  final lineIdx = _wordLineIdx!;
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
  return null;
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

/// Moves the cursor to the start of the current logical line.
/// If [lines] is provided (e.g. from a document cache), it is used directly
/// instead of rebuilding the entire tree with buildAllLogicalLines(root).
NavigationResult moveToLineStart(
  Root root,
  CaretStop current, {
  List<LogicalLine>? lines,
}) {
  final lines_ = lines ?? buildAllLogicalLines(root);
  final lineInfo = findLineForStop(lines_, current);
  if (lineInfo == null) return NavigationResult.none;

  final line = lines_[lineInfo.lineIndex];
  if (line.stops.isEmpty) return NavigationResult.none;

  final firstStop = line.stops.first;
  if (firstStop == current) return NavigationResult.none;

  return NavigationResult(position: firstStop, preferredX: 0.0);
}

/// Moves the cursor to the end of the current logical line.
NavigationResult moveToLineEnd(
  Root root,
  CaretStop current, {
  List<LogicalLine>? lines,
}) {
  final lines_ = lines ?? buildAllLogicalLines(root);
  final lineInfo = findLineForStop(lines_, current);
  if (lineInfo == null) return NavigationResult.none;

  final line = lines_[lineInfo.lineIndex];
  if (line.stops.isEmpty) return NavigationResult.none;

  final lastStop = line.stops.last;
  if (lastStop == current) return NavigationResult.none;

  return NavigationResult(position: lastStop, preferredX: 0.0);
}

/// Moves the cursor up by approximately 10-15 logical lines.
NavigationResult movePageUp(
  Root root,
  CaretStop current,
  double preferredX,
  CaretXResolver resolveX,
  CaretYResolver resolveY, {
  List<LogicalLine>? lines,
}) {
  final lines_ = lines ?? buildAllLogicalLines(root);
  final lineInfo = findLineForStop(lines_, current);
  if (lineInfo == null) return NavigationResult.none;

  final currentLineIndex = lineInfo.lineIndex;
  final targetLineIndex = (currentLineIndex - 10).clamp(0, lines_.length - 1);

  if (targetLineIndex == currentLineIndex) {
    // Use the first line's first stop instead of rebuilding all stops.
    if (lines_.isEmpty || lines_.first.stops.isEmpty) return NavigationResult.none;
    final firstStop = lines_.first.stops.first;
    if (firstStop == current) return NavigationResult.none;
    return NavigationResult(position: firstStop, preferredX: preferredX);
  }

  final targetLine = lines_[targetLineIndex];
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
  CaretYResolver resolveY, {
  List<LogicalLine>? lines,
}) {
  final lines_ = lines ?? buildAllLogicalLines(root);
  final lineInfo = findLineForStop(lines_, current);
  if (lineInfo == null) return NavigationResult.none;

  final currentLineIndex = lineInfo.lineIndex;
  final targetLineIndex = (currentLineIndex + 10).clamp(0, lines_.length - 1);

  if (targetLineIndex == currentLineIndex) {
    // Use the last line's last stop instead of rebuilding all stops.
    if (lines_.isEmpty || lines_.last.stops.isEmpty) return NavigationResult.none;
    final lastStop = lines_.last.stops.last;
    if (lastStop == current) return NavigationResult.none;
    return NavigationResult(position: lastStop, preferredX: preferredX);
  }

  final targetLine = lines_[targetLineIndex];
  if (targetLine.stops.isEmpty) return NavigationResult.none;

  final x = preferredX >= 0.0 ? preferredX : resolveX(current);
  final best = _stopNearestX(targetLine.stops, x, resolveX);

  return NavigationResult(position: best, preferredX: x);
}

/// Checks whether [nodeId] (with its two caret stops at offset 0 and 1)
/// falls within the current selection range defined by [cursor].
bool isNodeInSelectionRange(
  List<CaretStop> stops,
  Cursor cursor,
  String nodeId,
) {
  if (cursor.isCollapsed) return false;
  final anchorIdx = findStopIndex(stops, cursor.anchorId, cursor.anchorOffset);
  final focusIdx = findStopIndex(stops, cursor.focusId, cursor.focusOffset);
  final node0Idx = findStopIndex(stops, nodeId, 0);
  final node1Idx = findStopIndex(stops, nodeId, 1);
  if (anchorIdx < 0 || focusIdx < 0 || node0Idx < 0 || node1Idx < 0) return false;
  final lo = anchorIdx < focusIdx ? anchorIdx : focusIdx;
  final hi = anchorIdx < focusIdx ? focusIdx : anchorIdx;
  return lo <= node0Idx && node1Idx <= hi;
}
