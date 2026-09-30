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
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const crypto = require('crypto');

admin.initializeApp();

// Cloud Run reserves CPU quota for each function's maximum instances, and
// this project's regional quota is small: uncapped functions (default 100
// instances, 1 vCPU each) exhausted it and blocked every deploy. Each
// function is capped at 3 instances on a fractional CPU (the size gen-1
// functions ran on), which is plenty for these light Firestore handlers.
setGlobalOptions({ maxInstances: 3, cpu: 'gcf_gen1' });

const sessions = require('./sessions');
const streaks = require('./streaks');
const requests = require('./requests');
const privacy = require('./privacy');

exports.checkInSession = sessions.checkInSession;
exports.completeSwapSession = sessions.completeSwapSession;
exports.refreshMyStats = sessions.refreshMyStats;
exports.statsOnRating = sessions.statsOnRating;

const skills = require('./skills');

exports.syncSkillCatalog = skills.syncSkillCatalog;
exports.canonicalizeUserSkills = skills.canonicalizeUserSkills;
exports.requestSkill = skills.requestSkill;
exports.resolveSkillRequest = skills.resolveSkillRequest;

const referrals = require('./referrals');

exports.claimReferral = referrals.claimReferral;
exports.revokeReferral = referrals.revokeReferral;

const schedule = require('./schedule');

exports.proposeSession = schedule.proposeSession;
exports.respondSession = schedule.respondSession;
exports.cancelSession = schedule.cancelSession;
exports.myCancellationStats = schedule.myCancellationStats;
exports.requestReschedule = schedule.requestReschedule;
exports.respondReschedule = schedule.respondReschedule;
exports.busyTimes = schedule.busyTimes;
exports.askToConnectCalendar = schedule.askToConnectCalendar;

const calendar = require('./calendar');

exports.connectGoogleCalendar = calendar.connectGoogleCalendar;
exports.disconnectGoogleCalendar = calendar.disconnectGoogleCalendar;
exports.calendarStatus = calendar.calendarStatus;
exports.setBusySharing = calendar.setBusySharing;

const verification = require('./verification');

exports.syncVerification = verification.syncVerification;

const security = require('./security');

exports.registerDevice = security.registerDevice;
exports.devicePresence = security.devicePresence;
exports.signOutDevice = security.signOutDevice;
exports.signOutOtherDevices = security.signOutOtherDevices;
exports.startTwoFactorSetup = security.startTwoFactorSetup;
exports.confirmTwoFactorSetup = security.confirmTwoFactorSetup;
exports.verifyDeviceCode = security.verifyDeviceCode;
exports.disableTwoFactor = security.disableTwoFactor;
exports.twoFactorStatus = security.twoFactorStatus;
exports.securityOnUserChange = security.securityOnUserChange;

const web = require('./web');

exports.mySwapWeb = web.mySwapWeb;

exports.acceptSwapRequest = requests.acceptSwapRequest;
exports.syncUserPrivacy = privacy.syncUserPrivacy;
exports.adminUserEmails = privacy.adminUserEmails;

exports.pushOnNotification = onDocumentCreated(
  'notifications/{notificationId}',
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const notification = snapshot.data() || {};
    const userId = notification.userId;
    if (!userId) return;

    const tokens = await privacy.pushTokensOf(userId);
    if (tokens.length === 0) return;

    // Only the server writes notifications now, but the title still comes
    // from the sender's real profile rather than the stored senderName.
    let title = 'Swapnio';
    const sender = notification.senderId;
    if (sender && sender !== 'system') {
      const senderDoc = await admin.firestore().collection('users').doc(sender).get();
      const name = senderDoc.exists && senderDoc.get('name');
      if (name) title = `${name} - Swapnio`;
    }

    const payload = {
      tokens,
      notification: {
        title,
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

    await privacy.removePushTokens(userId, staleTokens);
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

    // Community pulse on Home reads this instead of querying `swaps`
    // directly: that query has no participants filter, so Firestore can't
    // prove every matching document is readable by a non-admin caller and
    // rejects the whole request. A maintained counter sidesteps that.
    await db.collection('stats').doc('public').set(
        { completedSwaps: FieldValue.increment(1) },
        { merge: true },
    );

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

    // Teaching/learning time, streaks and the badges built on them.
    for (const uid of participants) {
      await sessions.refreshStatsAndBadges(uid);
      // A referred user's first completed session qualifies their referral.
      await referrals.qualifyReferral(uid);
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
  await issuePassportNumberFor(db, uid);

  const count = await db.collection('users').count().get();
  await db.collection('stats').doc('public').set(
    {
      userCount: count.data().count,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
});

// No 0/O or 1/I, so a number read off a shared image can't be mistyped.
const PASSPORT_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

function formatPassportNumber(chars) {
  return `SWP-${chars.slice(0, 4)}-${chars.slice(4, 8)}`;
}

/**
 * Gives a user a Skill Passport number that no one else has, and keeps it.
 *
 * Every number is reserved in passportNumbers/{number} inside the same
 * transaction that writes it to the user, so two users can never end up
 * with the same one. The first choice is the number the app used to derive
 * from the uid (so passports people already shared stay valid); only if
 * that's taken does it fall back to random ones.
 */
async function issuePassportNumberFor(db, uid) {
  const userRef = db.collection('users').doc(uid);
  const derived = uid.replace(/[^A-Za-z0-9]/g, '').toUpperCase().padEnd(8, 'X');
  const candidates = [formatPassportNumber(derived)];
  for (let i = 0; i < 8; i++) {
    let chars = '';
    for (let j = 0; j < 8; j++) {
      chars += PASSPORT_ALPHABET[crypto.randomInt(PASSPORT_ALPHABET.length)];
    }
    candidates.push(formatPassportNumber(chars));
  }

  for (const number of candidates) {
    const issued = await db.runTransaction(async (tx) => {
      const regRef = db.collection('passportNumbers').doc(number);
      const [userSnap, regSnap] = await Promise.all([tx.get(userRef), tx.get(regRef)]);
      if (!userSnap.exists) return null;
      const existing = userSnap.get('passportNumber');
      if (existing) return existing;
      if (regSnap.exists) return null;
      tx.create(regRef, { uid, issuedAt: FieldValue.serverTimestamp() });
      tx.update(userRef, { passportNumber: number });
      return number;
    });
    if (issued) return issued;
  }
  return null;
}

/**
 * Returns the caller's passport number, issuing one first if they signed up
 * before numbers were issued at account creation.
 */
exports.issuePassportNumber = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  const number = await issuePassportNumberFor(admin.firestore(), uid);
  if (!number) {
    throw new HttpsError('unavailable', 'Could not issue a passport number. Try again.');
  }
  return { passportNumber: number };
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

    // Every message sent keeps the sender's daily streak (see streaks.js).
    await streaks.recordActivity(senderId);

    const db = admin.firestore();
    const ref = db.collection('gamification').doc(senderId);
    const doc = await ref.get();
    const badges = doc.exists ? doc.data().badges || [] : [];
    if (badges.includes('first_message')) return;

    await awardGamification(db, senderId, POINTS_FIRST_MESSAGE, ['first_message']);
  },
);

/**
 * A new swap request: sender details fixed from their profile, recipient
 * notified, sender's streak kept (functions/requests.js). The export keeps
 * its original name so the deployed function is updated in place.
 */
exports.streakOnRequest = onDocumentCreated(
  'swipeRequests/{requestId}',
  requests.onRequestCreated,
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
    const increment = FieldValue.increment(1);

    if (after.status === 'completed') {
      await Promise.all(
        participants.map((uid) =>
          // completedSwaps is the count shown on profiles and Discover
          // cards; only the server may write it.
          db.collection('users').doc(uid).set(
            { sessionsAttended: increment, completedSwaps: increment },
            { merge: true },
          ),
        ),
      );
      return;
    }

    if (after.status === 'no_show') {
      // A no-show breaks the blamed participant's reliability run.
      await Promise.all(participants.map((uid) => sessions.refreshStatsAndBadges(uid)));
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
 * Reminds both participants of an accepted swap session twice: ~1 hour
 * before, and again ~15 minutes before.
 *
 * Runs every 15 minutes. Each reminder tier looks at its own window around
 * its target offset (60 min / 15 min from now) sized so a session's
 * `scheduledFor` falls into exactly one run's window under normal
 * conditions, and is guarded by its own `reminderSent` flag inside a
 * transaction so an overlapping run (or a retry) can't double-send - and so
 * the two tiers can fire independently of each other for the same session.
 */
async function sendSessionReminders(db, {
  offsetMinutes,
  windowMinutes,
  flagField,
  messageFor,
}) {
  const nowMs = Date.now();
  const halfWindowMs = (windowMinutes / 2) * 60 * 1000;
  const targetMs = nowMs + offsetMinutes * 60 * 1000;
  const windowStart = Timestamp.fromMillis(targetMs - halfWindowMs);
  const windowEnd = Timestamp.fromMillis(targetMs + halfWindowMs);

  const snapshot = await db
    .collection('swaps')
    .where('status', '==', 'accepted')
    .where('scheduledFor', '>=', windowStart)
    .where('scheduledFor', '<=', windowEnd)
    .get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data[flagField]) continue;

    const claimed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists || fresh.data()[flagField]) return false;
      tx.update(doc.ref, { [flagField]: true });
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
            swapId: doc.id,
            message: messageFor(timeStr),
            timestamp: FieldValue.serverTimestamp(),
            read: false,
            senderName: 'Swapnio',
            senderPhoto: '',
          }),
        ),
    );
  }
}

exports.sessionReminders = onSchedule('every 15 minutes', async () => {
  const db = admin.firestore();
  await sessions.remindUnconfirmed();
  await streaks.remindStreaks();
  await privacy.migrateUsersBatch();
  await sendSessionReminders(db, {
    offsetMinutes: 60,
    windowMinutes: 20,
    flagField: 'reminderSent',
    messageFor: (timeStr) => `Your swap session is coming up at ${timeStr}`,
  });
  await sendSessionReminders(db, {
    offsetMinutes: 15,
    windowMinutes: 16,
    flagField: 'reminderSent15',
    messageFor: (timeStr) => `Your swap session starts in about 15 minutes (${timeStr})`,
  });
});

/**
 * Hard-deletes a user: the Auth login plus every document that references
 * them. Without this, "delete" only removed `users/{uid}` - the account could
 * sign in again with the same email, get the same uid back, and find all of
 * its old chats and swaps intact.
 *
 * Callable (admin only). The caller must have `isAdmin: true` on their own
 * user document; the same check the security rules use.
 */
/**
 * The complete wipe used by both delete paths: every collection that can
 * reference a uid, the login itself, and the public counter. Kept in one
 * place so "delete my account" and "admin deletes a user" can never drift
 * apart again - the earlier self-delete path only removed the Auth login and
 * left every chat, swap and rating behind, so the account looked freshly
 * re-created (with the same history) the next time that email signed in.
 */
async function wipeUserCompletely(db, uid) {
  const deleted = {};
  const deleteDocs = async (label, snapshot) => {
    if (snapshot.empty) return;
    let batch = db.batch();
    let count = 0;
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
      count += 1;
      if (count % 400 === 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
    await batch.commit();
    deleted[label] = (deleted[label] || 0) + snapshot.size;
  };

  // Chat rooms: messages live in a subcollection, so they need recursive
  // deletion rather than dropping the parent document.
  const rooms = await db.collection('chatRooms').where('users', 'array-contains', uid).get();
  for (const room of rooms.docs) {
    await db.recursiveDelete(room.ref);
  }
  deleted.chatRooms = rooms.size;

  await deleteDocs('swaps',
      await db.collection('swaps').where('participants', 'array-contains', uid).get());
  await deleteDocs('swipeRequestsSent',
      await db.collection('swipeRequests').where('fromUserId', '==', uid).get());
  await deleteDocs('swipeRequestsReceived',
      await db.collection('swipeRequests').where('toUserId', '==', uid).get());
  await deleteDocs('notifications',
      await db.collection('notifications').where('userId', '==', uid).get());
  await deleteDocs('profileViewsOf',
      await db.collection('profileViews').where('viewedUserId', '==', uid).get());
  await deleteDocs('profileViewsBy',
      await db.collection('profileViews').where('viewerId', '==', uid).get());
  await deleteDocs('ratingsReceived',
      await db.collection('ratings').where('toUserId', '==', uid).get());
  await deleteDocs('ratingsGiven',
      await db.collection('ratings').where('fromUserId', '==', uid).get());

  // Security data: the log and referral records.
  await deleteDocs('securityEvents',
      await db.collection('securityEvents').where('uid', '==', uid).get());
  await deleteDocs('referralsAsInvitee',
      await db.collection('referrals').where('refereeId', '==', uid).get());

  // Gamification and the user document itself (with its subcollections -
  // including devices and the private two-factor record).
  await db.recursiveDelete(db.collection('gamification').doc(uid));
  await db.recursiveDelete(db.collection('users').doc(uid));
  deleted.profile = 1;

  // Finally the login. Without this the same email signs back in and is
  // handed the same uid, with nothing actually gone.
  let authDeleted = false;
  try {
    await admin.auth().deleteUser(uid);
    authDeleted = true;
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }

  // Keep the public signup counter honest.
  try {
    await db.collection('stats').doc('public').set(
        { userCount: FieldValue.increment(-1) },
        { merge: true },
    );
  } catch (_) {
    // The counter is cosmetic; never fail a deletion over it.
  }

  return { authDeleted, deleted };
}

exports.adminDeleteUser = onCall(async (request) => {
  const callerUid = request.auth && request.auth.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }

  const db = admin.firestore();
  const callerDoc = await db.collection('users').doc(callerUid).get();
  if (!callerDoc.exists || callerDoc.data().isAdmin !== true) {
    throw new HttpsError('permission-denied', 'Admins only.');
  }

  const uid = request.data && request.data.uid;
  if (!uid || typeof uid !== 'string') {
    throw new HttpsError('invalid-argument', 'A uid is required.');
  }
  if (uid === callerUid) {
    throw new HttpsError('failed-precondition', 'You cannot delete your own admin account here.');
  }

  const { authDeleted, deleted } = await wipeUserCompletely(db, uid);
  console.log(`adminDeleteUser: ${callerUid} deleted ${uid}`, deleted, { authDeleted });
  // A minimal audit trail survives the deletion (90-day retention).
  await security.logEvent(uid, 'account_deleted', { detail: 'by an admin' });
  await security.logEvent(callerUid, 'admin_deleted_user', { detail: uid });
  return { ok: true, authDeleted, deleted };
});

/**
 * A signed-in user deleting their own account, from Profile > Settings.
 * No admin check needed - the target is always the caller.
 */
exports.selfDeleteAccount = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }

  const db = admin.firestore();
  const { authDeleted, deleted } = await wipeUserCompletely(db, uid);
  console.log(`selfDeleteAccount: ${uid} deleted their own account`, deleted, { authDeleted });
  await security.logEvent(uid, 'account_deleted', { detail: 'by the user' });
  return { ok: true, authDeleted, deleted };
});
