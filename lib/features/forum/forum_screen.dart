import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/skill_catalog_service.dart';
import 'forum_provider.dart';

class ForumScreen extends StatefulWidget {
  const ForumScreen({super.key});

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  String? _composerSkill;

  @override
  void initState() {
    super.initState();
    SkillCatalogService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final TextEditingController postController = TextEditingController();
    final knownSkills = SkillCatalogService.instance.allKnown;
    return ChangeNotifierProvider(
      create: (_) => ForumProvider(),
      child: Consumer<ForumProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            appBar: AppBar(title: const Text('Community Forum')),
            body: Column(
              children: [
                // Skill filter: threads scoped to a skill instead of one flat
                // feed, so "ask a question" can actually lead to "meet a
                // teacher" for that specific skill.
                if (knownSkills.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: const Text('All'),
                            selected: provider.selectedSkill == null,
                            onSelected: (_) => provider.setSkillFilter(null),
                          ),
                        ),
                        ...knownSkills.map((skill) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(skill),
                                selected: provider.selectedSkill == skill,
                                onSelected: (_) => provider.setSkillFilter(skill),
                              ),
                            )),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (knownSkills.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: _composerSkill,
                              hint: const Text('Tag with a skill (optional)'),
                              isDense: true,
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('General'),
                                ),
                                ...knownSkills.map((skill) => DropdownMenuItem<String?>(
                                      value: skill,
                                      child: Text(skill),
                                    )),
                              ],
                              onChanged: (value) => setState(() => _composerSkill = value),
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: postController,
                              decoration: const InputDecoration(
                                hintText: 'Share something with the community...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              if (postController.text.trim().isNotEmpty) {
                                final ok = await provider.addPost(
                                  userId,
                                  postController.text.trim(),
                                  skillName: _composerSkill,
                                );
                                if (ok) {
                                  postController.clear();
                                } else if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Could not post. Please try again.')),
                                  );
                                }
                              }
                            },
                            child: const Text('Post'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: provider.loading
                      ? const Center(child: CircularProgressIndicator())
                      : provider.error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Could not load the forum.'),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: provider.fetchPosts,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : provider.filteredPosts.isEmpty
                      ? Center(
                          child: Text(provider.selectedSkill == null
                              ? 'No posts yet - be the first to share!'
                              : 'No posts about ${provider.selectedSkill} yet - be the first!'),
                        )
                      : ListView.builder(
                          itemCount: provider.filteredPosts.length,
                          itemBuilder: (context, idx) {
                            final post = provider.filteredPosts[idx];
                            final replyController = TextEditingController();
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if ((post.skillName ?? '').isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            post.skillName!,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Text(post.content, style: const TextStyle(fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text('By: ${post.authorId}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    const SizedBox(height: 8),
                                    if (post.replies.isNotEmpty)
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Replies:', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ...post.replies.map((r) => Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                                child: Text('- $r'),
                                              )),
                                        ],
                                      ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: replyController,
                                            decoration: const InputDecoration(hintText: 'Reply...'),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.send),
                                          onPressed: () async {
                                            if (replyController.text.trim().isNotEmpty) {
                                              final ok = await provider.addReply(
                                                  post.id, replyController.text.trim());
                                              if (ok) {
                                                replyController.clear();
                                              } else if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                      content: Text('Could not reply. Please try again.')),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
