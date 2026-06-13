// Web-specific implementation using HTML5 drag and drop
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';

class WebDropTarget extends StatefulWidget {
  final Widget child;
  final void Function(List<int> bytes, String fileName, String extension)? onFileDropped;

  const WebDropTarget({
    super.key,
    required this.child,
    this.onFileDropped,
  });

  @override
  State<WebDropTarget> createState() => _WebDropTargetState();
}

class _WebDropTargetState extends State<WebDropTarget> {
  StreamSubscription? _dragOverSubscription;
  StreamSubscription? _dropSubscription;

  @override
  void initState() {
    super.initState();
    _setupGlobalDragAndDrop();
  }

  void _setupGlobalDragAndDrop() {
    // Add listeners to the document body to catch all drag events
    _dragOverSubscription = html.document.body?.onDragOver.listen((event) {
      event.preventDefault();
      event.dataTransfer.dropEffect = 'copy';
    });

    _dropSubscription = html.document.body?.onDrop.listen((event) {
      event.preventDefault();

      final dataTransfer = event.dataTransfer;
      final files = dataTransfer.files;
      if (files == null || files.isEmpty) return;

      final file = files.first;
      final reader = html.FileReader();

      reader.onLoad.listen((html.ProgressEvent event) {
        if (reader.result != null) {
          final bytes = reader.result as Uint8List;
          final fileName = file.name;
          final extension = fileName.split('.').last;
          widget.onFileDropped?.call(bytes, fileName, extension);
        }
      });

      reader.readAsArrayBuffer(file);
    });
  }

  @override
  void dispose() {
    _dragOverSubscription?.cancel();
    _dropSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
