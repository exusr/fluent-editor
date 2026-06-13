import 'package:fluent_editor/fluent_document.dart';

/// Applies line height and paragraph spacing at the document level.
/// These values are global and apply to all paragraphs.
bool executeHandleParagraphSpacing(
  FluentDocument document, {
  double? lineHeight,
  double? spacingBefore,
  double? spacingAfter,
}) {
  if (lineHeight != null) document.pendingLineHeight = lineHeight;
  if (spacingBefore != null) document.pendingSpacingBefore = spacingBefore;
  if (spacingAfter != null) document.pendingSpacingAfter = spacingAfter;

  document.updateContent();
  return true;
}
