import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'forum_model.dart';

class ForumProvider extends ChangeNotifier {
  List<ForumPost> _posts = [];
  bool _loading = false;
  String? _error;
  // Null means "show every skill" (the old flat-feed behavior).
  String? selectedSkill;

  List<ForumPost> get posts => _posts;
  bool get loading => _loading;
  String? get error => _error;

  /// Posts scoped to [selectedSkill], or every post when nothing's selected -
  /// this is what the UI actually renders, so a thread about "Guitar" isn't
  /// buried in a flat feed of everything else.
  List<ForumPost> get filteredPosts {
    if (selectedSkill == null) return _posts;
    return _posts.where((p) => p.skillName == selectedSkill).toList();
  }

  ForumProvider() {
    fetchPosts();
  }

  void setSkillFilter(String? skill) {
    selectedSkill = skill;
    notifyListeners();
  }

  Future<void> fetchPosts() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('forum_posts')
          .orderBy('createdAt', descending: true)
          .get();
      _posts = snapshot.docs.map((doc) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        return ForumPost(
          id: doc.id,
          authorId: (data['authorId'] as String?) ?? 'Unknown',
          content: (data['content'] as String?) ?? '',
          createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
          replies: List<String>.from(data['replies'] ?? []),
          skillName: data['skillName'] as String?,
        );
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> addPost(String authorId, String content, {String? skillName}) async {
    final post = ForumPost(
      id: '',
      authorId: authorId,
      content: content,
      createdAt: DateTime.now(),
      replies: [],
      skillName: skillName,
    );
    try {
      await FirebaseFirestore.instance.collection('forum_posts').add({
        'authorId': post.authorId,
        'content': post.content,
        'createdAt': post.createdAt,
        'replies': post.replies,
        'skillName': post.skillName,
      });
      await fetchPosts();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> addReply(String postId, String reply) async {
    try {
      final postRef = FirebaseFirestore.instance.collection('forum_posts').doc(postId);
      await postRef.update({
        'replies': FieldValue.arrayUnion([reply]),
      });
      await fetchPosts();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
