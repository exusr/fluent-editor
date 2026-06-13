import 'package:flutter/material.dart';

/// A color chip widget for color selection.
class ColorChip extends StatelessWidget {
  final String? label;
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const ColorChip({
    super.key,
    this.label,
    this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color ?? theme.colorScheme.surface,
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: label != null
            ? Center(
                child: Text(
                  label!,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// A color slider widget for RGB color selection.
class ColorSlider extends StatelessWidget {
  final String label;
  final double value;
  final double maxValue;
  final Color color;
  final ValueChanged<double> onChanged;

  const ColorSlider({
    super.key,
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: maxValue,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 35,
          child: Text(
            value.toInt().toString(),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
