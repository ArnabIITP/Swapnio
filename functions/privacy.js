/**
 * Keeps private data out of public profiles.
 *
 * users/{uid} is readable by other members (that's how profiles and
 * Discover work), and Firestore can't hide single fields - so anything
 * private must not live there:
 *   - `email` is only kept in Firebase Auth (the server reads it there);
 *   - push tokens live in users/{uid}/settings/push, readable by the owner
 *     only.
 * `discoverable` (server-set) mirrors the profile-visibility setting and is
 * what the rules require for listing profiles - so a "private" or
 * "matches only" profile can't be pulled in bulk by a query.
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');

const db = () => admin.firestore();
const PRIVATE_FIELDS = ['email', 'fcmTokens'];

function visibilityOf(data) {
  const v = data && data.privacy && data.privacy.profileVisibility;
  return v === 'private' || v === 'matches' ? v : 'public';
}

/**
 * Brings one user doc in line: moves push tokens to settings/push, drops
 * private fields and sets `discoverable`. No-op when already clean.
 */
async function cleanUserDoc(ref, data) {
  if (!data) return false;
  const update = {};
  const discoverable = visibilityOf(data) === 'public';
  if (data.discoverable !== discoverable) update.discoverable = discoverable;
  const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens.filter(Boolean) : [];
  for (const f of PRIVATE_FIELDS) if (f in data) update[f] = FieldValue.delete();
  if (Object.keys(update).length === 0) return false;
  if (tokens.length) {
    await ref.collection('settings').doc('push').set(
      { tokens: FieldValue.arrayUnion(...tokens) },
      { merge: true },
    );
  }
  await ref.update(update);
  return true;
}

exports.syncUserPrivacy = onDocumentWritten('users/{uid}', async (event) => {
  const after = event.data && event.data.after;
  if (!after || !after.exists) return;
  await cleanUserDoc(after.ref, after.data());
});

/**
 * One-time pass over every existing profile, a page per run (called from
 * the 15-minute scheduler) until all are done.
 */
exports.migrateUsersBatch = async () => {
  const markerRef = db().collection('meta').doc('privacyMigration');
  const marker = await markerRef.get();
  if (marker.exists && marker.get('done') === true) return;
  let query = db().collection('users').orderBy(admin.firestore.FieldPath.documentId()).limit(300);
  const cursor = marker.exists ? marker.get('lastId') : null;
  if (cursor) query = query.startAfter(cursor);
  const snap = await query.get();
  for (const doc of snap.docs) await cleanUserDoc(doc.ref, doc.data());
  await markerRef.set(
    snap.size < 300
      ? { done: true, finishedAt: FieldValue.serverTimestamp() }
      : { lastId: snap.docs[snap.docs.length - 1].id },
    { merge: true },
  );
};

/** Push tokens for a user: the private store, plus any not yet migrated. */
exports.pushTokensOf = async (uid) => {
  const [settings, user] = await Promise.all([
    db().collection('users').doc(uid).collection('settings').doc('push').get(),
    db().collection('users').doc(uid).get(),
  ]);
  const tokens = [
    ...((settings.exists && settings.get('tokens')) || []),
    ...((user.exists && user.get('fcmTokens')) || []),
  ];
  return [...new Set(tokens.filter(Boolean))];
};

exports.removePushTokens = async (uid, stale) => {
  if (!stale.length) return;
  await db().collection('users').doc(uid).collection('settings').doc('push').set(
    { tokens: FieldValue.arrayRemove(...stale) },
    { merge: true },
  );
};

/**
 * Admin panel: every member's sign-in email, straight from Firebase Auth
 * (profiles no longer carry it). Admins only.
 */
exports.adminUserEmails = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const me = await db().collection('users').doc(uid).get();
  if (!me.exists || me.get('isAdmin') !== true) {
    throw new HttpsError('permission-denied', 'Admins only.');
  }
  const emails = {};
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const u of page.users) if (u.email) emails[u.uid] = u.email;
    pageToken = page.pageToken;
  } while (pageToken);
  return { emails };
});

/** The account email, from Firebase Auth (never stored on the profile). */
exports.authEmailOf = async (uid) => {
  try {
    return (await admin.auth().getUser(uid)).email || '';
  } catch (_) {
    return '';
  }
};
