import 'package:flutter/material.dart';

/// Voce del menu contestuale dell'editor.
class FluentContextMenuItem {
  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;

  const FluentContextMenuItem({
    this.icon,
    required this.label,
    this.onPressed,
  });
}

/// PopupMenuItem custom che forza il cursore pointer.
class _FluentPopupMenuItem extends PopupMenuItem<int> {
  const _FluentPopupMenuItem({
    required super.value,
    required super.enabled,
    required super.child,
  });

  @override
  PopupMenuItemState<int, PopupMenuItem<int>> createState() =>
      _FluentPopupMenuItemState();
}

class _FluentPopupMenuItemState
    extends PopupMenuItemState<int, PopupMenuItem<int>> {
  @override
  Widget buildChild() {
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      child: super.buildChild(),
    );
  }
}

/// Shows a context menu positioned at the given global position.
Future<void> showFluentContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<FluentContextMenuItem> items,
}) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    ),
    items: items.asMap().entries.map((entry) {
      final item = entry.value;
      if (item.label.isEmpty && item.onPressed == null) {
        return const PopupMenuDivider() as PopupMenuEntry<int>;
      }
      return _FluentPopupMenuItem(
        value: entry.key,
        enabled: item.onPressed != null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 20),
              const SizedBox(width: 12),
            ],
            Text(item.label),
          ],
        ),
      );
    }).toList(),
  ).then((selectedIndex) {
    if (selectedIndex != null && selectedIndex < items.length) {
      items[selectedIndex].onPressed?.call();
    }
  });
}