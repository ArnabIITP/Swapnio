/**
 * Verified members.
 *
 * A member is verified only when BOTH their email and their phone number
 * are verified. The source of truth is Firebase Auth, never the client:
 *   - email: Auth's emailVerified (Google sign-ins arrive verified),
 *   - phone: a number linked to the account by SMS code.
 * Firebase Auth lets one phone number belong to one account only, so a
 * number can't verify two accounts. The number itself is never copied into
 * Firestore - only the yes/no flags.
 *
 * syncVerification copies those flags onto users/{uid} (protected fields,
 * see firestore.rules) so other people can see the verified ring. Becoming
 * verified for the first time earns the "verified" badge and +50 points;
 * both are kept if the phone is later removed, but the ring and the
 * Discover perks follow the current state.
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');

const VERIFIED_POINTS = 50;

const db = () => admin.firestore();

async function syncFor(uid) {
  const account = await admin.auth().getUser(uid);
  const emailVerified = account.emailVerified === true;
  const phoneVerified = Boolean(account.phoneNumber);
  const verified = emailVerified && phoneVerified;

  const userRef = db().collection('users').doc(uid);
  const before = await db().runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) throw new HttpsError('failed-precondition', 'Finish creating your profile first.');
    const was = snap.get('verified') === true;
    const update = { emailVerified, phoneVerified, verified };
    if (verified && !snap.get('verifiedAt')) update.verifiedAt = FieldValue.serverTimestamp();
    tx.update(userRef, update);
    return was;
  });

  let rewarded = false;
  if (verified) {
    const gRef = db().collection('gamification').doc(uid);
    rewarded = await db().runTransaction(async (tx) => {
      const g = await tx.get(gRef);
      const data = g.exists ? g.data() : {};
      const badges = [...(data.badges || [])];
      if (badges.includes('verified')) return false;
      badges.push('verified');
      const points = (data.points || 0) + VERIFIED_POINTS;
      tx.set(gRef, { badges, points, level: 1 + Math.floor(points / 100) }, { merge: true });
      return true;
    });
  }
  if (verified !== before) {
    await require('./security').logEvent(uid, verified ? 'account_verified' : 'verification_lost');
  }
  return { emailVerified, phoneVerified, verified, rewarded };
}

exports.syncVerification = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return syncFor(uid);
});

exports.syncFor = syncFor;
