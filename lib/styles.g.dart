// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'styles.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ParagraphStyle _$ParagraphStyleFromJson(Map<String, dynamic> json) =>
    ParagraphStyle(
      name: json['name'] as String,
      displayName: json['displayName'] as String,
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      styles:
          (json['styles'] as List<dynamic>?)?.map((e) => e as String).toList(),
      color: json['color'] as String?,
      highlightColor: json['highlightColor'] as String?,
      textAlign: json['textAlign'] as String?,
      lineHeight: (json['lineHeight'] as num?)?.toDouble(),
      spacingBefore: (json['spacingBefore'] as num?)?.toDouble(),
      spacingAfter: (json['spacingAfter'] as num?)?.toDouble(),
      indent: (json['indent'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ParagraphStyleToJson(ParagraphStyle instance) =>
    <String, dynamic>{
      'name': instance.name,
      'displayName': instance.displayName,
      'fontFamily': instance.fontFamily,
      'fontSize': instance.fontSize,
      'styles': instance.styles,
      'color': instance.color,
      'highlightColor': instance.highlightColor,
      'textAlign': instance.textAlign,
      'lineHeight': instance.lineHeight,
      'spacingBefore': instance.spacingBefore,
      'spacingAfter': instance.spacingAfter,
      'indent': instance.indent,
    };
