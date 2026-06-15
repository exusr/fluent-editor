import 'package:json_annotation/json_annotation.dart';

part 'styles.g.dart';

/// Defines a paragraph style with formatting properties.
/// Can be used as a base for "Normal Text", "Heading 1", etc.
@JsonSerializable()
class ParagraphStyle {
  /// Identifier name of the style (e.g. "heading1", "normal")
  String name;

  /// Display name (e.g. "Heading 1", "Normal Text")
  String displayName;

  /// Font family
  String? fontFamily;

  /// Font size in points
  double? fontSize;

  /// Applied inline styles (bold, italic, underline)
  List<String>? styles;

  /// Text color (hex)
  String? color;

  /// Highlight color (hex)
  String? highlightColor;

  /// Text alignment (left, center, right, justify)
  String? textAlign;

  /// Line height
  double? lineHeight;

  /// Spacing before the paragraph
  double? spacingBefore;

  /// Spacing after the paragraph
  double? spacingAfter;

  /// Indentation level
  int? indent;

  ParagraphStyle({
    required this.name,
    required this.displayName,
    this.fontFamily,
    this.fontSize,
    this.styles,
    this.color,
    this.highlightColor,
    this.textAlign,
    this.lineHeight,
    this.spacingBefore,
    this.spacingAfter,
    this.indent,
  });

  /// Predefined styles
  static final ParagraphStyle normal = ParagraphStyle(
    name: 'normal',
    displayName: 'Normal Text',
    fontFamily: 'DejaVu Sans',
    fontSize: 14.0,
    styles: [],
    textAlign: 'left',
  );

  static final ParagraphStyle heading1 = ParagraphStyle(
    name: 'heading1',
    displayName: 'Heading 1',
    fontFamily: 'DejaVu Sans',
    fontSize: 28.0,
    styles: ['bold'],
    textAlign: 'left',
    spacingBefore: 24.0,
    spacingAfter: 12.0,
  );

  static final ParagraphStyle heading2 = ParagraphStyle(
    name: 'heading2',
    displayName: 'Heading 2',
    fontFamily: 'DejaVu Sans',
    fontSize: 22.0,
    styles: ['bold'],
    textAlign: 'left',
    spacingBefore: 20.0,
    spacingAfter: 10.0,
  );

  static final ParagraphStyle heading3 = ParagraphStyle(
    name: 'heading3',
    displayName: 'Heading 3',
    fontFamily: 'DejaVu Sans',
    fontSize: 18.0,
    styles: ['bold'],
    textAlign: 'left',
    spacingBefore: 16.0,
    spacingAfter: 8.0,
  );

  static final ParagraphStyle heading4 = ParagraphStyle(
    name: 'heading4',
    displayName: 'Heading 4',
    fontFamily: 'DejaVu Sans',
    fontSize: 16.0,
    styles: ['bold'],
    textAlign: 'left',
    spacingBefore: 14.0,
    spacingAfter: 6.0,
  );

  static final ParagraphStyle heading5 = ParagraphStyle(
    name: 'heading5',
    displayName: 'Heading 5',
    fontFamily: 'DejaVu Sans',
    fontSize: 14.0,
    styles: ['bold'],
    textAlign: 'left',
    spacingBefore: 12.0,
    spacingAfter: 4.0,
  );

  static final ParagraphStyle heading6 = ParagraphStyle(
    name: 'heading6',
    displayName: 'Heading 6',
    fontFamily: 'DejaVu Sans',
    fontSize: 13.0,
    styles: ['bold'],
    textAlign: 'left',
    spacingBefore: 10.0,
    spacingAfter: 2.0,
  );

  static final ParagraphStyle quote = ParagraphStyle(
    name: 'quote',
    displayName: 'Quote',
    fontFamily: 'Georgia',
    fontSize: 14.0,
    styles: ['italic'],
    textAlign: 'left',
    indent: 2,
    spacingBefore: 12.0,
    spacingAfter: 12.0,
  );

  static final ParagraphStyle code = ParagraphStyle(
    name: 'code',
    displayName: 'Code',
    fontFamily: 'Courier New',
    fontSize: 13.0,
    styles: [],
    textAlign: 'left',
    spacingBefore: 8.0,
    spacingAfter: 8.0,
  );

  /// List of all predefined styles
  static final List<ParagraphStyle> predefinedStyles = [
    normal,
    heading1,
    heading2,
    heading3,
    heading4,
    heading5,
    heading6,
    quote,
    code,
  ];

  factory ParagraphStyle.fromJson(Map<String, dynamic> json) =>
      _$ParagraphStyleFromJson(json);

  Map<String, dynamic> toJson() => _$ParagraphStyleToJson(this);

  /// Creates a copy with some fields modified
  ParagraphStyle copyWith({
    String? name,
    String? displayName,
    String? fontFamily,
    double? fontSize,
    List<String>? styles,
    String? color,
    String? highlightColor,
    String? textAlign,
    double? lineHeight,
    double? spacingBefore,
    double? spacingAfter,
    int? indent,
  }) {
    return ParagraphStyle(
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      styles: styles ?? this.styles,
      color: color ?? this.color,
      highlightColor: highlightColor ?? this.highlightColor,
      textAlign: textAlign ?? this.textAlign,
      lineHeight: lineHeight ?? this.lineHeight,
      spacingBefore: spacingBefore ?? this.spacingBefore,
      spacingAfter: spacingAfter ?? this.spacingAfter,
      indent: indent ?? this.indent,
    );
  }
}
