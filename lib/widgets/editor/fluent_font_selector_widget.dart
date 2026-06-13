import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';
import 'package:flutter/material.dart';

const _channel = MethodChannel('com.fluenteditor/fonts');

/// Fallback for unsupported platforms or in case of error.
const _fallbackFonts = <String>[
  'Arial',
  'Calibri',
  'Cambria',
  'Comic Sans MS',
  'Courier New',
  'Georgia',
  'Helvetica',
  'Impact',
  'Inter',
  'Roboto',
  'Tahoma',
  'Times New Roman',
  'Trebuchet MS',
  'Verdana',
];

// ─── Font names to exclude (symbols, icons, internal system fonts) ──────

/// Fonts to always exclude, regardless of platform.
const _blocklist = <String>{
  // Symbols and dingbats
  'Wingdings', 'Wingdings 2', 'Wingdings 3',
  'Webdings', 'Symbol', 'Marlett',
  'MT Extra', 'Bookshelf Symbol 7',
  // Windows system fonts (internal UI, not for documents)
  'MS UI Gothic', 'Microsoft Sans Serif',
  'Small Fonts', 'Terminal', 'Fixedsys', 'System', 'Modern', 'Roman', 'Script',
  // macOS system fonts
  '.AppleSystemUIFont', '.SF NS', 'Apple Braille', 'Apple Color Emoji',
  'Apple SD Gothic Neo', 'Apple Symbols',
  'LastResort', 'Keyboard', 'Zapf Dingbats',
  // Common Linux system fonts
  'cursor', 'fixed',
};

/// Prefixes that identify internal/hidden operating system fonts.
final _internalPrefixes = ['.', '#'];

// ─── Regex to identify non-Latin scripts ─────────────────────────────────

/// Typical Unicode characters of non-Latin scripts in the font *name*.
/// Note: it's not necessary to filter CJK fonts by name on fc-list —
/// fc-list already returns families like "Noto Sans CJK SC"; we exclude them
/// with the ASCII name pattern, not searching for Unicode characters in the name.
final _nonLatinNamePatterns = <RegExp>[
  // Names with CJK, Devanagari, Arabic, Hangul etc. characters in the name itself
  RegExp(r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af\u0600-\u06ff'
      r'\u0590-\u05ff\u0900-\u097f\u0e00-\u0e7f]'),
  
  // ASCII names that explicitly indicate a non-Latin script (CORRECTED HERE)
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

// ─── Font retrieval by platform ───────────────────────────────────────────

/// Retrieves available font families on the current system.
/// Returns an ordered, deduplicated, and filtered list.
Future<List<String>> getSystemFonts() async {
  List<String> raw;

  if (kIsWeb) {
    return _fallbackFonts;
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

  if (raw.isEmpty) return _fallbackFonts;

  return _postProcess(raw);
}

/// Mobile: uses Platform Channel; fallback to minimal list.
Future<List<String>> _getMobileFonts() async {
  try {
    final List<dynamic> fonts = await _channel.invokeMethod('getSystemFonts');
    return fonts.cast<String>();
  } catch (_) {
    return const [
      'Arial', 'Roboto', 'Courier New', 'Georgia',
      'Times New Roman', 'Verdana', 'Tahoma',
    ];
  }
}

/// Linux: fc-list already returns families — just split by comma.
/// Example output: "DejaVu Sans,DejaVu Sans Book:style=Book,..."
Future<List<String>> _getLinuxFonts() async {
  try {
    // Get system locale (e.g., "it_IT" -> "it")
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
  // Attempt 1: fc-list (available if installed with Homebrew)
  try {
    final locale = Platform.localeName.split('_').first;
    final result = await Process.run('fc-list', [':lang=$locale', 'family']);
    if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
      return _parseFcList(result.stdout as String);
    }
  } catch (_) {}

  // Attempt 2: system_profiler (natively available on macOS)
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

// ─── Parsers for different output formats ──────────────────────────────────

/// Parses the output of `fc-list : family`.
/// Each line can contain multiple names separated by comma (e.g. localized names).
/// We take the first name per line (usually the ASCII/Latin one).
List<String> _parseFcList(String output) {
  final families = <String>[];
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // fc-list separates alternative names with comma
    final name = trimmed.split(',').first.trim();
    if (name.isNotEmpty) families.add(name);
  }
  return families;
}

/// Parses the JSON output of `system_profiler SPFontsDataType`.
/// Searches for "family" (preferred) or "name" fields in the raw JSON.
List<String> _parseSystemProfiler(String output) {
  final families = <String>{};
  // First look for the "family" field (direct family name)
  final familyRegex = RegExp(r'"family"\s*:\s*"([^"]+)"');
  for (final m in familyRegex.allMatches(output)) {
    families.add(m.group(1)!);
  }
  // If nothing found, fallback to the "name" field
  if (families.isEmpty) {
    final nameRegex = RegExp(r'"name"\s*:\s*"([^"]+)"');
    for (final m in nameRegex.allMatches(output)) {
      families.add(m.group(1)!);
    }
  }
  return families.toList();
}

// ─── Common post-processing ───────────────────────────────────────────────────

/// Applies all filters and returns an ordered and deduplicated list.
List<String> _postProcess(List<String> raw) {
  final seen = <String>{};   // key: lowercase for deduplication
  final result = <String>[];

  // Pre-trim to use for variant detection
  final allFonts = raw.map((f) => f.trim()).where((f) => f.isNotEmpty).toList();

  for (final font in raw) {
    final trimmed = font.trim();
    if (trimmed.isEmpty) continue;

    // 1. Filter hidden internal fonts (names starting with '.' or '#')
    if (_internalPrefixes.any((p) => trimmed.startsWith(p))) continue;

    // 2. Filter by exact blocklist
    if (_blocklist.contains(trimmed)) continue;

    // 3. Filter fonts with names containing non-Latin scripts or known patterns
    if (_isNonLatinFont(trimmed)) continue;

    // 4. Filter symbol fonts recognizable by name
    if (_isSymbolFont(trimmed)) continue;

    // 5. Filter style variants (e.g. "Cascadia Mono Light" when "Cascadia Mono" exists)
    if (_isStyleVariant(trimmed, allFonts)) continue;

    // 6. Case-insensitive deduplication
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

// ─── Widget ──────────────────────────────────────────────────────────────────

class FluentFontSelectorWidget extends StatefulWidget {
  final FluentDocument document;

  const FluentFontSelectorWidget({super.key, required this.document});

  @override
  State<FluentFontSelectorWidget> createState() =>
      _FluentFontSelectorWidgetState();
}

class _FluentFontSelectorWidgetState extends State<FluentFontSelectorWidget> {
  String _currentFont = 'Arial';
  List<String> _availableFonts = _fallbackFonts;

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
      setState(() => _currentFont = font.isEmpty ? 'Arial' : font);
    }
  }

  String _resolveCurrentFont() {
    final document = widget.document;
    final cursor = document.cursor;
    final root = document.content;

    if (cursor.anchorId != cursor.focusId ||
        cursor.anchorOffset != cursor.focusOffset) {
      final selection = resolveSelection(
        root,
        cursor.anchorId,
        cursor.anchorOffset,
        cursor.focusId,
        cursor.focusOffset,
      );
      if (selection != null) {
        final fonts = <String?>{};
        for (final node in selection.nodes) {
          final leaves =
              FragmentOperations.collectLeafFragments(node.container as FNode);
          bool inRange = false;
          for (final leaf in leaves) {
            if (leaf.id == node.startFragment.id) inRange = true;
            if (inRange && leaf is! FluentImage) {
              fonts.add(leaf.fontFamily);
            }
            if (leaf.id == node.endFragment.id) inRange = false;
          }
        }
        if (fonts.length == 1) return fonts.single ?? 'Arial';
        return 'Arial';
      }
    }

    final frag = findById(root, cursor.anchorId);
    if (frag is Fragment) return frag.fontFamily;
    return document.pendingFontFamily;
  }

  /// Returns the safe value for the DropdownButton.
  /// Priority: current font → Arial → first available font → null.
  String? _getDropdownValue() {
    if (_availableFonts.contains(_currentFont)) return _currentFont;
    if (_availableFonts.contains('Arial')) return 'Arial';
    return _availableFonts.isNotEmpty ? _availableFonts.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(100),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: colorScheme.outline.withAlpha(100),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _getDropdownValue(),
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
              selectedItemBuilder: (context) {
                return _availableFonts.map((font) {
                  return Center(
                    child: Text(
                      _currentFont,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
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
              onChanged: (String? newValue) {
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