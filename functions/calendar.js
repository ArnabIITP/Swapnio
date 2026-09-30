/**
 * Google Calendar + Meet for sessions, run on the server.
 *
 * Connecting: the app signs in with Google for the calendar scopes and sends
 * a one-time server auth code; we swap it for a refresh token, stored
 * encrypted (AES-256-GCM, key CAL_TOKEN_KEY) in users/{uid}/private/google.
 * Only these functions can read it. users/{uid}.calendarConnected is the
 * public yes/no (a protected field).
 *
 * BOTH people must be connected to book a session (checked when proposing,
 * see schedule.js) and again on ACCEPT, when the event is created in the
 * accepting person's calendar with BOTH people as guests - so both can join the Meet without
 * "Ask to join" - and Google emails the invite. Reschedules move it and
 * cancellations delete it, with Google's own updates to both.
 *
 * Busy times: with the free/busy scope, a person's Google busy blocks show
 * on their own time picker; they reach others' pickers only if the person
 * turned on sharing (off by default) - start and end only, never titles.
 */
const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');

const WEB_CLIENT_ID = '924792323555-ludfh213atbvrhtclsmj6of0c8s5o3rl.apps.googleusercontent.com';
const OAUTH_SECRET = defineSecret('GOOGLE_OAUTH_CLIENT_SECRET');
const TOKEN_KEY = defineSecret('CAL_TOKEN_KEY');
const SECRETS = [OAUTH_SECRET, TOKEN_KEY];

const EVENTS_SCOPE = 'https://www.googleapis.com/auth/calendar.events';
const FREEBUSY_SCOPE = 'https://www.googleapis.com/auth/calendar.freebusy';
const API = 'https://www.googleapis.com/calendar/v3';
const CALENDAR_REQUIRED = 'CALENDAR_REQUIRED';
const PARTNER_REQUIRED = 'PARTNER_CALENDAR_REQUIRED';

// Emulator-only stand-in for Google (functions/.env.local sets it): a user
// counts as connected when users/{uid}.calendarConnected is true, and API
// calls are recorded in _fakeCalendar instead of being sent.
const FAKE = process.env.FUNCTIONS_EMULATOR === 'true' && process.env.CALENDAR_FAKE === '1';

const db = () => admin.firestore();
const millis = (ts) => (ts && typeof ts.toMillis === 'function' ? ts.toMillis() : null);
const privateRef = (uid) => db().collection('users').doc(uid).collection('private').doc('google');

// ------------------------------------------------------------ token storage

function key() {
  return crypto.createHash('sha256').update(TOKEN_KEY.value()).digest();
}

function encrypt(text) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv);
  const enc = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), enc].map((b) => b.toString('base64')).join('.');
}

function decrypt(blob) {
  const [iv, tag, enc] = blob.split('.').map((s) => Buffer.from(s, 'base64'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
}

function oauth() {
  const { OAuth2Client } = require('google-auth-library');
  return new OAuth2Client(WEB_CLIENT_ID, OAUTH_SECRET.value(), '');
}

/** A fresh access token for [uid], or null if they aren't connected (or revoked access). */
async function accessTokenFor(uid) {
  if (FAKE) {
    const u = await db().collection('users').doc(uid).get();
    return u.get('calendarConnected') === true ? `fake-token-${uid}` : null;
  }
  const snap = await privateRef(uid).get();
  if (!snap.exists || !snap.get('refreshToken')) return null;
  const client = oauth();
  client.setCredentials({ refresh_token: decrypt(snap.get('refreshToken')) });
  try {
    const { token } = await client.getAccessToken();
    return token || null;
  } catch (e) {
    // Access was revoked in the Google account - mark as disconnected.
    if (/invalid_grant/.test(String(e && e.message))) await forget(uid);
    console.error('calendar token refresh failed', uid, e && e.message);
    return null;
  }
}

async function forget(uid) {
  await privateRef(uid).delete();
  await db().collection('users').doc(uid).update({ calendarConnected: false });
}

async function api(token, method, path, body) {
  if (FAKE) {
    const ref = await db().collection('_fakeCalendar').add({ token, method, path, body: body || null, at: Date.now() });
    if (path.startsWith('/freeBusy')) return { calendars: { primary: { busy: [] } } };
    return { id: `fake-${ref.id}`, htmlLink: 'https://calendar.google.com/fake', hangoutLink: `https://meet.google.com/fake-${ref.id.slice(0, 8)}` };
  }
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204 || res.status === 410) return {};
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Calendar API ${res.status}: ${JSON.stringify(json.error || json)}`);
  return json;
}

// ------------------------------------------------------------ connect

exports.connectGoogleCalendar = onCall({ secrets: SECRETS }, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const code = request.data && request.data.code;
  if (typeof code !== 'string' || !code) throw new HttpsError('invalid-argument', 'Missing Google code.');
  let tokens;
  try {
    ({ tokens } = await oauth().getToken({ code, redirect_uri: '' }));
  } catch (e) {
    console.error('code exchange failed', e && e.message);
    throw new HttpsError('failed-precondition', 'Google didn\'t accept that sign-in. Please try again.');
  }
  const scopes = String(tokens.scope || '').split(' ');
  if (!scopes.includes(EVENTS_SCOPE)) {
    throw new HttpsError('failed-precondition', 'Swapnio needs permission to add events to your calendar.');
  }
  const existing = await privateRef(uid).get();
  const refresh = tokens.refresh_token || (existing.exists ? decrypt(existing.get('refreshToken')) : null);
  if (!refresh) {
    throw new HttpsError(
      'failed-precondition',
      'Google didn\'t give Swapnio lasting access. Remove Swapnio in your Google account\'s third-party access, then connect again.',
    );
  }
  let email = '';
  if (tokens.id_token) {
    const ticket = await oauth().verifyIdToken({ idToken: tokens.id_token, audience: WEB_CLIENT_ID }).catch(() => null);
    email = (ticket && ticket.getPayload().email) || '';
  }
  await privateRef(uid).set({
    refreshToken: encrypt(refresh),
    email,
    scopes,
    shareBusy: existing.exists ? existing.get('shareBusy') === true : false,
    connectedAt: FieldValue.serverTimestamp(),
  });
  await db().collection('users').doc(uid).update({ calendarConnected: true });
  return { ok: true, email, freeBusy: scopes.includes(FREEBUSY_SCOPE) };
});

exports.disconnectGoogleCalendar = onCall({ secrets: SECRETS }, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const snap = await privateRef(uid).get();
  if (snap.exists && snap.get('refreshToken')) {
    await oauth().revokeToken(decrypt(snap.get('refreshToken'))).catch(() => null);
  }
  await forget(uid);
  return { ok: true };
});

exports.calendarStatus = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const snap = await privateRef(uid).get();
  if (!snap.exists) return { connected: false, email: '', freeBusy: false, shareBusy: false };
  const scopes = snap.get('scopes') || [];
  return {
    connected: true,
    email: snap.get('email') || '',
    freeBusy: scopes.includes(FREEBUSY_SCOPE),
    shareBusy: snap.get('shareBusy') === true,
  };
});

exports.setBusySharing = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const snap = await privateRef(uid).get();
  if (!snap.exists) throw new HttpsError('failed-precondition', 'Connect Google Calendar first.');
  const share = request.data && request.data.share === true;
  if (share && !(snap.get('scopes') || []).includes(FREEBUSY_SCOPE)) {
    throw new HttpsError('failed-precondition', 'Allow Swapnio to see when you\'re busy first.');
  }
  await privateRef(uid).update({ shareBusy: share });
  return { ok: true, shareBusy: share };
});

// ------------------------------------------------------------ session hooks

async function emailOf(uid) {
  const snap = await privateRef(uid).get();
  if (snap.exists && snap.get('email')) return snap.get('email');
  const user = await admin.auth().getUser(uid).catch(() => null);
  return (user && user.email) || '';
}

function eventBody(swap, emails) {
  const start = millis(swap.scheduledFor);
  const end = millis(swap.endsAt) || start + (Number(swap.plannedMinutes) || 60) * 60000;
  const names = swap.participantNames || {};
  const offered = (swap.skillOffered || '').trim();
  const wanted = (swap.skillWanted || '').trim();
  const organiser = names[swap.createdBy] || 'Swapnio member';
  const topic = offered && wanted
    ? `${offered} ↔ ${wanted}`
    : offered
      ? `${organiser.split(' ')[0]} teaches ${offered}`
      : `${organiser.split(' ')[0]} learns ${wanted}`;
  return {
    summary: `Swapnio: ${topic}`,
    description: [
      'Skill swap session arranged on Swapnio.',
      swap.agenda ? `\nAgenda: ${swap.agenda}` : '',
      '\nOpen Swapnio and tap "Join session" to check in and join.',
    ].join(''),
    start: { dateTime: new Date(start).toISOString() },
    end: { dateTime: new Date(end).toISOString() },
    attendees: emails.filter(Boolean).map((email) => ({ email })),
    guestsCanModify: false,
    reminders: { useDefault: true },
  };
}

/**
 * Before a session is accepted: both people must still be connected; the
 * event (with a Meet link) is created in the accepting person's calendar.
 * Returns fields to save on the session; throws if either isn't connected
 * or Google refuses.
 */
async function prepareAccept({ swapId, swap, acceptedBy }) {
  const parts = (swap.participants || []).filter(Boolean);
  const other = parts.find((p) => p !== acceptedBy);
  const [token, otherToken] = await Promise.all([accessTokenFor(acceptedBy), accessTokenFor(other)]);
  if (!token) {
    throw new HttpsError(
      'failed-precondition',
      `${CALENDAR_REQUIRED}: Connect Google Calendar to accept - it creates the Meet link and puts the session in both calendars.`,
    );
  }
  if (!otherToken) {
    const name = ((swap.participantNames || {})[other] || 'The other person').toString().split(' ')[0];
    throw new HttpsError(
      'failed-precondition',
      `${PARTNER_REQUIRED}: ${name} has disconnected Google Calendar, so this can't be accepted until they connect again.`,
    );
  }
  const organiser = acceptedBy;
  const emails = await Promise.all(parts.map(emailOf));
  const body = eventBody(swap, emails);
  body.conferenceData = {
    createRequest: { requestId: `swapnio-${swapId}`, conferenceSolutionKey: { type: 'hangoutsMeet' } },
  };
  let event;
  try {
    event = await api(token, 'POST', '/calendars/primary/events?conferenceDataVersion=1&sendUpdates=all', body);
  } catch (e) {
    console.error('event create failed', swapId, e.message);
    throw new HttpsError('unavailable', 'Google Calendar couldn\'t create the event just now. Please try again.');
  }
  const meet = (event.conferenceData && (event.conferenceData.entryPoints || []).find((p) => p.entryPointType === 'video')) || null;
  return {
    calendar: {
      eventId: event.id,
      organizer: organiser,
      meetLink: (meet && meet.uri) || event.hangoutLink || '',
      htmlLink: event.htmlLink || '',
    },
    meetingLink: (meet && meet.uri) || event.hangoutLink || '',
  };
}

async function onRescheduled({ swapId, swap }) {
  const cal = swap.calendar;
  if (!cal || !cal.eventId) return;
  const token = await accessTokenFor(cal.organizer);
  if (!token) return;
  const body = eventBody(swap, []);
  await api(token, 'PATCH', `/calendars/primary/events/${encodeURIComponent(cal.eventId)}?sendUpdates=all`, {
    start: body.start,
    end: body.end,
  }).catch((e) => console.error('event move failed', swapId, e.message));
}

async function onCancelled({ swapId, swap }) {
  const cal = swap.calendar;
  if (!cal || !cal.eventId) return;
  const token = await accessTokenFor(cal.organizer);
  if (!token) return;
  await api(token, 'DELETE', `/calendars/primary/events/${encodeURIComponent(cal.eventId)}?sendUpdates=all`)
    .catch((e) => console.error('event delete failed', swapId, e.message));
}

/**
 * Google busy blocks for [uid] between [from] and [to] (ms). [forOthers]
 * returns nothing unless the person chose to share.
 */
async function googleBusy(uid, from, to, forOthers) {
  if (FAKE) return [];
  const snap = await privateRef(uid).get();
  if (!snap.exists || !(snap.get('scopes') || []).includes(FREEBUSY_SCOPE)) return [];
  if (forOthers && snap.get('shareBusy') !== true) return [];
  const token = await accessTokenFor(uid);
  if (!token) return [];
  try {
    const res = await api(token, 'POST', '/freeBusy', {
      timeMin: new Date(from).toISOString(),
      timeMax: new Date(to).toISOString(),
      items: [{ id: 'primary' }],
    });
    const busy = (((res.calendars || {}).primary || {}).busy) || [];
    return busy.map((b) => ({ start: Date.parse(b.start), end: Date.parse(b.end) }));
  } catch (e) {
    console.error('freebusy failed', uid, e.message);
    return [];
  }
}

module.exports = {
  ...module.exports,
  SECRETS,
  CALENDAR_REQUIRED,
  PARTNER_REQUIRED,
  prepareAccept,
  onRescheduled,
  onCancelled,
  googleBusy,
  _test: { eventBody },
};
