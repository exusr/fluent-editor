/// Model for a document language with associated Hunspell dictionary paths.
class DocumentLanguage {
  final String code;
  final String name;
  final String flag;
  final String hunspellAff;
  final String hunspellDic;

  const DocumentLanguage({
    required this.code,
    required this.name,
    required this.flag,
    required this.hunspellAff,
    required this.hunspellDic,
  });

  static const DocumentLanguage italian = DocumentLanguage(
    code: 'it',
    name: 'Italiano',
    flag: '\u{1F1EE}\u{1F1F9}',
    hunspellAff: 'assets/dicts/it.aff',
    hunspellDic: 'assets/dicts/it.dic',
  );

  static const DocumentLanguage englishUS = DocumentLanguage(
    code: 'en_US',
    name: 'English (US)',
    flag: '\u{1F1FA}\u{1F1F8}',
    hunspellAff: 'assets/dicts/en_US.aff',
    hunspellDic: 'assets/dicts/en_US.dic',
  );

  static const DocumentLanguage englishUK = DocumentLanguage(
    code: 'en_GB',
    name: 'English (UK)',
    flag: '\u{1F1EC}\u{1F1E7}',
    hunspellAff: 'assets/dicts/en_GB.aff',
    hunspellDic: 'assets/dicts/en_GB.dic',
  );

  static const DocumentLanguage french = DocumentLanguage(
    code: 'fr',
    name: 'Fran\u00e7ais',
    flag: '\u{1F1EB}\u{1F1F7}',
    hunspellAff: 'assets/dicts/fr.aff',
    hunspellDic: 'assets/dicts/fr.dic',
  );

  static const DocumentLanguage german = DocumentLanguage(
    code: 'de',
    name: 'Deutsch',
    flag: '\u{1F1E9}\u{1F1EA}',
    hunspellAff: 'assets/dicts/de.aff',
    hunspellDic: 'assets/dicts/de.dic',
  );

  static const DocumentLanguage spanish = DocumentLanguage(
    code: 'es',
    name: 'Espa\u00f1ol',
    flag: '\u{1F1EA}\u{1F1F8}',
    hunspellAff: 'assets/dicts/es.aff',
    hunspellDic: 'assets/dicts/es.dic',
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
