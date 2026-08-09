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
    final effectiveEmptyMessage = emptyMessage ??
        document.labels?.emptySidebarMessage ??
        'No comments or suggestions in the document.';

    return FluentPositionedSidebar(
      document: document,
      width: width,
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
