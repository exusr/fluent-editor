import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/utils/color_utils.dart';
import 'package:fluent_editor/widgets/shared/color_picker_widgets.dart';
import 'package:flutter/material.dart';

class FluentHighlightColorButton extends StatelessWidget {
  final FluentDocument document;
  final FluentEditorLabels? labels;

  const FluentHighlightColorButton({super.key, required this.document, this.labels});

  String? _resolveCurrentColor() {
    return document.pendingHighlightColor;
  }

  void _showColorPicker(BuildContext context) {
    final currentColor = _resolveCurrentColor();
    final labels = this.labels ?? document.labels ?? const FluentEditorLabels();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(labels.highlightColor),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ColorChip(
                      label: 'None',
                      isSelected: currentColor == null || currentColor.isEmpty,
                      onTap: () {
                        document.saveState(description: 'Highlight color', forceNewAction: true);
                        document.eventHandler.handleHighlightColor(null);
                        document.requestEditorFocus();
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                    for (final hex in presetHighlightColors)
                      ColorChip(
                        color: ColorUtils.parseColor(hex),
                        isSelected: currentColor == hex,
                        onTap: () {
                          document.saveState(description: 'Highlight color', forceNewAction: true);
                          document.eventHandler.handleHighlightColor(hex);
                          document.requestEditorFocus();
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => _showCustomColorPicker(dialogContext, currentColor),
                  child: const Text('Custom color'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(labels.cancel),
            ),
          ],
        );
      },
    );
  }

  void _showCustomColorPicker(BuildContext context, String? currentColor) {
    final initialColor = ColorUtils.parseColor(currentColor) ?? const Color(0xFFFFFF00);
    Color selectedColor = initialColor;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Custom highlight color'),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        color: selectedColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ColorSlider(
                      label: 'R',
                      value: (selectedColor.r * 255.0).round().toDouble(),
                      maxValue: 255,
                      color: Colors.red,
                      onChanged: (value) {
                        setState(() {
                          selectedColor = Color.fromARGB(
                            (selectedColor.a * 255.0).round(), value.toInt(),
                            (selectedColor.g * 255.0).round(), (selectedColor.b * 255.0).round(),
                          );
                        });
                      },
                    ),
                    ColorSlider(
                      label: 'G',
                      value: (selectedColor.g * 255.0).round().toDouble(),
                      maxValue: 255,
                      color: Colors.green,
                      onChanged: (value) {
                        setState(() {
                          selectedColor = Color.fromARGB(
                            (selectedColor.a * 255.0).round(), (selectedColor.r * 255.0).round(),
                            value.toInt(), (selectedColor.b * 255.0).round(),
                          );
                        });
                      },
                    ),
                    ColorSlider(
                      label: 'B',
                      value: (selectedColor.b * 255.0).round().toDouble(),
                      maxValue: 255,
                      color: Colors.blue,
                      onChanged: (value) {
                        setState(() {
                          selectedColor = Color.fromARGB(
                            (selectedColor.a * 255.0).round(), (selectedColor.r * 255.0).round(),
                            (selectedColor.g * 255.0).round(), value.toInt(),
                          );
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    document.saveState(description: 'Highlight color', forceNewAction: true);
                    final hexColor = ColorUtils.colorToHex(selectedColor);
                    document.eventHandler.handleHighlightColor(hexColor);
                    document.requestEditorFocus();
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _resolveCurrentColor();
    final colorSwatch = ColorUtils.parseColor(currentColor);

    return Tooltip(
      message: 'Highlight',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: InkWell(
          onTap: () => _showColorPicker(context),
          borderRadius: BorderRadius.circular(4),
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.border_color, size: 20, color: colorSwatch),
          ),
        ),
      ),
    );
  }
}