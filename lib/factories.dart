import 'dart:collection';
import 'dart:math' as math;
import 'package:fluent_editor/core/constants.dart';
import 'package:fluent_editor/styles.dart';
import 'package:nanoid/nanoid.dart';
import 'package:json_annotation/json_annotation.dart';

part 'factories.g.dart';

abstract class InlineContainerNode {
  List<FNode> get fragments;
  List<FNode> getChildren();
  String get text;
}

class FNodeJsonConverter implements JsonConverter<FNode, Map<String, dynamic>> {
  const FNodeJsonConverter();

  @override
  FNode fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'paragraph':
        return Paragraph.fromJson(json);
      case 'link':
        return Link.fromJson(json);
      case 'list':
        return FluentList.fromJson(json);
      case 'listItem':
        return ListItem.fromJson(json);
      case 'row':
        return FluentRow.fromJson(json);
      case 'cell':
        return FluentCell.fromJson(json);
      case 'table':
        return FluentTable.fromJson(json);
      case 'image':
        return FluentImage.fromJson(json);
      case 'hr':
        return HorizontalRule.fromJson(json);
      case 'fragment':
        return Fragment.fromJson(json);
      default:
        throw Exception('Unknown node type: $type');
    }
  }

  @override
  Map<String, dynamic> toJson(FNode object) => object.toJson();
}

@JsonSerializable()
class FNode {
  String id;

  FNode(this.id);
  
  factory FNode.fromJson(Map<String, dynamic> json) => _$FNodeFromJson(json);
  Map<String, dynamic> toJson() => _$FNodeToJson(this);
}


@JsonSerializable()
class Root extends FNode implements InlineContainerNode {
  @FNodeJsonConverter()
  List<FNode> nodes;
  String type = 'root';

  @override
  List<FNode> get fragments => nodes;

  @override
  List<FNode> getChildren() {
    return nodes;
  }

  @override
  String get text => nodes.map((n) => (n as InlineContainerNode).text).join();

  Root({List<FNode>? nodes})
      : nodes = nodes ?? [],
        super(nanoid());

  factory Root.fromJson(Map<String, dynamic> json) => _$RootFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$RootToJson(this);
}

@JsonSerializable()
class Fragment extends FNode {
  String text;
  String type = 'fragment';

  /// List of applied inline styles, e.g. ['bold'], ['italic'], ['bold','italic'].
  List<String>? styles;

  /// Font family for this fragment (e.g. 'DejaVu Sans', 'Roboto').
  String fontFamily = 'DejaVu Sans';

  /// Font size in points (e.g. 14.0).
  double fontSize = 14.0;

  /// Text color in hex format (e.g. '#FF0000'). Null = auto (default color).
  String? color;

  /// Highlight color (background) in hex format. Null = no highlight.
  String? highlightColor;

  Fragment(this.text, {
    this.styles,
    this.fontFamily = 'DejaVu Sans',
    this.fontSize = 14.0,
    this.color,
    this.highlightColor,
  }) : super(nanoid());

  String get renderText => text;

  bool get isBold => styles?.contains('bold') ?? false;

  factory Fragment.fromJson(Map<String, dynamic> json) {
    final fragment = _$FragmentFromJson(json);
    fragment.styles = (json['styles'] as List<dynamic>?)?.cast<String>();
    fragment.fontFamily = json['fontFamily'] as String;
    fragment.fontSize = (json['fontSize'] as num?)?.toDouble() ?? 14.0;
    fragment.color = json['color'] as String?;
    fragment.highlightColor = json['highlightColor'] as String?;
    return fragment;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = _$FragmentToJson(this);
    if (styles != null && styles!.isNotEmpty) {
      json['styles'] = styles;
    }
    json['fontFamily'] = fontFamily;
    if (fontSize != 14.0) {
      json['fontSize'] = fontSize;
    }
    if (color != null) {
      json['color'] = color;
    }
    if (highlightColor != null) {
      json['highlightColor'] = highlightColor;
    }
    return json;
  }
}

/// Atomic node representing a horizontal line (<hr>).
/// Extends Fragment (like FluentImage) to participate in the
/// selection and copy/paste system. Has 2 caret stops (offset 0 and 1), no children.
class HorizontalRule extends Fragment implements InlineContainerNode {
  @override
  String get type => 'hr';

  @override
  String get text => Whitespaces.zws;

  HorizontalRule() : super(nanoid());

  @override
  List<FNode> get fragments => const [];

  @override
  List<FNode> getChildren() => const [];

  factory HorizontalRule.fromJson(Map<String, dynamic> json) {
    final hr = HorizontalRule();
    hr.id = json['id'] as String? ?? hr.id;
    return hr;
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'hr', 'id': id};
}

@JsonSerializable()
class FluentImage extends Fragment implements InlineContainerNode {
  String src;

  @override
  String get type => 'image';
  
  @override
  String get text => Whitespaces.zws;

  /// Alignment when the image is block-level (left, center, right).
  String textAlign = 'left';

  /// Image width in pixels. null = default width
  double? width;
  
  /// Image height in pixels. null = default height  
  double? height;

  @override
  FluentImage(this.src) : super(nanoid());

  /// FluentImage can behave as an "atomic container" when it is
  /// block-level (direct child of Root/ListItem/FluentCell): in that case
  /// it is its own LogicalLine. Has no children.
  @override
  List<FNode> get fragments => const [];

  @override
  List<FNode> getChildren() => const [];

  factory FluentImage.fromJson(Map<String, dynamic> json) {
    final img = _$FluentImageFromJson(json);
    img.textAlign = (json['textAlign'] as String?) ?? 'left';
    img.width = (json['width'] as num?)?.toDouble();
    img.height = (json['height'] as num?)?.toDouble();
    return img;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = _$FluentImageToJson(this);
    if (textAlign != 'left') json['textAlign'] = textAlign;
    if (width != null) json['width'] = width;
    if (height != null) json['height'] = height;
    return json;
  }
}

@JsonSerializable()
class Paragraph extends FNode implements InlineContainerNode {
  String type = 'paragraph';

  @override
  @FNodeJsonConverter()
  List<FNode> fragments;

  /// Text alignment (left, center, right, justify).
  String textAlign = 'left';

  /// Paragraph indentation level (0 = no indentation).
  int indent = 0;

  /// Style applied to the paragraph (e.g. "normal", "heading1").
  /// If null, uses the explicit properties of the paragraph.
  String? styleName;

  @override
  String get text => fragments.map((f) => (f as Fragment).text).join();

  Paragraph({
    String text = "",
    this.textAlign = 'left',
    this.indent = 0,
    this.styleName,
  }) : fragments = [Fragment(text)],
       super(nanoid());

  @override
  List<FNode> getChildren() {
    return fragments;
  }

  factory Paragraph.fromJson(Map<String, dynamic> json) {
    final p = _$ParagraphFromJson(json);
    p.textAlign = (json['textAlign'] as String?) ?? 'left';
    p.indent = (json['indent'] as int?) ?? 0;
    p.styleName = json['styleName'] as String?;
    return p;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = _$ParagraphToJson(this);
    if (textAlign != 'left') json['textAlign'] = textAlign;
    if (indent != 0) json['indent'] = indent;
    if (styleName != null && styleName != 'normal') {
      json['styleName'] = styleName;
    }
    return json;
  }

  /// Gets the style applied to this paragraph.
  /// If styleName is null or not found, returns the "normal" style.
  ParagraphStyle getStyle() {
    if (styleName == null) return ParagraphStyle.normal;
    return ParagraphStyle.predefinedStyles.firstWhere(
      (s) => s.name == styleName,
      orElse: () => ParagraphStyle.normal,
    );
  }

  /// Applies a style to the paragraph, overriding the properties.
  void applyStyle(ParagraphStyle style) {
    styleName = style.name;
    if (style.textAlign != null) textAlign = style.textAlign!;
    if (style.indent != null) indent = style.indent!;
  }
}

@JsonSerializable()
class Link extends Paragraph implements Fragment, InlineContainerNode {
  String url;

  @override
  String get text => fragments.map((f) => (f as Fragment).text).join();
  
  @override
  set text(String value) {
    fragments = [Fragment(value)];
  }

  @override
  String get renderText => text;
  
  @override
  String get type => 'link';

  // Link implements Fragment → override of new members
  @override
  List<String>? get styles => null;
  @override
  set styles(List<String>? value) {}
  @override
  bool get isBold => false;

  @override
  String get fontFamily => 'DejaVu Sans';
  @override
  set fontFamily(String? value) {}

  @override
  double get fontSize => 14.0;
  @override
  set fontSize(double value) {}

  @override
  String? get color => null;
  @override
  set color(String? value) {}

  @override
  String? get highlightColor => null;
  @override
  set highlightColor(String? value) {}

  Link({required this.url, String? text})
    : super(text: text ?? url);

  @override
  List<FNode> getChildren() {
    return fragments;
  }

  factory Link.fromJson(Map<String, dynamic> json) => _$LinkFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$LinkToJson(this);
}

@JsonSerializable()
class FluentList extends Paragraph implements InlineContainerNode {
  @override
  String get type => 'list';
  String listType;
  
  @FNodeJsonConverter()
  @JsonKey(name: 'items')
  List<ListItem> _items = [];
  
  List<ListItem> get items => _items;// TrackedList(_items, () => applyListMarkers(_items));
  
  set items(List<ListItem> value) {
    _items = value;
    //applyListMarkers(value);
  }
  
  FluentList({required this.listType}) : super();
  
  @override
  List<ListItem> getChildren() {
    return _items;
  }

  @override
  String get text {
    //applyListMarkers(_items);
    return _items.map((item) => item.text).join();
  }

  //@override
  //@FNodeJsonConverter()
  //List<FNode> get fragments => TrackedList(_items, () => applyListMarkers(_items));
  
  factory FluentList.fromJson(Map<String, dynamic> json) => _$FluentListFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$FluentListToJson(this);
}

/// ListItem as a generic container for list elements.
/// Can contain paragraphs, images, tables, etc. as children.
@JsonSerializable()
class ListItem extends FNode implements InlineContainerNode {
  String bulletType;
  List<int> indexList;

  String get type => 'listItem';

  @FNodeJsonConverter()
  List<FNode> children;

  ListItem({required this.bulletType, required this.indexList, List<FNode>? children})
      : children = children ?? [Paragraph()], // Default: an empty paragraph
        super(nanoid());

  @override
  List<FNode> getChildren() => children;

  /// Compatibility getter: aggregates all Fragments from Paragraph children
  @override
  List<FNode> get fragments {
    final result = <FNode>[];
    for (final child in children) {
      if (child is InlineContainerNode) {
        result.addAll((child as InlineContainerNode).fragments);
      } else if (child is Fragment) {
        result.add(child);
      }
    }
    return result;
  }

  /// Compatibility getter: returns concatenated text from Paragraph children
  @override
  String get text {
    return children
        .whereType<InlineContainerNode>()
        .map((c) => c.text)
        .join();
  }

  String get renderText => text;

  set text(String value) {}

  /// Compatibility setter: allows assigning fragments (creates Paragraph wrapper)
  set fragments(List<FNode> value) {
    // Replace children with Paragraph containing the fragments
    children = [Paragraph()..fragments = value];
  }

  factory ListItem.fromJson(Map<String, dynamic> json) {
    // BUG WORKAROUND: _$ListItemFromJson first calls ..children = [...] then
    // ..fragments = [...]. The `fragments` setter of ListItem overrides
    // children with a single wrapper Paragraph, destroying the actual
    // structure (e.g. nested sublists). Restore the real children from JSON.
    final item = _$ListItemFromJson(json);
    final rawChildren = json['children'] as List<dynamic>?;
    if (rawChildren != null) {
      item.children = rawChildren
          .map((e) =>
              const FNodeJsonConverter().fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return item;
  }

  @override
  Map<String, dynamic> toJson() => _$ListItemToJson(this);
}

@JsonSerializable()
class FluentTable extends FNode implements InlineContainerNode {
  String get type => 'table';
  
  @FNodeJsonConverter()
  @JsonKey(name: 'rows')
  List<FluentRow> _rows = [];

  /// Total width of the table (in logical pixels).
  /// If null, occupies all available width.
  double? tableWidth;

  /// Explicit widths for each column (in logical pixels).
  /// If null or length different from number of columns, it is ignored
  /// and calculated uniformly by the renderer.
  List<double>? columnWidths;
  
  List<FluentRow> get rows => _rows;
  
  set rows(List<FluentRow> value) {
    _rows = value;
  }
  
  @override
  List<FluentRow> getChildren() {
    return _rows;
  }

  @override
  String get text => _rows.map((r) => r.text).join();

  FluentTable({List<FluentRow>? rows, this.columnWidths, this.tableWidth})
    : _rows = rows ?? [],
      super(nanoid());

  @override
  List<FNode> get fragments => _rows;
  
  factory FluentTable.fromJson(Map<String, dynamic> json) {
    final table = _$FluentTableFromJson(json);
    table.id = json['id'] as String? ?? table.id;
    final rawWidths = json['columnWidths'];
    if (rawWidths is List) {
      table.columnWidths = rawWidths.map((e) => (e as num).toDouble()).toList();
    }
    table.tableWidth = (json['tableWidth'] as num?)?.toDouble();
    return table;
  }
  
  @override
  Map<String, dynamic> toJson() {
    final json = _$FluentTableToJson(this);
    json['type'] = 'table';
    if (columnWidths != null) json['columnWidths'] = columnWidths;
    if (tableWidth != null) json['tableWidth'] = tableWidth;
    return json;
  }
}

@JsonSerializable()
class FluentRow extends FNode implements InlineContainerNode {
  String get type => 'row';

  @FNodeJsonConverter()
  @JsonKey(name: 'cells')
  List<FluentCell> _cells = [];

  /// Explicit height of the row (in logical pixels). If null, calculated
  /// automatically based on content.
  double? rowHeight;

  List<FluentCell> get cells => TrackedList(_cells, () {});

  set cells(List<FluentCell> value) {
    _cells = value;
  }

  FluentRow({List<FluentCell>? cells, this.rowHeight})
    : _cells = cells ?? [],
      super(nanoid());

  @override
  @FNodeJsonConverter()
  List<FluentCell> getChildren() {
    return _cells;
  }

  @override
  List<FNode> get fragments => _cells;

  @override
  String get text => _cells.map((c) => c.text).join();
  
  factory FluentRow.fromJson(Map<String, dynamic> json) {
    final row = _$FluentRowFromJson(json);
    row.id = json['id'] as String? ?? row.id;
    row.rowHeight = (json['rowHeight'] as num?)?.toDouble();
    return row;
  }
  
  @override
  Map<String, dynamic> toJson() {
    final json = _$FluentRowToJson(this);
    json['type'] = 'row';
    if (rowHeight != null) json['rowHeight'] = rowHeight;
    return json;
  }
}

/// Generic container for table cells.
/// Can contain any type of node (paragraphs, images, tables, etc.)
/// Implements InlineContainerNode for backward compatibility.
@JsonSerializable()
class FluentCell extends FNode implements InlineContainerNode {
  String get type => 'cell';
  int colSpan = 1;
  int rowSpan = 1;

  @FNodeJsonConverter()
  List<FNode> children;

  FluentCell({List<FNode>? children})
      : children = children ?? [Paragraph()], // Default: an empty paragraph
        super(nanoid());

  @override
  List<FNode> getChildren() => children;

  @override
  List<FNode> get fragments {
    final result = <FNode>[];
    for (final child in children) {
      if (child is InlineContainerNode) {
        result.addAll((child as InlineContainerNode).fragments);
      } else if (child is Fragment) {
        result.add(child);
      }
    }
    return result;
  }

  /// Compatibility getter: returns concatenated text from children
  @override
  String get text {
    return children
        .whereType<InlineContainerNode>()
        .map((c) => c.text)
        .join();
  }

  factory FluentCell.fromJson(Map<String, dynamic> json) {
    final cell = FluentCell(
      children: (json['children'] as List<dynamic>?)
          ?.map((e) => const FNodeJsonConverter().fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    cell.id = json['id'] as String? ?? cell.id;
    cell.colSpan = (json['colSpan'] as num?)?.toInt() ?? 1;
    cell.rowSpan = (json['rowSpan'] as num?)?.toInt() ?? 1;
    return cell;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = _$FluentCellToJson(this);
    json['type'] = 'cell';
    return json;
  }
}

FNode makeNode(String nodeType, dynamic options) {
  switch (nodeType) {
    case 'paragraph':
      return Paragraph();
    case 'link':
      return Link(url: options['url'], text: options['text']);
    case 'list':
      final listType = options['listType'] as String? ?? 'bullet';
      final list = FluentList(listType: listType);
      // Create an initial ListItem with an empty Paragraph so the
      // cursor has a fragment to land on.
      final initialItem = ListItem(
        bulletType: listType,
        indexList: [1],
        children: [Paragraph()],
      );
      list.items.add(initialItem);
      return list;
    case 'table':
      final List<FluentRow> rows = [];
      for (var i = 0; i < options['rows']; i++) {
        final List<FluentCell> cells = [];
        for (var j = 0; j < options['cells']; j++) {
          cells.add(FluentCell()); // Default: empty paragraph
        }
        final currentRow = FluentRow(cells: cells);
        rows.add(currentRow);
      }
      return FluentTable(rows: rows);
    case 'image':
      return FluentImage(options['src']);
    case 'hr':
      return HorizontalRule();
    default:
      return Paragraph();
  }
}

FNode copyFrom(FNode node) {
  return switch (node) {
    Link() => Link(url: node.url),
    Fragment() => Fragment(node.text),
    Paragraph() => Paragraph()..fragments = node.fragments.map(copyFrom).toList(),
    _ => throw Exception('Node type not supported: ${node.runtimeType}'),
  };
}

class TrackedList<E> extends ListBase<E> {
  final List<E> _inner;
  final void Function() onUpdate;

  TrackedList(this._inner, this.onUpdate);

  @override
  int get length => _inner.length;

  @override
  set length(int newLength) {
    _inner.length = newLength;
    onUpdate();
  }

  @override
  E operator [](int index) => _inner[index];

  @override
  void operator []=(int index, E value) {
    _inner[index] = value;
    onUpdate();
  }

  @override
  void add(E element) {
    _inner.add(element);
    onUpdate();
  }

  @override
  void addAll(Iterable<E> iterable) {
    _inner.addAll(iterable);
    onUpdate();
  }

  @override
  void insert(int index, E element) {
    _inner.insert(index, element);
    onUpdate();
  }

  @override
  void insertAll(int index, Iterable<E> iterable) {
    _inner.insertAll(index, iterable);
    onUpdate();
  }

  @override
  bool remove(Object? element) {
    final removed = _inner.remove(element);
    if (removed) onUpdate();
    return removed;
  }

  @override
  E removeAt(int index) {
    final removed = _inner.removeAt(index);
    onUpdate();
    return removed;
  }

  @override
  E removeLast() {
    final removed = _inner.removeLast();
    onUpdate();
    return removed;
  }

  @override
  void removeRange(int start, int end) {
    _inner.removeRange(start, end);
    onUpdate();
  }

  @override
  void removeWhere(bool Function(E element) test) {
    _inner.removeWhere(test);
    onUpdate();
  }

  @override
  void clear() {
    _inner.clear();
    onUpdate();
  }

  @override
  void sort([int Function(E a, E b)? compare]) {
    _inner.sort(compare);
    onUpdate();
  }

  @override
  void shuffle([math.Random? random]) {
    _inner.shuffle(random);
    onUpdate();
  }

  @override
  void fillRange(int start, int end, [E? fill]) {
    _inner.fillRange(start, end, fill as E);
    onUpdate();
  }

  @override
  void setRange(int start, int end, Iterable<E> iterable, [int skipCount = 0]) {
    _inner.setRange(start, end, iterable, skipCount);
    onUpdate();
  }

  @override
  void replaceRange(int start, int end, Iterable<E> newContents) {
    _inner.replaceRange(start, end, newContents);
    onUpdate();
  }
}
