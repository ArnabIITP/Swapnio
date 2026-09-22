/*
 * Swapnio - A Flutter-based skill swapping platform.
 * Copyright (C) 2026 Arnab Das and Manab Kumar Barman
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../theme.dart';
import '../../ui/fade_slide_in.dart';
import '../../ui/session_actions.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import 'chat_page.dart';
import 'notifications_page.dart';
import 'session_detail.dart';
import 'setup.dart';

/// The app's landing surface, answering "what needs me right now?".
///
/// One hero card shows the single most important thing (next session, people
/// waiting, an unread reply, an unfinished profile - in that order). Showing
/// one open loop instead of five keeps the next action obvious.
class HomeDashboard extends StatefulWidget {
  /// Lets dashboard cards jump the bottom navigation to another tab.
  final ValueChanged<int>? onNavigateToTab;

  const HomeDashboard({super.key, this.onNavigateToTab});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Built once in initState, never inside build(): .snapshots() hands back a
  // new Stream object each call, which makes StreamBuilder re-subscribe on
  // every rebuild and the whole dashboard visibly churns.
  late final Stream<QuerySnapshot> _acceptedSessionsStream;
  late final Stream<QuerySnapshot> _incomingLikesStream;
  late final Stream<QuerySnapshot> _chatRoomsStream;
  late final Stream<QuerySnapshot> _completedSessionsStream;
  late Future<QuerySnapshot> _profileViewsFuture;
  late Future<DocumentSnapshot> _myProfileFuture;
  late Future<QuerySnapshot> _communityFuture;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    final uid = _uid;
    _acceptedSessionsStream = db
        .collection('swaps')
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots();
    _incomingLikesStream =
        db.collection('swipeRequests').where('toUserId', isEqualTo: uid).snapshots();
    _chatRoomsStream =
        db.collection('chatRooms').where('users', arrayContains: uid).snapshots();
    _completedSessionsStream = db
        .collection('swaps')
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'completed')
        .snapshots();
    _loadFutures();
  }

  void _loadFutures() {
    final db = FirebaseFirestore.instance;
    _profileViewsFuture = db
        .collection('profileViews')
        .where('viewedUserId', isEqualTo: _uid)
        .where('timestamp',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7))))
        .get();
    _myProfileFuture = db.collection('users').doc(_uid).get();
    _communityFuture =
        db.collection('swaps').where('status', isEqualTo: 'completed').limit(100).get();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _push(Widget page) {
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.give,
          onRefresh: () async => setState(_loadFutures),
          child: StreamBuilder<QuerySnapshot>(
            stream: _completedSessionsStream,
            builder: (context, completedSnap) {
              final completed = completedSnap.data?.docs ?? const [];
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  FadeSlideIn(child: _buildHeader()),
                  const SizedBox(height: 18),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 80),
                    child: _buildWeekStrip(completed),
                  ),
                  const SizedBox(height: 22),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 160),
                    child: _buildHero(),
                  ),
                  const SizedBox(height: 26),
                  const SectionLabel('More for today'),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 240),
                    child: _buildTiles(completed),
                  ),
                  const SizedBox(height: 14),
                  _buildProfileViews(),
                  _buildReciprocityNudge(completed),
                  const SizedBox(height: 6),
                  _buildCommunityPulse(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildHeader() {
    final c = context.sw;
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUser;
    final authName = FirebaseAuth.instance.currentUser?.displayName ?? '';
    final fullName = (user?.name.isNotEmpty ?? false) ? user!.name : authName;
    final firstName = fullName.split(' ').first;
    final unread = appState.unreadNotifications;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(),
                  style: GoogleFonts.manrope(fontSize: 13.5, color: c.textMuted)),
              const SizedBox(height: 2),
              Text(
                firstName.isEmpty ? 'Welcome' : firstName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.display(fontSize: 30, color: c.text),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'Notifications',
          button: true,
          child: Pressable(
            onTap: () => _push(const NotificationsPage()),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                  child: Icon(Icons.notifications_none_rounded, color: c.text, size: 22),
                ),
                if (unread > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                      decoration: BoxDecoration(
                        color: c.give,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: c.bg, width: 2),
                      ),
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Pressable(
          onTap: () => widget.onNavigateToTab?.call(3),
          child: SwapAvatar(
            name: fullName,
            photoUrl: user?.photoUrl,
            size: 44,
            radius: 22,
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- week strip

  /// Weekly rhythm rather than daily streaks: swaps happen on a weekly
  /// cadence, so a daily streak would punish completely normal behaviour.
  Widget _buildWeekStrip(List<QueryDocumentSnapshot> completed) {
    final c = context.sw;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final doneDays = <int>{};
    for (final doc in completed) {
      final ts = (doc.data() as Map<String, dynamic>)['completedAt'];
      if (ts is! Timestamp) continue;
      final d = ts.toDate();
      final offset = DateTime(d.year, d.month, d.day).difference(monday).inDays;
      if (offset >= 0 && offset < 7) doneDays.add(offset);
    }
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final count = doneDays.length;

    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: doneDays.contains(i)
                    ? c.give
                    : i == today.weekday - 1
                        ? c.ink
                        : c.surfaceLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                letters[i],
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: doneDays.contains(i) || i == today.weekday - 1
                      ? Colors.white
                      : c.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          count == 0 ? 'None yet' : '$count this week',
          style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w800, color: c.text),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- hero

  Widget _buildHero() {
    return StreamBuilder<QuerySnapshot>(
      stream: _acceptedSessionsStream,
      builder: (context, sessionSnap) {
        final session = _nextSession(sessionSnap.data?.docs ?? const []);
        // A session within the next two days outranks everything else.
        if (session != null &&
            session.$2.difference(DateTime.now()) < const Duration(hours: 48)) {
          return _sessionHero(session.$1, session.$2);
        }
        return StreamBuilder<QuerySnapshot>(
          stream: _incomingLikesStream,
          builder: (context, likesSnap) {
            final likes = likesSnap.data?.docs.length ?? 0;
            if (likes > 0) return _likesHero(likes);
            return StreamBuilder<QuerySnapshot>(
              stream: _chatRoomsStream,
              builder: (context, chatSnap) {
                final unread = _unreadRooms(chatSnap.data?.docs ?? const []);
                if (unread.isNotEmpty) return _chatHero(unread);
                if (session != null) return _sessionHero(session.$1, session.$2);
                final completion = _profileCompletion();
                if (completion != null && completion.$1 < 1) {
                  return _profileHero(completion.$1, completion.$2);
                }
                return _discoverHero();
              },
            );
          },
        );
      },
    );
  }

  (DocumentSnapshot, DateTime)? _nextSession(List<QueryDocumentSnapshot> docs) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 3));
    (DocumentSnapshot, DateTime)? best;
    for (final doc in docs) {
      final ts = (doc.data() as Map<String, dynamic>)['scheduledFor'];
      if (ts is! Timestamp) continue;
      final when = ts.toDate();
      if (when.isBefore(cutoff)) continue;
      if (best == null || when.isBefore(best.$2)) best = (doc, when);
    }
    return best;
  }

  List<QueryDocumentSnapshot> _unreadRooms(List<QueryDocumentSnapshot> rooms) =>
      rooms.where((doc) {
        final counts = Map<String, dynamic>.from(
            (doc.data() as Map<String, dynamic>)['unreadCount'] ?? {});
        return ((counts[_uid] as num?)?.toInt() ?? 0) > 0;
      }).toList();

  (double, String)? _profileCompletion() {
    final user = Provider.of<AppState>(context).currentUser;
    if (user == null) return null;
    final checks = <String, bool>{
      'a photo': user.photoUrl.isNotEmpty,
      'a short bio': user.bio.isNotEmpty,
      'skills you teach': user.skillsOffered.isNotEmpty,
      'skills you want': user.skillsWanted.isNotEmpty,
      'your availability': user.availability.isNotEmpty,
    };
    final done = checks.values.where((v) => v).length;
    final missing = checks.entries
        .firstWhere((e) => !e.value, orElse: () => checks.entries.first)
        .key;
    return (done / checks.length, missing);
  }

  Widget _heroShell({
    required IconData eyebrowIcon,
    required String eyebrow,
    required String headline,
    String? body,
    Widget? middle,
    required String cta,
    required VoidCallback onCta,
    String? secondary,
    VoidCallback? onSecondary,
  }) {
    final c = context.sw;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(eyebrowIcon, size: 14, color: c.win),
              const SizedBox(width: 6),
              Flexible(
                child: Text(eyebrow.toUpperCase(), style: AppTheme.label(color: c.win)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(headline,
              style: AppTheme.display(fontSize: 27, color: Colors.white, height: 1.12)),
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                  fontSize: 13.5, color: Colors.white.withValues(alpha: 0.72), height: 1.4),
            ),
          ],
          if (middle != null) ...[const SizedBox(height: 16), middle],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Pressable(
                  onTap: onCta,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: c.win, borderRadius: BorderRadius.circular(16)),
                    child: Text(cta,
                        style: GoogleFonts.manrope(
                            fontSize: 15, fontWeight: FontWeight.w800, color: c.onWin)),
                  ),
                ),
              ),
              if (secondary != null) ...[
                const SizedBox(width: 10),
                Pressable(
                  onTap: onSecondary,
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(secondary,
                        style: GoogleFonts.manrope(
                            fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _sessionHero(DocumentSnapshot doc, DateTime when) {
    final data = doc.data() as Map<String, dynamic>;
    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final otherId = List<String>.from(data['participants'] ?? [])
        .firstWhere((p) => p != _uid, orElse: () => '');
    final otherName = (names[otherId] as String?) ?? 'your partner';
    final link = (data['meetingLink'] as String?)?.trim() ?? '';
    final sides = swapSidesFor(data, _uid);
    final now = DateTime.now();
    final diff = when.difference(now);
    final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
    final eyebrow = diff.isNegative
        ? 'Happening now'
        : diff.inMinutes < 60
            ? 'Live in ${diff.inMinutes} min'
            : sameDay
                ? 'Today · ${DateFormat.jm().format(when)}'
                : '${DateFormat.MMMEd().format(when)} · ${DateFormat.jm().format(when)}';
    final topic = sides.myGet.isNotEmpty ? sides.myGet : sides.myGive;
    void openDetail() => _push(SessionDetailPage(swapId: doc.id));

    return _heroShell(
      eyebrowIcon: Icons.radio_button_checked_rounded,
      eyebrow: eyebrow,
      headline: topic.isEmpty
          ? 'Session with $otherName'
          : '$topic with ${otherName.split(' ').first}',
      middle: SwapSplit(giveSkill: sides.myGive, getSkill: sides.myGet),
      cta: link.isNotEmpty ? 'Join session' : 'View session',
      onCta: link.isNotEmpty ? () => copyMeetingLink(context, link) : openDetail,
      secondary: link.isNotEmpty ? 'Details' : null,
      onSecondary: openDetail,
    );
  }

  Widget _likesHero(int count) => _heroShell(
        eyebrowIcon: Icons.favorite_rounded,
        eyebrow: 'Waiting on you',
        headline: count == 1
            ? '1 person wants to swap with you'
            : '$count people want to swap with you',
        body: 'They already liked your profile. Reply before they move on.',
        cta: 'Review requests',
        onCta: () => widget.onNavigateToTab?.call(2),
      );

  Widget _chatHero(List<QueryDocumentSnapshot> rooms) {
    final data = rooms.first.data() as Map<String, dynamic>;
    final users = List<String>.from(data['users'] ?? []);
    final otherId = users.firstWhere((id) => id != _uid, orElse: () => '');
    final names = Map<String, dynamic>.from(data['userNames'] ?? {});
    final photos = Map<String, dynamic>.from(data['userPhotos'] ?? {});
    final otherName = (names[otherId] as String?) ?? 'Someone';
    return _heroShell(
      eyebrowIcon: Icons.mark_chat_unread_rounded,
      eyebrow: rooms.length == 1 ? 'New message' : '${rooms.length} chats unread',
      headline: '${otherName.split(' ').first} replied',
      body: (data['lastMessage'] as String?) ?? '',
      cta: 'Open chat',
      onCta: () => _push(ChatPage(
        chatRoomId: rooms.first.id,
        otherUserName: otherName,
        otherUserPhoto: (photos[otherId] as String?) ?? '',
        otherUserId: otherId,
      )),
      secondary: rooms.length > 1 ? 'All' : null,
      onSecondary: () => widget.onNavigateToTab?.call(2),
    );
  }

  Widget _profileHero(double progress, String missing) => _heroShell(
        eyebrowIcon: Icons.bolt_rounded,
        eyebrow: '${(progress * 100).round()}% done',
        headline: 'Finish your profile',
        body: 'Add $missing - complete profiles get far more matches.',
        middle: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(context.sw.win),
            ),
          ),
        ),
        cta: 'Continue',
        onCta: () => _push(const ProfileSetupPage()),
      );

  Widget _discoverHero() => _heroShell(
        eyebrowIcon: Icons.explore_rounded,
        eyebrow: 'Your next swap',
        headline: 'Find someone to learn from this week',
        body: 'People whose skills fit yours are ranked first.',
        cta: 'Discover people',
        onCta: () => widget.onNavigateToTab?.call(1),
      );

  // ---------------------------------------------------------------- tiles

  Widget _buildTiles(List<QueryDocumentSnapshot> completed) {
    final c = context.sw;
    final completion = _profileCompletion();
    final now = DateTime.now();
    final thisMonth = completed.where((d) {
      final ts = (d.data() as Map<String, dynamic>)['completedAt'];
      if (ts is! Timestamp) return false;
      final t = ts.toDate();
      return t.year == now.year && t.month == now.month;
    }).length;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _tile(
              countValue: completion == null ? null : (completion.$1 * 100).round(),
              value: completion == null ? '-' : '${(completion.$1 * 100).round()}%',
              label: 'profile strength',
              color: c.get,
              onTap: () => _push(const ProfileSetupPage()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FutureBuilder<DocumentSnapshot>(
              future: _myProfileFuture,
              builder: (context, snap) {
                final data = snap.data?.data() as Map<String, dynamic>?;
                final goal = (data?['monthlyGoal'] as String?)?.trim() ?? '';
                return _tile(
                  countValue: thisMonth,
                  value: '$thisMonth',
                  label: goal.isEmpty ? 'swaps this month' : goal,
                  color: c.give,
                  onTap: () => widget.onNavigateToTab?.call(1),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatRoomsStream,
              builder: (context, snap) {
                final n = _unreadRooms(snap.data?.docs ?? const []).length;
                return _tile(
                  countValue: n,
                  value: '$n',
                  label: n == 1 ? 'unread chat' : 'unread chats',
                  color: c.text,
                  onTap: () => widget.onNavigateToTab?.call(2),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required num? countValue,
    required String value,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final c = context.sw;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: countValue == null
                  ? Text(value,
                      style: AppTheme.display(fontSize: 30, color: color, height: 1.1))
                  : CountUpText(
                      value: countValue,
                      suffix: value.endsWith('%') ? '%' : '',
                      style: AppTheme.display(fontSize: 30, color: color, height: 1.1),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 11.5, color: c.textMuted, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- secondary rows

  Widget _slimRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.manrope(
                            fontSize: 13.5, fontWeight: FontWeight.w800, color: c.text)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted)),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// Social validation: knowing people looked is a nudge to keep a profile
  /// sharp, and a reason to open the app at all.
  Widget _buildProfileViews() {
    return FutureBuilder<QuerySnapshot>(
      future: _profileViewsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) return const SizedBox.shrink();
        final viewers = snapshot.data!.docs
            .map((d) => (d.data() as Map<String, dynamic>)['viewerId'])
            .toSet()
            .length;
        if (viewers == 0) return const SizedBox.shrink();
        return _slimRow(
          icon: Icons.visibility_rounded,
          color: context.sw.get,
          title: '$viewers ${viewers == 1 ? 'person' : 'people'} viewed your profile',
          subtitle: 'In the last 7 days',
        );
      },
    );
  }

  /// Reciprocity: someone who taught you is more likely to accept when you
  /// can give something back.
  Widget _buildReciprocityNudge(List<QueryDocumentSnapshot> completed) {
    final me = Provider.of<AppState>(context).currentUser;
    if (me == null || me.skillsOffered.isEmpty) return const SizedBox.shrink();
    final mine = me.skillsOffered.map((s) => s.toLowerCase()).toSet();
    for (final doc in completed.take(20)) {
      final data = doc.data() as Map<String, dynamic>;
      final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
      final otherId = List<String>.from(data['participants'] ?? [])
          .firstWhere((p) => p != _uid, orElse: () => '');
      if (otherId.isEmpty) continue;
      // What the partner learned from you in that swap.
      final theirWant = swapSidesFor(data, _uid).myGive.toLowerCase();
      if (theirWant.isEmpty || !mine.contains(theirWant)) continue;
      final otherName = (names[otherId] as String?) ?? 'Your past partner';
      return _slimRow(
        icon: Icons.volunteer_activism_rounded,
        color: context.sw.give,
        title: 'Swap again with ${otherName.split(' ').first}',
        subtitle: 'They learned $theirWant from you - there may be more to trade.',
        onTap: () => widget.onNavigateToTab?.call(2),
      );
    }
    return const SizedBox.shrink();
  }

  /// Social proof: visible activity makes the app feel alive.
  Widget _buildCommunityPulse() {
    return FutureBuilder<QuerySnapshot>(
      future: _communityFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) return const SizedBox.shrink();
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        var recent = 0;
        for (final doc in snapshot.data!.docs) {
          final ts = (doc.data() as Map<String, dynamic>)['completedAt'];
          if (ts is Timestamp && ts.toDate().isAfter(weekAgo)) recent++;
        }
        if (recent == 0) return const SizedBox.shrink();
        final c = context.sw;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.groups_rounded, size: 15, color: c.textMuted),
              const SizedBox(width: 6),
              Text(
                '$recent swap${recent == 1 ? '' : 's'} completed this week',
                style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}
