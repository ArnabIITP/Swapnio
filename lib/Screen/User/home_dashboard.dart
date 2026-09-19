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
import 'chat_page.dart';
import 'notifications_page.dart';
import 'setup.dart';

/// The app's landing surface, answering "what needs me right now?".
///
/// This used to be a second browse feed, duplicating the Discover deck. Browsing
/// is a task you do occasionally; the things that actually pull someone back
/// are their next session, unread messages and people waiting on them - all of
/// which were previously buried two or three levels deep.
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
  // new Stream object each call, which makes StreamBuilder tear down and
  // re-subscribe on every rebuild - and AppState notifies often enough that
  // the whole dashboard would visibly churn.
  late final Stream<QuerySnapshot> _acceptedSessionsStream;
  late final Stream<QuerySnapshot> _incomingLikesStream;
  late final Stream<QuerySnapshot> _chatRoomsStream;
  late final Stream<QuerySnapshot> _completedSessionsStream;
  late final Future<QuerySnapshot> _profileViewsFuture;
  late final Future<DocumentSnapshot> _myProfileFuture;

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    _acceptedSessionsStream = FirebaseFirestore.instance
        .collection('swaps')
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots();
    _incomingLikesStream = FirebaseFirestore.instance
        .collection('swipeRequests')
        .where('toUserId', isEqualTo: uid)
        .snapshots();
    _chatRoomsStream = FirebaseFirestore.instance
        .collection('chatRooms')
        .where('users', arrayContains: uid)
        .snapshots();
    _completedSessionsStream = FirebaseFirestore.instance
        .collection('swaps')
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'completed')
        .snapshots();
    _profileViewsFuture = FirebaseFirestore.instance
        .collection('profileViews')
        .where('viewedUserId', isEqualTo: uid)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(
                DateTime.now().subtract(const Duration(days: 7))))
        .get();
    _myProfileFuture =
        FirebaseFirestore.instance.collection('users').doc(uid).get();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final username =
        FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              _buildHeader(username),
              const SizedBox(height: 20),
              _buildProfileCompletion(),
              _buildMonthlyGoal(),
              _buildNextSession(),
              _buildWaitingOnYou(),
              _buildProfileViews(),
              _buildUnreadChats(),
              _buildWeeklyRhythm(),
              _buildReciprocityNudge(),
              _buildCommunityPulse(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String username) {
    final unread = Provider.of<AppState>(context).unreadNotifications;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting()}${username.isNotEmpty ? ', $username' : ''}!',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ebGaramond(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Here is what needs you today',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none,
                  size: 27, color: AppTheme.primaryColor),
              tooltip: 'Notifications',
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage()),
                );
              },
            ),
            if (unread > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Zeigarnik effect: an unfinished profile nags in a useful way, and the
  /// missing piece is one tap from being fixed.
  Widget _buildProfileCompletion() {
    final user = Provider.of<AppState>(context).currentUser;
    if (user == null) return const SizedBox.shrink();

    final checks = <String, bool>{
      'a photo': user.photoUrl.isNotEmpty,
      'a short bio': user.bio.isNotEmpty,
      'skills you teach': user.skillsOffered.isNotEmpty,
      'skills you want': user.skillsWanted.isNotEmpty,
      'your availability': user.availability.isNotEmpty,
    };
    final done = checks.values.where((v) => v).length;
    final total = checks.length;
    if (done == total) return const SizedBox.shrink();

    final missing = checks.entries.firstWhere((e) => !e.value).key;
    final progress = done / total;

    return _card(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSetupPage()),
        );
      },
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 5,
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
                    ),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Finish your profile',
                    style: _titleStyle(context)),
                const SizedBox(height: 3),
                Text(
                  'Add $missing — complete profiles get far more matches.',
                  style: _subtitleStyle(context),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        ],
      ),
    );
  }

  /// Commitment & consistency: a goal someone stated during onboarding,
  /// kept in view. People act in line with what they've said they'll do.
  Widget _buildMonthlyGoal() {
    return FutureBuilder<DocumentSnapshot>(
      future: _myProfileFuture,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final goal = (data?['monthlyGoal'] as String?)?.trim() ?? '';
        if (goal.isEmpty) return const SizedBox.shrink();
        return _card(
          accent: const Color(0xFFF2C14E),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onNavigateToTab?.call(1);
          },
          child: Row(
            children: [
              const Icon(Icons.flag, color: Color(0xFFD9A21B), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your goal this month', style: _subtitleStyle(context)),
                    const SizedBox(height: 2),
                    Text(goal, style: _titleStyle(context)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        );
      },
    );
  }

  /// Social validation: knowing people looked is a strong nudge to keep a
  /// profile sharp, and a reason to open the app at all.
  Widget _buildProfileViews() {
    return FutureBuilder<QuerySnapshot>(
      future: _profileViewsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final viewers = snapshot.data!.docs
            .map((d) => (d.data() as Map<String, dynamic>)['viewerId'])
            .toSet()
            .length;
        if (viewers == 0) return const SizedBox.shrink();
        return _card(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.visibility,
                    color: AppTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$viewers ${viewers == 1 ? 'person' : 'people'} viewed your profile',
                      style: _titleStyle(context),
                    ),
                    const SizedBox(height: 3),
                    Text('In the last 7 days. A clear bio and photo turn views into requests.',
                        style: _subtitleStyle(context)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The single most useful thing the app can show: your next commitment.
  Widget _buildNextSession() {
    if (_uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: _acceptedSessionsStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        // Soonest upcoming session, resolved client-side so this needs no
        // extra composite index.
        final now = DateTime.now();
        DocumentSnapshot? next;
        DateTime? nextTime;
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = data['scheduledFor'] as Timestamp?;
          if (ts == null) continue;
          final when = ts.toDate();
          if (when.isBefore(now.subtract(const Duration(hours: 3)))) continue;
          if (nextTime == null || when.isBefore(nextTime)) {
            nextTime = when;
            next = doc;
          }
        }
        if (next == null || nextTime == null) return const SizedBox.shrink();

        final data = next.data() as Map<String, dynamic>;
        final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
        final otherId = List<String>.from(data['participants'] ?? [])
            .firstWhere((p) => p != _uid, orElse: () => '');
        final otherName = (names[otherId] as String?) ?? 'your partner';
        final meetingLink = (data['meetingLink'] as String?) ?? '';
        final diff = nextTime.difference(now);
        final countdown = diff.isNegative
            ? 'Happening now'
            : diff.inHours < 1
                ? 'In ${diff.inMinutes} min'
                : diff.inHours < 24
                    ? 'In ${diff.inHours}h'
                    : DateFormat.MMMd().add_jm().format(nextTime);

        return _card(
          accent: AppTheme.primaryColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_available,
                      color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text('Next session', style: _titleStyle(context)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      countdown,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('With $otherName', style: _subtitleStyle(context)),
              Text(
                '${data['skillOffered'] ?? ''} ⇄ ${data['skillWanted'] ?? ''}',
                style: _subtitleStyle(context),
              ),
              if ((data['agenda'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Agenda: ${data['agenda']}',
                    style: _subtitleStyle(context)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (meetingLink.isNotEmpty)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Clipboard.setData(ClipboardData(text: meetingLink));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Link copied: $meetingLink')),
                          );
                        },
                        icon: const Icon(Icons.videocam, size: 18),
                        label: const Text('Join'),
                      ),
                    ),
                  if (meetingLink.isNotEmpty) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        widget.onNavigateToTab?.call(2);
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Details'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// People who liked you and are waiting - the strongest pull in the app,
  /// previously only discoverable by chance while swiping.
  Widget _buildWaitingOnYou() {
    if (_uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: _incomingLikesStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return _card(
          accent: AppTheme.tertiaryColor,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onNavigateToTab?.call(2);
          },
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.tertiaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.favorite,
                    color: AppTheme.tertiaryColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? '1 person is waiting on you'
                          : '$count people are waiting on you',
                      style: _titleStyle(context),
                    ),
                    const SizedBox(height: 3),
                    Text('They liked you — reply before they move on.',
                        style: _subtitleStyle(context)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnreadChats() {
    if (_uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: _chatRoomsStream,
      builder: (context, snapshot) {
        final rooms = snapshot.data?.docs ?? [];
        final unreadRooms = rooms.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final counts = Map<String, dynamic>.from(data['unreadCount'] ?? {});
          return ((counts[_uid] as num?)?.toInt() ?? 0) > 0;
        }).toList();
        if (unreadRooms.isEmpty) return const SizedBox.shrink();

        final first = unreadRooms.first;
        final data = first.data() as Map<String, dynamic>;
        final users = List<String>.from(data['users'] ?? []);
        final otherId = users.firstWhere((id) => id != _uid, orElse: () => '');
        final names = Map<String, dynamic>.from(data['userNames'] ?? {});
        final photos = Map<String, dynamic>.from(data['userPhotos'] ?? {});
        final otherName = (names[otherId] as String?) ?? 'Someone';

        return _card(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPage(
                  chatRoomId: first.id,
                  otherUserName: otherName,
                  otherUserPhoto: (photos[otherId] as String?) ?? '',
                  otherUserId: otherId,
                ),
              ),
            );
          },
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.forum,
                    color: AppTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unreadRooms.length == 1
                          ? 'Unread message from $otherName'
                          : 'Unread messages in ${unreadRooms.length} chats',
                      style: _titleStyle(context),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (data['lastMessage'] as String?) ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _subtitleStyle(context),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        );
      },
    );
  }

  /// Weekly rhythm rather than daily streaks: swaps happen on a weekly
  /// cadence, so a daily streak would punish completely normal behaviour.
  Widget _buildWeeklyRhythm() {
    if (_uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: _completedSessionsStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        var thisWeek = 0;
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = data['completedAt'] as Timestamp?;
          if (ts != null && ts.toDate().isAfter(weekAgo)) thisWeek++;
        }

        return _card(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF86A89B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_fire_department,
                    color: Color(0xFF86A89B), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thisWeek == 0
                          ? 'No sessions yet this week'
                          : '$thisWeek session${thisWeek == 1 ? '' : 's'} this week',
                      style: _titleStyle(context),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      thisWeek == 0
                          ? 'One session this week keeps your rhythm going.'
                          : 'Nice. ${docs.length} completed all-time.',
                      style: _subtitleStyle(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Reciprocity: someone who taught you is far more likely to accept when
  /// you can give something back, and the data to spot that already exists.
  Widget _buildReciprocityNudge() {
    final me = Provider.of<AppState>(context).currentUser;
    if (me == null || me.skillsOffered.isEmpty || _uid.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('swaps')
          .where('participants', arrayContains: _uid)
          .where('status', isEqualTo: 'completed')
          .limit(20)
          .get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        final mine = me.skillsOffered.map((s) => s.toLowerCase()).toSet();
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
          final otherId = List<String>.from(data['participants'] ?? [])
              .firstWhere((p) => p != _uid, orElse: () => '');
          if (otherId.isEmpty) continue;
          // What the partner wanted in that swap, from their perspective.
          final theirWant = (data['createdBy'] == _uid
                  ? data['skillOffered']
                  : data['skillWanted'])
              ?.toString()
              .toLowerCase();
          if (theirWant == null || theirWant.isEmpty) continue;
          if (!mine.contains(theirWant)) continue;

          final otherName = (names[otherId] as String?) ?? 'Your past partner';
          return _card(
            accent: const Color(0xFF86A89B),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onNavigateToTab?.call(2);
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF86A89B).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.volunteer_activism,
                      color: Color(0xFF86A89B), size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Give back to $otherName',
                          style: _titleStyle(context)),
                      const SizedBox(height: 3),
                      Text(
                        'They wanted to learn $theirWant — which you teach.',
                        style: _subtitleStyle(context),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// Social proof: an app with visible activity feels alive, which matters
  /// most while the community is still small.
  Widget _buildCommunityPulse() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('swaps')
          .where('status', isEqualTo: 'completed')
          .limit(100)
          .get(),
      builder: (context, snapshot) {
        // Requires the swaps(status, scheduledFor) index shape; failures just
        // hide the card rather than breaking the dashboard.
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data!.docs;
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        final skills = <String>{};
        var recent = 0;
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = data['completedAt'] as Timestamp?;
          if (ts != null && ts.toDate().isAfter(weekAgo)) recent++;
          final offered = data['skillOffered']?.toString();
          if (offered != null && offered.isNotEmpty) skills.add(offered);
        }
        if (recent == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(
            child: Text(
              '$recent session${recent == 1 ? '' : 's'} happened this week'
              '${skills.isEmpty ? '' : ' across ${skills.length} skills'}',
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle _titleStyle(BuildContext context) => GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      );

  TextStyle _subtitleStyle(BuildContext context) => GoogleFonts.manrope(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      );

  Widget _card({required Widget child, VoidCallback? onTap, Color? accent}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: (accent ?? AppTheme.warmBorder)
                    .withValues(alpha: accent != null ? 0.35 : 1),
              ),
              boxShadow: AppTheme.softShadow,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
