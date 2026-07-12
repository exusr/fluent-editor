/// Model for a document language.
class DocumentLanguage {
  final String code;
  final String name;
  final String flag;

  const DocumentLanguage({
    required this.code,
    required this.name,
    required this.flag,
  });

  static const DocumentLanguage italian = DocumentLanguage(
    code: 'it',
    name: 'Italiano',
    flag: '\u{1F1EE}\u{1F1F9}',
  );

  static const DocumentLanguage englishUS = DocumentLanguage(
    code: 'en_US',
    name: 'English (US)',
    flag: '\u{1F1FA}\u{1F1F8}',
  );

  static const DocumentLanguage englishUK = DocumentLanguage(
    code: 'en_GB',
    name: 'English (UK)',
    flag: '\u{1F1EC}\u{1F1E7}',
  );

  static const DocumentLanguage french = DocumentLanguage(
    code: 'fr',
    name: 'Fran\u00e7ais',
    flag: '\u{1F1EB}\u{1F1F7}',
  );

  static const DocumentLanguage german = DocumentLanguage(
    code: 'de',
    name: 'Deutsch',
    flag: '\u{1F1E9}\u{1F1EA}',
  );

  static const DocumentLanguage spanish = DocumentLanguage(
    code: 'es',
    name: 'Espa\u00f1ol',
    flag: '\u{1F1EA}\u{1F1F8}',
  );

  static const List<DocumentLanguage> supported = [
    italian,
    englishUS,
    englishUK,
    french,
    german,
    spanish,
  ];

  static DocumentLanguage fromCode(String code) {
    return supported.firstWhere(
      (l) => l.code == code,
      orElse: () => italian,
    );
  }
}
