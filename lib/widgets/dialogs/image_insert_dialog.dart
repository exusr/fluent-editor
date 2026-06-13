import 'dart:convert';
import 'dart:io' show File, Platform, Process;
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'image_drop_stub.dart'
    if (dart.library.html) 'image_drop_web.dart'
    // ignore: unused_import
    ;

/// Returns true if the platform supports drag & drop from the filesystem.
bool _isDesktopPlatform() {
  if (kIsWeb) return false;
  return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
}

/// Returns true if the platform supports drag & drop (desktop or web).
bool _supportsDragAndDrop() {
  return kIsWeb || Platform.isLinux || Platform.isMacOS || Platform.isWindows;
}

/// Dialog to insert an image via URL, drag & drop, or file picker.
/// - Desktop (Linux/macOS/Windows): shows drop zone + choose file button.
/// - Web: shows drop zone + choose file button.
/// - Mobile (Android/iOS): shows only choose file button.
class ImageInsertDialog extends StatefulWidget {
  const ImageInsertDialog({super.key, this.labels});

  final FluentEditorLabels? labels;

  @override
  State<ImageInsertDialog> createState() => _ImageInsertDialogState();
}

class _ImageInsertDialogState extends State<ImageInsertDialog> {
  final _urlController = TextEditingController();
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  String? _selectedFileExtension;
  String? _errorMessage;
  bool _isDragOver = false;

  FluentEditorLabels get _labels => widget.labels ?? const FluentEditorLabels();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String _mimeFromExtension(String ext) {
    return switch (ext.toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'bmp' => 'image/bmp',
      _ => 'image/png',
    };
  }

  void _insert() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      Navigator.of(context).pop({'src': url});
      return;
    }
    if (_selectedFileBytes != null && _selectedFileExtension != null) {
      final mime = _mimeFromExtension(_selectedFileExtension!);
      final dataUri = 'data:$mime;base64,${base64Encode(_selectedFileBytes!)}';
      Navigator.of(context).pop({'src': dataUri});
      return;
    }
    setState(() => _errorMessage = 'Enter a URL or select an image');
  }

  /// Selects an image file with file_picker (works on all platforms).
  /// On Linux, if file_picker fails, uses zenity/kdialog as fallback.
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        
        // Check if bytes are available and not empty
        if (bytes != null && bytes.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _selectedFileBytes = bytes;
            _selectedFileName = file.name;
            _selectedFileExtension = file.extension ?? 'png';
            _urlController.clear();
            _errorMessage = null;
          });
        } else if (!kIsWeb && file.path != null) {
          // Fallback for desktop platforms: read from file path
          try {
            final ioFile = File(file.path!);
            if (await ioFile.exists()) {
              final ioBytes = await ioFile.readAsBytes();
              if (ioBytes.isNotEmpty) {
                if (!mounted) return;
                setState(() {
                  _selectedFileBytes = ioBytes;
                  _selectedFileName = file.name;
                  _selectedFileExtension = file.extension ?? 'png';
                  _urlController.clear();
                  _errorMessage = null;
                });
                return;
              }
            }
          } catch (e) {
            // If file reading fails, show error
            if (!mounted) return;
            setState(() => _errorMessage = 'Error reading file: $e');
            return;
          }
        } else {
          // No bytes available and no path to read from
          if (!mounted) return;
          setState(() => _errorMessage = 'Unable to read image data. Please try a different file.');
        }
      }
    } catch (e) {
      // Fallback for Linux: use zenity or kdialog if file_picker fails
      if (!kIsWeb && Platform.isLinux) {
        final picked = await _pickFileNativeLinux();
        if (picked) return;
      }
      if (!mounted) return;
      setState(() => _errorMessage = 'Error selecting file: $e');
    }
  }

  /// Native fallback for Linux using zenity or kdialog.
  Future<bool> _pickFileNativeLinux() async {
    try {
      // Try zenity
      final result = await Process.run('zenity', [
        '--file-selection',
        '--file-filter=Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg',
        '--title=Select an image',
      ]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) {
          final file = File(path);
          if (file.existsSync()) {
            final bytes = file.readAsBytesSync();
            final ext = path.split('.').last;
            if (!mounted) return true;
            setState(() {
              _selectedFileBytes = bytes;
              _selectedFileName = path.split('/').last;
              _selectedFileExtension = ext;
              _urlController.clear();
              _errorMessage = null;
            });
            return true;
          }
        }
      }
    } catch (_) {
      // zenity not available, try kdialog
      try {
        final result = await Process.run('kdialog', [
          '--getopenfilename',
          '~',
          'Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg)',
        ]);
        if (result.exitCode == 0) {
          final path = (result.stdout as String).trim();
          if (path.isNotEmpty) {
            final file = File(path);
            if (file.existsSync()) {
              final bytes = file.readAsBytesSync();
              final ext = path.split('.').last;
              if (!mounted) return true;
              setState(() {
                _selectedFileBytes = bytes;
                _selectedFileName = path.split('/').last;
                _selectedFileExtension = ext;
                _urlController.clear();
                _errorMessage = null;
              });
              return true;
            }
          }
        }
      } catch (_) {}
    }
    return false;
  }

  /// Handles drag & drop (desktop only).
  void _onDragDone(DropDoneDetails details) {
    if (details.files.isEmpty) return;
    final droppedFile = details.files.first;
    final path = droppedFile.path;
    try {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        final ext = path.split('.').last;
        setState(() {
          _selectedFileBytes = bytes;
          _selectedFileName = path.split('/').last;
          _selectedFileExtension = ext;
          _urlController.clear();
          _errorMessage = null;
          _isDragOver = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '${_labels.fileReadError}: $e';
        _isDragOver = false;
      });
    }
  }

  /// Handles drag & drop (web only).
  void _onWebFileDropped(List<int> bytes, String fileName, String extension) {
    setState(() {
      _selectedFileBytes = Uint8List.fromList(bytes);
      _selectedFileName = fileName;
      _selectedFileExtension = extension;
      _urlController.clear();
      _errorMessage = null;
      _isDragOver = false;
    });
  }

  Widget _buildFileSelectionArea(BuildContext context) {
    final hasFile = _selectedFileBytes != null;

    // Central content (selected file or placeholder)
    final content = hasFile
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image, size: 32, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                _selectedFileName ?? _labels.imageSelected,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 32, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(height: 8),
              Text(
                _supportsDragAndDrop()
                    ? _labels.dragImageHere
                    : _labels.clickToChooseImage,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                textAlign: TextAlign.center,
              ),
            ],
          );

    final box = GestureDetector(
      onTap: _pickFile,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(
            color: _isDragOver
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: _isDragOver ? 2 : 1,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          borderRadius: BorderRadius.circular(8),
          color: _isDragOver
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
              : Theme.of(context).colorScheme.surface,
        ),
        child: Center(child: content),
      ),
    );

    // On desktop: wrap with DropTarget for drag & drop
    if (_isDesktopPlatform()) {
      return DropTarget(
        onDragDone: _onDragDone,
        onDragEntered: (_) => setState(() => _isDragOver = true),
        onDragExited: (_) => setState(() => _isDragOver = false),
        child: box,
      );
    }

    // On web: wrap with WebDropTarget for HTML5 drag & drop
    if (kIsWeb) {
      return WebDropTarget(
        onFileDropped: _onWebFileDropped,
        child: box,
      );
    }

    return box;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_labels.insertImage),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // URL input
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: _labels.imageUrl,
                hintText: _labels.imageUrlHint,
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {
                _errorMessage = null;
                _selectedFileBytes = null;
                _selectedFileName = null;
                _selectedFileExtension = null;
              }),
            ),
            const SizedBox(height: 16),
            Center(child: Text(_labels.or, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)))),
            const SizedBox(height: 16),
            // File selection area (drag & drop on desktop, click anywhere)
            _buildFileSelectionArea(context),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_labels.cancel),
        ),
        FilledButton(
          onPressed: _insert,
          child: Text(_labels.insertButton),
        ),
      ],
    );
  }
}

/// Shows the dialog to insert an image.
/// Returns a Map with 'src' or null if cancelled.
Future<Map<String, String>?> showImageInsertDialog(
  BuildContext context, {
  FluentEditorLabels? labels,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => ImageInsertDialog(labels: labels),
  );
}
