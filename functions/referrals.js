/**
 * Referral program.
 *
 * One QR does both jobs: every profile QR is a Play Store link tagged with
 * its owner's passport number. Scanning it only ever *opens a profile* -
 * except for an account on its first day, which is attributed to that QR's
 * owner automatically (through the Play Store install referrer, or by
 * scanning in the app). Established users can share and scan freely without
 * creating referrals.
 *
 * Attribution (claimReferral) requires: account under 24 h old, never
 * referred, no completed sessions, not your own code. It happens once and
 * can't be changed (referredBy / referredAt / boostUntil are protected).
 *
 * A referral only *qualifies* when the new user completes their first
 * verified session (both checked in, 30+ minutes, both confirmed). There are
 * no device checks and no daily cap - admins can revoke abuse by hand. Qualified referrals unlock badges for the referrer:
 *   1 -> referral_1  "Connector"  (+20 points)
 *   5 -> referral_5  "Ambassador"
 *  15 -> referral_15 "Web Weaver"
 * The new user gets a two-week "welcome boost" in Discover from the moment
 * the referral is recorded.
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const CLAIM_WINDOW_HOURS = 24;
const BOOST_DAYS = 14;
const CONNECTOR_POINTS = 20;
const REFERRAL_BADGES = [
  [1, 'referral_1'],
  [5, 'referral_5'],
  [15, 'referral_15'],
];

const db = () => admin.firestore();

/** "SWP-ABCD-EFGH" out of anything a QR or referrer string might hold. */
function passportFrom(raw) {
  const match = (raw || '').toString().toUpperCase().match(/SWP-[A-Z0-9]{4}-[A-Z0-9]{4}/);
  return match ? match[0] : null;
}

async function notify(userId, message) {
  await db().collection('notifications').add({
    userId,
    type: 'referral',
    message,
    timestamp: FieldValue.serverTimestamp(),
    read: false,
    senderName: 'Swapnio',
    senderPhoto: '',
  });
}

exports.claimReferral = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const passport = passportFrom(request.data && request.data.code);
  if (!passport) throw new HttpsError('invalid-argument', "That isn't a Swapnio code.");

  const reg = await db().collection('passportNumbers').doc(passport).get();
  if (!reg.exists) throw new HttpsError('not-found', "That code doesn't belong to anyone on Swapnio.");
  const referrerId = reg.data().uid;
  if (referrerId === uid) throw new HttpsError('failed-precondition', "You can't invite yourself.");

  const account = await admin.auth().getUser(uid);
  const created = Date.parse(account.metadata.creationTime);
  if (Date.now() - created > CLAIM_WINDOW_HOURS * 3600000) {
    throw new HttpsError('failed-precondition', 'Invites only count on your first day.');
  }
  const done = await db().collection('swaps')
    .where('participants', 'array-contains', uid)
    .where('status', '==', 'completed')
    .limit(1)
    .get();
  if (!done.empty) throw new HttpsError('failed-precondition', 'Invites only count before your first session.');
  const userRef = db().collection('users').doc(uid);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) throw new HttpsError('failed-precondition', 'Finish creating your profile first.');
    const existing = snap.get('referredBy');
    if (existing) return { already: true, referrerId: existing, name: snap.get('name') };
    tx.update(userRef, {
      referredBy: referrerId,
      referredAt: FieldValue.serverTimestamp(),
      boostUntil: Timestamp.fromMillis(Date.now() + BOOST_DAYS * 86400000),
    });
    tx.set(db().collection('referrals').doc(uid), {
      referrerId,
      refereeId: uid,
      refereeName: snap.get('name') || '',
      status: 'pending',
      source: (request.data && request.data.source) === 'scan' ? 'scan' : 'install',
      createdAt: FieldValue.serverTimestamp(),
    });
    return { already: false, referrerId, name: snap.get('name') };
  });

  const referrer = await db().collection('users').doc(result.referrerId).get();
  if (!result.already) {
    await require('./security').logEvent(uid, 'referral_claimed', { detail: passport });
    await notify(
      result.referrerId,
      `${result.name || 'Someone'} joined Swapnio with your QR - it counts once they finish their first session`,
    );
  }
  return { already: result.already, referrerName: (referrer.data() || {}).name || '' };
});

/**
 * Called when a session completes. If [uid] was referred and this is their
 * first completed session, the referral qualifies and the referrer's
 * referral badges are updated.
 */
async function qualifyReferral(uid) {
  if (!uid) return;
  const refRef = db().collection('referrals').doc(uid);
  const pending = await refRef.get();
  if (!pending.exists || pending.get('status') !== 'pending') return;
  const referrerId = pending.get('referrerId');
  const security = require('./security');
  const qualified = await db().runTransaction(async (tx) => {
    const snap = await tx.get(refRef);
    if (!snap.exists || snap.get('status') !== 'pending') return false;
    tx.update(refRef, { status: 'qualified', qualifiedAt: FieldValue.serverTimestamp() });
    return true;
  });
  if (!qualified) return;
  await security.logEvent(referrerId, 'referral_credited', { detail: uid });

  const gRef = db().collection('gamification').doc(referrerId);
  const unlocked = await db().runTransaction(async (tx) => {
    const g = await tx.get(gRef);
    const data = g.exists ? g.data() : {};
    const count = ((data.stats || {}).referralsQualified || 0) + 1;
    const badges = [...(data.badges || [])];
    const fresh = [];
    for (const [threshold, id] of REFERRAL_BADGES) {
      if (count >= threshold && !badges.includes(id)) {
        badges.push(id);
        fresh.push(id);
      }
    }
    const points = (data.points || 0) + (fresh.includes('referral_1') ? CONNECTOR_POINTS : 0);
    tx.set(
      gRef,
      { stats: { referralsQualified: count }, badges, points, level: 1 + Math.floor(points / 100) },
      { merge: true },
    );
    return { count, fresh };
  });

  const referee = await db().collection('users').doc(uid).get();
  const name = (referee.data() || {}).name || 'Someone you invited';
  await notify(
    referrerId,
    unlocked.fresh.length
      ? `${name} finished their first session - you unlocked a new referral badge!`
      : `${name} finished their first session - that's ${unlocked.count} qualified invites`,
  );
}

exports.qualifyReferral = qualifyReferral;
exports.passportFrom = passportFrom;

/**
 * Admin: revokes a referral (e.g. abuse spotted in the admin panel) and
 * recounts the referrer's referral badges.
 */
exports.revokeReferral = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const me = await db().collection('users').doc(uid).get();
  if (!me.exists || me.data().isAdmin !== true) throw new HttpsError('permission-denied', 'Admins only.');
  const refereeId = request.data && request.data.refereeId;
  if (typeof refereeId !== 'string' || !refereeId) throw new HttpsError('invalid-argument', 'refereeId is required.');
  const refRef = db().collection('referrals').doc(refereeId);
  const snap = await refRef.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Referral not found.');
  const referrerId = snap.get('referrerId');
  await refRef.update({ status: 'revoked', revokedBy: uid, decidedAt: FieldValue.serverTimestamp() });
  const qualified = await db().collection('referrals')
    .where('referrerId', '==', referrerId)
    .where('status', '==', 'qualified')
    .get();
  const count = qualified.size;
  const gRef = db().collection('gamification').doc(referrerId);
  await db().runTransaction(async (tx) => {
    const g = await tx.get(gRef);
    const badges = (g.exists ? g.data().badges || [] : [])
      .filter((b) => !REFERRAL_BADGES.some(([threshold, id]) => id === b && count < threshold));
    tx.set(gRef, { badges, stats: { referralsQualified: count } }, { merge: true });
  });
  await require('./security').logEvent(referrerId, 'referral_revoked', { detail: refereeId });
  return { referralsQualified: count };
});
