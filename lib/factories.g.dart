// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'factories.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FNode _$FNodeFromJson(Map<String, dynamic> json) => FNode(
      json['id'] as String,
    );

Map<String, dynamic> _$FNodeToJson(FNode instance) => <String, dynamic>{
      'id': instance.id,
    };

Root _$RootFromJson(Map<String, dynamic> json) => Root(
      nodes: (json['nodes'] as List<dynamic>?)
          ?.map((e) =>
              const FNodeJsonConverter().fromJson(e as Map<String, dynamic>))
          .toList(),
    )
      ..id = json['id'] as String
      ..type = json['type'] as String;

Map<String, dynamic> _$RootToJson(Root instance) => <String, dynamic>{
      'id': instance.id,
      'nodes': instance.nodes.map(const FNodeJsonConverter().toJson).toList(),
      'type': instance.type,
    };

Fragment _$FragmentFromJson(Map<String, dynamic> json) => Fragment(
      json['text'] as String,
      styles:
          (json['styles'] as List<dynamic>?)?.map((e) => e as String).toList(),
      fontFamily: json['fontFamily'] as String? ?? 'DejaVu Sans',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      color: json['color'] as String?,
      highlightColor: json['highlightColor'] as String?,
    )
      ..id = json['id'] as String
      ..type = json['type'] as String;

Map<String, dynamic> _$FragmentToJson(Fragment instance) => <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'type': instance.type,
      'styles': instance.styles,
      'fontFamily': instance.fontFamily,
      'fontSize': instance.fontSize,
      'color': instance.color,
      'highlightColor': instance.highlightColor,
    };

FluentImage _$FluentImageFromJson(Map<String, dynamic> json) => FluentImage(
      json['src'] as String,
    )
      ..id = json['id'] as String
      ..styles =
          (json['styles'] as List<dynamic>?)?.map((e) => e as String).toList()
      ..fontFamily = json['fontFamily'] as String
      ..fontSize = (json['fontSize'] as num).toDouble()
      ..color = json['color'] as String?
      ..highlightColor = json['highlightColor'] as String?
      ..type = json['type'] as String
      ..text = json['text'] as String
      ..textAlign = json['textAlign'] as String
      ..width = (json['width'] as num?)?.toDouble()
      ..height = (json['height'] as num?)?.toDouble();

Map<String, dynamic> _$FluentImageToJson(FluentImage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'styles': instance.styles,
      'fontFamily': instance.fontFamily,
      'fontSize': instance.fontSize,
      'color': instance.color,
      'highlightColor': instance.highlightColor,
      'src': instance.src,
      'type': instance.type,
      'text': instance.text,
      'textAlign': instance.textAlign,
      'width': instance.width,
      'height': instance.height,
    };

Paragraph _$ParagraphFromJson(Map<String, dynamic> json) => Paragraph(
      text: json['text'] as String? ?? "",
      textAlign: json['textAlign'] as String? ?? 'left',
      indent: (json['indent'] as num?)?.toInt() ?? 0,
      styleName: json['styleName'] as String?,
    )
      ..id = json['id'] as String
      ..type = json['type'] as String
      ..fragments = (json['fragments'] as List<dynamic>)
          .map((e) =>
              const FNodeJsonConverter().fromJson(e as Map<String, dynamic>))
          .toList();

Map<String, dynamic> _$ParagraphToJson(Paragraph instance) => <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'fragments':
          instance.fragments.map(const FNodeJsonConverter().toJson).toList(),
      'textAlign': instance.textAlign,
      'indent': instance.indent,
      'styleName': instance.styleName,
      'text': instance.text,
    };

Link _$LinkFromJson(Map<String, dynamic> json) => Link(
      url: json['url'] as String,
      text: json['text'] as String?,
    )
      ..id = json['id'] as String
      ..fragments = (json['fragments'] as List<dynamic>)
          .map((e) =>
              const FNodeJsonConverter().fromJson(e as Map<String, dynamic>))
          .toList()
      ..textAlign = json['textAlign'] as String
      ..indent = (json['indent'] as num).toInt()
      ..styleName = json['styleName'] as String?
      ..type = json['type'] as String
      ..styles =
          (json['styles'] as List<dynamic>?)?.map((e) => e as String).toList()
      ..fontFamily = json['fontFamily'] as String
      ..fontSize = (json['fontSize'] as num).toDouble()
      ..color = json['color'] as String?
      ..highlightColor = json['highlightColor'] as String?;

Map<String, dynamic> _$LinkToJson(Link instance) => <String, dynamic>{
      'id': instance.id,
      'fragments':
          instance.fragments.map(const FNodeJsonConverter().toJson).toList(),
      'textAlign': instance.textAlign,
      'indent': instance.indent,
      'styleName': instance.styleName,
      'url': instance.url,
      'text': instance.text,
      'type': instance.type,
      'styles': instance.styles,
      'fontFamily': instance.fontFamily,
      'fontSize': instance.fontSize,
      'color': instance.color,
      'highlightColor': instance.highlightColor,
    };

FluentList _$FluentListFromJson(Map<String, dynamic> json) => FluentList(
      listType: json['listType'] as String,
    )
      ..id = json['id'] as String
      ..fragments = (json['fragments'] as List<dynamic>)
          .map((e) =>
              const FNodeJsonConverter().fromJson(e as Map<String, dynamic>))
          .toList()
      ..textAlign = json['textAlign'] as String
      ..indent = (json['indent'] as num).toInt()
      ..styleName = json['styleName'] as String?
      ..type = json['type'] as String
      ..items = (json['items'] as List<dynamic>)
          .map((e) => ListItem.fromJson(e as Map<String, dynamic>))
          .toList();

Map<String, dynamic> _$FluentListToJson(FluentList instance) =>
    <String, dynamic>{
      'id': instance.id,
      'fragments':
          instance.fragments.map(const FNodeJsonConverter().toJson).toList(),
      'textAlign': instance.textAlign,
      'indent': instance.indent,
      'styleName': instance.styleName,
      'type': instance.type,
      'listType': instance.listType,
      'items': instance.items,
    };

ListItem _$ListItemFromJson(Map<String, dynamic> json) => ListItem(
      bulletType: json['bulletType'] as String,
      indexList: (json['indexList'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList(),
      children: (json['children'] as List<dynamic>?)
          ?.map((e) =>
              const FNodeJsonConverter().fromJson(e as Map<String, dynamic>))
          .toList(),
    )
      ..id = json['id'] as String
      ..fragments = (json['fragments'] as List<dynamic>)
          .map((e) => FNode.fromJson(e as Map<String, dynamic>))
          .toList()
      ..text = json['text'] as String;

Map<String, dynamic> _$ListItemToJson(ListItem instance) => <String, dynamic>{
      'id': instance.id,
      'bulletType': instance.bulletType,
      'indexList': instance.indexList,
      'children':
          instance.children.map(const FNodeJsonConverter().toJson).toList(),
      'fragments': instance.fragments,
      'text': instance.text,
    };

FluentTable _$FluentTableFromJson(Map<String, dynamic> json) => FluentTable(
      rows: (json['rows'] as List<dynamic>?)
          ?.map((e) => FluentRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      columnWidths: (json['columnWidths'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      tableWidth: (json['tableWidth'] as num?)?.toDouble(),
    )..id = json['id'] as String;

Map<String, dynamic> _$FluentTableToJson(FluentTable instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tableWidth': instance.tableWidth,
      'columnWidths': instance.columnWidths,
      'rows': instance.rows,
    };

FluentRow _$FluentRowFromJson(Map<String, dynamic> json) => FluentRow(
      cells: (json['cells'] as List<dynamic>?)
          ?.map((e) => FluentCell.fromJson(e as Map<String, dynamic>))
          .toList(),
      rowHeight: (json['rowHeight'] as num?)?.toDouble(),
    )..id = json['id'] as String;

Map<String, dynamic> _$FluentRowToJson(FluentRow instance) => <String, dynamic>{
      'id': instance.id,
      'rowHeight': instance.rowHeight,
      'cells': instance.cells,
    };

FluentCell _$FluentCellFromJson(Map<String, dynamic> json) => FluentCell(
      children: (json['children'] as List<dynamic>?)
          ?.map((e) =>
              const FNodeJsonConverter().fromJson(e as Map<String, dynamic>))
          .toList(),
    )
      ..id = json['id'] as String
      ..colSpan = (json['colSpan'] as num).toInt()
      ..rowSpan = (json['rowSpan'] as num).toInt();

Map<String, dynamic> _$FluentCellToJson(FluentCell instance) =>
    <String, dynamic>{
      'id': instance.id,
      'colSpan': instance.colSpan,
      'rowSpan': instance.rowSpan,
      'children':
          instance.children.map(const FNodeJsonConverter().toJson).toList(),
    };
