/// Localization system for FluentEditor.
///
/// To customize labels, pass an instance of this class to the FluentEditor
/// widget via the [labels] parameter.
///
/// Example:
/// ```dart
/// FluentEditor(
///   labels: FluentEditorLabels(
///     file: 'File',
///     edit: 'Edit',
///   ),
/// )
/// ```
class FluentEditorLabels {
  /// Menu File
  final String file;
  final String save;
  final String open;
  final String exportAs;
  final String microsoftWord;
  final String libreOffice;
  final String pdf;
  final String html;
  final String markdown;
  final String importHtml;
  final String importMarkdown;
  final String importDocx;
  final String importOdt;
  final String fileSaved;
  final String fileLoaded;
  final String fileLoadError;
  final String exportSuccess;
  final String exportError;
  final String documentCopied;

  /// Menu Edit
  final String edit;
  final String undo;
  final String redo;
  final String cut;
  final String copy;
  final String paste;
  final String pasteWithoutFormatting;
  final String selectAll;
  final String delete;
  final String wordCount;
  final String characterCount;

  /// Menu Insert
  final String insert;
  final String link;
  final String image;
  final String table;
  final String horizontalLine;

  /// Menu Settings
  final String settings;
  final String showStats;
  final String documentLanguage;

  /// Menu Format
  final String format;
  final String text;
  final String bold;
  final String italic;
  final String underline;
  final String strikethrough;
  final String superscript;
  final String subscript;
  final String smallCaps;
  final String styles;
  final String align;
  final String alignLeft;
  final String alignCenter;
  final String alignRight;
  final String justify;
  final String increaseIndent;
  final String decreaseIndent;
  final String alignAndIndent;
  final String lineSpacing;
  final String lineSpacingSingle;
  final String lineSpacing115;
  final String lineSpacing15;
  final String lineSpacingDouble;
  final String paragraphSpacing;
  final String textColor;
  final String highlightColor;

  /// Dialogs
  final String insertLink;
  final String cancel;
  final String confirmButton;
  final String insertButton;
  final String apply;
  final String insertImage;
  final String or;
  final String done;
  final String url;
  final String urlHint;
  final String urlRequired;
  final String linkText;
  final String linkTextHint;
  final String linkTextRequired;
  final String lineHeight;
  final String spacingBefore;
  final String spacingAfter;
  final String imageUrl;
  final String imageUrlHint;
  final String dragImageHere;
  final String clickToChooseImage;
  final String imageSelected;
  final String fileReadError;
  final String chooseListMarkerType;
  final String all;
  final String bullets;
  final String numbers;
  final String checkboxes;
  final String replaceImage;
  final String replaceLink;
  final String deleteImage;
  final String deleteLink;
  final String goToLink;

  final String insertRowAbove;
  final String insertRowBelow;

  final String addCommentLabel;
  final String commentDialogTitle;
  final String commentHint;
  final String commentOverlapWarning;
  final String sidebarTitle;
  final String emptySidebarMessage;
  final String showResolvedLabel;
  final String showCommentsLabel;
  final String hideCommentsLabel;
  final String deletedTextLabel;
  final String resolvedLabel;
  final String replyHint;
  final String resolveButton;
  final String defaultAuthorName;
  final String anonymousLabel;
  final String pdfCommentSubject;
  final String authorInfoDialogTitle;
  final String authorNameLabel;
  final String authorNameHint;
  final String setAuthorLabel;

  /// Constructor with default values in English
  const FluentEditorLabels({
    this.file = 'File',
    this.save = 'Save (.fluent)',
    this.open = 'Open (.fluent)',
    this.exportAs = 'Export as...',
    this.microsoftWord = 'Microsoft Word (.docx)',
    this.libreOffice = 'LibreOffice (.odt)',
    this.pdf = 'PDF (.pdf)',
    this.html = 'HTML (.html)',
    this.markdown = 'Markdown (.md)',
    this.importHtml = 'Import HTML (.html)',
    this.importMarkdown = 'Import Markdown (.md)',
    this.importDocx = 'Import Word (.docx)',
    this.importOdt = 'Import ODT (.odt)',
    this.fileSaved = 'File saved',
    this.fileLoaded = 'File loaded successfully',
    this.fileLoadError = 'Error loading file',
    this.exportSuccess = 'Exported',
    this.exportError = 'Error exporting',
    this.documentCopied = 'Document copied as JSON',

    this.edit = 'Edit',
    this.undo = 'Undo',
    this.redo = 'Redo',
    this.cut = 'Cut',
    this.copy = 'Copy',
    this.paste = 'Paste',
    this.pasteWithoutFormatting = 'Paste without formatting',
    this.selectAll = 'Select all',
    this.delete = 'Delete',
    this.wordCount = 'Word count',
    this.characterCount = 'Characters',

    this.insert = 'Insert',
    this.link = 'Link',
    this.image = 'Image',
    this.table = 'Table',
    this.horizontalLine = 'Horizontal line',

    this.settings = 'Settings',
    this.showStats = 'Show stats',
    this.documentLanguage = 'Document Language',

    this.format = 'Format',
    this.text = 'Text',
    this.bold = 'Bold',
    this.italic = 'Italic',
    this.underline = 'Underline',
    this.strikethrough = 'Strikethrough',
    this.superscript = 'Superscript',
    this.subscript = 'Subscript',
    this.smallCaps = 'Small caps',
    this.styles = 'Styles',
    this.align = 'Align and indent',
    this.alignLeft = 'Align left',
    this.alignCenter = 'Align center',
    this.alignRight = 'Align right',
    this.justify = 'Justify',
    this.increaseIndent = 'Increase indent',
    this.decreaseIndent = 'Decrease indent',
    this.alignAndIndent = 'Align and indent',
    this.lineSpacing = 'Line and paragraph spacing',
    this.lineSpacingSingle = 'Single',
    this.lineSpacing115 = '1.15',
    this.lineSpacing15 = '1.5',
    this.lineSpacingDouble = 'Double',
    this.paragraphSpacing = 'Paragraph Spacing',
    this.textColor = 'Text color',
    this.highlightColor = 'Highlight',

    this.insertLink = 'Insert Link',
    this.cancel = 'Cancel',
    this.confirmButton = 'Confirm',
    this.insertButton = 'Insert',
    this.apply = 'Apply',
    this.insertImage = 'Insert image',
    this.or = 'or',
    this.done = 'Done',
    this.url = 'URL',
    this.urlHint = 'https://example.com',
    this.urlRequired = 'Please enter a URL',
    this.linkText = 'Text',
    this.linkTextHint = 'Link text',
    this.linkTextRequired = 'Please enter link text',
    this.lineHeight = 'Line height',
    this.spacingBefore = 'Spacing before',
    this.spacingAfter = 'Spacing after',
    this.imageUrl = 'Image URL',
    this.imageUrlHint = 'https://example.com/image.png',
    this.dragImageHere = 'Drag an image here or click to choose',
    this.clickToChooseImage = 'Click to choose an image',
    this.imageSelected = 'Image selected',
    this.fileReadError = 'Error reading file',
    this.chooseListMarkerType = 'Choose List Marker Type',
    this.all = 'All',
    this.bullets = 'Bullets',
    this.numbers = 'Numbers',
    this.checkboxes = 'Checkboxes',
    this.replaceImage = 'Replace image',
    this.replaceLink = 'Replace link',
    this.deleteImage = 'Delete',
    this.deleteLink = 'Delete',
    this.goToLink = 'Go to link',

    this.insertRowAbove = 'Insert row above',
    this.insertRowBelow = 'Insert row below',

    this.addCommentLabel = 'Add comment',
    this.commentDialogTitle = 'Add comment',
    this.commentHint = 'Write a comment...',
    this.commentOverlapWarning =
        'Warning: the comment overlaps an existing comment.',
    this.sidebarTitle = 'Activities',
    this.emptySidebarMessage = 'No comments or suggestions in the document.',
    this.showResolvedLabel = 'Show resolved',
    this.showCommentsLabel = 'Show comments',
    this.hideCommentsLabel = 'Hide comments',
    this.deletedTextLabel = 'Text deleted',
    this.resolvedLabel = 'Resolved',
    this.replyHint = 'Reply...',
    this.resolveButton = 'Resolve',
    this.defaultAuthorName = 'User',
    this.anonymousLabel = 'Anonymous',
    this.pdfCommentSubject = 'Comment',
    this.authorInfoDialogTitle = 'Author Information',
    this.authorNameLabel = 'Author Name',
    this.authorNameHint = 'Enter your name...',
    this.setAuthorLabel = 'Set author',
  });

  /// Creates a copy of this [FluentEditorLabels] with specified fields overridden.
  FluentEditorLabels copyWith({
    String? file,
    String? save,
    String? open,
    String? exportAs,
    String? microsoftWord,
    String? libreOffice,
    String? pdf,
    String? html,
    String? markdown,
    String? importHtml,
    String? importMarkdown,
    String? importDocx,
    String? importOdt,
    String? fileSaved,
    String? fileLoaded,
    String? fileLoadError,
    String? exportSuccess,
    String? exportError,
    String? documentCopied,
    String? edit,
    String? undo,
    String? redo,
    String? cut,
    String? copy,
    String? paste,
    String? pasteWithoutFormatting,
    String? selectAll,
    String? delete,
    String? wordCount,
    String? characterCount,
    String? insert,
    String? link,
    String? image,
    String? table,
    String? horizontalLine,
    String? settings,
    String? showStats,
    String? documentLanguage,
    String? format,
    String? text,
    String? bold,
    String? italic,
    String? underline,
    String? strikethrough,
    String? superscript,
    String? subscript,
    String? smallCaps,
    String? styles,
    String? align,
    String? alignLeft,
    String? alignCenter,
    String? alignRight,
    String? justify,
    String? increaseIndent,
    String? decreaseIndent,
    String? alignAndIndent,
    String? lineSpacing,
    String? lineSpacingSingle,
    String? lineSpacing115,
    String? lineSpacing15,
    String? lineSpacingDouble,
    String? paragraphSpacing,
    String? textColor,
    String? highlightColor,
    String? insertLink,
    String? cancel,
    String? confirmButton,
    String? insertButton,
    String? apply,
    String? insertImage,
    String? or,
    String? done,
    String? url,
    String? urlHint,
    String? urlRequired,
    String? linkText,
    String? linkTextHint,
    String? linkTextRequired,
    String? lineHeight,
    String? spacingBefore,
    String? spacingAfter,
    String? imageUrl,
    String? imageUrlHint,
    String? dragImageHere,
    String? clickToChooseImage,
    String? imageSelected,
    String? fileReadError,
    String? chooseListMarkerType,
    String? all,
    String? bullets,
    String? numbers,
    String? checkboxes,
    String? replaceImage,
    String? replaceLink,
    String? deleteImage,
    String? deleteLink,
    String? goToLink,
    String? insertRowAbove,
    String? insertRowBelow,
    String? addCommentLabel,
    String? commentDialogTitle,
    String? commentHint,
    String? commentOverlapWarning,
    String? sidebarTitle,
    String? emptySidebarMessage,
    String? showResolvedLabel,
    String? showCommentsLabel,
    String? hideCommentsLabel,
    String? deletedTextLabel,
    String? resolvedLabel,
    String? replyHint,
    String? resolveButton,
    String? defaultAuthorName,
    String? anonymousLabel,
    String? pdfCommentSubject,
    String? authorInfoDialogTitle,
    String? authorNameLabel,
    String? authorNameHint,
    String? setAuthorLabel,
  }) {
    return FluentEditorLabels(
      file: file ?? this.file,
      save: save ?? this.save,
      open: open ?? this.open,
      exportAs: exportAs ?? this.exportAs,
      microsoftWord: microsoftWord ?? this.microsoftWord,
      libreOffice: libreOffice ?? this.libreOffice,
      pdf: pdf ?? this.pdf,
      html: html ?? this.html,
      markdown: markdown ?? this.markdown,
      importHtml: importHtml ?? this.importHtml,
      importMarkdown: importMarkdown ?? this.importMarkdown,
      importDocx: importDocx ?? this.importDocx,
      importOdt: importOdt ?? this.importOdt,
      fileSaved: fileSaved ?? this.fileSaved,
      fileLoaded: fileLoaded ?? this.fileLoaded,
      fileLoadError: fileLoadError ?? this.fileLoadError,
      exportSuccess: exportSuccess ?? this.exportSuccess,
      exportError: exportError ?? this.exportError,
      documentCopied: documentCopied ?? this.documentCopied,
      edit: edit ?? this.edit,
      undo: undo ?? this.undo,
      redo: redo ?? this.redo,
      cut: cut ?? this.cut,
      copy: copy ?? this.copy,
      paste: paste ?? this.paste,
      pasteWithoutFormatting:
          pasteWithoutFormatting ?? this.pasteWithoutFormatting,
      selectAll: selectAll ?? this.selectAll,
      delete: delete ?? this.delete,
      wordCount: wordCount ?? this.wordCount,
      characterCount: characterCount ?? this.characterCount,
      insert: insert ?? this.insert,
      link: link ?? this.link,
      image: image ?? this.image,
      table: table ?? this.table,
      horizontalLine: horizontalLine ?? this.horizontalLine,
      settings: settings ?? this.settings,
      showStats: showStats ?? this.showStats,
      documentLanguage: documentLanguage ?? this.documentLanguage,
      format: format ?? this.format,
      text: text ?? this.text,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      superscript: superscript ?? this.superscript,
      subscript: subscript ?? this.subscript,
      smallCaps: smallCaps ?? this.smallCaps,
      styles: styles ?? this.styles,
      align: align ?? this.align,
      alignLeft: alignLeft ?? this.alignLeft,
      alignCenter: alignCenter ?? this.alignCenter,
      alignRight: alignRight ?? this.alignRight,
      justify: justify ?? this.justify,
      increaseIndent: increaseIndent ?? this.increaseIndent,
      decreaseIndent: decreaseIndent ?? this.decreaseIndent,
      alignAndIndent: alignAndIndent ?? this.alignAndIndent,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      lineSpacingSingle: lineSpacingSingle ?? this.lineSpacingSingle,
      lineSpacing115: lineSpacing115 ?? this.lineSpacing115,
      lineSpacing15: lineSpacing15 ?? this.lineSpacing15,
      lineSpacingDouble: lineSpacingDouble ?? this.lineSpacingDouble,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      textColor: textColor ?? this.textColor,
      highlightColor: highlightColor ?? this.highlightColor,
      insertLink: insertLink ?? this.insertLink,
      cancel: cancel ?? this.cancel,
      confirmButton: confirmButton ?? this.confirmButton,
      insertButton: insertButton ?? this.insertButton,
      apply: apply ?? this.apply,
      insertImage: insertImage ?? this.insertImage,
      or: or ?? this.or,
      done: done ?? this.done,
      url: url ?? this.url,
      urlHint: urlHint ?? this.urlHint,
      urlRequired: urlRequired ?? this.urlRequired,
      linkText: linkText ?? this.linkText,
      linkTextHint: linkTextHint ?? this.linkTextHint,
      linkTextRequired: linkTextRequired ?? this.linkTextRequired,
      lineHeight: lineHeight ?? this.lineHeight,
      spacingBefore: spacingBefore ?? this.spacingBefore,
      spacingAfter: spacingAfter ?? this.spacingAfter,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrlHint: imageUrlHint ?? this.imageUrlHint,
      dragImageHere: dragImageHere ?? this.dragImageHere,
      clickToChooseImage: clickToChooseImage ?? this.clickToChooseImage,
      imageSelected: imageSelected ?? this.imageSelected,
      fileReadError: fileReadError ?? this.fileReadError,
      chooseListMarkerType: chooseListMarkerType ?? this.chooseListMarkerType,
      all: all ?? this.all,
      bullets: bullets ?? this.bullets,
      numbers: numbers ?? this.numbers,
      checkboxes: checkboxes ?? this.checkboxes,
      replaceImage: replaceImage ?? this.replaceImage,
      replaceLink: replaceLink ?? this.replaceLink,
      deleteImage: deleteImage ?? this.deleteImage,
      deleteLink: deleteLink ?? this.deleteLink,
      goToLink: goToLink ?? this.goToLink,
      insertRowAbove: insertRowAbove ?? this.insertRowAbove,
      insertRowBelow: insertRowBelow ?? this.insertRowBelow,
      addCommentLabel: addCommentLabel ?? this.addCommentLabel,
      commentDialogTitle: commentDialogTitle ?? this.commentDialogTitle,
      commentHint: commentHint ?? this.commentHint,
      commentOverlapWarning:
          commentOverlapWarning ?? this.commentOverlapWarning,
      sidebarTitle: sidebarTitle ?? this.sidebarTitle,
      emptySidebarMessage: emptySidebarMessage ?? this.emptySidebarMessage,
      showResolvedLabel: showResolvedLabel ?? this.showResolvedLabel,
      showCommentsLabel: showCommentsLabel ?? this.showCommentsLabel,
      hideCommentsLabel: hideCommentsLabel ?? this.hideCommentsLabel,
      deletedTextLabel: deletedTextLabel ?? this.deletedTextLabel,
      resolvedLabel: resolvedLabel ?? this.resolvedLabel,
      replyHint: replyHint ?? this.replyHint,
      resolveButton: resolveButton ?? this.resolveButton,
      defaultAuthorName: defaultAuthorName ?? this.defaultAuthorName,
      anonymousLabel: anonymousLabel ?? this.anonymousLabel,
      pdfCommentSubject: pdfCommentSubject ?? this.pdfCommentSubject,
      authorInfoDialogTitle:
          authorInfoDialogTitle ?? this.authorInfoDialogTitle,
      authorNameLabel: authorNameLabel ?? this.authorNameLabel,
      authorNameHint: authorNameHint ?? this.authorNameHint,
      setAuthorLabel: setAuthorLabel ?? this.setAuthorLabel,
    );
  }
}
