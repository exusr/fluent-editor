import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/widgets/fluent_document_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Forward all Flutter framework errors to the console (visible on web debug)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };

  // Catch async errors that escape the framework (zone-level)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformError: $error\n$stack');
    return true;
  };

  // We do not await this, so the app starts immediately (preventing the white screen).
  // Fonts will "pop in" automatically as they finish downloading in the background.
  loadBundledFonts();

  runApp(const MyApp());
}

/// Loads all bundled fonts from the fluent_editor package assets.
/// Includes DejaVu family, Google Fonts, and NotoColorEmoji.
Future<void> loadBundledFonts() async {
  final tasks = <Future<void>>[];

  // DejaVu family (in assets/fonts/)
  const dejavuFonts = [
    (
      'DejaVu Sans',
      [
        'DejaVuSans.ttf',
        'DejaVuSans-Oblique.ttf',
        'DejaVuSans-Bold.ttf',
        'DejaVuSans-BoldOblique.ttf',
      ]
    ),
    (
      'DejaVu Sans Mono',
      [
        'DejaVuSansMono.ttf',
        'DejaVuSansMono-Bold.ttf',
      ]
    ),
    (
      'DejaVu Serif',
      [
        'DejaVuSerif.ttf',
        'DejaVuSerif-Italic.ttf',
        'DejaVuSerif-Bold.ttf',
        'DejaVuSerif-BoldItalic.ttf',
      ]
    ),
  ];

  for (final (familyName, files) in dejavuFonts) {
    tasks.add(() async {
      final loader = FontLoader(familyName);
      var loadedAny = false;
      final results = await Future.wait(files.map((file) =>
          rootBundle.load('packages/fluent_editor/assets/fonts/$file').catchError((_) => ByteData(0))));
      
      for (final data in results) {
        if (data.lengthInBytes > 0) {
          loader.addFont(Future.value(data));
          loadedAny = true;
        }
      }
      if (loadedAny) {
        try { await loader.load(); } catch (_) {}
      }
    }());
  }

  // Google Fonts (in assets/fonts/)
  // Commented out to prevent massive 10s parsing freeze in CanvasKit on Web startup.
  /*
  const googleFonts = [
    'Crimson Text',
    'Fira Sans',
    'Lato',
    'Poppins',
    'Titillium Web',
    'Barlow',
    'SpaceMono',
  ];

  for (final fontName in googleFonts) {
    tasks.add(() async {
      final loader = FontLoader(fontName);
      final fileName = fontName.replaceAll(' ', '');
      var loadedAny = false;

      final suffixes = ['-Regular.ttf', '-Italic.ttf', '-Bold.ttf', '-BoldItalic.ttf'];
      final results = await Future.wait(suffixes.map((suffix) =>
          rootBundle.load('packages/fluent_editor/assets/fonts/$fileName$suffix').catchError((_) => ByteData(0))));
      
      for (final data in results) {
        if (data.lengthInBytes > 0) {
          loader.addFont(Future.value(data));
          loadedAny = true;
        }
      }
      if (loadedAny) {
        try { await loader.load(); } catch (_) {}
      }
    }());
  }
  */

  // NotoColorEmoji is extremely heavy (11MB) and can cause network/server 
  // bottlenecks during startup on local development. We disable it by default.
  /*
  tasks.add(() async {
    try {
      final loader = FontLoader('NotoColorEmoji');
      final data = await rootBundle.load('packages/fluent_editor/assets/fonts/NotoColorEmoji.ttf');
      loader.addFont(Future.value(data));
      await loader.load();
    } catch (_) {}
  }());
  */

  await Future.wait(tasks);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _themeMode = platformBrightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        () {
      setState(() {
        final platformBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        _themeMode = platformBrightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light;
      });
    };
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluent Editor',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1d2d2c),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1d2d2c),
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      home: MyHomePage(
        title: 'Fluent Editor Demo',
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage(
      {super.key, required this.title, required this.onToggleTheme});
  final String title;
  final VoidCallback onToggleTheme;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FluentDocument? _document;
  FluentToolbarMode _toolbarMode = FluentToolbarMode.fixed;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadDocument() async {
    FluentDocument doc;
    try {
      final jsonString = await rootBundle.loadString('assets/example.json');
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      doc = FluentDocument.fromJson(jsonMap);
    } catch (e) {
      // Fallback: create an empty document if loading fails
      doc = FluentDocument();
    }

    setState(() {
      _document = doc;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_document == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(
              _toolbarMode == FluentToolbarMode.bubble
                  ? Icons.view_headline
                  : Icons.bubble_chart,
            ),
            tooltip: _toolbarMode == FluentToolbarMode.bubble
                ? 'Switch to fixed toolbar'
                : 'Switch to bubble toolbar',
            onPressed: () {
              setState(() {
                _toolbarMode = _toolbarMode == FluentToolbarMode.fixed
                    ? FluentToolbarMode.bubble
                    : FluentToolbarMode.fixed;
              });
            },
          ),
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: SafeArea(
        child: FluentEditor(
          document: _document,
          plugins: [
          ],
          toolbarMode: _toolbarMode,
          // Sidebar is automatically resolved from plugins:
          // comments and suggestions are merged into a single unified sidebar
          // with scroll synchronization to document positions.
          bubbleActions: [
          ],
        ),
      ),
    );
  }
}
