import 'package:flutter/material.dart';

/// Preset colors for the text color picker (common palette).
const presetColors = [
  '#000000',
  '#424242',
  '#757575',
  '#BDBDBD',
  '#FFFFFF',
  '#F44336',
  '#E91E63',
  '#9C27B0',
  '#673AB7',
  '#3F51B5',
  '#2196F3',
  '#03A9F4',
  '#00BCD4',
  '#009688',
  '#4CAF50',
  '#8BC34A',
  '#CDDC39',
  '#FFEB3B',
  '#FFC107',
  '#FF9800',
  '#FF5722',
  '#795548',
];

/// Preset colors for the highlight color picker (marker palette).
const presetHighlightColors = [
  '#FFFF00',
  '#FFEB3B',
  '#FFC107',
  '#FF9800',
  '#FF5722',
  '#F44336',
  '#E91E63',
  '#9C27B0',
  '#673AB7',
  '#3F51B5',
  '#2196F3',
  '#03A9F4',
  '#00BCD4',
  '#009688',
  '#4CAF50',
  '#8BC34A',
  '#CDDC39',
  '#E0E0E0',
  '#BDBDBD',
  '#9E9E9E',
];

/// Utility functions for color operations.
class ColorUtils {
  /// Parses a hex color string to a Color object.
  /// Supports 7-character hex (#RRGGBB) and 9-character hex (#AARRGGBB).
  /// Returns null if the hex string is invalid.
  static Color? parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      if (hex.length == 7 && hex.startsWith('#')) {
        return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
      }
      if (hex.length == 9 && hex.startsWith('#')) {
        return Color(int.parse(hex.substring(1), radix: 16));
      }
    } catch (_) {}
    return null;
  }

  /// Converts a Color object to a hex string.
  static String colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }
}
