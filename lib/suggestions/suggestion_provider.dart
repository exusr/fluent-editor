import 'dart:async';
import 'package:fluent_editor/suggestions/suggestion_style_hook.dart';

/// Abstract interface for a suggestion / tracked changes system.
///
/// The [FluentDocument] holds an optional instance. When set,
/// exporters (DOCX, ODT, etc.) and renderers can query
/// tracked additions and deletions with full metadata.
abstract class SuggestionProvider {
  /// Hook configuration for suggestion addition and deletion styles.
  SuggestionStyleHook get styleHook => const SuggestionStyleHook();

  /// Stream emitting whenever suggestions change.
  Stream<void> get suggestionsChanged;

  /// Export all pending suggestions as serialized maps:
  ///   'id'           -> String
  ///   'nodeId'       -> String
  ///   'startOffset'  -> int
  ///   'endOffset'    -> int
  ///   'type'         -> String ('addition' | 'deletion')
  ///   'authorName'   -> String
  ///   'text'         -> String
  ///   'createdAt'    -> String / DateTime
  List<Map<String, dynamic>> exportSuggestions();

  /// Returns pending suggestions for [nodeId].
  List<Map<String, dynamic>> suggestionsForNode(String nodeId);
}
