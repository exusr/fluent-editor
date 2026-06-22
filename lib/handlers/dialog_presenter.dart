import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_insert_node.dart';
import 'package:fluent_editor/widgets/editor/fluent_link_dialog.dart';
import 'package:fluent_editor/widgets/dialogs/image_insert_dialog.dart';
import 'package:flutter/widgets.dart';

/// Handles dialog presentation for editor actions that require user input
/// (link insertion, image insertion). Separated from EventHandler to respect
/// SRP: EventHandler processes keyboard/tap input, DialogPresenter shows UI.
class DialogPresenter {
  final FluentDocument document;

  DialogPresenter(this.document);

  /// Shows the dialog to insert a link and inserts it if confirmed.
  Future<void> handleInsertLink(BuildContext context) async {
    final result = await showFluentLinkDialog(context, labels: document.labels);
    if (result != null) {
      final url = result['url']!;
      final text = result['text']!;
      document.saveState(description: 'Insert link', forceNewAction: true);
      handleInsertNodeExceution(
        'link',
        document,
        {'url': url, 'text': text},
      );
    }
  }

  /// Shows the dialog to insert an image and inserts it if confirmed.
  Future<void> handleInsertImage(BuildContext context) async {
    final result = await showImageInsertDialog(context, labels: document.labels);
    if (result != null) {
      final src = result['src']!;
      document.saveState(description: 'Insert image', forceNewAction: true);
      handleInsertNodeExceution(
        'image',
        document,
        {'src': src},
      );
    }
  }
}
