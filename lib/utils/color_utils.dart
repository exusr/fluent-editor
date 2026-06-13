import 'package:flutter/material.dart';

/// Preset colors for the text color picker (common palette).
const presetColors = [
  '#000000', // Black
  '#424242', // Dark gray
  '#757575', // Medium gray
  '#BDBDBD', // Light gray
  '#FFFFFF', // White
  '#F44336', // Red
  '#E91E63', // Pink
  '#9C27B0', // Purple
  '#673AB7', // Deep purple
  '#3F51B5', // Indigo
  '#2196F3', // Blue
  '#03A9F4', // Light blue
  '#00BCD4', // Cyan
  '#009688', // Teal
  '#4CAF50', // Green
  '#8BC34A', // Light green
  '#CDDC39', // Lime
  '#FFEB3B', // Yellow
  '#FFC107', // Amber
  '#FF9800', // Orange
  '#FF5722', // Deep orange
  '#795548', // Brown
];

/// Preset colors for the highlight color picker (marker palette).
const presetHighlightColors = [
  '#FFFF00', // Yellow (classic marker)
  '#FFEB3B', // Light yellow
  '#FFC107', // Amber
  '#FF9800', // Orange
  '#FF5722', // Deep orange
  '#F44336', // Red
  '#E91E63', // Pink
  '#9C27B0', // Purple
  '#673AB7', // Deep purple
  '#3F51B5', // Indigo
  '#2196F3', // Blue
  '#03A9F4', // Light blue
  '#00BCD4', // Cyan
  '#009688', // Teal
  '#4CAF50', // Green
  '#8BC34A', // Light green
  '#CDDC39', // Lime
  '#E0E0E0', // Light gray
  '#BDBDBD', // Medium gray
  '#9E9E9E', // Dark gray
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
