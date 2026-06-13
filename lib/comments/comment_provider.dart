import 'dart:async';

/// Abstract interface for a comment system plugin.
///
/// The [FluentDocument] holds an optional instance. When set,
/// the editor will display comment highlights, a sidebar with
/// comment cards, and allow adding / resolving / replying to
/// comments.
abstract class CommentProvider {
  /// Stream that emits whenever comments change (add, reply, resolve, delete,
  /// or mutation shift).
  Stream<void> get commentsChanged;

  /// Returns the list of active (non-orphan) comments for [nodeId].
  /// Each item is a map with the keys expected by the render layer:
  ///   'id'           -> String
  ///   'startOffset'  -> int
  ///   'endOffset'    -> int
  ///   'resolved'     -> bool
  ///   'orphan'       -> bool
  List<Map<String, dynamic>> commentsForNode(String nodeId);

  /// Returns the currently selected comment id (the one whose card is
  /// active in the sidebar). Null when none is selected.
  String? get selectedCommentId;
  set selectedCommentId(String? value);

  /// Adds a new comment anchored to [nodeId] from [startOffset] to [endOffset].
  /// Returns true if the comment was added, false if it overlaps an existing
  /// comment on the same node (in which case the caller should show a warning).
  bool addComment(String nodeId, int startOffset, int endOffset, String author, String text);

  /// Adds a reply to an existing comment.
  void addReply(String commentId, String author, String text);

  /// Marks a comment as resolved.
  void resolveComment(String commentId);

  /// Permanently deletes a comment.
  void deleteComment(String commentId);

  /// Notifies the provider that the text of [nodeId] was mutated.
  /// [fromOffset] is the point where characters were inserted or deleted.
  /// [delta] is positive for insertions, negative for deletions.
  void onDocumentMutation(String nodeId, int fromOffset, int delta);

  /// Exports all comments as serialisable maps for use by exporters.
  /// Each map contains:
  ///   'id', 'nodeId', 'startOffset', 'endOffset',
  ///   'authorName', 'text', 'createdAt',
  ///   'replies' -> List<Map>,
  ///   'resolved', 'orphan'
  List<Map<String, dynamic>> exportComments();

  /// Imports comments from a list of serialised maps (the inverse of
  /// [exportComments]). Replaces any existing comments.
  void importComments(List<Map<String, dynamic>> data);

  /// Default author name used when adding new comments or replies.
  String get currentAuthor;
  set currentAuthor(String value);

  /// Whether resolved comments should be visible.
  bool get showResolved;
  set showResolved(bool value);

  /// Disposes the provider.
  void dispose();
}
