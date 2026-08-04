import 'package:flutter/material.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'fluent_positioned_sidebar.dart';

/// A single, unified sidebar component provided by the core editor library.
/// Displays all comments and suggestions together in a single integrated list,
/// aligned to their respective document positions and scrolling seamlessly
/// with the document text.
class FluentUnifiedSidebar extends StatelessWidget {
  const FluentUnifiedSidebar({
    super.key,
    required this.document,
    required this.items,
    this.title,
    this.icon = Icons.rate_review_outlined,
    this.emptyMessage,
    this.width = 300.0,
  });

  final FluentDocument document;
  final List<FluentSidebarItem> items;
  final String? title;
  final IconData icon;
  final String? emptyMessage;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTitle =
        title ?? document.labels?.sidebarTitle ?? 'Activities & Reviews';
    final effectiveEmptyMessage = emptyMessage ??
        document.labels?.emptySidebarMessage ??
        'No comments or suggestions in the document.';

    return FluentPositionedSidebar(
      document: document,
      width: width,
      header: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                effectiveTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (items.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${items.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
      emptyState: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mark_chat_read_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                effectiveEmptyMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      items: items,
    );
  }
}
