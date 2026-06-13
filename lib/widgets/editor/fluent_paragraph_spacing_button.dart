import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/widgets/editor/fluent_paragraph_spacing_dialog.dart';
import 'package:flutter/material.dart';

class FluentParagraphSpacingButton extends StatelessWidget {
  final FluentDocument document;
  final FluentEditorLabels? labels;

  const FluentParagraphSpacingButton({super.key, required this.document, this.labels});

  void _showDialog(BuildContext context) async {
    final result = await ParagraphSpacingDialog.show(
      context,
      lineHeight: document.pendingLineHeight,
      spacingBefore: document.pendingSpacingBefore,
      spacingAfter: document.pendingSpacingAfter,
      labels: labels ?? document.labels,
    );

    if (result != null) {
      document.eventHandler.handleParagraphSpacing(
        lineHeight: result.$1,
        spacingBefore: result.$2,
        spacingAfter: result.$3,
      );
      document.requestEditorFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Paragraph spacing',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: InkWell(
          onTap: () => _showDialog(context),
          borderRadius: BorderRadius.circular(4),
          mouseCursor: SystemMouseCursors.click,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.format_line_spacing, size: 20),
          ),
        ),
      ),
    );
  }
}