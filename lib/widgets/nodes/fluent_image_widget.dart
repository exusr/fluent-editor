import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/widgets/dialogs/image_insert_dialog.dart';
import 'package:fluent_editor/widgets/editor/fluent_context_menu.dart';
import 'package:fluent_editor/widgets/nodes/fluent_paragraph_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class FluentImageWidget extends FluentParagraphWidget {
  const FluentImageWidget({
    super.key,
    required super.node,
    required super.document,
  });

  @override
  FluentImage get node => super.node as FluentImage;

  @override
  FluentParagraphWidgetState<FluentImageWidget> createState() =>
      _FluentImageWidgetState();
}

class _FluentImageWidgetState
    extends FluentParagraphWidgetState<FluentImageWidget> {
  static const double _defaultImgWidth = 300;
  static const double _defaultImgHeight = 300;
  static double get _handleSize => kIsWeb || Platform.isAndroid || Platform.isIOS ? 24.0 : 12.0;
  static const double _minSize = 50.0;
  static const double _maxSize = 800.0;

  bool _isDragging = false;
  _ResizeHandle? _activeHandle;
  _ResizeHandle? _hoveredHandle;
  Offset? _dragStartPosition;
  
  // Resize mode: activated by double-tap, gives image priority over scroll/selection
  bool _isResizeMode = false;

  // Aspect ratio tracking
  double? _originalAspectRatio;
  bool _aspectRatioConstrained = true;
  static const double _aspectRatioThreshold = 0.1; // 10% deviation threshold

  // Cached image bytes for data URIs to avoid re-decoding on every rebuild
  String? _cachedSrc;
  Uint8List? _cachedBytes;

  @override
  void initState() {
    super.initState();
    _resolveImageDimensions();
  }

  @override
  void didUpdateWidget(covariant FluentImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.src != widget.node.src) {
      _resolveImageDimensions();
    }
  }

  /// If width and height are null, reads the real dimensions from the image
  /// and saves them in the model for persistence and export.
  void _resolveImageDimensions() {
    final node = widget.node;
    if (node.width != null && node.height != null) return;

    ImageProvider provider;
    if (node.src.startsWith('data:')) {
      final commaIndex = node.src.indexOf(',');
      if (commaIndex == -1) return;
      if (_cachedSrc != node.src || _cachedBytes == null) {
        _cachedSrc = node.src;
        _cachedBytes = base64Decode(node.src.substring(commaIndex + 1));
      }
      provider = MemoryImage(_cachedBytes!);
    } else if (node.src.startsWith('http://') || node.src.startsWith('https://')) {
      provider = NetworkImage(node.src);
    } else {
      provider = AssetImage(node.src);
    }

    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (node.width == null && node.height == null) {
          // Limita a dimensioni ragionevoli per l'editor
          final maxW = math.min(w, _maxSize);
          final scale = maxW / w;
          node.width = maxW;
          node.height = h * scale;
          if (mounted) {
            setState(() {});
            widget.document.updateContent();
          }
        }
        stream.removeListener(listener);
        info.dispose();
      },
      onError: (_, _) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  Alignment _parseAlignment(String value) {
    return switch (value) {
      'center' => Alignment.center,
      'right' => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
  }

  void _onTapDown(TapDownDetails details) {
    if (_isDragging) return;

    widget.document.requestEditorFocus();

    // Initialize original aspect ratio if not set
    _initializeAspectRatio();

    // Position the cursor at offset 0 (before) or 1 (after) based on the tap x.
    final box = context.findRenderObject() as RenderBox?;
    final localX = box != null
        ? box.globalToLocal(details.globalPosition).dx
        : 0.0;
    final imgWidth = widget.node.width ?? _defaultImgWidth;
    final offset = localX < imgWidth / 2 ? 0 : 1;
    widget.document.cursor.moveTo(widget.node.id, offset);
  }

  void _initializeAspectRatio() {
    if (_originalAspectRatio == null) {
      final imgWidth = widget.node.width ?? _defaultImgWidth;
      final imgHeight = widget.node.height ?? _defaultImgHeight;
      _originalAspectRatio = imgWidth / imgHeight;
    }
  }

  bool _isAspectRatioDeviating(double newWidth, double newHeight) {
    if (_originalAspectRatio == null || newHeight <= 0) return false;

    final currentAspectRatio = newWidth / newHeight;
    final deviation =
        (currentAspectRatio - _originalAspectRatio!).abs() /
        _originalAspectRatio!;

    return deviation > _aspectRatioThreshold;
  }

  void _onHoverUpdate(bool hovering, Offset localPosition) {
    if (!hovering) {
      if (_hoveredHandle != null) {
        setState(() => _hoveredHandle = null);
      }
      return;
    }

    // Detect which handle is near the cursor
    final imgWidth = widget.node.width ?? _defaultImgWidth;
    final imgHeight = widget.node.height ?? _defaultImgHeight;
    final tolerance = _handleSize;

    _ResizeHandle? newHoveredHandle;

    // Check corners
    if (localPosition.dx <= tolerance && localPosition.dy <= tolerance) {
      newHoveredHandle = _ResizeHandle.topLeft;
    } else if (localPosition.dx >= imgWidth - tolerance &&
        localPosition.dy <= tolerance) {
      newHoveredHandle = _ResizeHandle.topRight;
    } else if (localPosition.dx <= tolerance &&
        localPosition.dy >= imgHeight - tolerance) {
      newHoveredHandle = _ResizeHandle.bottomLeft;
    } else if (localPosition.dx >= imgWidth - tolerance &&
        localPosition.dy >= imgHeight - tolerance) {
      newHoveredHandle = _ResizeHandle.bottomRight;
    }
    // Check edges
    else if (localPosition.dx <= tolerance) {
      newHoveredHandle = _ResizeHandle.left;
    } else if (localPosition.dx >= imgWidth - tolerance) {
      newHoveredHandle = _ResizeHandle.right;
    } else if (localPosition.dy <= tolerance) {
      newHoveredHandle = _ResizeHandle.top;
    } else if (localPosition.dy >= imgHeight - tolerance) {
      newHoveredHandle = _ResizeHandle.bottom;
    }

    if (newHoveredHandle != _hoveredHandle) {
      setState(() => _hoveredHandle = newHoveredHandle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.node;
    final cursor = widget.document.cursor;
    final imgWidth = image.width ?? _defaultImgWidth;
    final imgHeight = image.height ?? _defaultImgHeight;

    final cursorOnImage = cursor.isCollapsed && cursor.anchorId == image.id;
    final cursorBefore = cursorOnImage && cursor.anchorOffset == 0;
    final cursorAfter = cursorOnImage && cursor.anchorOffset == 1;

    // Check if image is selected
    bool isSelected = false;
    if (!cursor.isCollapsed) {
      final stops = widget.document.caretStops;
      final anchorIdx = findStopIndex(
        stops,
        cursor.anchorId,
        cursor.anchorOffset,
      );
      final focusIdx = findStopIndex(stops, cursor.focusId, cursor.focusOffset);
      final img0Idx = findStopIndex(stops, image.id, 0);
      final img1Idx = findStopIndex(stops, image.id, 1);
      if (anchorIdx >= 0 && focusIdx >= 0 && img0Idx >= 0 && img1Idx >= 0) {
        final lo = anchorIdx < focusIdx ? anchorIdx : focusIdx;
        final hi = anchorIdx < focusIdx ? focusIdx : anchorIdx;
        isSelected = lo <= img0Idx && img1Idx <= hi;
      }
    }

    // Show resize handles only in resize mode (activated by double-tap)
    final showHandles = _isResizeMode;

    return Container(
      alignment: _parseAlignment(image.textAlign),
      child: MouseRegion(
        onEnter: (_) => _onHoverUpdate(true, Offset.zero),
        onExit: (_) => _onHoverUpdate(false, Offset.zero),
        onHover: (event) => _onHoverUpdate(true, event.localPosition),
        child: GestureDetector(
          behavior: HitTestBehavior
              .opaque, // Capture gestures before they reach the link
          onTapDown: _onTapDown,
          onTap: () {
            widget.document.requestEditorFocus();
            // Handle tap to prevent it from reaching the link
            // Position cursor on the image
            widget.document.cursor.moveTo(widget.node.id, 0);
          },
          onDoubleTap: () {
            // Toggle resize mode on double tap
            setState(() {
              _isResizeMode = !_isResizeMode;
              widget.document.isResizingImage = _isResizeMode;
            });
          },
          onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
          onLongPressStart: (details) => _showContextMenu(details.globalPosition),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate the actual width to use
              final availableWidth = constraints.maxWidth;
              final actualWidth = _calculateActualWidth(
                imgWidth,
                availableWidth,
              );
              final actualHeight = _calculateActualHeight(
                imgHeight,
                actualWidth,
                imgWidth,
              );

              return SizedBox(
                width: actualWidth,
                height: actualHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildImage(image.src),
                    ),
                    if (isSelected)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    if (cursorBefore)
                      const Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: _CaretLine(),
                      ),
                    if (cursorAfter)
                      const Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: _CaretLine(),
                      ),
                    // Resize handles - MUST be last to be on top
                    if (showHandles) ..._buildResizeHandles(actualWidth, actualHeight)
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String src) {
    if (src.startsWith('data:')) {
      // Parse data URI: data:[<mediatype>][;base64],<data>
      final commaIndex = src.indexOf(',');
      if (commaIndex != -1) {
        try {
          // Cache decoded bytes to avoid re-decoding on every rebuild
          if (_cachedSrc != src || _cachedBytes == null) {
            _cachedSrc = src;
            _cachedBytes = base64Decode(src.substring(commaIndex + 1));
          }
          return Image.memory(_cachedBytes!, fit: BoxFit.cover, gaplessPlayback: true);
        } catch (e) {
          return const SizedBox.shrink();
        }
      }
    }
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(src, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return Image.asset(src, fit: BoxFit.cover, gaplessPlayback: true);
  }

  List<Widget> _buildResizeHandles(double imgWidth, double imgHeight) {
    // Show all handles for better visibility and usability
    return [
      // Corner handles
      _buildHandle(
        0,
        0,
        _ResizeHandle.topLeft,
        SystemMouseCursors.resizeUpLeft,
      ),
      _buildHandle(
        imgWidth - _handleSize,
        0,
        _ResizeHandle.topRight,
        SystemMouseCursors.resizeUpRight,
      ),
      _buildHandle(
        0,
        imgHeight - _handleSize,
        _ResizeHandle.bottomLeft,
        SystemMouseCursors.resizeDownLeft,
      ),
      _buildHandle(
        imgWidth - _handleSize,
        imgHeight - _handleSize,
        _ResizeHandle.bottomRight,
        SystemMouseCursors.resizeDownRight,
      ),
      // Edge handles
      _buildHandle(
        imgWidth / 2 - _handleSize / 2,
        0,
        _ResizeHandle.top,
        SystemMouseCursors.resizeUpDown,
      ),
      _buildHandle(
        imgWidth / 2 - _handleSize / 2,
        imgHeight - _handleSize,
        _ResizeHandle.bottom,
        SystemMouseCursors.resizeUpDown,
      ),
      _buildHandle(
        0,
        imgHeight / 2 - _handleSize / 2,
        _ResizeHandle.left,
        SystemMouseCursors.resizeLeftRight,
      ),
      _buildHandle(
        imgWidth - _handleSize,
        imgHeight / 2 - _handleSize / 2,
        _ResizeHandle.right,
        SystemMouseCursors.resizeLeftRight,
      ),
    ];
  }

  Widget _buildHandle(
    double x,
    double y,
    _ResizeHandle handle,
    MouseCursor cursor,
  ) {
    final isActive = _activeHandle == handle;
    return Positioned(
      left: x,
      top: y,
      width: _handleSize,
      height: _handleSize,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isDragging = true;
            _activeHandle = handle;
            // Reset aspect ratio constraint for new drag operations
            // This allows users to "re-enable" aspect ratio by starting fresh
            _aspectRatioConstrained = true;
            // Store the handle's initial position relative to the image
            final imgWidth = widget.node.width ?? _defaultImgWidth;
            final imgHeight = widget.node.height ?? _defaultImgHeight;
            _dragStartPosition = _getHandlePosition(
              handle,
              imgWidth,
              imgHeight,
            );
          });
          // Notify document that image resize is in progress
          // This prevents text selection from interfering
          widget.document.isResizingImage = true;
        },
        onPanUpdate: (details) {
          if (_activeHandle == null || _dragStartPosition == null) return;

          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;

          final currentPos = box.globalToLocal(details.globalPosition);
          final imgWidth = widget.node.width ?? _defaultImgWidth;
          final imgHeight = widget.node.height ?? _defaultImgHeight;

          double newWidth = imgWidth;
          double newHeight = imgHeight;

          switch (_activeHandle!) {
            case _ResizeHandle.topLeft:
              newWidth = math.max(currentPos.dx, _minSize);
              newHeight = math.max(currentPos.dy, _minSize);
              break;
            case _ResizeHandle.topRight:
              newWidth = math.max(currentPos.dx, _minSize);
              newHeight = math.max(
                imgHeight - (currentPos.dy - _dragStartPosition!.dy),
                _minSize,
              );
              break;
            case _ResizeHandle.bottomLeft:
              newWidth = math.max(currentPos.dx, _minSize);
              newHeight = math.max(currentPos.dy, _minSize);
              break;
            case _ResizeHandle.bottomRight:
              newWidth = math.max(currentPos.dx, _minSize);
              newHeight = math.max(currentPos.dy, _minSize);
              break;
            case _ResizeHandle.left:
              newWidth = math.max(currentPos.dx, _minSize);
              break;
            case _ResizeHandle.right:
              newWidth = math.max(currentPos.dx, _minSize);
              break;
            case _ResizeHandle.top:
              newHeight = math.max(currentPos.dy, _minSize);
              break;
            case _ResizeHandle.bottom:
              newHeight = math.max(currentPos.dy, _minSize);
              break;
          }

          // Apply max size constraints
          newWidth = math.min(newWidth, _maxSize);
          newHeight = math.min(newHeight, _maxSize);

          // Check if aspect ratio is deviating and disable constraint if needed
          if (_aspectRatioConstrained &&
              _isAspectRatioDeviating(newWidth, newHeight)) {
            _aspectRatioConstrained = false;
          }

          // Apply aspect ratio constraint only if still enabled
          if (_aspectRatioConstrained && _originalAspectRatio != null) {
            // For corner handles, maintain aspect ratio
            if (_activeHandle == _ResizeHandle.topLeft ||
                _activeHandle == _ResizeHandle.topRight ||
                _activeHandle == _ResizeHandle.bottomLeft ||
                _activeHandle == _ResizeHandle.bottomRight) {
              // Calculate the dimension that changed more
              final widthRatio = newWidth / imgWidth;
              final heightRatio = newHeight / imgHeight;

              // Use the ratio that preserves the constraint better
              if (widthRatio > heightRatio) {
                newHeight = newWidth / _originalAspectRatio!;
              } else {
                newWidth = newHeight * _originalAspectRatio!;
              }
            }
            // For edge handles, adjust the other dimension to maintain aspect ratio
            else if (_activeHandle == _ResizeHandle.left ||
                _activeHandle == _ResizeHandle.right) {
              newHeight = newWidth / _originalAspectRatio!;
            } else if (_activeHandle == _ResizeHandle.top ||
                _activeHandle == _ResizeHandle.bottom) {
              newWidth = newHeight * _originalAspectRatio!;
            }
          }

          // Apply minimal threshold for smooth but responsive resize
          const double threshold = 1.0;

          final widthDiff = (newWidth - imgWidth).abs();
          final heightDiff = (newHeight - imgHeight).abs();

          if (widthDiff >= threshold || heightDiff >= threshold) {
            widget.node.width = newWidth;
            widget.node.height = newHeight;
            setState(() {});
          }
        },
        onPanEnd: (_) {
          setState(() {
            _isDragging = false;
            _activeHandle = null;
            _dragStartPosition = null;
          });
          // Clear the resize flag when drag ends
          widget.document.isResizingImage = false;
          // Update document only when drag ends
          widget.document.updateContent();
        },
        child: MouseRegion(
          cursor: cursor,
          child: Container(
            decoration: BoxDecoration(
              color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Offset _getHandlePosition(
    _ResizeHandle handle,
    double imgWidth,
    double imgHeight,
  ) {
    switch (handle) {
      case _ResizeHandle.topLeft:
        return Offset(0, 0);
      case _ResizeHandle.topRight:
        return Offset(imgWidth - _handleSize, 0);
      case _ResizeHandle.bottomLeft:
        return Offset(0, imgHeight - _handleSize);
      case _ResizeHandle.bottomRight:
        return Offset(imgWidth - _handleSize, imgHeight - _handleSize);
      case _ResizeHandle.top:
        return Offset(imgWidth / 2 - _handleSize / 2, 0);
      case _ResizeHandle.bottom:
        return Offset(imgWidth / 2 - _handleSize / 2, imgHeight - _handleSize);
      case _ResizeHandle.left:
        return Offset(0, imgHeight / 2 - _handleSize / 2);
      case _ResizeHandle.right:
        return Offset(imgWidth - _handleSize, imgHeight / 2 - _handleSize / 2);
    }
  }

  void _showContextMenu(Offset globalPosition) {
    showFluentContextMenu(
      context: context,
      globalPosition: globalPosition,
      items: [
        FluentContextMenuItem(
          icon: Icons.image,
          label: widget.document.labels?.replaceImage ?? 'Replace image',
          onPressed: () async {
            final result = await showImageInsertDialog(context, labels: widget.document.labels);
            if (result != null) {
              widget.node.src = result['src']!;
              widget.document.updateContent();
            }
          },
        ),
        FluentContextMenuItem(
          icon: Icons.delete,
          label: widget.document.labels?.deleteImage ?? 'Delete',
          onPressed: () {
            widget.document.saveState(description: 'Delete image', forceNewAction: true);
            removeNode(widget.document.content, widget.node);
            widget.document.updateContent();
          },
        ),
      ],
    );
  }

  /// Calculate the actual width to use for the image
  /// If the image width exceeds available width, stretch it to fit
  double _calculateActualWidth(double imageWidth, double availableWidth) {
    // If available width is 0 or infinite, return the original width
    if (availableWidth <= 0 || availableWidth == double.infinity) {
      return imageWidth;
    }

    // If image width is greater than available width, stretch to fit
    if (imageWidth > availableWidth) {
      return availableWidth;
    }

    // Otherwise, use the original width
    return imageWidth;
  }

  /// Calculate the actual height maintaining aspect ratio
  double _calculateActualHeight(
    double imageHeight,
    double actualWidth,
    double originalWidth,
  ) {
    // If we're stretching the width, adjust height to maintain aspect ratio
    if (actualWidth != originalWidth && originalWidth > 0) {
      final aspectRatio = imageHeight / originalWidth;
      return actualWidth * aspectRatio;
    }

    return imageHeight;
  }
}

enum _ResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

class _CaretLine extends StatelessWidget {
  const _CaretLine();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(width: 2, child: ColoredBox(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
