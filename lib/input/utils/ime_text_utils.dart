import 'package:fluent_editor/utils/fragment_operations.dart';

class ImeTextUtils {
  static int findDiffIndex(String a, String b) {
    final minLen = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLen; i++) {
      if (a[i] != b[i]) return i;
    }
    if (a.length != b.length) return minLen;
    return -1;
  }

  static int snapCursorOffset(String text, int offset) {
    if (text.isEmpty) return offset;
    return FragmentOperations.adjustIndex(text, offset.clamp(0, text.length));
  }

  static int findWordStartOffset(String text, int offset) {
    if (offset <= 0 || offset > text.length) return offset;
    int start = offset;
    while (start > 0 && !isWordBoundary(text[start - 1])) {
      start--;
    }
    return start;
  }

  static int findWordEndOffset(String text, int offset) {
    int end = offset;
    while (end < text.length && !isWordBoundary(text[end])) {
      end++;
    }
    return end;
  }

  static bool isWordBoundary(String char) {
    if (char.isEmpty) return true;
    final codeUnit = char.codeUnitAt(0);
    return codeUnit == 32 || // Space
        (codeUnit >= 33 && codeUnit <= 47) || // Punctuation !"#$%&'()*+,-./
        (codeUnit >= 58 && codeUnit <= 64) || // Punctuation :;<=>?@
        (codeUnit >= 91 && codeUnit <= 96) || // Punctuation [\]^_`
        (codeUnit >= 123 && codeUnit <= 126); // Punctuation {|}~
  }

  static String computeInsertedText(String oldText, String newText) {
    int commonPrefix = 0;
    while (commonPrefix < oldText.length &&
        commonPrefix < newText.length &&
        oldText[commonPrefix] == newText[commonPrefix]) {
      commonPrefix++;
    }

    int commonSuffix = 0;
    while (commonSuffix < oldText.length - commonPrefix &&
        commonSuffix < newText.length - commonPrefix &&
        oldText[oldText.length - 1 - commonSuffix] ==
            newText[newText.length - 1 - commonSuffix]) {
      commonSuffix++;
    }

    return newText.substring(
      commonPrefix,
      newText.length - commonSuffix,
    );
  }

  static int commonPrefixLength(String a, String b) {
    int i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    return i;
  }

  static String sanitizeUtf16(String s) {
    if (s.isEmpty) return s;
    final codeUnits = s.codeUnits;
    final cleanUnits = <int>[];
    for (int i = 0; i < codeUnits.length; i++) {
      int unit = codeUnits[i];
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 < codeUnits.length &&
            codeUnits[i + 1] >= 0xDC00 &&
            codeUnits[i + 1] <= 0xDFFF) {
          cleanUnits.add(unit);
          cleanUnits.add(codeUnits[i + 1]);
          i++;
        } else {
          cleanUnits.add(0xFFFD);
        }
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        cleanUnits.add(0xFFFD);
      } else {
        cleanUnits.add(unit);
      }
    }
    return String.fromCharCodes(cleanUnits);
  }
}
