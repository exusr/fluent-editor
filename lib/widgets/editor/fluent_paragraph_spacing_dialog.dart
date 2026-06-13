import 'package:flutter/material.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';

/// Modal to set line height and spacing between paragraphs.
class ParagraphSpacingDialog extends StatefulWidget {
  final double initialLineHeight;
  final double initialSpacingBefore;
  final double initialSpacingAfter;
  final FluentEditorLabels? labels;

  const ParagraphSpacingDialog({
    super.key,
    required this.initialLineHeight,
    required this.initialSpacingBefore,
    required this.initialSpacingAfter,
    this.labels,
  });

  @override
  State<ParagraphSpacingDialog> createState() => _ParagraphSpacingDialogState();

  /// Shows the dialog and returns the applied values (null = cancelled).
  static Future<(double, double, double)?> show(
    BuildContext context, {
    required double lineHeight,
    required double spacingBefore,
    required double spacingAfter,
    FluentEditorLabels? labels,
  }) {
    return showDialog<(double, double, double)?>(
      context: context,
      builder: (_) => ParagraphSpacingDialog(
        initialLineHeight: lineHeight,
        initialSpacingBefore: spacingBefore,
        initialSpacingAfter: spacingAfter,
        labels: labels,
      ),
    );
  }
}

class _ParagraphSpacingDialogState extends State<ParagraphSpacingDialog> {
  late final TextEditingController _lhCtrl;
  late final TextEditingController _sbCtrl;
  late final TextEditingController _saCtrl;

  FluentEditorLabels get _labels => widget.labels ?? const FluentEditorLabels();

  @override
  void initState() {
    super.initState();
    _lhCtrl = TextEditingController(
      text: widget.initialLineHeight.toStringAsFixed(2),
    );
    _sbCtrl = TextEditingController(
      text: widget.initialSpacingBefore.toStringAsFixed(0),
    );
    _saCtrl = TextEditingController(
      text: widget.initialSpacingAfter.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _lhCtrl.dispose();
    _sbCtrl.dispose();
    _saCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final lh = double.tryParse(_lhCtrl.text.replaceAll(',', '.'));
    final sb = double.tryParse(_sbCtrl.text);
    final sa = double.tryParse(_saCtrl.text);

    final result = (
      lh ?? widget.initialLineHeight,
      sb ?? widget.initialSpacingBefore,
      sa ?? widget.initialSpacingAfter,
    );
    Navigator.of(context).pop(result);
  }

  Widget _buildField(String label, TextEditingController controller, String suffix) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                suffixText: suffix,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_labels.paragraphSpacing),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildField(_labels.lineHeight, _lhCtrl, ''),
            _buildField(_labels.spacingBefore, _sbCtrl, 'pt'),
            _buildField(_labels.spacingAfter, _saCtrl, 'pt'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(_labels.cancel),
        ),
        FilledButton(
          onPressed: _apply,
          child: Text(_labels.apply),
        ),
      ],
    );
  }
}
