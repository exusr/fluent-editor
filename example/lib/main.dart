import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/fluent_document.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Forward all Flutter framework errors to the console (visible on web debug)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };

  // Catch async errors that escape the framework (zone-level)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformError: $error\n$stack');
    return true;
  };

  // Load bundled Google Fonts on web platform
  if (kIsWeb) {
    await _loadBundledFonts();
  }

  runApp(const MyApp());
}

/// Loads bundled Google Fonts from local assets.
/// On Flutter Web, this ensures fonts are available before the app starts.
Future<void> _loadBundledFonts() async {
  const bundledFonts = [
    'Crimson Text', 'Fira Sans', 'Lato', 'Poppins', 'Titillium Web',
  ];
  
  for (final fontName in bundledFonts) {
    final fontLoader = FontLoader(fontName);
    final fileName = fontName.replaceAll(' ', '');
    var loadedAny = false;
    
    for (final suffix in ['-Regular.ttf', '-Italic.ttf', '-Bold.ttf', '-BoldItalic.ttf']) {
      try {
        final fontData = await rootBundle.load(
          'packages/fluent_editor/assets/google_fonts/$fileName$suffix',
        );
        fontLoader.addFont(Future.value(fontData));
        loadedAny = true;
      } catch (_) {
        // Variant not available, skip
      }
    }
    
    if (loadedAny) {
      try {
        await fontLoader.load();
      } catch (_) {
        // Font loading failed, will fall back to default
      }
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluent Editor',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      home: MyHomePage(title: 'Fluent Editor Demo', onToggleTheme: _toggleTheme),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, required this.onToggleTheme});
  final String title;
  final VoidCallback onToggleTheme;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FluentDocument? _document;

  @override
  void initState() {
    super.initState();
    _loadDocument();
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
        ),
      ),
    );
  }
}