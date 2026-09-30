import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../Screen/User/session_detail.dart';
import '../theme.dart';
import 'session_actions.dart';
import 'swapnio_widgets.dart';

/// A proposed session, as it appears in the chat (a `type: 'session'`
/// message the server posts when someone proposes). It follows the session
/// live - status, time and any requested new time - and opens it on tap.
class SessionChatCard extends StatelessWidget {
  final String swapId;
  final bool mine;

  const SessionChatCard({super.key, required this.swapId, required this.mine});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('swaps')
                .doc(swapId)
                .snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data();
              if (data == null) {
                return Container(
                  height: 90,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }
              final status = data['status'] as String? ?? 'pending';
              final when = (data['scheduledFor'] as Timestamp?)?.toDate();
              final minutes = (data['plannedMinutes'] as num?)?.toInt() ?? 60;
              final sides = swapSidesFor(data, uid);
              final (label, color) = switch (status) {
                'accepted' => ('Accepted', c.success),
                'completed' => ('Completed', c.get),
                'awaiting_ratings' => ('Waiting for ratings', c.get),
                'declined' => ('Declined', c.textMuted),
                'cancelled' => ('Cancelled', c.textMuted),
                'no_show' => ('No-show', c.textMuted),
                _ =>
                  data['createdBy'] == uid
                      ? ('Waiting for reply', c.give)
                      : ('Needs your answer', c.give),
              };
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDetailPage(swapId: swapId),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.event_rounded, size: 18, color: c.give),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              mine
                                  ? 'You proposed a session'
                                  : 'Session proposed',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: c.text,
                              ),
                            ),
                          ),
                          TintTag(label, color: color),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SwapSplit(giveSkill: sides.myGive, getSkill: sides.myGet),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 15,
                            color: c.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              when == null
                                  ? 'Time to be agreed'
                                  : '${DateFormat('EEE d MMM, h:mm a').format(when)} · $minutes min',
                              style: GoogleFonts.manrope(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: status == 'cancelled'
                                    ? c.textMuted
                                    : c.text,
                                decoration: status == 'cancelled'
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          Text(
                            'Open',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c.get,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: c.get,
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
      ),
    );
  }
}
