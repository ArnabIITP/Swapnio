import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/referral_service.dart';
import '../../theme.dart';
import '../../ui/swapnio_badges.dart';
import '../../ui/swapnio_kit.dart';
import 'profile_share_sheet.dart';

/// Referral program: your QR, how many people it brought in, progress to the
/// next referral badge, and - for new accounts - claiming who invited you.
class InviteFriendsPage extends StatelessWidget {
  final Map<String, dynamic> userData;

  const InviteFriendsPage({super.key, required this.userData});

  static const _tiers = [
    (1, 'referral_1', 'Connector', '+20 points'),
    (5, 'referral_5', 'Ambassador', 'badge + stamp'),
    (15, 'referral_15', 'Web Weaver', 'top badge + stamp'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SwapHeader(
              title: 'Invite friends',
              subtitle: 'Grow your web, earn badges',
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ReferralService.instance.myReferrals(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? const [];
                  final joined = docs.length;
                  final qualified = docs
                      .where((d) => d.data()['status'] == 'qualified')
                      .length;
                  final next = _tiers
                      .where((t) => qualified < t.$1)
                      .firstOrNull;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _stat(context, '$joined', 'joined'),
                                const SizedBox(width: 24),
                                _stat(context, '$qualified', 'qualified'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              next == null
                                  ? 'You have every referral badge. Legend.'
                                  : '${next.$1 - qualified} more to ${next.$3}',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800,
                                color: c.text,
                              ),
                            ),
                            if (next != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: qualified / next.$1,
                                  minHeight: 6,
                                  backgroundColor: c.surfaceLow,
                                  valueColor: AlwaysStoppedAnimation(c.give),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              'Friends who join by scanning your QR on their first day are linked to you. '
                              'It counts once they finish their first verified session.',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                height: 1.4,
                                color: c.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      PillButton(
                        label: 'Show my QR',
                        icon: Icons.qr_code_2_rounded,
                        onTap: () =>
                            showProfileShareSheet(context, userData: userData),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'REWARDS',
                        style: AppTheme.label(
                          color: c.textMuted,
                        ).copyWith(letterSpacing: 1.8),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final t in _tiers)
                            Column(
                              children: [
                                SwapBadge(
                                  spec: badgeSpecFor(t.$2),
                                  earned: qualified >= t.$1,
                                  size: 72,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  t.$3,
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: c.text,
                                  ),
                                ),
                                Text(
                                  '${t.$1} · ${t.$4}',
                                  style: GoogleFonts.manrope(
                                    fontSize: 10.5,
                                    color: c.textMuted,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (docs.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'YOUR INVITES',
                          style: AppTheme.label(
                            color: c.textMuted,
                          ).copyWith(letterSpacing: 1.8),
                        ),
                        const SizedBox(height: 8),
                        for (final d in docs)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              (d.data()['refereeName'] as String?)
                                          ?.isNotEmpty ==
                                      true
                                  ? d.data()['refereeName'] as String
                                  : 'New member',
                            ),
                            trailing: Text(
                              switch (d.data()['status']) {
                                'qualified' => 'Qualified',
                                'revoked' => 'Revoked',
                                _ => 'Waiting for first session',
                              },
                              style: TextStyle(
                                color: d.data()['status'] == 'qualified'
                                    ? c.success
                                    : c.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    final c = context.sw;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTheme.display(fontSize: 34, color: c.text)),
        Text(
          label,
          style: GoogleFonts.manrope(fontSize: 12.5, color: c.textMuted),
        ),
      ],
    );
  }
}
