import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: unused_import
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Provides TTF fonts for PDF generation.
///
/// Strategy:
/// 1. Loads DejaVu fonts bundled in the package assets
/// 2. Last fallback: built-in PDF fonts (Helvetica, etc.)
///
/// DejaVu Sans has extended Unicode coverage (bullet, check marks,
/// em-dash, ballot boxes, etc.) - Bitstream Vera license + public domain.
///
/// Supports 3 families: sans-serif, serif, monospace.
/// Each family has 4 variants: regular, bold, italic, bold-italic.
class PdfFontProvider {
  /// Cache of loaded fonts, to avoid reloading them.
  final Map<String, pw.Font> _cache = {};

  /// Fonts loaded dynamically from the OS file system.
  /// Key: lowercase family name. Value: set of 4 variants.
  final Map<String, ({pw.Font regular, pw.Font? bold, pw.Font? italic, pw.Font? boldItalic})> _dynamicFonts = {};

  bool _initialized = false;

  // Sans-serif (default)
  pw.Font? sansRegular;
  pw.Font? sansBold;
  pw.Font? sansItalic;
  pw.Font? sansBoldItalic;

  // Serif (quotations, Georgia, Times)
  pw.Font? serifRegular;
  pw.Font? serifBold;
  pw.Font? serifItalic;
  pw.Font? serifBoldItalic;

  // Monospace (code, Courier)
  pw.Font? monoRegular;
  pw.Font? monoBold;

  /// Initializes the provider by loading all necessary fonts.
  /// [requiredFamilies] are the font families actually used in the document;
  /// the provider tries to load them from the OS so the PDF embeds the real fonts.
  Future<void> init([Set<String> requiredFamilies = const {}]) async {
    if (_initialized) return;

    // Load bundled fonts (fallback)
    await _loadBundledFonts();

    // Load any system fonts that match families used in the document
    for (final family in requiredFamilies) {
      if (family.trim().isEmpty) continue;
      await _tryLoadSystemFont(family);
    }

    _initialized = true;
  }

  /// Loads DejaVu fonts from bundled assets.
  Future<void> _loadBundledFonts() async {
    sansRegular ??= await _loadAssetFont('assets/fonts/DejaVuSans.ttf');
    sansBold ??= await _loadAssetFont('assets/fonts/DejaVuSans-Bold.ttf');
    sansItalic ??= await _loadAssetFont('assets/fonts/DejaVuSans-Oblique.ttf');
    sansBoldItalic ??= await _loadAssetFont('assets/fonts/DejaVuSans-BoldOblique.ttf');

    serifRegular ??= await _loadAssetFont('assets/fonts/DejaVuSerif.ttf');
    serifBold ??= await _loadAssetFont('assets/fonts/DejaVuSerif-Bold.ttf');
    serifItalic ??= await _loadAssetFont('assets/fonts/DejaVuSerif-Italic.ttf');
    serifBoldItalic ??= await _loadAssetFont('assets/fonts/DejaVuSerif-BoldItalic.ttf');

    monoRegular ??= await _loadAssetFont('assets/fonts/DejaVuSansMono.ttf');
    monoBold ??= await _loadAssetFont('assets/fonts/DejaVuSansMono-Bold.ttf');
  }

  /// Loads a font from a bundled asset.
  Future<pw.Font?> _loadAssetFont(String assetPath) async {
    final key = 'packages/fluent_editor/$assetPath';
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final data = await rootBundle.load(key);
      final font = pw.Font.ttf(data);
      _cache[key] = font;
      return font;
    } catch (_) {
      return null;
    }
  }

  // ─── Dynamic system-font loading ────────────────────────────────────────

  Future<void> _tryLoadSystemFont(String fontFamily) async {
    final lower = fontFamily.toLowerCase();
    if (_dynamicFonts.containsKey(lower)) return;

    final regular = await _findFontVariant(fontFamily, '');
    if (regular == null) return;

    try {
      final regBytes = await regular.readAsBytes();
      final regFont = pw.Font.ttf(ByteData.sublistView(regBytes));

      pw.Font? boldFont;
      pw.Font? italicFont;
      pw.Font? boldItalicFont;

      final bold = await _findFontVariant(fontFamily, 'b');
      if (bold != null) {
        final bytes = await bold.readAsBytes();
        boldFont = pw.Font.ttf(ByteData.sublistView(bytes));
      }

      final italic = await _findFontVariant(fontFamily, 'i');
      if (italic != null) {
        final bytes = await italic.readAsBytes();
        italicFont = pw.Font.ttf(ByteData.sublistView(bytes));
      }

      final boldItalic = await _findFontVariant(fontFamily, 'z');
      if (boldItalic != null) {
        final bytes = await boldItalic.readAsBytes();
        boldItalicFont = pw.Font.ttf(ByteData.sublistView(bytes));
      }

      _dynamicFonts[lower] = (
        regular: regFont,
        bold: boldFont,
        italic: italicFont,
        boldItalic: boldItalicFont,
      );
    } catch (_) {}
  }

  /// Attempts to locate a specific variant of [fontFamily] on the current OS.
  /// [suffix] is the variant suffix: '' for regular, 'b' for bold, 'i' for italic, 'z' for bold-italic.
  Future<File?> _findFontVariant(String fontFamily, String suffix) async {
    if (kIsWeb) return null; // Web doesn't have file system access

    final lower = fontFamily.toLowerCase().replaceAll(' ', '');
    final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final fontsDir = '$windir\\Fonts';

    // Build candidate names
    final candidates = <String>[];

    if (Platform.isWindows) {
      // Windows naming: calibri.ttf, calibrib.ttf, calibrii.ttf, calibriz.ttf
      final base = suffix.isEmpty ? lower : '$lower$suffix';
      candidates.addAll([
        '$fontsDir\\$base.ttf',
        '$fontsDir\\$base.TTF',
        '$fontsDir\\$base.otf',
        '$fontsDir\\$base.OTF',
      ]);
      // Also try spaced names: "Calibri Bold.ttf"
      if (suffix.isNotEmpty) {
        final spaced = suffix == 'b'
            ? 'Bold'
            : suffix == 'i'
                ? 'Italic'
                : suffix == 'z'
                    ? 'Bold Italic'
                    : '';
        final spacedBase = '$fontFamily $spaced'.trim();
        final spacedLower = spacedBase.toLowerCase().replaceAll(' ', '');
        candidates.addAll([
          '$fontsDir\\$spacedLower.ttf',
          '$fontsDir\\$spacedLower.TTF',
          '$fontsDir\\$spacedLower.otf',
          '$fontsDir\\$spacedLower.OTF',
        ]);
      }
    } else if (Platform.isMacOS) {
      final base = suffix.isEmpty ? fontFamily : '$fontFamily-$suffix';
      candidates.addAll([
        '/System/Library/Fonts/$base.ttf',
        '/Library/Fonts/$base.ttf',
        '/System/Library/Fonts/$base.ttc',
        '/Library/Fonts/$base.ttc',
      ]);
    } else if (Platform.isLinux) {
      final base = suffix.isEmpty ? fontFamily : '$fontFamily-$suffix';
      candidates.addAll([
        '/usr/share/fonts/truetype/$lower/$base.ttf',
        '/usr/share/fonts/$base.ttf',
        '/usr/share/fonts/opentype/$lower/$base.otf',
      ]);
    }

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }

    // Deep search on Windows (fontsDir listing) for suffix matching
    if (Platform.isWindows && suffix.isNotEmpty) {
      final dir = Directory(fontsDir);
      if (await dir.exists()) {
        final suffixPatterns = suffix == 'b'
            ? ['b', 'bd', 'bold']
            : suffix == 'i'
                ? ['i', 'it', 'italic']
                : suffix == 'z'
                    ? ['z', 'bi', 'bolditalic', 'boldit']
                    : <String>[];
        await for (final entity in dir.list()) {
          if (entity is File) {
            final name = entity.path.split(Platform.pathSeparator).last.toLowerCase();
            final ext = name.split('.').last;
            if (ext != 'ttf' && ext != 'ttc' && ext != 'otf') continue;
            final stem = name.substring(0, name.length - ext.length - 1);
            if (stem.startsWith(lower)) {
              final rest = stem.substring(lower.length);
              if (suffixPatterns.contains(rest)) return entity;
            }
          }
        }
      }
    }

    return null;
  }

  /// Returns the set of 4 fonts (regular, bold, italic, bold-italic)
  /// for a given font family.
  ({pw.Font regular, pw.Font bold, pw.Font italic, pw.Font boldItalic})
      getFontSet(String fontFamily, String? styleName) {
    final lower = fontFamily.toLowerCase();
    final isCode = styleName == 'code';

    // Explicit DejaVu Sans mapping (bundled fallback)
    if (lower.contains('dejavu')) {
      return (
        regular: sansRegular ?? pw.Font.helvetica(),
        bold: sansBold ?? pw.Font.helveticaBold(),
        italic: sansItalic ?? pw.Font.helveticaOblique(),
        boldItalic: sansBoldItalic ?? pw.Font.helveticaBoldOblique(),
      );
    }

    if (isCode || lower.contains('courier') || lower.contains('mono') || lower.contains('consolas')) {
      return (
        regular: monoRegular ?? pw.Font.courier(),
        bold: monoBold ?? pw.Font.courierBold(),
        italic: monoRegular ?? pw.Font.courierOblique(), // Mono has no italic
        boldItalic: monoBold ?? pw.Font.courierBoldOblique(),
      );
    }

    if (lower.contains('times') || lower.contains('georgia') || lower.contains('serif') ||
        lower.contains('garamond') || lower.contains('palatino')) {
      return (
        regular: serifRegular ?? pw.Font.times(),
        bold: serifBold ?? pw.Font.timesBold(),
        italic: serifItalic ?? pw.Font.timesItalic(),
        boldItalic: serifBoldItalic ?? pw.Font.timesBoldItalic(),
      );
    }

    // Default: sans-serif (DejaVu Sans, Helvetica, Roboto, Noto Sans, etc.)
    return (
      regular: sansRegular ?? pw.Font.helvetica(),
      bold: sansBold ?? pw.Font.helveticaBold(),
      italic: sansItalic ?? pw.Font.helveticaOblique(),
      boldItalic: sansBoldItalic ?? pw.Font.helveticaBoldOblique(),
    );
  }

  /// Selects the correct font based on bold/italic.
  /// If the family was loaded dynamically from the OS, uses the specific variant.
  pw.Font selectFont(String fontFamily, String? styleName, {bool bold = false, bool italic = false}) {
    final lower = fontFamily.toLowerCase();
    final dynamic = _dynamicFonts[lower];
    if (dynamic != null) {
      if (bold && italic && dynamic.boldItalic != null) return dynamic.boldItalic!;
      if (bold && dynamic.bold != null) return dynamic.bold!;
      if (italic && dynamic.italic != null) return dynamic.italic!;
      return dynamic.regular;
    }

    final set = getFontSet(fontFamily, styleName);
    if (bold && italic) return set.boldItalic;
    if (bold) return set.bold;
    if (italic) return set.italic;
    return set.regular;
  }
}
