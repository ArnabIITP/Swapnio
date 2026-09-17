import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'forum_model.dart';

class ForumProvider extends ChangeNotifier {
  List<ForumPost> _posts = [];
  bool _loading = false;
  String? _error;

  List<ForumPost> get posts => _posts;
  bool get loading => _loading;
  String? get error => _error;

  ForumProvider() {
    fetchPosts();
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
        );
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> addPost(String authorId, String content) async {
    final post = ForumPost(
      id: '',
      authorId: authorId,
      content: content,
      createdAt: DateTime.now(),
      replies: [],
    );
    try {
      await FirebaseFirestore.instance.collection('forum_posts').add({
        'authorId': post.authorId,
        'content': post.content,
        'createdAt': post.createdAt,
        'replies': post.replies,
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
