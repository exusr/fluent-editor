import 'package:flutter/widgets.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';

/// DEPRECATED: With the new architecture, Links are managed as TextSpan
/// inside RenderFluentParagraph. This widget returns an empty widget
/// because the link is already rendered by the parent paragraph.
class FluentLinkWidget extends StatelessWidget {
  const FluentLinkWidget({super.key, required this.node, required this.document});

  final Link node;
  final FluentDocument document;

  @override
  Widget build(BuildContext context) {
    // The link is already rendered by the parent paragraph as TextSpan
    return const SizedBox.shrink();
  }
}