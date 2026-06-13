import 'package:flutter/material.dart';
import 'package:fluent_editor/comments/comment_provider.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';

/// Dialog that lets the user set their author name for comments and replies.
Future<void> showAuthorInfoDialog(
  BuildContext context, {
  required CommentProvider commentProvider,
  FluentEditorLabels? labels,
}) async {
  final controller = TextEditingController(text: commentProvider.currentAuthor);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(labels?.authorInfoDialogTitle ?? 'Author Information'),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: labels?.authorNameLabel ?? 'Author Name',
          hintText: labels?.authorNameHint ?? 'Enter your name...',
        ),
        autofocus: true,
        maxLines: 1,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(labels?.cancel ?? 'Cancel'),
        ),
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              commentProvider.currentAuthor = name;
            }
            Navigator.of(ctx).pop();
          },
          child: Text(labels?.confirmButton ?? 'Confirm'),
        ),
      ],
    ),
  );
  controller.dispose();
}
