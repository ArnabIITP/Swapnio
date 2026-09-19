/**
 * Swapnio - Cloud Functions
 *
 * Push notifications are triggered by writes to the `notifications` collection
 * (the app already creates those documents for requests, accepted requests and
 * proposed swap sessions). Each FCM token stored on the user document receives
 * a data+notification payload, so tapping the notification can deep-link
 * straight into the relevant screen.
 *
 * Tokens are stored as an array on `users/{uid}.fcmTokens` by
 * `lib/services/notification_service.dart`.
 *
 * Deploy with:  firebase deploy --only functions
 */
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

admin.initializeApp();

exports.pushOnNotification = onDocumentCreated(
  'notifications/{notificationId}',
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const notification = snapshot.data() || {};
    const userId = notification.userId;
    if (!userId) return;

    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const tokens = (userDoc.get('fcmTokens') || []).filter(Boolean);
    if (tokens.length === 0) return;

    const payload = {
      tokens,
      notification: {
        title: notification.senderName
          ? `${notification.senderName} - Swapnio`
          : 'Swapnio',
        body: notification.message || 'You have a new update',
      },
      data: {
        type: String(notification.type || 'general'),
        senderId: String(notification.senderId || ''),
        senderName: String(notification.senderName || ''),
      },
      android: {
        priority: 'high',
        notification: { channelId: 'swapnio_default' },
      },
      apns: {
        payload: { aps: { sound: 'default', badge: 1 } },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(payload);

    // Clean up tokens that are no longer valid.
    const staleTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.success) {
        const code = result.error && result.error.code;
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token'
        ) {
          staleTokens.push(tokens[index]);
        }
      }
    });

    if (staleTokens.length > 0) {
      await admin
        .firestore()
        .collection('users')
        .doc(userId)
        .update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleTokens),
        });
    }
  },
);

/**
 * When a swap session transitions to `completed`:
 *   - award +25 points and recompute the level for BOTH participants
 *   - grant the "first_swap" badge
 *
 * Runs with admin privileges (bypasses security rules), which is required
 * because a client may only write its OWN gamification doc - the partner's
 * points were silently rejected when this was done client-side. A transition
 * guard (before != completed, after == completed) prevents double awards.
 */
const POINTS_PER_SWAP = 25;
const POINTS_FIRST_MESSAGE = 5;
const POINTS_PROFILE_COMPLETE = 10;
const SWAP_MILESTONES = [
  { count: 1, badge: 'first_swap' },
  { count: 5, badge: '5_swaps' },
  { count: 10, badge: '10_swaps' },
  { count: 25, badge: '25_swaps' },
];

/**
 * Awards points and (optionally) a one-time badge on a user's gamification
 * doc. Runs with admin privileges, which is required because a client may
 * only write its OWN gamification doc - the partner's points were silently
 * rejected when award attempts were done client-side.
 */
async function awardGamification(db, uid, points, badgesToAdd = [], extra = {}) {
  const ref = db.collection('gamification').doc(uid);
  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const currentPoints = doc.exists ? doc.data().points || 0 : 0;
    const badges = doc.exists ? doc.data().badges || [] : [];
    const newPoints = currentPoints + points;
    const newBadges = [...badges];
    for (const badge of badgesToAdd) {
      if (!newBadges.includes(badge)) newBadges.push(badge);
    }
    tx.set(
      ref,
      {
        points: newPoints,
        level: 1 + Math.floor(newPoints / 100),
        badges: newBadges,
        ...extra,
      },
      { merge: true },
    );
  });
}

/**
 * When a swap session transitions to `completed`:
 *   - award +25 points to both participants
 *   - track each participant's lifetime completed-swap count on their own
 *     gamification doc, and grant milestone badges (1st, 5th, 10th, 25th)
 *
 * A transition guard (before != completed, after == completed) prevents
 * double awards from re-triggering on unrelated doc updates.
 */
exports.badgeOnCompletedSwap = onDocumentUpdated(
  'swaps/{swapId}',
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (after.status !== 'completed' || before.status === 'completed') return;

    const participants = after.participants || [];
    const db = admin.firestore();
    for (const uid of participants) {
      if (!uid) continue;
      const ref = db.collection('gamification').doc(uid);
      await db.runTransaction(async (tx) => {
        const doc = await tx.get(ref);
        const data = doc.exists ? doc.data() : {};
        const currentPoints = data.points || 0;
        const badges = data.badges || [];
        const completedSwaps = (data.completedSwapsCount || 0) + 1;
        const newPoints = currentPoints + POINTS_PER_SWAP;
        const newBadges = [...badges];
        for (const milestone of SWAP_MILESTONES) {
          if (completedSwaps >= milestone.count && !newBadges.includes(milestone.badge)) {
            newBadges.push(milestone.badge);
          }
        }
        tx.set(
          ref,
          {
            points: newPoints,
            level: 1 + Math.floor(newPoints / 100),
            badges: newBadges,
            completedSwapsCount: completedSwaps,
          },
          { merge: true },
        );
      });
    }
  },
);

/**
 * On signup:
 *   - grant a "welcome" badge, so nobody starts with an empty badge shelf
 *     (people finish collections they've already started - an empty shelf
 *     reads as "nothing here for me")
 *   - refresh the public user count shown on the signup screen, which is the
 *     only place unauthenticated visitors can see any activity at all
 */
exports.onUserCreated = onDocumentCreated('users/{uid}', async (event) => {
  const db = admin.firestore();
  const uid = event.params.uid;
  await awardGamification(db, uid, 0, ['welcome']);

  const count = await db.collection('users').count().get();
  await db.collection('stats').doc('public').set(
    {
      userCount: count.data().count,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
});

/**
 * Awards a small one-time bonus for a user's very first chat message ever
 * sent, so gamification isn't only tied to completing a full swap session.
 */
exports.badgeOnFirstMessage = onDocumentCreated(
  'chatRooms/{roomId}/messages/{messageId}',
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const message = snapshot.data() || {};
    const senderId = message.senderId;
    if (!senderId || senderId === 'system') return;

    const db = admin.firestore();
    const ref = db.collection('gamification').doc(senderId);
    const doc = await ref.get();
    const badges = doc.exists ? doc.data().badges || [] : [];
    if (badges.includes('first_message')) return;

    await awardGamification(db, senderId, POINTS_FIRST_MESSAGE, ['first_message']);
  },
);

/**
 * Awards a one-time bonus the first time a profile becomes "complete"
 * (name, bio, at least one skill offered/wanted, and a photo).
 */
function isProfileComplete(data) {
  return Boolean(
    (data.name || '').trim() &&
      (data.bio || '').trim() &&
      (data.photoUrl || '').trim() &&
      Array.isArray(data.skillsOffered) && data.skillsOffered.length > 0 &&
      Array.isArray(data.skillsWanted) && data.skillsWanted.length > 0,
  );
}

exports.badgeOnProfileComplete = onDocumentUpdated(
  'users/{uid}',
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (isProfileComplete(before) || !isProfileComplete(after)) return;

    const db = admin.firestore();
    const uid = event.params.uid;
    const ref = db.collection('gamification').doc(uid);
    const doc = await ref.get();
    const badges = doc.exists ? doc.data().badges || [] : [];
    if (badges.includes('profile_complete')) return;

    await awardGamification(db, uid, POINTS_PROFILE_COMPLETE, ['profile_complete']);
  },
);

/**
 * Maintains a reliability record on each user as sessions resolve.
 *
 * Runs server-side because a client can only write its OWN user doc for these
 * fields - the whole point is recording something about the OTHER person.
 * A no-show is attributed to the participant who did NOT report it
 * (`noShowReportedBy`), since the reporter is the one who turned up.
 */
exports.trackSessionReliability = onDocumentUpdated(
  'swaps/{swapId}',
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (before.status === after.status) return;

    const db = admin.firestore();
    const participants = (after.participants || []).filter(Boolean);
    const increment = admin.firestore.FieldValue.increment(1);

    if (after.status === 'completed') {
      await Promise.all(
        participants.map((uid) =>
          db.collection('users').doc(uid).set(
            { sessionsAttended: increment },
            { merge: true },
          ),
        ),
      );
      return;
    }

    if (after.status === 'no_show') {
      const reporter = after.noShowReportedBy;
      const blamed = participants.filter((uid) => uid !== reporter);
      await Promise.all([
        ...blamed.map((uid) =>
          db.collection('users').doc(uid).set(
            { noShowCount: increment },
            { merge: true },
          ),
        ),
        // The person who showed up still gets credit for turning up.
        ...(reporter
          ? [
              db.collection('users').doc(reporter).set(
                { sessionsAttended: increment },
                { merge: true },
              ),
            ]
          : []),
      ]);
    }
  },
);

/**
 * Reminds both participants ~1 hour before an accepted swap session.
 *
 * Runs every 15 minutes and looks at a 20-minute window starting 50 minutes
 * from now, so each session's `scheduledFor` falls into exactly one run's
 * window under normal conditions. `reminderSent` is set inside a transaction
 * before notifying, so an overlapping run (or a retry) can't double-send.
 */
exports.sessionReminders = onSchedule('every 15 minutes', async () => {
  const db = admin.firestore();
  const nowMs = Date.now();
  const windowStart = admin.firestore.Timestamp.fromMillis(nowMs + 50 * 60 * 1000);
  const windowEnd = admin.firestore.Timestamp.fromMillis(nowMs + 70 * 60 * 1000);

  const snapshot = await db
    .collection('swaps')
    .where('status', '==', 'accepted')
    .where('scheduledFor', '>=', windowStart)
    .where('scheduledFor', '<=', windowEnd)
    .get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.reminderSent) continue;

    const claimed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists || fresh.data().reminderSent) return false;
      tx.update(doc.ref, { reminderSent: true });
      return true;
    });
    if (!claimed) continue;

    const participants = data.participants || [];
    const scheduledFor = data.scheduledFor;
    const timeStr = scheduledFor && scheduledFor.toDate
      ? scheduledFor.toDate().toLocaleString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true,
        })
      : 'soon';

    await Promise.all(
      participants
        .filter(Boolean)
        .map((uid) =>
          db.collection('notifications').add({
            userId: uid,
            type: 'session_reminder',
            message: `Your swap session is coming up at ${timeStr}`,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
            senderName: 'Swapnio',
            senderPhoto: '',
          }),
        ),
    );
  }
});