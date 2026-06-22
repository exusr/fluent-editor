import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;

Future<List<String>> loadSystemFonts() async {
  if (kIsWeb) return [];
  if (Platform.isLinux) {
    try {
      final result = await Process.run('fc-list', [':', 'family']);
      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        final families = <String>{};
        for (final line in stdout.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final mainFamily = trimmed.split(',').first.trim();
          if (mainFamily.isNotEmpty) families.add(mainFamily);
        }
        return families.toList()..sort();
      }
    } catch (e) {
    }
  }
  return _fallbackFonts;
}

const _fallbackFonts = <String>[
  'DejaVu Sans', 'Cantarell', 'Helvetica', 'Liberation Sans',
  'Lucida Grande', 'Noto Sans', 'Roboto', 'Segoe UI', 'Tahoma',
  'Trebuchet MS', 'Ubuntu', 'Verdana', 'Book Antiqua', 'Garamond',
  'Georgia', 'Liberation Serif', 'Noto Serif', 'Palatino',
  'Times New Roman', 'Andale Mono', 'Consolas', 'Courier New',
  'Courier', 'DejaVu Sans Mono', 'Liberation Mono', 'Lucida Console',
  'Monaco', 'Ubuntu Mono',
];

/// Normalizes a font family name, mapping generic/legacy families to our bundled default.
String normalizeFontFamily(String? fontFamily) {
  if (fontFamily == null || fontFamily.isEmpty) return 'DejaVu Sans';
  final lower = fontFamily.toLowerCase();
  if (lower == 'sans-serif' || lower == 'arial' || lower == 'helvetica') {
    return 'DejaVu Sans';
  }
  return fontFamily;
}
