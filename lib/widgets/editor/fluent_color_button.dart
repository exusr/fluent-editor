import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/utils/color_utils.dart';
import 'package:fluent_editor/widgets/shared/color_picker_widgets.dart';
import 'package:flutter/material.dart';

/// A reusable color picker button for text color or highlight color.
class FluentColorButton extends StatelessWidget {
  final FluentDocument document;
  final FluentEditorLabels? labels;

  /// Dialog title and tooltip text.
  final String title;

  /// Label for the "none/auto" chip.
  final String noneLabel;

  /// Preset color hex list to show as chips.
  final List<String> presets;

  /// Description used in saveState.
  final String saveStateDescription;

  /// Default color for the custom color picker.
  final Color defaultCustomColor;

  /// Title for the custom color dialog.
  final String customDialogTitle;

  /// Icon to display.
  final IconData icon;

  /// Resolves the current color from the document.
  final String? Function(FluentDocument) resolveColor;

  /// Applies the selected color via the event handler.
  final void Function(String?) handleColor;

  const FluentColorButton({
    super.key,
    required this.document,
    this.labels,
    required this.title,
    required this.noneLabel,
    required this.presets,
    required this.saveStateDescription,
    required this.defaultCustomColor,
    required this.customDialogTitle,
    required this.icon,
    required this.resolveColor,
    required this.handleColor,
  });

  void _showColorPicker(BuildContext context) {
    final currentColor = resolveColor(document);
    final effectiveLabels = labels ?? document.labels ?? const FluentEditorLabels();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
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
                      label: noneLabel,
                      isSelected: currentColor == null || currentColor.isEmpty,
                      onTap: () {
                        document.saveState(description: saveStateDescription, forceNewAction: true);
                        handleColor(null);
                        document.requestEditorFocus();
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                    for (final hex in presets)
                      ColorChip(
                        color: ColorUtils.parseColor(hex),
                        isSelected: currentColor == hex,
                        onTap: () {
                          document.saveState(description: saveStateDescription, forceNewAction: true);
                          handleColor(hex);
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
              child: Text(effectiveLabels.cancel),
            ),
          ],
        );
      },
    );
  }

  void _showCustomColorPicker(BuildContext context, String? currentColor) {
    final initialColor = ColorUtils.parseColor(currentColor) ?? defaultCustomColor;
    Color selectedColor = initialColor;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(customDialogTitle),
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
                    document.saveState(description: saveStateDescription, forceNewAction: true);
                    final hexColor = ColorUtils.colorToHex(selectedColor);
                    handleColor(hexColor);
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
    final currentColor = resolveColor(document);
    final colorSwatch = ColorUtils.parseColor(currentColor);

    return Tooltip(
      message: title,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: InkWell(
          onTap: () => _showColorPicker(context),
          borderRadius: BorderRadius.circular(4),
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: colorSwatch),
          ),
        ),
      ),
    );
  }
}
