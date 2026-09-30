import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';
import '../User/security_page.dart';

/// Admin view of one member: their security log and devices (the same
/// screen members see, read-only), plus the invites they've made, with a
/// revoke action for abuse.
class AdminMemberSecurityPage extends StatelessWidget {
  final String userId;
  final String name;

  const AdminMemberSecurityPage({
    super.key,
    required this.userId,
    required this.name,
  });

  Future<void> _revoke(
    BuildContext context,
    String refereeId,
    String refereeName,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Revoke invite of $refereeName?'),
        content: const Text(
          'It stops counting for this member, and their referral badges are recounted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFunctions.instance.httpsCallable('revokeReferral').call({
        'refereeId': refereeId,
      });
      messenger.showSnackBar(const SnackBar(content: Text('Invite revoked.')));
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? 'Could not revoke.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(name.isEmpty ? 'Member' : name),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Security'),
              Tab(text: 'Invites'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SecurityPage(userId: userId),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('referrals')
                  .where('referrerId', isEqualTo: userId)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                final counted = docs
                    .where((d) => d.data()['status'] == 'qualified')
                    .length;
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      snap.hasData ? 'No invites yet.' : 'Loading…',
                      style: TextStyle(color: c.textMuted),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${docs.length} invited · $counted counted',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final d in docs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          (d.data()['refereeName'] as String?)?.isNotEmpty ==
                                  true
                              ? d.data()['refereeName'] as String
                              : d.id,
                        ),
                        subtitle: Text(
                          '${d.data()['status']} · via ${d.data()['source'] ?? 'install'}',
                        ),
                        trailing: d.data()['status'] == 'revoked'
                            ? null
                            : TextButton(
                                onPressed: () => _revoke(
                                  context,
                                  d.id,
                                  d.data()['refereeName'] as String? ?? '',
                                ),
                                child: const Text('Revoke'),
                              ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
