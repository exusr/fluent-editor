import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:flutter/material.dart';

const _channel = MethodChannel('com.fluenteditor/fonts');

/// Fallback for unsupported platforms or in case of error.
const _fallbackFonts = <String>[
  'DejaVu Sans',
  'Calibri',
  'Cambria',
  'Comic Sans MS',
  'Courier New',
  'Georgia',
  'Helvetica',
  'Impact',
  'Lato',
  'Poppins',
  'Tahoma',
  'Times New Roman',
  'Trebuchet MS',
  'Verdana',
];

/// Curated list of popular Google Fonts for web.
/// These fonts are bundled locally in assets/fonts/.
/// To add more fonts, place .ttf files in that directory and update this list.
const _googleFontsForWeb = <String>[
  'DejaVu Sans',
  'Crimson Text',
  'Fira Sans',
  'Lato',
  'Poppins',
  'Titillium Web',
];

/// Fonts to always exclude, regardless of platform.
const _blocklist = <String>{
  'Wingdings', 'Wingdings 2', 'Wingdings 3',
  'Webdings', 'Symbol', 'Marlett',
  'MT Extra', 'Bookshelf Symbol 7',
  'MS UI Gothic', 'Microsoft Sans Serif',
  'Small Fonts', 'Terminal', 'Fixedsys', 'System', 'Modern', 'Roman', 'Script',
  '.AppleSystemUIFont', '.SF NS', 'Apple Braille', 'Apple Color Emoji',
  'Apple SD Gothic Neo', 'Apple Symbols',
  'LastResort', 'Keyboard', 'Zapf Dingbats',
  'cursor', 'fixed',
};

/// Prefixes that identify internal/hidden operating system fonts.
final _internalPrefixes = ['.', '#'];

/// Typical Unicode characters of non-Latin scripts in the font *name*.
/// Note: it's not necessary to filter CJK fonts by name on fc-list —
/// fc-list already returns families like "Noto Sans CJK SC"; we exclude them
/// with the ASCII name pattern, not searching for Unicode characters in the name.
final _nonLatinNamePatterns = <RegExp>[
  RegExp(r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af\u0600-\u06ff'
      r'\u0590-\u05ff\u0900-\u097f\u0e00-\u0e7f]'),
  
  RegExp(
    r'\b(CJK|Noto\s+(?:Sans|Serif)\s+(?:SC|TC|HK|JP|KR|Mono)|'
    r'SimSun|SimHei|SimKai|FangSong|KaiTi|'
    r'Malgun|Gulim|Batang|Dotum|Gungsuh|'
    r'Meiryo|Yu\s+Gothic|Yu\s+Mincho|'
    r'Droid\s+Sans\s+Fallback|Nirmala|Leelawadee|'
    r'Estrangelo|Sylfaen|Segoe\s+UI\s+Symbol|'
    r'MS\s+Gothic|MS\s+Mincho|MS\s+PGothic|MS\s+PMincho|'
    r'Osaka|Hiragino|Heiti|PingFang)\b',
    caseSensitive: false, // <--- This replaces (?i)
  ),
];

/// Returns the list of Google Fonts bundled locally for web.
/// These fonts are registered in pubspec.yaml and loaded from
/// assets/fonts/ without network requests.
List<String> _getWebFonts() {
  return _googleFontsForWeb;
}

/// Fonts bundled with the fluent_editor package, always available.
const _bundledFonts = <String>[
  'DejaVu Sans', 'DejaVu Serif', 'DejaVu Sans Mono',
  'Crimson Text', 'Fira Sans', 'Lato', 'Poppins', 'Titillium Web',
  'Barlow', 'SpaceMono',
];

/// Retrieves available font families on the current system.
/// Returns an ordered, deduplicated, and filtered list.
Future<List<String>> getSystemFonts() async {
  List<String> raw;

  if (kIsWeb) {
    return _getWebFonts();
  } else if (Platform.isAndroid || Platform.isIOS) {
    raw = await _getMobileFonts();
  } else if (Platform.isLinux) {
    raw = await _getLinuxFonts();
  } else if (Platform.isMacOS) {
    raw = await _getMacOSFonts();
  } else if (Platform.isWindows) {
    raw = await _getWindowsFonts();
  } else {
    return _fallbackFonts;
  }

  if (raw.isEmpty) return [..._bundledFonts, ..._fallbackFonts];

  return _postProcess([..._bundledFonts, ...raw]);
}

/// Mobile: uses Platform Channel; fallback to bundled + common fonts.
Future<List<String>> _getMobileFonts() async {
  try {
    final List<dynamic> fonts = await _channel.invokeMethod('getSystemFonts');
    return fonts.cast<String>();
  } catch (_) {
    return const [
      'DejaVu Sans', 'DejaVu Serif', 'DejaVu Sans Mono',
      'Crimson Text', 'Fira Sans', 'Lato', 'Poppins', 'Titillium Web',
      'DejaVu Sans', 'Roboto', 'Courier New', 'Georgia',
      'Times New Roman', 'Verdana', 'Tahoma',
    ];
  }
}

/// Linux: fc-list already returns families — just split by comma.
/// Example output: "DejaVu Sans,DejaVu Sans Book:style=Book,..."
Future<List<String>> _getLinuxFonts() async {
  try {
    final locale = Platform.localeName.split('_').first;
    final result = await Process.run('fc-list', [':lang=$locale', 'family']);
    if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
      return _parseFcList(result.stdout as String);
    }
  } catch (_) {}
  return [];
}

/// macOS: try fc-list first (Homebrew), then CTFontManager via system_profiler.
Future<List<String>> _getMacOSFonts() async {
  try {
    final locale = Platform.localeName.split('_').first;
    final result = await Process.run('fc-list', [':lang=$locale', 'family']);
    if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
      return _parseFcList(result.stdout as String);
    }
  } catch (_) {}

  try {
    final result = await Process.run(
      'system_profiler', ['SPFontsDataType', '-json'],
    );
    if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
      return _parseSystemProfiler(result.stdout as String);
    }
  } catch (_) {}

  return [];
}

/// Windows: [System.Drawing.FontFamily]::Families already returns base
/// font families (not individual styles like Bold/Italic) and uses the
/// system locale for localized names.
/// We filter upfront in PowerShell for families that expose a Regular
/// style — these are the usable base families for documents.
Future<List<String>> _getWindowsFonts() async {
  try {
    final result = await Process.run('powershell', [
      '-NoProfile', '-Command',
      r'Add-Type -AssemblyName System.Drawing; '
      r'[System.Drawing.FontFamily]::Families | '
      r'Where-Object { '
      r'  $_.IsStyleAvailable([System.Drawing.FontStyle]::Regular) '
      r'} | '
      r'Select-Object -ExpandProperty Name | '
      r'Sort-Object',
    ]);
    if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
      return (result.stdout as String)
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
  } catch (_) {}

  return [];
}

/// Parses the output of `fc-list : family`.
/// Each line can contain multiple names separated by comma (e.g. localized names).
/// We take the first name per line (usually the ASCII/Latin one).
List<String> _parseFcList(String output) {
  final families = <String>[];
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final name = trimmed.split(',').first.trim();
    if (name.isNotEmpty) families.add(name);
  }
  return families;
}

/// Parses the JSON output of `system_profiler SPFontsDataType`.
/// Searches for "family" (preferred) or "name" fields in the raw JSON.
List<String> _parseSystemProfiler(String output) {
  final families = <String>{};
  final familyRegex = RegExp(r'"family"\s*:\s*"([^"]+)"');
  for (final m in familyRegex.allMatches(output)) {
    families.add(m.group(1)!);
  }
  if (families.isEmpty) {
    final nameRegex = RegExp(r'"name"\s*:\s*"([^"]+)"');
    for (final m in nameRegex.allMatches(output)) {
      families.add(m.group(1)!);
    }
  }
  return families.toList();
}

/// Applies all filters and returns an ordered and deduplicated list.
List<String> _postProcess(List<String> raw) {
  final seen = <String>{};   // key: lowercase for deduplication
  final result = <String>[];

  final allFonts = raw.map((f) => f.trim()).where((f) => f.isNotEmpty).toList();

  for (final font in raw) {
    final trimmed = font.trim();
    if (trimmed.isEmpty) continue;

    if (_internalPrefixes.any((p) => trimmed.startsWith(p))) continue;

    if (_blocklist.contains(trimmed)) continue;

    if (_isNonLatinFont(trimmed)) continue;

    if (_isSymbolFont(trimmed)) continue;

    if (_isStyleVariant(trimmed, allFonts)) continue;

    final key = trimmed.toLowerCase();
    if (!seen.add(key)) continue;

    result.add(trimmed);
  }

  result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}

/// Returns true if the font is almost certainly non-Latin.
bool _isNonLatinFont(String name) {
  for (final pattern in _nonLatinNamePatterns) {
    if (pattern.hasMatch(name)) return true;
  }
  return false;
}

/// Returns true if the name suggests a symbol or icon font.
bool _isSymbolFont(String name) {
  final lower = name.toLowerCase();
  return lower.contains('dingbat') ||
      lower.contains('emoji') ||
      lower.contains('symbol') ||
      lower.contains('wingding') ||
      lower.contains('webding') ||
      lower.contains('ornament') ||
      lower.contains('marlett');
}

/// Returns true if [font] is a style variant of another base font.
/// E.g. "Cascadia Mono Light" is a variant of "Cascadia Mono".
bool _isStyleVariant(String font, List<String> allFonts) {
  for (final other in allFonts) {
    if (other != font && font.startsWith('$other ')) {
      return true;
    }
  }
  return false;
}

class FluentFontSelectorWidget extends StatefulWidget {
  final FluentDocument document;

  const FluentFontSelectorWidget({super.key, required this.document});

  @override
  State<FluentFontSelectorWidget> createState() =>
      _FluentFontSelectorWidgetState();
}

class _FluentFontSelectorWidgetState extends State<FluentFontSelectorWidget> {
  String _currentFont = 'DejaVu Sans';
  List<String> _availableFonts = _fallbackFonts;

  _FluentFontSelectorWidgetState() {
    if (kIsWeb) {
      _currentFont = 'Lato';
      _availableFonts = _googleFontsForWeb;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChanged);
    _loadSystemFonts();
    _updateFont();
  }

  Future<void> _loadSystemFonts() async {
    final fonts = await getSystemFonts();
    if (mounted) {
      setState(() => _availableFonts = fonts);
    }
  }

  @override
  void didUpdateWidget(covariant FluentFontSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
      _updateFont();
    }
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged() => _updateFont();

  void _updateFont() {
    final font = _resolveCurrentFont();
    if (font != _currentFont) {
      setState(() => _currentFont = font.isEmpty ? 'DejaVu Sans' : font);
    }
  }

  String _resolveCurrentFont() {
    final document = widget.document;
    final cursor = document.cursor;

    if (cursor.anchorId != cursor.focusId ||
        cursor.anchorOffset != cursor.focusOffset) {
      final selection = resolveSelectionFromCursor(document);
      if (selection != null) {
        final fonts = <String?>{};
        for (final node in selection.nodes) {
          for (final leaf in FragmentOperations.collectLeavesInRange(node)) {
            fonts.add(leaf.fontFamily);
          }
        }
        if (fonts.length == 1) return fonts.single ?? 'DejaVu Sans';
        return 'DejaVu Sans';
      }
    }

    final frag = document.nodeById(cursor.anchorId);
    if (frag is Fragment) return frag.fontFamily;
    return document.pendingFontFamily;
  }

  /// Returns the safe value for the DropdownButton.
  /// Priority: current font → DejaVu Sans → first available font → null.
  String? _getDropdownValue() {
    if (_availableFonts.contains(_currentFont)) return _currentFont;
    if (_availableFonts.contains('DejaVu Sans')) return 'DejaVu Sans';
    return _availableFonts.isNotEmpty ? _availableFonts.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDisabled = widget.document.registry.isFormattingDisabled(widget.document);

    return MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(isDisabled ? 40 : 100),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: colorScheme.outline.withAlpha(isDisabled ? 40 : 100),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _getDropdownValue(),
              isDense: true,
              icon: Icon(Icons.arrow_drop_down, size: 18, color: isDisabled ? colorScheme.onSurface.withAlpha(90) : null),
              style: TextStyle(
                fontSize: 13,
                color: isDisabled ? colorScheme.onSurface.withAlpha(90) : colorScheme.onSurface,
              ),
              selectedItemBuilder: (context) {
                return _availableFonts.map((font) {
                  return Center(
                    child: Text(
                      _currentFont,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: _currentFont,
                        fontSize: 13,
                        color: isDisabled ? colorScheme.onSurface.withAlpha(90) : null,
                      ),
                    ),
                  );
                }).toList();
              },
              items: _availableFonts.map((String font) {
                return DropdownMenuItem<String>(
                  value: font,
                  child: Text(
                    font,
                    style: TextStyle(fontFamily: font, fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: widget.document.registry.isFormattingDisabled(widget.document)
                  ? null
                  : (String? newValue) {
                      if (newValue != null) {
                        widget.document.eventHandler.handleFontFamily(newValue);
                        if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
                          widget.document.requestEditorFocus();
                        }
                      }
                    },
            ),
          ),
        ),
      ),
    );
  }
}