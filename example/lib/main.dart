import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/widgets/fluent_document_widget.dart';
import 'package:fluent_editor_comments/fluent_editor_comments.dart';
import 'package:fluent_editor_character_map/fluent_editor_character_map.dart';
import 'package:fluent_editor_review/fluent_editor_review.dart';

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

  await loadBundledFonts();

  runApp(const MyApp());
}

/// Loads all bundled fonts from the fluent_editor package assets.
/// Includes DejaVu family, Google Fonts, and NotoColorEmoji.
Future<void> loadBundledFonts() async {
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
    final loader = FontLoader(familyName);
    var loadedAny = false;
    for (final file in files) {
      try {
        final data =
            await rootBundle.load('packages/fluent_editor/assets/fonts/$file');
        loader.addFont(Future.value(data));
        loadedAny = true;
      } catch (_) {}
    }
    if (loadedAny) {
      try {
        await loader.load();
      } catch (_) {}
    }
  }

  // Google Fonts (in assets/fonts/)
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
    final loader = FontLoader(fontName);
    final fileName = fontName.replaceAll(' ', '');
    var loadedAny = false;

    for (final suffix in [
      '-Regular.ttf',
      '-Italic.ttf',
      '-Bold.ttf',
      '-BoldItalic.ttf'
    ]) {
      try {
        final data = await rootBundle.load(
          'packages/fluent_editor/assets/fonts/$fileName$suffix',
        );
        loader.addFont(Future.value(data));
        loadedAny = true;
      } catch (_) {}
    }

    if (loadedAny) {
      try {
        await loader.load();
      } catch (_) {}
    }
  }

  // NotoColorEmoji (in assets/fonts/)
  try {
    final emojiLoader = FontLoader('NotoColorEmoji')
      ..addFont(rootBundle
          .load('packages/fluent_editor/assets/fonts/NotoColorEmoji.ttf'));
    await emojiLoader.load();
  } catch (_) {}
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
        colorSchemeSeed: Colors.green,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      home:
          MyHomePage(title: 'Fluent Editor Demo', onToggleTheme: _toggleTheme),
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
  final FluentCommentProvider _commentProvider = FluentCommentProvider();
  final FluentSuggestionController _suggestionController =
      FluentSuggestionController();

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _commentProvider.dispose();
    _suggestionController.dispose();
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

    // Attach the comment provider so the editor shows comment highlights
    // and enables add-comment via right-click context menu.
    doc.commentProvider = _commentProvider;
    // If the loaded JSON contains comments, import them.
    if (doc.commentProvider != null) {
      try {
        final jsonMap =
            jsonDecode(await rootBundle.loadString('assets/example.json'))
                as Map<String, dynamic>;
        final comments = jsonMap['comments'];
        if (comments is List) {
          _commentProvider.importComments(
            comments.map((e) => e as Map<String, dynamic>).toList(),
          );
        }
      } catch (_) {}
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
            FluentCharacterMapPlugin(),
            FluentCommentPlugin(provider: _commentProvider),
            FluentSuggestionPlugin(controller: _suggestionController),
          ],
          toolbarMode: _toolbarMode,
          // Sidebar is automatically resolved from plugins:
          // comments and suggestions are merged into a single unified sidebar
          // with scroll synchronization to document positions.
          bubbleActions: [
            CommentBubbleAction(
              document: _document!,
              provider: _commentProvider,
            ),
          ],
        ),
      ),
    );
  }
}
