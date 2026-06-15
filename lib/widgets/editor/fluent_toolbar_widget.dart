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
import 'package:fluent_editor/utils/resolve_selection.dart';
import 'package:fluent_editor/widgets/dialogs/author_info_dialog.dart';
import 'package:fluent_editor/widgets/editor/fluent_font_selector_widget.dart';
import 'package:fluent_editor/widgets/editor/fluent_font_size_selector_widget.dart';
import 'package:fluent_editor/widgets/editor/fluent_paragraph_style_selector.dart';
import 'package:fluent_editor/widgets/editor/fluent_paragraph_spacing_button.dart';
import 'package:fluent_editor/widgets/editor/fluent_text_color_button.dart';
import 'package:fluent_editor/controllers/document_language_controller.dart';
import 'package:fluent_editor/models/document_language.dart';
import 'package:fluent_editor/widgets/editor/fluent_highlight_color_button.dart';
import 'package:fluent_editor/widgets/toolbar/language_selector_widget.dart';
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
    DocumentLanguageController.instance.currentLanguage.addListener(_onLanguageControllerChanged);
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
    DocumentLanguageController.instance.currentLanguage.removeListener(_onLanguageControllerChanged);
    _commentSub?.cancel();
    super.dispose();
  }

  void _onLanguageControllerChanged() {
    widget.document.documentLanguage = DocumentLanguageController.instance.current.code;
  }

  void _onDocumentChanged() {
    // Cursor-only changes are handled by _onCursorChanged; skip here
    // to avoid duplicate _updateFormats calls.
    if (widget.document.cursorOnlyChange) return;
    _updateFormats();
  }

  void _onCursorChanged() => _updateFormats();

  void _updateFormats() {
    final newBold = _checkStyle('bold');
    final newItalic = _checkStyle('italic');
    final newUnderline = _checkStyle('underline');
    final newStrikethrough = _checkStyle('strikethrough');
    final newSmallCaps = _checkStyle('smallcaps');
    final newSuperscript = _checkStyle('superscript');
    final newSubscript = _checkStyle('subscript');
    final newTextAlign = _resolveTextAlign();

    if (newBold != _isBold || newItalic != _isItalic || newUnderline != _isUnderline ||
        newStrikethrough != _isStrikethrough || newSmallCaps != _isSmallCaps ||
        newSuperscript != _isSuperscript || newSubscript != _isSubscript || newTextAlign != _textAlign) {
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
    final containerId = widget.document
        .findLogicalContainerId(widget.document.cursor.anchorId);
    if (containerId == null) return TextAlign.left;
    final container = widget.document.nodeById(containerId);
    if (container is Paragraph) return _parseTextAlign(container.textAlign);
    if (container is FluentImage) return _parseTextAlign(container.textAlign);
    return TextAlign.left;
  }

  TextAlign _parseTextAlign(String value) {
    return switch (value) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };
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

  bool _checkStyle(String styleName) {
    final root = widget.document.content;
    final cursor = widget.document.cursor;
    if (!cursor.isCollapsed) {
      final selection = resolveSelection(
        root, cursor.anchorId, cursor.anchorOffset, cursor.focusId, cursor.focusOffset,
        cachedStops: widget.document.caretStops,
        cachedLines: widget.document.logicalLines,
      );
      if (selection != null) {
        for (final node in selection.nodes) {
          final leaves = FragmentOperations.collectLeafFragments(node.container as FNode);
          bool inRange = false;
          for (final leaf in leaves) {
            if (leaf.id == node.startFragment.id) inRange = true;
            if (inRange && leaf is! FluentImage) {
              if (leaf.styles?.contains(styleName) ?? false) return true;
            }
            if (leaf.id == node.endFragment.id) inRange = false;
          }
        }
        return false;
      }
    }
    return widget.document.pendingStyles.contains(styleName);
  }

  Widget _buildAlignButton(IconData icon, TextAlign align, String tooltip) {
    final isActive = _textAlign == align;
    return _buildToolbarButton(
      icon: icon,
      tooltip: tooltip,
      iconColor: isActive ? Theme.of(context).colorScheme.primary : null,
      backgroundColor: isActive
          ? Theme.of(context).colorScheme.primaryContainer.withAlpha(180)
          : null,
      onPressed: () {
        widget.document.eventHandler.handleTextAlign(_serializeTextAlign(align));
        widget.document.requestEditorFocus();
      },
    );
  }

  String _serializeTextAlign(TextAlign value) {
    return switch (value) {
      TextAlign.center => 'center',
      TextAlign.right => 'right',
      TextAlign.justify => 'justify',
      _ => 'left',
    };
  }

  Future<void> _saveFluentFile() async {
    final json = widget.document.toJson();
    final bytes = Uint8List.fromList(utf8.encode(json));
    final exportService = ExportService(widget.document);
    final path = await exportService.saveFileNative(bytes, 'document.fluent', 'fluent');
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_labels.fileSaved}: $path')),
      );
    }
  }

  Future<void> _loadFluentFile() async {
    try {
      String? jsonContent;

      // Web: use file_picker with HTML5 file input
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['fluent', 'json'],
          withData: true,
        );
        if (!mounted) return;
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          if (file.bytes != null) {
            jsonContent = utf8.decode(file.bytes!);
          }
        }
      }
      // On Linux, use zenity directly to ensure GNOME file dialog
      else if (Platform.isLinux) {
        try {
          // Set GTK to use Adwaita theme (GNOME default)
          final env = Map<String, String>.from(Platform.environment);
          env['GTK_THEME'] = 'Adwaita';

          final result = await Process.run('zenity', [
            '--file-selection',
            '--file-filter=Fluent Editor | *.fluent *.json',
            '--title=Open file',
          ], environment: env);
          if (result.exitCode == 0) {
            final path = (result.stdout as String).trim();
            if (path.isNotEmpty) {
              jsonContent = File(path).readAsStringSync();
            }
          }
        } catch (_) {}
      } else if (Platform.isMacOS || Platform.isWindows) {
        // Desktop: use file_selector for native dialogs
        const typeGroup = XTypeGroup(
          label: 'Fluent documents',
          extensions: ['fluent', 'json'],
        );
        final file = await openFile(acceptedTypeGroups: [typeGroup]);
        if (!mounted) return;
        if (file != null) {
          jsonContent = await file.readAsString();
        }
      } else {
        // Android/iOS: use file_picker
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: true,
        );
        if (!mounted) return;
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          if (file.path != null) {
            final path = file.path!;
            if (!path.endsWith('.fluent') && !path.endsWith('.json')) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${_labels.fileLoadError}: Please select a .fluent or .json file')),
              );
              return;
            }
          }
          if (file.bytes != null) {
            jsonContent = utf8.decode(file.bytes!);
          } else if (!kIsWeb && file.path != null) {
            jsonContent = File(file.path!).readAsStringSync();
          }
        }
      }
      
      if (jsonContent == null) return;
      if (!mounted) return;
      final jsonMap = jsonDecode(jsonContent) as Map<String, dynamic>;
      if (jsonMap.containsKey('nodes') && jsonMap.containsKey('settings')) {
        // New format: wrapped with settings
        widget.document.loadContent(Root.fromJson(jsonMap['nodes'] as Map<String, dynamic>));
        final settings = jsonMap['settings'] as Map<String, dynamic>;
        widget.document.pendingLineHeight = (settings['lineHeight'] as num?)?.toDouble() ?? widget.document.pendingLineHeight;
        widget.document.pendingSpacingBefore = (settings['spacingBefore'] as num?)?.toDouble() ?? widget.document.pendingSpacingBefore;
        widget.document.pendingSpacingAfter = (settings['spacingAfter'] as num?)?.toDouble() ?? widget.document.pendingSpacingAfter;
        widget.document.pendingFontFamily = settings['fontFamily'] as String? ?? widget.document.pendingFontFamily;
        widget.document.pendingFontSize = (settings['fontSize'] as num?)?.toDouble() ?? widget.document.pendingFontSize;
        widget.document.pendingTextAlign = settings['textAlign'] as String? ?? widget.document.pendingTextAlign;
        widget.document.pendingIndent = (settings['indent'] as num?)?.toInt() ?? widget.document.pendingIndent;
        widget.document.pendingColor = settings['color'] as String?;
        widget.document.pendingHighlightColor = settings['highlightColor'] as String?;
        if (settings['styles'] is List) {
          widget.document.pendingStyles = (settings['styles'] as List).map((e) => e as String).toList();
        }
        final loadedLang = settings['documentLanguage'] as String?;
        if (loadedLang != null) {
          widget.document.documentLanguage = loadedLang;
          DocumentLanguageController.instance.setLanguage(
            DocumentLanguage.fromCode(loadedLang),
          );
        }
        // Restore comments if present
        final comments = jsonMap['comments'];
        if (comments is List && widget.document.commentProvider != null) {
          widget.document.commentProvider!.importComments(
            comments.map((e) => e as Map<String, dynamic>).toList(),
          );
        }
      } else {
        // Legacy format: Root JSON directly
        widget.document.loadContent(Root.fromJson(jsonMap));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_labels.fileLoaded)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_labels.fileLoadError}: $e')),
      );
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
      String? content;
      Uint8List? bytes;

      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [format],
          withData: true,
        );
        if (!mounted) return;
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          bytes = file.bytes;
          if (bytes != null && format != 'docx' && format != 'odt') {
            content = utf8.decode(bytes, allowMalformed: true);
          }
        }
      } else if (Platform.isLinux) {
        try {
          final env = Map<String, String>.from(Platform.environment);
          env['GTK_THEME'] = 'Adwaita';
          final result = await Process.run('zenity', [
            '--file-selection',
            '--file-filter=${format.toUpperCase()} | *.$format',
            '--title=Import file',
          ], environment: env);
          if (result.exitCode == 0) {
            final path = (result.stdout as String).trim();
            if (path.isNotEmpty) {
              final file = File(path);
              if (format == 'docx' || format == 'odt') {
                bytes = await file.readAsBytes();
              } else {
                content = await file.readAsString();
              }
            }
          }
        } catch (_) {}
      } else if (Platform.isMacOS || Platform.isWindows) {
        final typeGroup = XTypeGroup(
          label: format.toUpperCase(),
          extensions: [format],
        );
        final file = await openFile(acceptedTypeGroups: [typeGroup]);
        if (!mounted) return;
        if (file != null) {
          if (format == 'docx' || format == 'odt') {
            bytes = Uint8List.fromList(await file.readAsBytes());
          } else {
            content = await file.readAsString();
          }
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: true,
        );
        if (!mounted) return;
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          if (file.path != null && !file.path!.endsWith('.$format')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${_labels.fileLoadError}: Please select a .$format file')),
            );
            return;
          }
          bytes = file.bytes;
          if (bytes != null && format != 'docx' && format != 'odt') {
            content = utf8.decode(bytes, allowMalformed: true);
          }
        }
      }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_labels.fileLoaded)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_labels.fileLoadError}: $e')),
      );
    }
  }

  Future<void> _exportDocument(String format) async {
    final exportService = ExportService(widget.document);
    String? savedPath;
    try {
      switch (format) {
        case 'pdf':
          final pdfBytes = await exportService.exportToPdf();
          savedPath = await exportService.saveFileNative(pdfBytes, 'document.pdf', 'pdf');
          break;
        case 'docx':
          final docxBytes = await exportService.exportToDocx();
          savedPath = await exportService.saveFileNative(docxBytes, 'document.docx', 'docx');
          break;
        case 'odt':
          final odtBytes = await exportService.exportToOdt();
          savedPath = await exportService.saveFileNative(odtBytes, 'document.odt', 'odt');
          break;
        case 'html':
          final htmlText = await exportService.exportToHtml();
          savedPath = await exportService.saveTextFileNative(htmlText, 'document.html', 'html');
          break;
        case 'md':
          final mdText = exportService.exportToMarkdown();
          savedPath = await exportService.saveTextFileNative(mdText, 'document.md', 'md');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_labels.exportError}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
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
          // ── Top row ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                // ── File ────────────────────────────────────────────
                MenuAnchor(
                  menuChildren: [
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.save),
                      onPressed: _saveFluentFile,
                      child: Text(_labels.save),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.folder_open),
                      onPressed: _loadFluentFile,
                      child: Text(_labels.open),
                    )),
                    const Divider(height: 1),
                    _withClickCursor(SubmenuButton(
                      leadingIcon: const Icon(Icons.file_upload),
                      menuChildren: [
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.html),
                          onPressed: () => _importDocument('html'),
                          child: Text(_labels.importHtml),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.code),
                          onPressed: () => _importDocument('md'),
                          child: Text(_labels.importMarkdown),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.description),
                          onPressed: () => _importDocument('docx'),
                          child: Text(_labels.importDocx),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.article),
                          onPressed: () => _importDocument('odt'),
                          child: Text(_labels.importOdt),
                        )),
                      ],
                      child: const Text('Import'),
                    )),
                    const Divider(height: 1),
                    _withClickCursor(SubmenuButton(
                      leadingIcon: const Icon(Icons.file_download),
                      menuChildren: [
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.description),
                          onPressed: () => _exportDocument('docx'),
                          child: Text(_labels.microsoftWord),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.article),
                          onPressed: () => _exportDocument('odt'),
                          child: Text(_labels.libreOffice),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.picture_as_pdf),
                          onPressed: () => _exportDocument('pdf'),
                          child: Text(_labels.pdf),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.html),
                          onPressed: () => _exportDocument('html'),
                          child: Text(_labels.html),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.code),
                          onPressed: () => _exportDocument('md'),
                          child: Text(_labels.markdown),
                        )),
                      ],
                      child: Text(_labels.exportAs),
                    )),
                    const Divider(height: 1),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.settings),
                      onPressed: () {
                        _showSettingsDialog(context);
                      },
                      child: Text(_labels.settings),
                    )),
                    _withClickCursor(MenuItemButton(
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
                    )),
                  ],
                  builder: (context, controller, child) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => controller.isOpen ? controller.close() : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(_labels.file),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                // ── Edit ────────────────────────────────────────────
                MenuAnchor(
                  menuChildren: [
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.undo),
                      onPressed: widget.document.canUndo ? widget.document.undo : null,
                      child: Text(_labels.undo),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.redo),
                      onPressed: widget.document.canRedo ? widget.document.redo : null,
                      child: Text(_labels.redo),
                    )),
                    const Divider(height: 1),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.content_cut),
                      onPressed: _hasSelection() ? () {
                        widget.document.saveState(description: 'Cut', forceNewAction: true);
                        executeHandleCut(widget.document);
                      } : null,
                      child: Text(_labels.cut),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.copy),
                      onPressed: _hasSelection() ? () => executeHandleCopy(widget.document) : null,
                      child: Text(_labels.copy),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.paste),
                      onPressed: _hasClipboardContent() ? () {
                        widget.document.saveState(description: 'Paste', forceNewAction: true);
                        executeHandlePaste(widget.document);
                      } : null,
                      child: Text(_labels.paste),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.paste),
                      onPressed: _hasClipboardContent() ? () {
                        widget.document.saveState(description: 'Paste Plain', forceNewAction: true);
                        executeHandlePastePlain(widget.document);
                      } : null,
                      child: Text(_labels.pasteWithoutFormatting),
                    )),
                    const Divider(height: 1),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.select_all),
                      onPressed: () => handleSelectAll(widget.document),
                      child: Text(_labels.selectAll),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.delete),
                      onPressed: _isCursorOnImage() ? () {
                        widget.document.saveState(description: 'Delete', forceNewAction: true);
                        executeHandleBackspace(widget.document);
                      } : null,
                      child: Text(_labels.delete),
                    )),
                  ],
                  builder: (context, controller, child) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => controller.isOpen ? controller.close() : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(_labels.edit),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                // ── Insert ──────────────────────────────────────────
                MenuAnchor(
                  menuChildren: [
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.link),
                      onPressed: () => widget.document.eventHandler.handleInsertLink(context),
                      child: Text(_labels.link),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.image),
                      onPressed: () => widget.document.eventHandler.handleInsertImage(context),
                      child: Text(_labels.image),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.table_chart),
                      onPressed: () => widget.document.eventHandler.handleInsertNode('table'),
                      child: Text(_labels.table),
                    )),
                    _withClickCursor(MenuItemButton(
                      leadingIcon: const Icon(Icons.horizontal_rule),
                      onPressed: () => widget.document.eventHandler.handleInsertNode('hr'),
                      child: Text(_labels.horizontalLine),
                    )),
                  ],
                  builder: (context, controller, child) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => controller.isOpen ? controller.close() : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(_labels.insert),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                // ── Format ──────────────────────────────────────────
                MenuAnchor(
                  menuChildren: [
                    _withClickCursor(SubmenuButton(
                      leadingIcon: const Icon(Icons.text_format),
                      menuChildren: [
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_bold),
                          trailingIcon: _isBold ? const Icon(Icons.check, size: 18) : null,
                          onPressed: _hasSelection() ? () {
                            widget.document.eventHandler.handleBold();
                            widget.document.requestEditorFocus();
                          } : null,
                          child: Text(_labels.bold),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_italic),
                          trailingIcon: _isItalic ? const Icon(Icons.check, size: 18) : null,
                          onPressed: _hasSelection() ? () {
                            widget.document.eventHandler.handleItalic();
                            widget.document.requestEditorFocus();
                          } : null,
                          child: Text(_labels.italic),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_underline),
                          trailingIcon: _isUnderline ? const Icon(Icons.check, size: 18) : null,
                          onPressed: _hasSelection() ? () {
                            widget.document.eventHandler.handleUnderline();
                            widget.document.requestEditorFocus();
                          } : null,
                          child: Text(_labels.underline),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_strikethrough),
                          trailingIcon: _isStrikethrough ? const Icon(Icons.check, size: 18) : null,
                          onPressed: _hasSelection() ? () {
                            widget.document.eventHandler.handleStrikethrough();
                            widget.document.requestEditorFocus();
                          } : null,
                          child: Text(_labels.strikethrough),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.text_fields),
                          trailingIcon: _isSmallCaps ? const Icon(Icons.check, size: 18) : null,
                          onPressed: _hasSelection() ? () {
                            widget.document.eventHandler.handleSmallCaps();
                            widget.document.requestEditorFocus();
                          } : null,
                          child: Text(_labels.smallCaps),
                        )),
                        const Divider(height: 1),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.superscript),
                          trailingIcon: _isSuperscript ? const Icon(Icons.check, size: 18) : null,
                          onPressed: _hasSelection() ? () {
                            widget.document.eventHandler.handleSuperscript();
                            widget.document.requestEditorFocus();
                          } : null,
                          child: Text(_labels.superscript),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.subscript),
                          trailingIcon: _isSubscript ? const Icon(Icons.check, size: 18) : null,
                          onPressed: _hasSelection() ? () {
                            widget.document.eventHandler.handleSubscript();
                            widget.document.requestEditorFocus();
                          } : null,
                          child: Text(_labels.subscript),
                        )),
                      ],
                      child: Text(_labels.text),
                    )),
                    _withClickCursor(SubmenuButton(
                      leadingIcon: const Icon(Icons.style),
                      menuChildren: ParagraphStyle.predefinedStyles.map((style) {
                        return _withClickCursor(MenuItemButton(
                          trailingIcon: widget.document.pendingStyle.name == style.name
                              ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleParagraphStyle(style);
                            widget.document.requestEditorFocus();
                          },
                          child: Text(
                            style.displayName,
                            style: TextStyle(
                              fontFamily: style.fontFamily,
                              fontSize: (style.fontSize ?? 14).clamp(12.0, 18.0),
                              fontWeight: style.styles?.contains('bold') == true
                                  ? FontWeight.bold : FontWeight.normal,
                              fontStyle: style.styles?.contains('italic') == true
                                  ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ));
                      }).toList(),
                      child: Text(_labels.styles),
                    )),
                    _withClickCursor(SubmenuButton(
                      leadingIcon: const Icon(Icons.format_align_left),
                      menuChildren: [
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_align_left),
                          trailingIcon: _textAlign == TextAlign.left ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleTextAlign('left');
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.alignLeft),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_align_center),
                          trailingIcon: _textAlign == TextAlign.center ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleTextAlign('center');
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.alignCenter),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_align_right),
                          trailingIcon: _textAlign == TextAlign.right ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleTextAlign('right');
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.alignRight),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_align_justify),
                          trailingIcon: _textAlign == TextAlign.justify ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleTextAlign('justify');
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.justify),
                        )),
                        const Divider(height: 1),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_indent_increase),
                          onPressed: () {
                            widget.document.eventHandler.handleTab();
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.increaseIndent),
                        )),
                        _withClickCursor(MenuItemButton(
                          leadingIcon: const Icon(Icons.format_indent_decrease),
                          onPressed: () {
                            widget.document.eventHandler.handleShiftTab();
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.decreaseIndent),
                        )),
                      ],
                      child: Text(_labels.alignAndIndent),
                    )),
                    _withClickCursor(SubmenuButton(
                      leadingIcon: const Icon(Icons.format_line_spacing),
                      menuChildren: [
                        _withClickCursor(MenuItemButton(
                          trailingIcon: widget.document.pendingLineHeight == 1.0
                              ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleParagraphSpacing(lineHeight: 1.0);
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.lineSpacingSingle),
                        )),
                        _withClickCursor(MenuItemButton(
                          trailingIcon: widget.document.pendingLineHeight == 1.15
                              ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleParagraphSpacing(lineHeight: 1.15);
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.lineSpacing115),
                        )),
                        _withClickCursor(MenuItemButton(
                          trailingIcon: widget.document.pendingLineHeight == 1.5
                              ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleParagraphSpacing(lineHeight: 1.5);
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.lineSpacing15),
                        )),
                        _withClickCursor(MenuItemButton(
                          trailingIcon: widget.document.pendingLineHeight == 2.0
                              ? const Icon(Icons.check, size: 18) : null,
                          onPressed: () {
                            widget.document.eventHandler.handleParagraphSpacing(lineHeight: 2.0);
                            widget.document.requestEditorFocus();
                          },
                          child: Text(_labels.lineSpacingDouble),
                        )),
                      ],
                      child: Text(_labels.lineSpacing),
                    )),
                  ],
                  builder: (context, controller, child) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => controller.isOpen ? controller.close() : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(_labels.format),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                // ── Comments ────────────────────────────────────────
                if (widget.document.commentProvider != null)
                  MenuAnchor(
                    menuChildren: [
                      _withClickCursor(MenuItemButton(
                        leadingIcon: const Icon(Icons.comment),
                        trailingIcon: widget.document.commentProvider!.showResolved
                            ? const Icon(Icons.check, size: 18)
                            : null,
                        onPressed: () {
                          widget.document.commentProvider!.showResolved =
                              !widget.document.commentProvider!.showResolved;
                        },
                        child: Text(_labels.showResolvedLabel),
                      )),
                    ],
                    builder: (context, controller, child) {
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => controller.isOpen ? controller.close() : controller.open(),
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
          // ── Bottom row: formatting ────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FluentParagraphStyleSelector(document: widget.document),
                const SizedBox(width: 4),
                FluentFontSelectorWidget(document: widget.document),
                const SizedBox(width: 4),
                FluentFontSizeSelectorWidget(document: widget.document),
                _buildVerticalDivider(),
                _buildToolbarButton(
                  icon: Icons.format_bold,
                  tooltip: "Bold (Ctrl+B)",
                  iconColor: _isBold ? Theme.of(context).colorScheme.primary : null,
                  backgroundColor: _isBold
                      ? Theme.of(context).colorScheme.primaryContainer.withAlpha(180) : null,
                  onPressed: () {
                    widget.document.eventHandler.handleBold();
                    widget.document.requestEditorFocus();
                  },
                ),
                _buildToolbarButton(
                  icon: Icons.format_italic,
                  tooltip: "Italic (Ctrl+I)",
                  iconColor: _isItalic ? Theme.of(context).colorScheme.primary : null,
                  backgroundColor: _isItalic
                      ? Theme.of(context).colorScheme.primaryContainer.withAlpha(180) : null,
                  onPressed: () {
                    widget.document.eventHandler.handleItalic();
                    widget.document.requestEditorFocus();
                  },
                ),
                _buildToolbarButton(
                  icon: Icons.format_underline,
                  tooltip: "Underline (Ctrl+U)",
                  iconColor: _isUnderline ? Theme.of(context).colorScheme.primary : null,
                  backgroundColor: _isUnderline
                      ? Theme.of(context).colorScheme.primaryContainer.withAlpha(180) : null,
                  onPressed: () {
                    widget.document.eventHandler.handleUnderline();
                    widget.document.requestEditorFocus();
                  },
                ),
                FluentTextColorButton(document: widget.document, labels: widget.labels),
                FluentHighlightColorButton(document: widget.document, labels: widget.labels),
                _buildVerticalDivider(),
                _buildToolbarButton(
                  icon: Icons.link,
                  tooltip: "Insert Link",
                  onPressed: () {
                    widget.document.eventHandler.handleInsertLink(context);
                    widget.document.requestEditorFocus();
                  },
                ),
                _buildToolbarButton(
                  icon: Icons.format_list_bulleted,
                  tooltip: "Insert Bullet List",
                  onPressed: () {
                    widget.document.eventHandler.handleInsertNode('list', {'listType': 'bullet'});
                    widget.document.requestEditorFocus();
                  },
                ),
                _buildToolbarButton(
                  icon: Icons.format_list_numbered,
                  tooltip: "Insert Numbered List",
                  onPressed: () {
                    widget.document.eventHandler.handleInsertNode('list', {'listType': 'ordered'});
                    widget.document.requestEditorFocus();
                  },
                ),
                _buildToolbarButton(
                  icon: Icons.format_clear,
                  tooltip: "Clear formatting",
                  onPressed: () {
                    widget.document.eventHandler.handleClearFormatting();
                    widget.document.requestEditorFocus();
                  },
                ),
                _buildVerticalDivider(),
                _buildAlignButton(Icons.format_align_left, TextAlign.left, 'Align left'),
                _buildAlignButton(Icons.format_align_center, TextAlign.center, 'Align center'),
                _buildAlignButton(Icons.format_align_right, TextAlign.right, 'Align right'),
                _buildAlignButton(Icons.format_align_justify, TextAlign.justify, 'Justify'),
                _buildVerticalDivider(),
                _buildToolbarButton(
                  icon: Icons.format_indent_increase,
                  tooltip: "Indent (Tab)",
                  onPressed: () {
                    widget.document.eventHandler.handleTab();
                    widget.document.requestEditorFocus();
                  },
                ),
                _buildToolbarButton(
                  icon: Icons.format_indent_decrease,
                  tooltip: "Outdent (Shift+Tab)",
                  onPressed: () {
                    widget.document.eventHandler.handleShiftTab();
                    widget.document.requestEditorFocus();
                  },
                ),
                _buildVerticalDivider(),
                FluentParagraphSpacingButton(document: widget.document, labels: widget.labels),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? iconColor,
    Color? backgroundColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          mouseCursor: onPressed != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }
}