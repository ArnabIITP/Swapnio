import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import 'gamification_provider.dart';
import '../../ui/swapnio_badges.dart';
import '../../ui/swapnio_kit.dart';
import 'package:google_fonts/google_fonts.dart';

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
                const KitSection('Badges'),
                BadgeCollection(earnedIds: gamification.badges),
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
    final c = context.sw;
    return SurfaceCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.give.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: c.give, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: num.tryParse(value) == null
                      ? Text(value, style: AppTheme.display(fontSize: 24, color: c.text))
                      : CountUpText(
                          value: num.parse(value),
                          style: AppTheme.display(fontSize: 24, color: c.text),
                        ),
                ),
                Text(label,
                    style: GoogleFonts.manrope(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: c.textMuted)),
              ],
            ),
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
                          ? context.sw.give.withValues(alpha: 0.15)
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      child: Text(
                        '#${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: i < 3
                              ? context.sw.give
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