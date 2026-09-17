// Forum post model
class ForumPost {
  String id;
  String authorId;
  String content;
  DateTime createdAt;
  List<String> replies;
  // Null/empty means "General" - posts don't have to be tied to a skill.
  String? skillName;

  ForumPost({
    required this.id,
    required this.authorId,
    required this.content,
    required this.createdAt,
    required this.replies,
    this.skillName,
  });
}
