import 'package:fluent_editor/factories.dart';

import 'import_html_service.dart';
import 'import_markdown_service.dart';
import 'import_docx_service.dart';
import 'import_odt_service.dart';

/// Facade for importing content from various formats into a FluentEditor Root.
class ImportService {
  final _html = ImportHtmlService();
  final _md = ImportMarkdownService();
  final _docx = ImportDocxService();
  final _odt = ImportOdtService();

  Root importFromHtml(String html) => _html.importFromHtml(html);
  Root importFromMarkdown(String md) => _md.importFromMarkdown(md);
  Root importFromDocx(List<int> bytes) => _docx.importFromDocx(bytes);
  Root importFromOdt(List<int> bytes) => _odt.importFromOdt(bytes);
}
