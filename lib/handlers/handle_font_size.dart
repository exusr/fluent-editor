import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';

bool executeHandleFontSize(FluentDocument document, double fontSize) =>
    applyStyleProperty(document, fontSize,
        modifyLeaf: (leaf, v) => leaf.fontSize = v,
        setPending: (doc, v) => doc.pendingFontSize = v);
