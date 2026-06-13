/// An annotation representing a single spell-check error in the document.
/// It maps to a span of text within a specific fragment.
class SpellAnnotation {
  final String nodeId;
  final int fragmentIndex;
  final int startOffset;
  final int endOffset;
  final List<String> suggestions;
  final String misspelledWord;

  const SpellAnnotation({
    required this.nodeId,
    required this.fragmentIndex,
    required this.startOffset,
    required this.endOffset,
    required this.suggestions,
    required this.misspelledWord,
  });

  /// Returns true if this annotation covers the given global offset
  /// in the fragment identified by [nodeId].
  bool covers(String id, int offset) {
    return id == nodeId && offset >= startOffset && offset < endOffset;
  }
}

/// Holds the current spell-check annotations for the entire document.
/// Organized as a map from nodeId (paragraph id) to a list of annotations.
class SpellCheckState {
  final Map<String, List<SpellAnnotation>> _annotations = {};

  List<SpellAnnotation> annotationsForNode(String nodeId) {
    return List.unmodifiable(_annotations[nodeId] ?? const []);
  }

  /// Replaces all annotations for [nodeId] with [annotations].
  void updateNode(String nodeId, List<SpellAnnotation> annotations) {
    if (annotations.isEmpty) {
      _annotations.remove(nodeId);
    } else {
      _annotations[nodeId] = annotations;
    }
  }

  /// Removes all annotations for [nodeId].
  void clearNode(String nodeId) {
    _annotations.remove(nodeId);
  }

  /// Clears all annotations.
  void clearAll() {
    _annotations.clear();
  }

  /// Shifts all annotations in [nodeId] that start at or after [fromOffset]
  /// by [delta] characters. Used when the user inserts/deletes text
  /// without re-triggering a full spell check.
  void shiftAnnotations(String nodeId, int fromOffset, int delta) {
    final list = _annotations[nodeId];
    if (list == null || list.isEmpty) return;

    final updated = <SpellAnnotation>[];
    for (final ann in list) {
      // Annotation entirely before the edit point → unchanged
      if (ann.endOffset <= fromOffset) {
        updated.add(ann);
        continue;
      }
      // Annotation entirely after the edit point → shift both offsets
      if (ann.startOffset >= fromOffset) {
        updated.add(SpellAnnotation(
          nodeId: ann.nodeId,
          fragmentIndex: ann.fragmentIndex,
          startOffset: ann.startOffset + delta,
          endOffset: ann.endOffset + delta,
          suggestions: ann.suggestions,
          misspelledWord: ann.misspelledWord,
        ));
        continue;
      }
      // Annotation overlaps the edit point → invalidate it (clear it)
      // A new check will be triggered by the debounce mechanism.
    }

    if (updated.isEmpty) {
      _annotations.remove(nodeId);
    } else {
      _annotations[nodeId] = updated;
    }
  }

  /// Removes all annotations whose misspelled word equals [word].
  void removeWord(String word) {
    final wordLower = word.toLowerCase();
    for (final entry in _annotations.entries.toList()) {
      final filtered = entry.value
          .where((a) => a.misspelledWord.toLowerCase() != wordLower)
          .toList();
      if (filtered.isEmpty) {
        _annotations.remove(entry.key);
      } else {
        _annotations[entry.key] = filtered;
      }
    }
  }
}
