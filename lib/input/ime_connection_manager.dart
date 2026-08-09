import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart' show Fragment;
import 'composition_detector_stub.dart'
    if (dart.library.html) 'composition_detector_web.dart';

class ImeConnectionManager {
  final TextInputClient client;
  TextInputConnection? connection;
  FluentDocument? document;

  Rect? lastCaretRect;
  Size? lastViewSize;

  Timer? connectionRetryTimer;
  int connectionRetryCount = 0;
  static const int maxConnectionRetries = 5;
  static const List<Duration> windowsRetryDelays = [
    Duration(milliseconds: 50),
    Duration(milliseconds: 100),
    Duration(milliseconds: 200),
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];

  ImeConnectionManager(this.client);

  bool get isConnectionActive => connection != null && connection!.attached;

  void attachInput(FluentDocument doc) {
    document = doc;
    CompositionDetector.initialize();
  }

  void detachInput() {
    connectionRetryTimer?.cancel();
    connectionRetryTimer = null;
    connectionRetryCount = 0;
    connection?.close();
    connection = null;
    document = null;
  }


  void setViewSize(Size size) {
    lastViewSize = size;
    if (connection == null || !connection!.attached) return;
    if (kIsWeb) return;
    connection!.setEditableSizeAndTransform(
      size,
      Matrix4.identity(),
    );
  }

  void updateCaretRect(Rect rect) {
    lastCaretRect = rect;
    if (connection == null || !connection!.attached) return;
    if (kIsWeb) {
      updateWebImePosition();
      return;
    }
    connection!.setCaretRect(rect);
    connection!.setComposingRect(rect);
  }

  void updateWebImePosition() {
    if (connection == null || !connection!.attached) return;
    if (document == null) return;
    final doc = document!;

    final fragId = doc.cursor.focusId.isNotEmpty
        ? doc.cursor.focusId
        : doc.cursor.anchorId;
    if (fragId.isEmpty) return;

    final containerId = doc.findLogicalContainerId(fragId);
    if (containerId == null) return;

    final render = doc.paragraphRegistry.renderFor(containerId);
    if (render == null || !render.attached || !render.hasSize) return;

    String fontFamily = 'DejaVu Sans';
    double fontSize = 14.0;
    FontWeight fontWeight = FontWeight.normal;
    final fragNode = doc.nodeById(fragId);
    if (fragNode is Fragment) {
      fontFamily = fragNode.fontFamily;
      fontSize = fragNode.fontSize;
      fontWeight = fragNode.isBold ? FontWeight.bold : FontWeight.normal;
    }

    final fragmentStartRect = render.getCaretScreenRect(fragId, 0);

    final Matrix4 transform;
    if (fragmentStartRect != null) {
      final renderBoxOrigin = render.localToGlobal(Offset.zero);
      final fragOffsetX = fragmentStartRect.left - renderBoxOrigin.dx;
      final fragOffsetY = fragmentStartRect.top - renderBoxOrigin.dy;
      transform = render
          .getTransformTo(null)
          .multiplied(Matrix4.translationValues(fragOffsetX, fragOffsetY, 0));
    } else {
      transform = render.getTransformTo(null);
    }

    connection!.setEditableSizeAndTransform(render.size, transform);

    final browserFontFamily = _webFontFallback(fontFamily);
    connection!.setStyle(
      fontFamily: browserFontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
  }

  String _webFontFallback(String fontFamily) {
    const webFontFamilies = {
      'Crimson Text',
      'Fira Sans',
      'Lato',
      'Poppins',
      'Titillium Web',
      'DejaVu Sans',
      'DejaVu Sans Mono',
      'DejaVu Serif',
    };
    if (webFontFamilies.contains(fontFamily)) {
      return '$fontFamily, sans-serif';
    }
    return switch (fontFamily) {
      _ => '$fontFamily, sans-serif',
    };
  }

  bool attachConnection({
    required int viewId,
    required VoidCallback onSyncBuffer,
  }) {
    if (document == null) return false;
    try {
      connection = TextInput.attach(
        client,
        TextInputConfiguration(
          inputType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          inputAction: TextInputAction.newline,
          enableDeltaModel: true,
          autocorrect: true,
          enableSuggestions: true,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          viewId: viewId,
        ),
      );
      if (connection == null || !connection!.attached) return false;
      connection!.setEditingState(const TextEditingValue());
      connection!.show();
      onSyncBuffer();
      connectionRetryCount = 0;
      connectionRetryTimer?.cancel();
      return true;
    } catch (e) {
      debugPrint('FluentTextInputHandler: attachConnection failed: $e');
      if (connectionRetryCount < maxConnectionRetries) {
        final delay = windowsRetryDelays[connectionRetryCount];
        connectionRetryCount++;
        connectionRetryTimer?.cancel();
        connectionRetryTimer = Timer(delay, () {
          attachConnection(viewId: viewId, onSyncBuffer: onSyncBuffer);
        });
      }
      return false;
    }
  }

  void showKeyboard(
    BuildContext context, {
    required VoidCallback onSyncBuffer,
  }) {
    final int viewId = View.of(context).viewId;
    if (connection == null || !connection!.attached) {
      attachConnection(viewId: viewId, onSyncBuffer: onSyncBuffer);
    }
    connection?.show();
    if (kIsWeb) {
      updateWebImePosition();
      return;
    }
    final s = lastViewSize;
    if (s != null) setViewSize(s);
    final rect = lastCaretRect;
    if (rect != null) {
      connection?.setCaretRect(rect);
      connection?.setComposingRect(rect);
    }
  }

  void hideKeyboard() {
    connection?.close();
  }
}
