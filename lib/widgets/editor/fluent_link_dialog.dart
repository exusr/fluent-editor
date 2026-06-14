import 'package:flutter/material.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';

/// Dialog for inserting a link with URL and custom text.
class FluentLinkDialog extends StatefulWidget {
  const FluentLinkDialog({
    super.key,
    this.labels,
    this.initialUrl,
    this.initialText,
  });

  final FluentEditorLabels? labels;
  final String? initialUrl;
  final String? initialText;

  @override
  State<FluentLinkDialog> createState() => _FluentLinkDialogState();
}

class _FluentLinkDialogState extends State<FluentLinkDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _textController;
  final _formKey = GlobalKey<FormState>();

  FluentEditorLabels get _labels => widget.labels ?? const FluentEditorLabels();

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
    _textController = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_labels.insertLink),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: _labels.url,
                hintText: _labels.urlHint,
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return _labels.urlRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _textController,
              decoration: InputDecoration(
                labelText: _labels.linkText,
                hintText: _labels.linkTextHint,
                prefixIcon: Icon(Icons.text_fields),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return _labels.linkTextRequired;
                }
                return null;
              },
            ),
          ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_labels.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop({
                'url': _urlController.text.trim(),
                'text': _textController.text.trim(),
              });
            }
          },
          child: Text(_labels.insertButton),
        ),
      ],
    );
  }
}

/// Shows the dialog to insert a link.
/// Returns a Map with 'url' and 'text' or null if cancelled.
Future<Map<String, String>?> showFluentLinkDialog(
  BuildContext context, {
  FluentEditorLabels? labels,
  String? initialUrl,
  String? initialText,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => FluentLinkDialog(
      labels: labels,
      initialUrl: initialUrl,
      initialText: initialText,
    ),
  );
}
