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
        const currentPoints = doc.exists ? doc.data().points || 0 : 0;
        const badges = doc.exists ? doc.data().badges || [] : [];
        const newPoints = currentPoints + POINTS_PER_SWAP;
        const newBadges = badges.includes('first_swap')
          ? badges
          : badges.concat('first_swap');
        tx.set(
          ref,
          {
            points: newPoints,
            level: 1 + Math.floor(newPoints / 100),
            badges: newBadges,
          },
          { merge: true },
        );
      });
    }
  },
);