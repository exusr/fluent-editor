class ListMarkerType {
  final String id;
  final String displayName;
  final String icon;
  final List<String> examples;

  const ListMarkerType({
    required this.id,
    required this.displayName,
    required this.icon,
    required this.examples,
  });
}

class ListMarkerTypes {
  static const List<ListMarkerType> allTypes = [
    // Bullet types
    ListMarkerType(
      id: 'bullet',
      displayName: 'Bullet',
      icon: '•',
      examples: ['• Item 1', '  ◦ Item 1.1', '    ▪ Item 1.1.1'],
    ),
    ListMarkerType(
      id: 'bullet-circle',
      displayName: 'Circle Bullet',
      icon: '○',
      examples: ['○ Item 1', '  ◦ Item 1.1', '    ● Item 1.1.1'],
    ),
    ListMarkerType(
      id: 'bullet-square',
      displayName: 'Square Bullet',
      icon: '□',
      examples: ['□ Item 1', '  ▫ Item 1.1', '    ■ Item 1.1.1'],
    ),

    // Numbered types
    ListMarkerType(
      id: 'ordered',
      displayName: 'Numbered',
      icon: '1.',
      examples: ['1. Item 1', '2. Item 2', '3. Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-parenthesis',
      displayName: 'Numbered (Parenthesis)',
      icon: '1)',
      examples: ['1) Item 1', '2) Item 2', '3) Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-alpha',
      displayName: 'Alphabetical',
      icon: 'a.',
      examples: ['a. Item 1', 'b. Item 2', 'c. Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-alpha-parenthesis',
      displayName: 'Alphabetical (Parenthesis)',
      icon: 'a)',
      examples: ['a) Item 1', 'b) Item 2', 'c) Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-alpha-upper',
      displayName: 'Alphabetical (Upper)',
      icon: 'A.',
      examples: ['A. Item 1', 'B. Item 2', 'C. Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-alpha-upper-parenthesis',
      displayName: 'Alphabetical (Upper, Parenthesis)',
      icon: 'A)',
      examples: ['A) Item 1', 'B) Item 2', 'C) Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-roman',
      displayName: 'Roman Numerals',
      icon: 'i.',
      examples: ['i. Item 1', 'ii. Item 2', 'iii. Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-roman-parenthesis',
      displayName: 'Roman Numerals (Parenthesis)',
      icon: 'i)',
      examples: ['i) Item 1', 'ii) Item 2', 'iii) Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-roman-upper',
      displayName: 'Roman Numerals (Upper)',
      icon: 'I.',
      examples: ['I. Item 1', 'II. Item 2', 'III. Item 3'],
    ),
    ListMarkerType(
      id: 'ordered-roman-upper-parenthesis',
      displayName: 'Roman Numerals (Upper, Parenthesis)',
      icon: 'I)',
      examples: ['I) Item 1', 'II) Item 2', 'III) Item 3'],
    ),

    // Checkbox types
    ListMarkerType(
      id: 'checkbox',
      displayName: 'Checkbox',
      icon: '☐',
      examples: ['☐ Item 1', '☐ Item 2', '☐ Item 3'],
    ),
    ListMarkerType(
      id: 'checkbox-checked',
      displayName: 'Checkbox (Checked)',
      icon: '☑',
      examples: ['☑ Item 1', '☑ Item 2', '☑ Item 3'],
    ),
    ListMarkerType(
      id: 'checkbox-crossed',
      displayName: 'Checkbox (Crossed)',
      icon: '☒',
      examples: ['☒ Item 1', '☒ Item 2', '☒ Item 3'],
    ),
  ];

  static ListMarkerType? getById(String id) {
    try {
      return allTypes.firstWhere((type) => type.id == id);
    } catch (e) {
      return null;
    }
  }

  static List<ListMarkerType> getByCategory(String category) {
    switch (category) {
      case 'bullet':
        return allTypes.where((type) => type.id.startsWith('bullet')).toList();
      case 'ordered':
        return allTypes.where((type) => type.id.startsWith('ordered')).toList();
      case 'checkbox':
        return allTypes.where((type) => type.id.startsWith('checkbox')).toList();
      default:
        return allTypes;
    }
  }
}
