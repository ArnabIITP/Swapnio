/**
 * Account security: device footprint, remote sign-out, the security log and
 * app-level two-factor authentication.
 *
 * Devices
 *   Each install has a random device id (kept in the phone's secure
 *   storage). registerDevice records model / OS / app version, the
 *   approximate city (looked up from the caller's IP in the bundled GeoLite
 *   database - no location permission, no third-party call) and last-seen
 *   time, and says whether that device has been signed out remotely or still
 *   needs a 2FA code.
 *
 * Security log
 *   securityEvents: sign-ins, new devices, sign-outs, 2FA changes, failed
 *   codes, referral decisions, bans and deletions. Written only here, kept
 *   90 days (expireAt + a Firestore TTL policy).
 *
 * 2FA
 *   TOTP (Google Authenticator etc.) with 10 single-use backup codes. The
 *   secret is AES-256-GCM encrypted with a key held in Secret Manager
 *   (TOTP_KEY). A device with 2FA on must enter a code once before the app
 *   unlocks; wrong codes are rate-limited (5 tries, then a 15-minute lock).
 *
 * Sign-out is enforced by the app: a revoked device signs itself out the
 * next time it checks in. (Revoking Firebase refresh tokens would also sign
 * out the device doing the revoking, so it isn't used for per-device
 * sign-out.)
 */
const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const TOTP_KEY = defineSecret('TOTP_KEY');
const RETENTION_DAYS = 90;
const MAX_FAILURES = 5;
const LOCK_MINUTES = 15;
const DEVICE_ID = /^[a-f0-9]{32}$/;

const db = () => admin.firestore();

function requireUid(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function requireDeviceId(value) {
  if (typeof value !== 'string' || !DEVICE_ID.test(value)) {
    throw new HttpsError('invalid-argument', 'A valid device id is required.');
  }
  return value;
}

const clip = (v, n = 80) => (typeof v === 'string' ? v.slice(0, n) : '');

/** Appends to the security log. Never throws - logging must not break a flow. */
async function logEvent(uid, type, extra = {}) {
  try {
    await db().collection('securityEvents').add({
      uid,
      type,
      ...extra,
      at: FieldValue.serverTimestamp(),
      expireAt: Timestamp.fromMillis(Date.now() + RETENTION_DAYS * 86400000),
    });
  } catch (e) {
    console.error('logEvent failed', type, e);
  }
}

async function geoFor(request) {
  try {
    const fwd = (request.rawRequest && request.rawRequest.headers['x-forwarded-for']) || '';
    const ip = fwd.split(',')[0].trim() || (request.rawRequest && request.rawRequest.ip) || '';
    if (!ip) return { city: '', country: '' };
    const geo = await require('fast-geoip').lookup(ip.replace(/^::ffff:/, ''));
    return { city: (geo && geo.city) || '', country: (geo && geo.country) || '' };
  } catch (_) {
    return { city: '', country: '' };
  }
}

async function twoFactorDoc(uid) {
  const snap = await db().collection('users').doc(uid).collection('private').doc('twoFactor').get();
  return snap.exists ? snap.data() : null;
}

// ------------------------------------------------------------------ devices

exports.registerDevice = onCall(async (request) => {
  const uid = requireUid(request);
  const data = request.data || {};
  const deviceId = requireDeviceId(data.deviceId);
  const authTime = Number(request.auth.token.auth_time || 0) * 1000;
  const geo = await geoFor(request);
  const ref = db().collection('users').doc(uid).collection('devices').doc(deviceId);

  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const cur = snap.exists ? snap.data() : null;
    const revokedAt = cur && cur.revokedAt ? cur.revokedAt.toMillis() : 0;
    // Signed out remotely, and not signed in again since - stay signed out.
    if (cur && cur.revoked && revokedAt >= authTime) return { revoked: true };
    const freshSignIn = !cur || authTime > (cur.lastAuthAt ? cur.lastAuthAt.toMillis() : 0);
    tx.set(ref, {
      model: clip(data.model),
      osVersion: clip(data.osVersion),
      appVersion: clip(data.appVersion, 20),
      platform: clip(data.platform, 20),
      city: geo.city,
      country: geo.country,
      lastSeenAt: FieldValue.serverTimestamp(),
      online: true,
      lastAuthAt: Timestamp.fromMillis(authTime || Date.now()),
      revoked: false,
      ...(cur ? {} : { firstSeenAt: FieldValue.serverTimestamp(), trusted: false }),
      // A new sign-in on a device that was signed out has to pass 2FA again.
      ...(cur && cur.revoked ? { trusted: false } : {}),
    }, { merge: true });
    return {
      revoked: false,
      isNew: !cur,
      freshSignIn,
      trusted: cur ? cur.trusted === true && !cur.revoked : false,
    };
  });
  if (result.revoked) return { revoked: true, requires2fa: false };

  const where = [geo.city, geo.country].filter(Boolean).join(', ') || 'an unknown location';
  if (result.isNew) {
    await logEvent(uid, 'new_device', { deviceId, detail: `${clip(data.model)} · ${where}` });
    await db().collection('notifications').add({
      userId: uid,
      type: 'security',
      message: `New sign-in on ${clip(data.model) || 'a device'} near ${where}. Not you? Open Settings > Security.`,
      timestamp: FieldValue.serverTimestamp(),
      read: false,
      senderName: 'Swapnio',
      senderPhoto: '',
    });
  } else if (result.freshSignIn) {
    await logEvent(uid, 'sign_in', { deviceId, detail: `${clip(data.model)} · ${where}` });
  }

  const tf = await twoFactorDoc(uid);
  const requires2fa = Boolean(tf && tf.enabled) && !result.trusted;
  return { revoked: false, requires2fa };
});

/**
 * Presence: the app calls this with online:true when it comes to the
 * foreground and then about once a minute while it stays there, and with
 * online:false when it goes to the background. A device is shown as
 * "Active now" only while it's online AND has been heard from in the last
 * couple of minutes - so a phone that was killed without saying goodbye
 * drops to "Last active ..." on its own.
 */
exports.devicePresence = onCall(async (request) => {
  const uid = requireUid(request);
  const data = request.data || {};
  const deviceId = requireDeviceId(data.deviceId);
  const ref = db().collection('users').doc(uid).collection('devices').doc(deviceId);
  const snap = await ref.get();
  // Unknown or signed-out devices check in through registerDevice first.
  if (!snap.exists || snap.get('revoked') === true) return { ok: false };
  await ref.update({ online: data.online === true, lastSeenAt: FieldValue.serverTimestamp() });
  return { ok: true };
});

exports.signOutDevice = onCall(async (request) => {
  const uid = requireUid(request);
  const deviceId = requireDeviceId(request.data && request.data.deviceId);
  const ref = db().collection('users').doc(uid).collection('devices').doc(deviceId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Device not found.');
  await ref.update({ revoked: true, revokedAt: Timestamp.now(), trusted: false, online: false });
  await logEvent(uid, 'device_signed_out', { deviceId, detail: snap.get('model') || '' });
  return { ok: true };
});

exports.signOutOtherDevices = onCall(async (request) => {
  const uid = requireUid(request);
  const keep = requireDeviceId(request.data && request.data.currentDeviceId);
  const devices = await db().collection('users').doc(uid).collection('devices').get();
  const now = Timestamp.now();
  let count = 0;
  for (const d of devices.docs) {
    if (d.id === keep || d.get('revoked')) continue;
    await d.ref.update({ revoked: true, revokedAt: now, trusted: false, online: false });
    count++;
  }
  await logEvent(uid, 'signed_out_everywhere', { deviceId: keep, detail: `${count} device(s)` });
  return { count };
});

// ---------------------------------------------------------------------- 2FA

function aesKey() {
  return crypto.createHash('sha256').update(TOTP_KEY.value()).digest();
}

function encrypt(text) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', aesKey(), iv);
  const enc = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), enc].map((b) => b.toString('base64')).join('.');
}

function decrypt(blob) {
  const [iv, tag, enc] = blob.split('.').map((s) => Buffer.from(s, 'base64'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', aesKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
}

const hashCode = (code) => crypto.createHash('sha256').update(code.toUpperCase()).digest('hex');

function totp() {
  const { authenticator } = require('otplib');
  authenticator.options = { window: 1 }; // accept the previous/next 30 s step
  return authenticator;
}

const tfRef = (uid) => db().collection('users').doc(uid).collection('private').doc('twoFactor');

/**
 * Checks a TOTP or backup code with rate limiting. Consumes a backup code on
 * use. Returns 'totp' | 'backup'; throws with a user-facing message otherwise.
 */
async function checkCode(uid, rawCode, { allowPending = false } = {}) {
  const code = (rawCode || '').toString().replace(/\s+/g, '');
  const ref = tfRef(uid);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('failed-precondition', 'Two-factor is not set up.');
    const tf = snap.data();
    const lockedUntil = tf.lockedUntil ? tf.lockedUntil.toMillis() : 0;
    if (lockedUntil > Date.now()) {
      const mins = Math.ceil((lockedUntil - Date.now()) / 60000);
      throw new HttpsError('resource-exhausted', `Too many wrong codes. Try again in ${mins} min.`);
    }
    const secretBlob = allowPending && tf.pendingSecret ? tf.pendingSecret : tf.secret;
    let kind = null;
    if (/^\d{6}$/.test(code) && secretBlob && totp().check(code, decrypt(secretBlob))) kind = 'totp';
    if (!kind && /^[A-Za-z0-9]{8}$/.test(code)) {
      const h = hashCode(code);
      if ((tf.backupHashes || []).includes(h)) {
        kind = 'backup';
        tx.update(ref, { backupHashes: FieldValue.arrayRemove(h) });
      }
    }
    if (!kind) {
      const failures = (tf.failures || 0) + 1;
      tx.update(ref, failures >= MAX_FAILURES
        ? { failures: 0, lockedUntil: Timestamp.fromMillis(Date.now() + LOCK_MINUTES * 60000) }
        : { failures });
      return null;
    }
    tx.update(ref, { failures: 0, lockedUntil: FieldValue.delete() });
    return kind;
  }).then(async (kind) => {
    if (!kind) {
      await logEvent(uid, '2fa_failed');
      throw new HttpsError('permission-denied', "That code isn't right.");
    }
    if (kind === 'backup') await logEvent(uid, 'backup_code_used');
    return kind;
  });
}

exports.startTwoFactorSetup = onCall({ secrets: [TOTP_KEY] }, async (request) => {
  const uid = requireUid(request);
  const tf = await twoFactorDoc(uid);
  if (tf && tf.enabled) throw new HttpsError('failed-precondition', 'Two-factor is already on.');
  const secret = totp().generateSecret();
  const user = await admin.auth().getUser(uid);
  const label = user.email || uid;
  await tfRef(uid).set({ pendingSecret: encrypt(secret), enabled: false, failures: 0 }, { merge: true });
  return { secret, otpauth: totp().keyuri(label, 'Swapnio', secret) };
});

exports.confirmTwoFactorSetup = onCall({ secrets: [TOTP_KEY] }, async (request) => {
  const uid = requireUid(request);
  const deviceId = requireDeviceId(request.data && request.data.deviceId);
  const tf = await twoFactorDoc(uid);
  if (!tf || !tf.pendingSecret) throw new HttpsError('failed-precondition', 'Start setup first.');
  await checkCode(uid, request.data.code, { allowPending: true });
  const codes = Array.from({ length: 10 }, () =>
    crypto.randomBytes(6).toString('base64').replace(/[^A-Za-z0-9]/g, 'X').slice(0, 8).toUpperCase());
  await tfRef(uid).set({
    secret: tf.pendingSecret,
    pendingSecret: FieldValue.delete(),
    enabled: true,
    enabledAt: FieldValue.serverTimestamp(),
    backupHashes: codes.map(hashCode),
  }, { merge: true });
  await db().collection('users').doc(uid).collection('devices').doc(deviceId)
    .set({ trusted: true }, { merge: true });
  await logEvent(uid, '2fa_enabled', { deviceId });
  return { backupCodes: codes };
});

exports.verifyDeviceCode = onCall({ secrets: [TOTP_KEY] }, async (request) => {
  const uid = requireUid(request);
  const deviceId = requireDeviceId(request.data && request.data.deviceId);
  const kind = await checkCode(uid, request.data.code);
  await db().collection('users').doc(uid).collection('devices').doc(deviceId)
    .set({ trusted: true }, { merge: true });
  await logEvent(uid, 'device_verified', { deviceId, detail: kind });
  const tf = await twoFactorDoc(uid);
  return { backupCodesLeft: (tf.backupHashes || []).length };
});

exports.disableTwoFactor = onCall({ secrets: [TOTP_KEY] }, async (request) => {
  const uid = requireUid(request);
  await checkCode(uid, request.data && request.data.code);
  await tfRef(uid).delete();
  await logEvent(uid, '2fa_disabled');
  return { ok: true };
});

exports.twoFactorStatus = onCall(async (request) => {
  const uid = requireUid(request);
  const tf = await twoFactorDoc(uid);
  return {
    enabled: Boolean(tf && tf.enabled),
    backupCodesLeft: tf && tf.enabled ? (tf.backupHashes || []).length : 0,
  };
});

// ----------------------------------------------------- account-level events

/** Logs bans and admin changes made to a user document. */
exports.securityOnUserChange = onDocumentUpdated('users/{uid}', async (event) => {
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};
  if (Boolean(before.isBanned) !== Boolean(after.isBanned)) {
    await logEvent(event.params.uid, after.isBanned ? 'banned' : 'unbanned');
  }
  if (Boolean(before.isAdmin) !== Boolean(after.isAdmin)) {
    await logEvent(event.params.uid, after.isAdmin ? 'admin_granted' : 'admin_removed');
  }
});

exports.logEvent = logEvent;
