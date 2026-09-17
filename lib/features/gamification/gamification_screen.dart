import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import 'gamification_provider.dart';

class GamificationScreen extends StatelessWidget {
  const GamificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return ChangeNotifierProvider(
      create: (_) => GamificationProvider(userId: userId),
      child: Consumer<GamificationProvider>(
        builder: (context, provider, _) {
          final gamification = provider.gamification;
          if (gamification == null) {
            return Scaffold(
              appBar: AppBar(title: Text('Gamification')),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Gamification')),
            body: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        context,
                        icon: Icons.stars,
                        label: 'Points',
                        value: '${gamification.points}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard(
                        context,
                        icon: Icons.military_tech,
                        label: 'Level',
                        value: '${gamification.level}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Badges:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: gamification.badges.isEmpty
                      ? const [Text('No badges yet - complete a swap session!')]
                      : gamification.badges
                          .map((b) => Chip(
                                label: Text(b),
                                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                                side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                              ))
                          .toList(),
                ),
                const SizedBox(height: 24),
                Text(
                  'Leaderboard',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildLeaderboard(userId),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warmBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 30),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  /// Top 10 users by gamification points. Gamification docs use the uid as the
  /// document id, so names are resolved with a single `whereIn` user query.
  Widget _buildLeaderboard(String myUserId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('gamification')
          .orderBy('points', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text('No points earned yet - be the first!');
        }
        final uids = docs.map((d) => d.id).toList();
        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: uids)
              .get(),
          builder: (context, usersSnap) {
            final names = <String, String>{};
            for (final doc in usersSnap.data?.docs ?? []) {
              names[doc.id] = (doc.data()['name'] as String?) ?? 'Swapnio user';
            }
            return Column(
              children: [
                for (var i = 0; i < docs.length; i++)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: i < 3
                          ? AppTheme.primaryColor.withValues(alpha: 0.15)
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      child: Text(
                        '#${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: i < 3
                              ? AppTheme.primaryColor
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                        ),
                      ),
                    ),
                    title: Text(
                      docs[i].id == myUserId
                          ? 'You'
                          : (names[docs[i].id] ?? 'Swapnio user'),
                      style: TextStyle(
                        fontWeight:
                            docs[i].id == myUserId ? FontWeight.bold : null,
                      ),
                    ),
                    trailing: Text(
                      '${docs[i].data()['points'] ?? 0} pts',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}