void main() {
  String currentFragText = 'Ho scritto una fr';
  String valueText = 'Ho scritto una frase ';
  
  int prefixLen = 0;
  final minLen = currentFragText.length < valueText.length ? currentFragText.length : valueText.length;
  while (prefixLen < minLen && currentFragText[prefixLen] == valueText[prefixLen]) {
    prefixLen++;
  }
  int suffixLen = 0;
  while (suffixLen < currentFragText.length - prefixLen &&
      suffixLen < valueText.length - prefixLen &&
      currentFragText[currentFragText.length - 1 - suffixLen] ==
          valueText[valueText.length - 1 - suffixLen]) {
    suffixLen++;
  }
  
  int expandedPrefix = prefixLen;
  while (expandedPrefix > 0 && currentFragText[expandedPrefix - 1] != ' ') {
    expandedPrefix--;
  }
  
  final deleted = currentFragText.substring(expandedPrefix, currentFragText.length - suffixLen);
  final inserted = valueText.substring(expandedPrefix, valueText.length - suffixLen);
  
  print('deleted: "$deleted", inserted: "$inserted", expandedPrefix: $expandedPrefix');
}
