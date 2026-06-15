/// Localization system for FluentEditor.
///
/// To make the editor multilingual, pass an instance of this class
/// to the FluentEditor widget via the [labels] parameter.
///
/// Example:
/// ```dart
/// FluentEditor(
///   labels: FluentEditorLabels(
///     file: 'File',
///     edit: 'Edit',
///     insert: 'Insert',
///     format: 'Format',
///     // ... other translations
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
  final String markdown;
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

  // Table
  final String insertRowAbove;
  final String insertRowBelow;

  // Comments
  final String addCommentLabel;
  final String commentDialogTitle;
  final String commentHint;
  final String commentOverlapWarning;
  final String sidebarTitle;
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
    this.markdown = 'Markdown (.md)',
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

    // Comments
    this.addCommentLabel = 'Add comment',
    this.commentDialogTitle = 'Add comment',
    this.commentHint = 'Write a comment...',
    this.commentOverlapWarning = 'Warning: the comment overlaps an existing comment.',
    this.sidebarTitle = 'Comments',
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
}
