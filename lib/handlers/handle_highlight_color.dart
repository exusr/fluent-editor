import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';

/// Applies highlight color to fragments affected by the selection
/// or stores the pending color for collapsed cursor.
/// Pass [null] or empty string to remove the highlight.
bool executeHandleHighlightColor(FluentDocument document, String? color) =>
    applyStyleProperty(document, color,
        modifyLeaf: (leaf, v) => leaf.highlightColor = v,
        setPending: (doc, v) => doc.pendingHighlightColor = v);
