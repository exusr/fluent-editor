import 'dart:async';

import 'spell_annotation.dart';

/// Abstract interface that a spell-check plugin must implement.
///
/// The [FluentDocument] holds an optional instance of this provider.
/// Widgets and render objects call the provider when a spell-check
/// feature is available, and gracefully degrade when it is null.
abstract class SpellCheckProvider {
  /// Stream that emits the [nodeId] whose annotations have changed.
  Stream<String> get annotationsChanged;

  /// Whether spell checking is globally enabled.
  bool get enabled;
  set enabled(bool value);

  /// Initializes the provider with the given language code.
  Future<void> initialize(String languageCode);

  /// Reloads the provider with a new language code.
  Future<void> reloadLanguage(String languageCode);

  /// Requests a spell check for [nodeId] with text [plainText].
  void checkParagraph(String nodeId, String plainText);

  /// Cancels any pending check for [nodeId].
  void cancelCheck(String nodeId);

  /// Shifts existing annotations after a document mutation.
  void onDocumentMutation(String nodeId, int fromOffset, int delta);

  /// Returns the current annotations for [nodeId].
  List<SpellAnnotation> annotationsForNode(String nodeId);

  /// Requests on-demand suggestions for [word].
  Future<List<String>> requestSuggestions(String word);

  /// Adds [word] to the runtime dictionary.
  Future<void> addToDictionary(String word);

  /// Ignores [word] for the current session.
  void ignoreWord(String word);

  /// Disposes the provider.
  void dispose();
}
