import 'package:flutter/material.dart';
import 'package:fluent_editor/controllers/document_language_controller.dart';
import 'package:fluent_editor/models/document_language.dart';

/// Toolbar widget that lets the user pick the document language.
/// Uses [showMenu] wrapped in an [InkWell] to match the project's cursor
/// and interaction patterns (no native DropdownButton/PopupMenuButton).
class LanguageSelectorWidget extends StatefulWidget {
  const LanguageSelectorWidget({super.key});

  @override
  State<LanguageSelectorWidget> createState() => _LanguageSelectorWidgetState();
}

class _LanguageSelectorWidgetState extends State<LanguageSelectorWidget> {
  final DocumentLanguageController _controller = DocumentLanguageController.instance;

  @override
  void initState() {
    super.initState();
    _controller.initialize();
    _controller.currentLanguage.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    _controller.currentLanguage.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _showLanguageMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<DocumentLanguage>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + button.size.height,
        overlay.size.width - position.dx - button.size.width,
        overlay.size.height - position.dy,
      ),
      items: DocumentLanguage.supported.map((lang) {
        final isCurrent = _controller.current.code == lang.code;
        return PopupMenuItem<DocumentLanguage>(
          value: lang,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                Text(lang.flag, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang.name,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isCurrent)
                  Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) {
        _controller.setLanguage(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = _controller.current;

    return InkWell(
      onTap: () => _showLanguageMenu(context),
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 160,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(lang.flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      lang.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}
