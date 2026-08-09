import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';

/// Applies text color to fragments affected by the selection
/// or stores the pending color for collapsed cursor.
/// Pass [null] or empty string for "auto" (removes the color).
bool executeHandleTextColor(FluentDocument document, String? color) =>
    applyStyleProperty(document, color,
        description: 'Change text color',
        modifyLeaf: (leaf, v) => leaf.color = v,
        setPending: (doc, v) => doc.pendingColor = v);
