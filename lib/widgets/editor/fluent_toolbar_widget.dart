import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform, Process;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/services/export_service.dart';
import 'package:fluent_editor/services/import_service.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';
import 'package:fluent_editor/handlers/handle_clipboard.dart';
import 'package:fluent_editor/handlers/handle_select_all.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';
import 'package:fluent_editor/widgets/dialogs/author_info_dialog.dart';
import 'package:fluent_editor/widgets/editor/fluent_formatting_bar.dart';
import 'package:fluent_editor/controllers/document_language_controller.dart';
import 'package:fluent_editor/models/document_language.dart';
import 'package:fluent_editor/widgets/toolbar/language_selector_widget.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Wrappa qualsiasi widget in un MouseRegion con cursore pointer.
Widget _withClickCursor(Widget child) =>
    MouseRegion(cursor: SystemMouseCursors.click, child: child);

class FluentToolbar extends StatefulWidget {
  const FluentToolbar({super.key, required this.document, this.labels});
  final FluentDocument document;
  final FluentEditorLabels? labels;

  @override
  State<FluentToolbar> createState() => _FluentToolbarState();
}

class _FluentToolbarState extends State<FluentToolbar> {
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  bool _isStrikethrough = false;
  bool _isSmallCaps = false;
  bool _isSuperscript = false;
  bool _isSubscript = false;
  TextAlign _textAlign = TextAlign.left;
  StreamSubscription<void>? _commentSub;

  FluentEditorLabels get _labels => widget.labels ?? const FluentEditorLabels();

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChanged);
    widget.document.cursor.addListener(_onCursorChanged);
    DocumentLanguageController.instance.currentLanguage.addListener(
      _onLanguageControllerChanged,
    );
    _updateFormats();
    _listenToComments();
  }

  void _listenToComments() {
    _commentSub?.cancel();
    final provider = widget.document.commentProvider;
    if (provider != null) {
      _commentSub = provider.commentsChanged.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant FluentToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
      oldWidget.document.cursor.removeListener(_onCursorChanged);
      widget.document.cursor.addListener(_onCursorChanged);
      _updateFormats();
      _listenToComments();
    }
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocumentChanged);
    widget.document.cursor.removeListener(_onCursorChanged);
    DocumentLanguageController.instance.currentLanguage.removeListener(
      _onLanguageControllerChanged,
    );
    _commentSub?.cancel();
    super.dispose();
  }

  void _onLanguageControllerChanged() {
    widget.document.documentLanguage =
        DocumentLanguageController.instance.current.code;
  }

  void _onDocumentChanged() {
    if (widget.document.cursorOnlyChange) return;
    _updateFormats();
  }

  void _onCursorChanged() => _updateFormats();

  void _updateFormats() {
    final cursor = widget.document.cursor;
    final pendingStyles = widget.document.pendingStyles;

    if (cursor.isCollapsed) {
      final newBold = pendingStyles.contains('bold');
      final newItalic = pendingStyles.contains('italic');
      final newUnderline = pendingStyles.contains('underline');
      final newStrikethrough = pendingStyles.contains('strikethrough');
      final newSmallCaps = pendingStyles.contains('smallcaps');
      final newSuperscript = pendingStyles.contains('superscript');
      final newSubscript = pendingStyles.contains('subscript');
      final newTextAlign = _resolveTextAlign();

      if (newBold != _isBold ||
          newItalic != _isItalic ||
          newUnderline != _isUnderline ||
          newStrikethrough != _isStrikethrough ||
          newSmallCaps != _isSmallCaps ||
          newSuperscript != _isSuperscript ||
          newSubscript != _isSubscript ||
          newTextAlign != _textAlign) {
        setState(() {
          _isBold = newBold;
          _isItalic = newItalic;
          _isUnderline = newUnderline;
          _isStrikethrough = newStrikethrough;
          _isSmallCaps = newSmallCaps;
          _isSuperscript = newSuperscript;
          _isSubscript = newSubscript;
          _textAlign = newTextAlign;
        });
      }
      return;
    }

    final selection = resolveSelectionFromCursor(widget.document);
    final allLeaves = <Fragment>[];
    if (selection != null) {
      for (final node in selection.nodes) {
        allLeaves.addAll(FragmentOperations.collectLeavesInRange(node));
      }
    }

    bool hasStyle(String name) =>
        allLeaves.any((leaf) => leaf.styles?.contains(name) ?? false);

    final newBold = hasStyle('bold');
    final newItalic = hasStyle('italic');
    final newUnderline = hasStyle('underline');
    final newStrikethrough = hasStyle('strikethrough');
    final newSmallCaps = hasStyle('smallcaps');
    final newSuperscript = hasStyle('superscript');
    final newSubscript = hasStyle('subscript');
    final newTextAlign = _resolveTextAlign();

    if (newBold != _isBold ||
        newItalic != _isItalic ||
        newUnderline != _isUnderline ||
        newStrikethrough != _isStrikethrough ||
        newSmallCaps != _isSmallCaps ||
        newSuperscript != _isSuperscript ||
        newSubscript != _isSubscript ||
        newTextAlign != _textAlign) {
      setState(() {
        _isBold = newBold;
        _isItalic = newItalic;
        _isUnderline = newUnderline;
        _isStrikethrough = newStrikethrough;
        _isSmallCaps = newSmallCaps;
        _isSuperscript = newSuperscript;
        _isSubscript = newSubscript;
        _textAlign = newTextAlign;
      });
    }
  }

  TextAlign _resolveTextAlign() {
    final containerId = widget.document.findLogicalContainerId(
      widget.document.cursor.anchorId,
    );
    if (containerId == null) return TextAlign.left;
    final container = widget.document.nodeById(containerId);
    if (container is Paragraph) return parseTextAlign(container.textAlign);
    if (container is FluentImage) return parseTextAlign(container.textAlign);
    return TextAlign.left;
  }

  bool _hasSelection() => !widget.document.cursor.isCollapsed;

  bool _isCursorOnImage() {
    final cursor = widget.document.cursor;
    final currentNode = widget.document.nodeById(cursor.anchorId);
    if (currentNode is FluentImage) return true;
    if (currentNode is Paragraph) {
      final fragments = currentNode.fragments;
      if (fragments.length == 1 && fragments.first is FluentImage) return true;
    }
    return false;
  }

  bool _hasClipboardContent() => widget.document.clipboardPayload != null;

  /// Picks a file using the platform-appropriate dialog.
  /// Returns content as text and/or bytes depending on [binary].
  Future<({String? content, Uint8List? bytes})> _pickFile({
    required String label,
    required List<String> extensions,
    required String title,
    bool binary = false,
  }) async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: true,
      );
      if (!mounted) return (content: null, bytes: null);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes != null) {
          if (binary) return (content: null, bytes: bytes);
          return (
            content: utf8.decode(bytes, allowMalformed: true),
            bytes: bytes,
          );
        }
      }
      return (content: null, bytes: null);
    }

    if (Platform.isLinux) {
      try {
        final env = Map<String, String>.from(Platform.environment);
        env['GTK_THEME'] = 'Adwaita';
        final filter = extensions.map((e) => '*.$e').join(' ');
        final result = await Process.run('zenity', [
          '--file-selection',
          '--file-filter=$label | $filter',
          '--title=$title',
        ], environment: env);
        if (result.exitCode == 0) {
          final path = (result.stdout as String).trim();
          if (path.isNotEmpty) {
            final file = File(path);
            if (binary) {
              return (content: null, bytes: await file.readAsBytes());
            }
            return (content: await file.readAsString(), bytes: null);
          }
        }
      } catch (_) {}
      return (content: null, bytes: null);
    }

    if (Platform.isMacOS || Platform.isWindows) {
      final typeGroup = XTypeGroup(label: label, extensions: extensions);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (!mounted) return (content: null, bytes: null);
      if (file != null) {
        if (binary) {
          return (
            content: null,
            bytes: Uint8List.fromList(await file.readAsBytes()),
          );
        }
        return (content: await file.readAsString(), bytes: null);
      }
      return (content: null, bytes: null);
    }

    // Fallback for other platforms
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (!mounted) return (content: null, bytes: null);
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        final path = file.path!;
        final valid = extensions.any((e) => path.endsWith('.$e'));
        if (!valid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_labels.fileLoadError}: Please select a .${extensions.first} file',
              ),
            ),
          );
          return (content: null, bytes: null);
        }
      }
      final bytes = file.bytes;
      if (bytes != null) {
        if (binary) return (content: null, bytes: bytes);
        return (
          content: utf8.decode(bytes, allowMalformed: true),
          bytes: bytes,
        );
      } else if (!kIsWeb && file.path != null) {
        final fileOnDisk = File(file.path!);
        if (binary)
          return (content: null, bytes: await fileOnDisk.readAsBytes());
        return (content: await fileOnDisk.readAsString(), bytes: null);
      }
    }
    return (content: null, bytes: null);
  }

  Future<void> _saveFluentFile() async {
    final json = widget.document.toJson();
    final bytes = Uint8List.fromList(utf8.encode(json));
    final exportService = ExportService(widget.document);
    final path = await exportService.saveFileNative(
      bytes,
      'document.fluent',
      'fluent',
    );
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_labels.fileSaved}: $path')));
    }
  }

  Future<void> _loadFluentFile() async {
    try {
      final picked = await _pickFile(
        label: 'Fluent Editor',
        extensions: ['fluent', 'json'],
        title: 'Open file',
      );
      final jsonContent = picked.content;
      if (jsonContent == null) return;
      if (!mounted) return;
      final jsonMap = jsonDecode(jsonContent) as Map<String, dynamic>;
      if (jsonMap.containsKey('nodes') && jsonMap.containsKey('settings')) {
        widget.document.loadContent(
          Root.fromJson(jsonMap['nodes'] as Map<String, dynamic>),
        );
        final settings = jsonMap['settings'] as Map<String, dynamic>;
        widget.document.pendingLineHeight =
            (settings['lineHeight'] as num?)?.toDouble() ??
            widget.document.pendingLineHeight;
        widget.document.pendingSpacingBefore =
            (settings['spacingBefore'] as num?)?.toDouble() ??
            widget.document.pendingSpacingBefore;
        widget.document.pendingSpacingAfter =
            (settings['spacingAfter'] as num?)?.toDouble() ??
            widget.document.pendingSpacingAfter;
        widget.document.pendingFontFamily =
            settings['fontFamily'] as String? ??
            widget.document.pendingFontFamily;
        widget.document.pendingFontSize =
            (settings['fontSize'] as num?)?.toDouble() ??
            widget.document.pendingFontSize;
        widget.document.pendingTextAlign =
            settings['textAlign'] as String? ??
            widget.document.pendingTextAlign;
        widget.document.pendingIndent =
            (settings['indent'] as num?)?.toInt() ??
            widget.document.pendingIndent;
        widget.document.pendingColor = settings['color'] as String?;
        widget.document.pendingHighlightColor =
            settings['highlightColor'] as String?;
        if (settings['styles'] is List) {
          widget.document.pendingStyles = (settings['styles'] as List)
              .map((e) => e as String)
              .toList();
        }
        final loadedLang = settings['documentLanguage'] as String?;
        if (loadedLang != null) {
          widget.document.documentLanguage = loadedLang;
          DocumentLanguageController.instance.setLanguage(
            DocumentLanguage.fromCode(loadedLang),
          );
        }
        final comments = jsonMap['comments'];
        if (comments is List && widget.document.commentProvider != null) {
          widget.document.commentProvider!.importComments(
            comments.map((e) => e as Map<String, dynamic>).toList(),
          );
        }
      } else {
        widget.document.loadContent(Root.fromJson(jsonMap));
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_labels.fileLoaded)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_labels.fileLoadError}: $e')));
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_labels.settings),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_labels.documentLanguage),
            const SizedBox(height: 8),
            const LanguageSelectorWidget(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_labels.done),
          ),
        ],
      ),
    );
  }

  Future<void> _importDocument(String format) async {
    try {
      final isBinary = format == 'docx' || format == 'odt';
      final picked = await _pickFile(
        label: format.toUpperCase(),
        extensions: [format],
        title: 'Import file',
        binary: isBinary,
      );
      final content = picked.content;
      final bytes = picked.bytes;

      if (content == null && bytes == null) return;
      if (!mounted) return;

      final importService = ImportService();
      final Root root = switch (format) {
        'html' => importService.importFromHtml(content!),
        'md' => importService.importFromMarkdown(content!),
        'docx' => importService.importFromDocx(bytes!),
        'odt' => importService.importFromOdt(bytes!),
        _ => Root(nodes: [Paragraph(text: '')]),
      };

      widget.document.loadContent(root);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_labels.fileLoaded)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_labels.fileLoadError}: $e')));
    }
  }

  Future<void> _exportDocument(String format) async {
    final exportService = ExportService(widget.document);
    String? savedPath;
    try {
      switch (format) {
        case 'pdf':
          final pdfBytes = await exportService.exportToPdf();
          savedPath = await exportService.saveFileNative(
            pdfBytes,
            'document.pdf',
            'pdf',
          );
          break;
        case 'docx':
          final docxBytes = await exportService.exportToDocx();
          savedPath = await exportService.saveFileNative(
            docxBytes,
            'document.docx',
            'docx',
          );
          break;
        case 'odt':
          final odtBytes = await exportService.exportToOdt();
          savedPath = await exportService.saveFileNative(
            odtBytes,
            'document.odt',
            'odt',
          );
          break;
        case 'html':
          final htmlText = await exportService.exportToHtml();
          savedPath = await exportService.saveTextFileNative(
            htmlText,
            'document.html',
            'html',
          );
          break;
        case 'md':
          final mdText = exportService.exportToMarkdown();
          savedPath = await exportService.saveTextFileNative(
            mdText,
            'document.md',
            'md',
          );
          break;
      }
      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_labels.exportSuccess}: $savedPath')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_labels.exportError}: $e')));
    }
  }

  List<Widget> _buildInsertMenuPluginContributions(BuildContext context) {
    final doc = widget.document;
    return doc.registry
        .uiAt(FluentPluginUiLocation.insertMenu)
        .where((c) => c.visible?.call(doc) ?? true)
        .map((c) => _withClickCursor(c.builder(context, doc)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                MenuAnchor(
                  menuChildren: [
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.save),
                        onPressed: _saveFluentFile,
                        child: Text(_labels.save),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.folder_open),
                        onPressed: _loadFluentFile,
                        child: Text(_labels.open),
                      ),
                    ),
                    const Divider(height: 1),
                    _withClickCursor(
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.file_upload),
                        menuChildren: [
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.html),
                              onPressed: () => _importDocument('html'),
                              child: Text(_labels.importHtml),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.code),
                              onPressed: () => _importDocument('md'),
                              child: Text(_labels.importMarkdown),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.description),
                              onPressed: () => _importDocument('docx'),
                              child: Text(_labels.importDocx),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.article),
                              onPressed: () => _importDocument('odt'),
                              child: Text(_labels.importOdt),
                            ),
                          ),
                        ],
                        child: const Text('Import'),
                      ),
                    ),
                    const Divider(height: 1),
                    _withClickCursor(
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.file_download),
                        menuChildren: [
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.description),
                              onPressed: () => _exportDocument('docx'),
                              child: Text(_labels.microsoftWord),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.article),
                              onPressed: () => _exportDocument('odt'),
                              child: Text(_labels.libreOffice),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.picture_as_pdf),
                              onPressed: () => _exportDocument('pdf'),
                              child: Text(_labels.pdf),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.html),
                              onPressed: () => _exportDocument('html'),
                              child: Text(_labels.html),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.code),
                              onPressed: () => _exportDocument('md'),
                              child: Text(_labels.markdown),
                            ),
                          ),
                        ],
                        child: Text(_labels.exportAs),
                      ),
                    ),
                    const Divider(height: 1),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.settings),
                        onPressed: () {
                          _showSettingsDialog(context);
                        },
                        child: Text(_labels.settings),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.person_outline),
                        onPressed: () {
                          final provider = widget.document.commentProvider;
                          if (provider != null) {
                            showAuthorInfoDialog(
                              context,
                              commentProvider: provider,
                              labels: widget.labels,
                            );
                          }
                        },
                        child: Text(_labels.setAuthorLabel),
                      ),
                    ),
                  ],
                  builder: (context, controller, child) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(_labels.file),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                MenuAnchor(
                  menuChildren: [
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.undo),
                        onPressed: widget.document.canUndo
                            ? widget.document.undo
                            : null,
                        child: Text(_labels.undo),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.redo),
                        onPressed: widget.document.canRedo
                            ? widget.document.redo
                            : null,
                        child: Text(_labels.redo),
                      ),
                    ),
                    const Divider(height: 1),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.content_cut),
                        onPressed: _hasSelection()
                            ? () {
                                widget.document.saveState(
                                  description: 'Cut',
                                  forceNewAction: true,
                                );
                                executeHandleCut(widget.document);
                              }
                            : null,
                        child: Text(_labels.cut),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.copy),
                        onPressed: _hasSelection()
                            ? () => executeHandleCopy(widget.document)
                            : null,
                        child: Text(_labels.copy),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.paste),
                        onPressed: _hasClipboardContent()
                            ? () {
                                widget.document.saveState(
                                  description: 'Paste',
                                  forceNewAction: true,
                                );
                                executeHandlePaste(widget.document);
                              }
                            : null,
                        child: Text(_labels.paste),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.paste),
                        onPressed: _hasClipboardContent()
                            ? () {
                                widget.document.saveState(
                                  description: 'Paste Plain',
                                  forceNewAction: true,
                                );
                                executeHandlePastePlain(widget.document);
                              }
                            : null,
                        child: Text(_labels.pasteWithoutFormatting),
                      ),
                    ),
                    const Divider(height: 1),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.select_all),
                        onPressed: () => handleSelectAll(widget.document),
                        child: Text(_labels.selectAll),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.delete),
                        onPressed: _isCursorOnImage()
                            ? () {
                                widget.document.saveState(
                                  description: 'Delete',
                                  forceNewAction: true,
                                );
                                executeHandleBackspace(widget.document);
                              }
                            : null,
                        child: Text(_labels.delete),
                      ),
                    ),
                  ],
                  builder: (context, controller, child) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(_labels.edit),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                MenuAnchor(
                  menuChildren: [
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.link),
                        onPressed: () => widget.document.dialogPresenter
                            .handleInsertLink(context),
                        child: Text(_labels.link),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.image),
                        onPressed: () => widget.document.dialogPresenter
                            .handleInsertImage(context),
                        child: Text(_labels.image),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.table_chart),
                        onPressed: () => widget.document.eventHandler
                            .handleInsertNode('table'),
                        child: Text(_labels.table),
                      ),
                    ),
                    _withClickCursor(
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.horizontal_rule),
                        onPressed: () =>
                            widget.document.eventHandler.handleInsertNode('hr'),
                        child: Text(_labels.horizontalLine),
                      ),
                    ),
                    ..._buildInsertMenuPluginContributions(context),
                  ],
                  builder: (context, controller, child) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(_labels.insert),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                MenuAnchor(
                  menuChildren: [
                    _withClickCursor(
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.text_format),
                        menuChildren: [
                          _buildFormatMenuItem(
                            icon: Icons.format_bold,
                            label: _labels.bold,
                            isActive: _isBold,
                            handler: widget.document.eventHandler.handleBold,
                          ),
                          _buildFormatMenuItem(
                            icon: Icons.format_italic,
                            label: _labels.italic,
                            isActive: _isItalic,
                            handler: widget.document.eventHandler.handleItalic,
                          ),
                          _buildFormatMenuItem(
                            icon: Icons.format_underline,
                            label: _labels.underline,
                            isActive: _isUnderline,
                            handler:
                                widget.document.eventHandler.handleUnderline,
                          ),
                          _buildFormatMenuItem(
                            icon: Icons.format_strikethrough,
                            label: _labels.strikethrough,
                            isActive: _isStrikethrough,
                            handler: widget
                                .document
                                .eventHandler
                                .handleStrikethrough,
                          ),
                          _buildFormatMenuItem(
                            icon: Icons.text_fields,
                            label: _labels.smallCaps,
                            isActive: _isSmallCaps,
                            handler:
                                widget.document.eventHandler.handleSmallCaps,
                          ),
                          const Divider(height: 1),
                          _buildFormatMenuItem(
                            icon: Icons.superscript,
                            label: _labels.superscript,
                            isActive: _isSuperscript,
                            handler:
                                widget.document.eventHandler.handleSuperscript,
                          ),
                          _buildFormatMenuItem(
                            icon: Icons.subscript,
                            label: _labels.subscript,
                            isActive: _isSubscript,
                            handler:
                                widget.document.eventHandler.handleSubscript,
                          ),
                        ],
                        child: Text(_labels.text),
                      ),
                    ),
                    _withClickCursor(
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.style),
                        menuChildren: ParagraphStyle.predefinedStyles.map((
                          style,
                        ) {
                          return _withClickCursor(
                            MenuItemButton(
                              trailingIcon:
                                  widget.document.pendingStyle.name ==
                                      style.name
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler
                                    .handleParagraphStyle(style);
                                widget.document.requestEditorFocus();
                              },
                              child: Text(
                                style.displayName,
                                style: TextStyle(
                                  fontFamily: style.fontFamily,
                                  fontSize: (style.fontSize ?? 14).clamp(
                                    12.0,
                                    18.0,
                                  ),
                                  fontWeight:
                                      style.styles?.contains('bold') == true
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontStyle:
                                      style.styles?.contains('italic') == true
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                        child: Text(_labels.styles),
                      ),
                    ),
                    _withClickCursor(
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.format_align_left),
                        menuChildren: [
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.format_align_left),
                              trailingIcon: _textAlign == TextAlign.left
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler.handleTextAlign(
                                  'left',
                                );
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.alignLeft),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(
                                Icons.format_align_center,
                              ),
                              trailingIcon: _textAlign == TextAlign.center
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler.handleTextAlign(
                                  'center',
                                );
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.alignCenter),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.format_align_right),
                              trailingIcon: _textAlign == TextAlign.right
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler.handleTextAlign(
                                  'right',
                                );
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.alignRight),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(
                                Icons.format_align_justify,
                              ),
                              trailingIcon: _textAlign == TextAlign.justify
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler.handleTextAlign(
                                  'justify',
                                );
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.justify),
                            ),
                          ),
                          const Divider(height: 1),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(
                                Icons.format_indent_increase,
                              ),
                              onPressed: () {
                                widget.document.eventHandler.handleTab();
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.increaseIndent),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              leadingIcon: const Icon(
                                Icons.format_indent_decrease,
                              ),
                              onPressed: () {
                                widget.document.eventHandler.handleShiftTab();
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.decreaseIndent),
                            ),
                          ),
                        ],
                        child: Text(_labels.alignAndIndent),
                      ),
                    ),
                    _withClickCursor(
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.format_line_spacing),
                        menuChildren: [
                          _withClickCursor(
                            MenuItemButton(
                              trailingIcon:
                                  widget.document.pendingLineHeight == 1.0
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler
                                    .handleParagraphSpacing(lineHeight: 1.0);
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.lineSpacingSingle),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              trailingIcon:
                                  widget.document.pendingLineHeight == 1.15
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler
                                    .handleParagraphSpacing(lineHeight: 1.15);
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.lineSpacing115),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              trailingIcon:
                                  widget.document.pendingLineHeight == 1.5
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler
                                    .handleParagraphSpacing(lineHeight: 1.5);
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.lineSpacing15),
                            ),
                          ),
                          _withClickCursor(
                            MenuItemButton(
                              trailingIcon:
                                  widget.document.pendingLineHeight == 2.0
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onPressed: () {
                                widget.document.eventHandler
                                    .handleParagraphSpacing(lineHeight: 2.0);
                                widget.document.requestEditorFocus();
                              },
                              child: Text(_labels.lineSpacingDouble),
                            ),
                          ),
                        ],
                        child: Text(_labels.lineSpacing),
                      ),
                    ),
                  ],
                  builder: (context, controller, child) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(_labels.format),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                if (widget.document.commentProvider != null)
                  MenuAnchor(
                    menuChildren: [
                      _withClickCursor(
                        MenuItemButton(
                          leadingIcon: const Icon(Icons.comment),
                          trailingIcon:
                              widget.document.commentProvider!.showResolved
                              ? const Icon(Icons.check, size: 18)
                              : null,
                          onPressed: () {
                            widget.document.commentProvider!.showResolved =
                                !widget.document.commentProvider!.showResolved;
                          },
                          child: Text(_labels.showResolvedLabel),
                        ),
                      ),
                    ],
                    builder: (context, controller, child) {
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(_labels.sidebarTitle),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          FluentFormattingBar(document: widget.document, labels: widget.labels),
        ],
      ),
    );
  }

  Widget _buildFormatMenuItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback handler,
  }) {
    return _withClickCursor(
      MenuItemButton(
        leadingIcon: Icon(icon),
        trailingIcon: isActive ? const Icon(Icons.check, size: 18) : null,
        onPressed: _hasSelection()
            ? () {
                handler();
                widget.document.requestEditorFocus();
              }
            : null,
        child: Text(label),
      ),
    );
  }
}
