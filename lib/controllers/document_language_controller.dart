import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluent_editor/models/document_language.dart';

/// Singleton controller that manages the document-level language selection.
/// Persists the choice via SharedPreferences and exposes it through a
/// [ValueNotifier] so consumers (e.g. SpellCheckController) can listen
/// without direct coupling.
class DocumentLanguageController {
  DocumentLanguageController._();

  static final DocumentLanguageController _instance = DocumentLanguageController._();
  static DocumentLanguageController get instance => _instance;

  static const String _prefsKey = 'fluent_document_language';
  static const String _defaultCode = 'it';

  final ValueNotifier<DocumentLanguage> currentLanguage =
      ValueNotifier<DocumentLanguage>(DocumentLanguage.fromCode(_defaultCode));

  bool _initialized = false;

  /// Returns the closest supported language code based on the system locale.
  static String _resolveSystemLocale() {
    try {
      final raw = Platform.localeName;
      // Extract locale before any '.' (e.g. "it_IT.UTF-8" -> "it_IT")
      final locale = raw.split('.').first;
      final lower = locale.toLowerCase();

      // Exact match first
      for (final lang in DocumentLanguage.supported) {
        if (lang.code.toLowerCase() == lower) return lang.code;
      }

      // Partial match by primary language (e.g. "en_CA" -> "en_US")
      final primary = lower.split('_').first;
      for (final lang in DocumentLanguage.supported) {
        if (lang.code.toLowerCase().split('_').first == primary) {
          return lang.code;
        }
      }
    } catch (_) {}
    return _defaultCode;
  }

  /// Initializes the controller by reading the saved language from
  /// SharedPreferences. Falls back to the system locale when nothing
  /// has been saved. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_prefsKey);
    final targetCode = savedCode ?? _resolveSystemLocale();
    final lang = DocumentLanguage.fromCode(targetCode);
    if (currentLanguage.value.code != lang.code) {
      currentLanguage.value = lang;
    }
    _initialized = true;
  }

  /// Synchronous access to the current language value.
  DocumentLanguage get current => currentLanguage.value;

  /// Changes the document language and persists the choice.
  Future<void> setLanguage(DocumentLanguage lang) async {
    if (currentLanguage.value.code == lang.code) return;

    currentLanguage.value = lang;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, lang.code);
  }
}
