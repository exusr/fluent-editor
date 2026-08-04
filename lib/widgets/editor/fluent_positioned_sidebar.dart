import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/widgets/fluent_document_widget.dart';

/// Categories for items displayed in the sidebar.
enum FluentSidebarItemCategory {
  comment,
  suggestion,
  other,
}

/// A generic item entry for the positioned sidebar.
class FluentSidebarItem {
  final String id;
  final String nodeId;
  final Widget widget;
  final double estimatedHeight;
  final DateTime? createdAt;
  final FluentSidebarItemCategory category;

  const FluentSidebarItem({
    required this.id,
    required this.nodeId,
    required this.widget,
    this.estimatedHeight = 130.0,
    this.createdAt,
    this.category = FluentSidebarItemCategory.other,
  });
}

/// Generic sidebar widget that positions [FluentSidebarItem] cards vertically
/// at the Y coordinate of their target document node, resolving collisions and
/// scrolling in 1-to-1 sync with the document.
class FluentPositionedSidebar extends StatefulWidget {
  const FluentPositionedSidebar({
    super.key,
    required this.document,
    required this.items,
    this.header,
    this.emptyState,
    this.width = 300.0,
  });

  final FluentDocument document;
  final List<FluentSidebarItem> items;
  final Widget? header;
  final Widget? emptyState;
  final double width;

  @override
  State<FluentPositionedSidebar> createState() =>
      _FluentPositionedSidebarState();
}

class _FluentPositionedSidebarState extends State<FluentPositionedSidebar> {
  ScrollController? _scrollController;
  final GlobalKey _sidebarAreaKey = GlobalKey();

  // Cache: node id -> Y position within the scrollable content.
  final Map<String, double> _nodeYInContent = {};
  int _cachedContentVersion = -1;

  // Measured card heights: item id -> rendered height.
  final Map<String, double> _cardHeights = {};

  void _invalidateNodeYCache() {
    _nodeYInContent.clear();
    _cachedContentVersion = widget.document.contentVersion;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final layout = DocumentLayout.of(context);
    final newController = layout?.scrollController;
    if (newController != _scrollController) {
      _scrollController = newController;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocChanged);
  }

  void _onDocChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 2,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.15),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.header != null) widget.header!,
            Expanded(
              child: Stack(
                children: [
                  widget.items.isEmpty
                      ? (widget.emptyState ?? const SizedBox.shrink())
                      : _buildPositionedItems(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionedItems(BuildContext context) {
    final doc = widget.document;
    final layout = DocumentLayout.of(context);
    final scrollController = layout?.scrollController ?? _scrollController;

    if (doc.contentVersion != _cachedContentVersion) {
      _invalidateNodeYCache();
    }

    final nodeIds = <String>{};
    for (final item in widget.items) {
      nodeIds.add(item.nodeId);
    }
    for (final nodeId in nodeIds) {
      if (!_nodeYInContent.containsKey(nodeId)) {
        final y = _computeNodeYInContent(doc, nodeId, scrollController);
        if (_sidebarAreaKey.currentContext?.findRenderObject() is RenderBox) {
          _nodeYInContent[nodeId] = y;
        }
      }
    }

    if (nodeIds.any((id) => !_nodeYInContent.containsKey(id))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }

    final cardKeys = <GlobalKey>[];
    final cards = [
      for (final item in widget.items)
        () {
          final key = GlobalKey(debugLabel: 'sidebar_item_${item.id}');
          cardKeys.add(key);
          return KeyedSubtree(
            key: key,
            child: item.widget,
          );
        }(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var changed = false;
      for (int i = 0; i < widget.items.length; i++) {
        final box = cardKeys[i].currentContext?.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final h = box.size.height;
          final prev = _cardHeights[widget.items[i].id];
          if (prev == null || (prev - h).abs() > 0.5) {
            _cardHeights[widget.items[i].id] = h;
            changed = true;
          }
        }
      }
      if (changed) setState(() {});
    });

    final indexed = <int>[];
    for (int i = 0; i < widget.items.length; i++) {
      indexed.add(i);
    }
    indexed.sort((a, b) {
      final ya = _nodeYInContent[widget.items[a].nodeId] ?? 0;
      final yb = _nodeYInContent[widget.items[b].nodeId] ?? 0;
      if ((ya - yb).abs() > 0.1) return ya.compareTo(yb);
      final ca = widget.items[a].createdAt;
      final cb = widget.items[b].createdAt;
      if (ca != null && cb != null) return ca.compareTo(cb);
      return a.compareTo(b);
    });

    final baseYs = List<double>.filled(widget.items.length, 0);
    double nextAvailable = -double.infinity;
    for (final i in indexed) {
      final targetY = _nodeYInContent[widget.items[i].nodeId] ?? 0;
      var y = targetY < nextAvailable ? nextAvailable : targetY;
      baseYs[i] = y;
      final h = _cardHeights[widget.items[i].id] ?? widget.items[i].estimatedHeight;
      nextAvailable = y + h;
    }

    return AnimatedBuilder(
      animation: scrollController ?? AlwaysStoppedAnimation(0),
      builder: (context, _) {
        final scrollOffset = scrollController?.hasClients == true
            ? scrollController!.position.pixels
            : 0.0;
        final viewportHeight = scrollController?.hasClients == true
            ? scrollController!.position.viewportDimension
            : double.infinity;

        final positionedChildren = <Widget>[];
        for (int i = 0; i < widget.items.length; i++) {
          final y = baseYs[i] - scrollOffset;
          final cardH =
              _cardHeights[widget.items[i].id] ?? widget.items[i].estimatedHeight;

          if (y + cardH < 0 || y > viewportHeight) continue;

          positionedChildren.add(
            Positioned(
              top: y,
              left: 0,
              right: 0,
              child: cards[i],
            ),
          );
        }

        return Stack(
          key: _sidebarAreaKey,
          clipBehavior: Clip.hardEdge,
          children: positionedChildren,
        );
      },
    );
  }

  double _computeNodeYInContent(
    FluentDocument doc,
    String nodeId,
    ScrollController? scrollController,
  ) {
    final resolvedNodeId = doc.findLogicalContainerId(nodeId) ?? nodeId;
    final render = doc.paragraphRegistry.renderFor(resolvedNodeId);
    if (render != null && render.attached && render.hasSize) {
      final areaBox =
          _sidebarAreaKey.currentContext?.findRenderObject() as RenderBox?;
      if (areaBox != null && areaBox.hasSize) {
        final nodeGlobal = render.localToGlobal(Offset.zero);
        final areaGlobal = areaBox.localToGlobal(Offset.zero);
        final scrollOffset = scrollController?.hasClients == true
            ? scrollController!.position.pixels
            : 0.0;
        return nodeGlobal.dy - areaGlobal.dy + scrollOffset;
      }
      final stackCtx =
          DocumentLayout.of(context)?.contentStackKey.currentContext;
      if (stackCtx?.findRenderObject() is RenderBox) {
        final stackBox = stackCtx!.findRenderObject() as RenderBox;
        final nodeGlobal = render.localToGlobal(Offset.zero);
        final stackGlobal = stackBox.localToGlobal(Offset.zero);
        final scrollOffset = scrollController?.hasClients == true
            ? scrollController!.position.pixels
            : 0.0;
        return nodeGlobal.dy - stackGlobal.dy + scrollOffset;
      }
    }
    return 0.0;
  }
}
