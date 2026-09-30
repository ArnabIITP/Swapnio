/**
 * Session scheduling: propose, accept / decline, cancel, reschedule.
 *
 * These used to be plain client writes. They run here so every change can be
 * checked against BOTH people's calendars:
 *   - a clash with an ACCEPTED session is refused,
 *   - a clash with a PENDING one (a proposal or a requested new time) is a
 *     warning the caller confirms with `force: true`.
 * Sessions are compared with a 10-minute buffer on either side.
 *
 * Session types (from the organiser's side): 'swap' - both teach; 'teach' -
 * the organiser only teaches (skillWanted empty); 'learn' - the organiser only
 * learns (skillOffered empty). The time rules already split minutes this way
 * (see sessionSplit in sessions.js).
 *
 * Every session has a planned length (plannedMinutes) and so an end time
 * (endsAt), which is what the clash check and the in-app calendar use.
 *
 * Cancelling
 *   - before the start: a reason is optional, but required inside the last
 *     LATE_CANCEL_HOURS, which also marks it a late cancel;
 *   - while running: only in the first MIN_SESSION_MINUTES (after that the
 *     session can be completed instead). No time is counted.
 *   Cancelling never counts as a no-show. Anyone cancelling more than
 *   CANCEL_FLAG_COUNT times in CANCEL_FLAG_DAYS is flagged for admins.
 *
 * Google Calendar is required of BOTH people: you can't propose a session
 * until you and the other person have connected it (see calendar.js), and
 * accepting checks both connections again before the event is created. A
 * partner who hasn't connected yet is nudged (at most once a day per person
 * asking).
 *
 * Rescheduling asks the other person: the original time stays booked until
 * they accept the new one (then it moves) or decline it (then nothing
 * changes).
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const calendar = require('./calendar');
const streaks = require('./streaks');

const PLANNED_MINUTES = [30, 45, 60, 90];
const BUFFER_MINUTES = 10;
const LEGACY_PLANNED_MINUTES = 60;
const LATE_CANCEL_HOURS = 2;
const RUNNING_CANCEL_MINUTES = 30;
const CANCEL_FLAG_COUNT = 5;
const CANCEL_FLAG_DAYS = 30;
const MAX_DAYS_AHEAD = 365;
const OPEN = ['pending', 'accepted'];

const db = () => admin.firestore();
const millis = (ts) => (ts && typeof ts.toMillis === 'function' ? ts.toMillis() : null);
const clip = (v, n = 80) => (typeof v === 'string' ? v.trim().slice(0, n) : '');

function requireUid(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function plannedOf(v) {
  const n = Number(v);
  if (!PLANNED_MINUTES.includes(n)) {
    throw new HttpsError('invalid-argument', `Length must be one of ${PLANNED_MINUTES.join(', ')} minutes.`);
  }
  return n;
}

function startOf(v) {
  const ms = Number(v);
  if (!Number.isFinite(ms)) throw new HttpsError('invalid-argument', 'Pick a date and time.');
  if (ms < Date.now() - 5 * 60000) throw new HttpsError('invalid-argument', 'That time has already passed.');
  if (ms > Date.now() + MAX_DAYS_AHEAD * 86400000) {
    throw new HttpsError('invalid-argument', 'Sessions can be planned up to a year ahead.');
  }
  return ms;
}

/** [start, end] of a session in ms, falling back for sessions made before lengths existed. */
function spanOf(swap) {
  const start = millis(swap.scheduledFor);
  if (start === null) return null;
  const end = millis(swap.endsAt) || start + (Number(swap.plannedMinutes) || LEGACY_PLANNED_MINUTES) * 60000;
  return [start, end];
}

function timeLabel(ms, tzOffsetMinutes) {
  // Shown in the caller's own time zone when the app tells us its offset.
  const d = new Date(ms - (Number(tzOffsetMinutes) || 0) * 60000);
  const hh = d.getUTCHours();
  const mm = String(d.getUTCMinutes()).padStart(2, '0');
  const h12 = ((hh + 11) % 12) + 1;
  const day = d.toUTCString().slice(0, 11);
  return `${day}, ${h12}:${mm} ${hh < 12 ? 'AM' : 'PM'}`;
}

/**
 * Everything on [uid]'s calendar that overlaps [start, end] (plus buffer):
 * [{swapId, kind: 'accepted'|'pending', start, end, withName}].
 * A requested new time on an accepted session counts as pending.
 */
async function clashesFor(uid, start, end, excludeId) {
  const snap = await db().collection('swaps')
    .where('participants', 'array-contains', uid)
    .where('status', 'in', OPEN)
    .limit(300)
    .get();
  const pad = BUFFER_MINUTES * 60000;
  const out = [];
  for (const doc of snap.docs) {
    if (doc.id === excludeId) continue;
    const s = doc.data();
    // A session that has already ended isn't in the way any more.
    if (s.endedAt) continue;
    const other = (s.participants || []).find((p) => p !== uid);
    const withName = ((s.participantNames || {})[other] || 'someone').toString();
    const spans = [];
    const own = spanOf(s);
    if (own) spans.push({ span: own, kind: s.status === 'accepted' ? 'accepted' : 'pending' });
    const r = s.pendingReschedule;
    if (r && millis(r.at)) {
      spans.push({ span: [millis(r.at), millis(r.endsAt) || millis(r.at) + LEGACY_PLANNED_MINUTES * 60000], kind: 'pending' });
    }
    for (const { span, kind } of spans) {
      if (span[0] < end + pad && start < span[1] + pad) {
        out.push({ swapId: doc.id, kind, start: span[0], end: span[1], withName });
      }
    }
  }
  return out;
}

/**
 * Checks both people. Accepted clashes throw; pending ones come back as
 * warnings unless [force]. The partner's clashes never reveal who they're with.
 */
async function checkClashes({ uid, otherId, otherName, start, end, excludeId, force, tz }) {
  const [mine, theirs] = await Promise.all([
    clashesFor(uid, start, end, excludeId),
    otherId ? clashesFor(otherId, start, end, excludeId) : Promise.resolve([]),
  ]);
  const hardMine = mine.find((c) => c.kind === 'accepted');
  if (hardMine) {
    throw new HttpsError(
      'failed-precondition',
      `You already have a session with ${hardMine.withName} at ${timeLabel(hardMine.start, tz)}. Pick another time.`,
    );
  }
  const hardTheirs = theirs.find((c) => c.kind === 'accepted');
  if (hardTheirs) {
    throw new HttpsError(
      'failed-precondition',
      `${otherName || 'They'} already ${otherName ? 'has' : 'have'} a session at ${timeLabel(hardTheirs.start, tz)}. Pick another time.`,
    );
  }
  const warnings = [
    ...mine.map((c) => `You have a pending session with ${c.withName} at ${timeLabel(c.start, tz)}.`),
    ...theirs.map((c) => `${otherName || 'They'} ${otherName ? 'has' : 'have'} a pending session at ${timeLabel(c.start, tz)}.`),
  ];
  if (warnings.length && !force) return warnings;
  return [];
}

async function notify(userId, type, message, senderId, senderName, extra = {}) {
  if (!userId) return;
  await db().collection('notifications').add({
    userId,
    type,
    message,
    timestamp: FieldValue.serverTimestamp(),
    read: false,
    senderId: senderId || '',
    senderName: senderName || 'Swapnio',
    senderPhoto: '',
    // Where tapping the notification should go (see notifications_page.dart).
    ...extra,
  });
}

const roomIdOf = (a, b) => (a < b ? `${a}_${b}` : `${b}_${a}`);

/**
 * Posts the proposal into the pair's chat as a session card. It counts as an
 * unread message for the other person - the Chats counter is driven by
 * messages, not by sessions.
 */
async function postSessionCard({ swapId, from, to, fromName, toName, summary, when }) {
  const roomRef = db().collection('chatRooms').doc(roomIdOf(from, to));
  const room = await roomRef.get();
  if (!room.exists) {
    await roomRef.set({
      users: [from, to],
      userNames: { [from]: fromName, [to]: toName },
      unreadCount: { [from]: 0, [to]: 0 },
    }, { merge: true });
  }
  const text = `Proposed a session: ${summary} · ${when}`;
  await roomRef.collection('messages').add({
    senderId: from,
    type: 'session',
    swapId,
    text,
    timestamp: FieldValue.serverTimestamp(),
  });
  await roomRef.update({
    lastMessage: `📅 ${text}`,
    lastMessageTime: FieldValue.serverTimestamp(),
    lastMessageSenderId: from,
    [`unreadCount.${to}`]: FieldValue.increment(1),
  });
}

async function loadSwap(swapId, uid) {
  if (typeof swapId !== 'string' || !swapId) throw new HttpsError('invalid-argument', 'A swapId is required.');
  const ref = db().collection('swaps').doc(swapId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Session not found.');
  const swap = snap.data();
  if (!(swap.participants || []).includes(uid)) throw new HttpsError('permission-denied', 'This is not your session.');
  const otherId = swap.participants.find((p) => p !== uid) || null;
  const names = swap.participantNames || {};
  return { ref, swap, otherId, me: (names[uid] || 'Your swap partner').toString(), other: (names[otherId] || '').toString() };
}

function reliable(user) {
  const attended = Number(user.sessionsAttended) || 0;
  const noShows = Number(user.noShowCount) || 0;
  return attended + noShows < 3 || attended * 2 >= attended + noShows;
}

async function calendarHook(name, payload) {
  // Google Calendar sync after the fact (move / delete the event) never
  // blocks the session change itself.
  try {
    await calendar[name](payload);
  } catch (e) {
    console.error(`calendar.${name} failed`, e);
  }
}

/** Tells [uid] someone wants to book with them - at most daily per asker. */
async function nudgeToConnect(uid, askerId, askerName) {
  const ref = db().collection('calendarNudges').doc(`${uid}_${askerId}`);
  const snap = await ref.get();
  if (snap.exists && Date.now() - (millis(snap.get('at')) || 0) < 86400000) return;
  await ref.set({ uid, askerId, at: FieldValue.serverTimestamp() });
  await notify(
    uid,
    'calendar_required',
    `${askerName} wants to book a session with you - connect Google Calendar in Settings so you can swap`,
    askerId,
    askerName,
  );
}

/** "Let them know": nudges a partner who hasn't connected Google Calendar. */
exports.askToConnectCalendar = onCall(async (request) => {
  const uid = requireUid(request);
  const otherId = clip(request.data && request.data.otherUserId, 128);
  if (!otherId || otherId === uid) throw new HttpsError('invalid-argument', 'Pick who to ask.');
  const [meDoc, otherDoc] = await Promise.all([
    db().collection('users').doc(uid).get(),
    db().collection('users').doc(otherId).get(),
  ]);
  if (!otherDoc.exists) throw new HttpsError('not-found', 'That member is not available.');
  if (otherDoc.get('calendarConnected') === true) return { ok: true, alreadyConnected: true };
  await nudgeToConnect(otherId, uid, (meDoc.get('name') || 'Someone').toString());
  return { ok: true };
});

// --------------------------------------------------------------- propose

exports.proposeSession = onCall(async (request) => {
  const uid = requireUid(request);
  const d = request.data || {};
  const otherId = clip(d.otherUserId, 128);
  if (!otherId || otherId === uid) throw new HttpsError('invalid-argument', 'Pick who the session is with.');
  const type = ['swap', 'teach', 'learn'].includes(d.sessionType) ? d.sessionType : 'swap';
  const offered = type === 'learn' ? '' : clip(d.skillOffered);
  const wanted = type === 'teach' ? '' : clip(d.skillWanted);
  if (type !== 'learn' && !offered) throw new HttpsError('invalid-argument', 'Pick what you will teach.');
  if (type !== 'teach' && !wanted) throw new HttpsError('invalid-argument', 'Pick what you want to learn.');
  const planned = plannedOf(d.plannedMinutes);
  const start = startOf(d.scheduledFor);
  const end = start + planned * 60000;

  const [meDoc, otherDoc, blockA, blockB] = await Promise.all([
    db().collection('users').doc(uid).get(),
    db().collection('users').doc(otherId).get(),
    db().collection('blocks').where('userId', '==', uid).where('blockedUserId', '==', otherId).limit(1).get(),
    db().collection('blocks').where('userId', '==', otherId).where('blockedUserId', '==', uid).limit(1).get(),
  ]);
  if (!otherDoc.exists || otherDoc.get('isBanned') === true) throw new HttpsError('not-found', 'That member is not available.');
  if (!blockA.empty || !blockB.empty) throw new HttpsError('permission-denied', 'You can\'t book a session with this member.');
  const meData = meDoc.data() || {};
  if (!reliable(meData)) {
    throw new HttpsError('failed-precondition', 'Too many missed sessions recently - attend your booked sessions to book new ones.');
  }
  const myName = (meData.name || 'Swapnio user').toString();
  const otherName = (otherDoc.get('name') || 'your partner').toString();
  if (meData.calendarConnected !== true) {
    throw new HttpsError(
      'failed-precondition',
      `${calendar.CALENDAR_REQUIRED}: Connect Google Calendar to book sessions - it creates the Meet link and puts the session in both calendars.`,
    );
  }
  if (otherDoc.get('calendarConnected') !== true) {
    await nudgeToConnect(otherId, uid, myName);
    throw new HttpsError(
      'failed-precondition',
      `${calendar.PARTNER_REQUIRED}: ${otherName.split(' ')[0]} hasn't connected Google Calendar yet, so you can't book a session with them. We've let them know.`,
    );
  }

  const warnings = await checkClashes({ uid, otherId, otherName: otherName.split(' ')[0], start, end, force: d.force === true, tz: d.tzOffset });
  if (warnings.length) return { needsConfirm: true, warnings };

  const ref = await db().collection('swaps').add({
    participants: [uid, otherId],
    participantNames: { [uid]: myName, [otherId]: otherName },
    sessionType: type,
    skillOffered: offered,
    skillWanted: wanted,
    scheduledFor: Timestamp.fromMillis(start),
    plannedMinutes: planned,
    endsAt: Timestamp.fromMillis(end),
    agenda: clip(d.agenda, 500),
    meetingLink: '',
    status: 'pending',
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  const what = type === 'teach' ? `to teach you ${offered}` : type === 'learn' ? `to learn ${wanted} from you` : 'a swap session';
  await notify(otherId, 'session_proposed', `${myName} proposed ${what}`, uid, myName, { swapId: ref.id });
  const summary = type === 'teach'
    ? `${myName.split(' ')[0]} teaches ${offered}`
    : type === 'learn'
      ? `${myName.split(' ')[0]} learns ${wanted}`
      : `${offered} ↔ ${wanted}`;
  await postSessionCard({
    swapId: ref.id,
    from: uid,
    to: otherId,
    fromName: myName,
    toName: otherName,
    summary,
    when: `${timeLabel(start, d.tzOffset)} · ${planned} min`,
  }).catch((e) => console.error('session card failed', ref.id, e));
  await streaks.recordActivity(uid);
  return { ok: true, swapId: ref.id };
});

// --------------------------------------------------------------- respond

exports.respondSession = onCall({ secrets: calendar.SECRETS }, async (request) => {
  const uid = requireUid(request);
  const d = request.data || {};
  const { ref, swap, otherId, me } = await loadSwap(d.swapId, uid);
  if (swap.status !== 'pending') throw new HttpsError('failed-precondition', 'This session was already answered.');
  if (swap.createdBy === uid) throw new HttpsError('permission-denied', 'The other person answers your proposal.');
  if (d.accept !== true) {
    await ref.update({ status: 'declined', respondedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    await notify(otherId, 'session_declined', `${me} declined the session`, uid, me, { swapId: ref.id });
    return { ok: true, status: 'declined' };
  }
  const span = spanOf(swap);
  if (span && span[1] < Date.now()) throw new HttpsError('failed-precondition', 'This session time has passed - ask for a new time.');
  if (span) {
    // Accepting only has to avoid accepted sessions; pending ones are fine.
    await checkClashes({ uid, otherId, otherName: '', start: span[0], end: span[1], excludeId: ref.id, force: true, tz: d.tzOffset });
  }
  // Needs one of the two connected to Google; creates the Meet event with
  // both as guests. Throws (and nothing is accepted) if that isn't possible.
  const cal = await calendar.prepareAccept({ swapId: ref.id, swap, acceptedBy: uid });
  await ref.update({
    ...cal,
    status: 'accepted',
    respondedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await notify(otherId, 'session_accepted', `${me} accepted your session`, uid, me, { swapId: ref.id });
  await streaks.recordActivity(uid);
  return { ok: true, status: 'accepted' };
});

// --------------------------------------------------------------- cancel

exports.cancelSession = onCall({ secrets: calendar.SECRETS }, async (request) => {
  const uid = requireUid(request);
  const d = request.data || {};
  const reason = clip(d.reason, 300);
  const { ref, swap, otherId, me } = await loadSwap(d.swapId, uid);
  if (!OPEN.includes(swap.status)) throw new HttpsError('failed-precondition', 'This session can\'t be cancelled any more.');
  if (swap.status === 'pending' && swap.createdBy !== uid) {
    throw new HttpsError('failed-precondition', 'Decline the proposal instead.');
  }
  if (Object.keys(swap.completionConfirmations || {}).length) {
    throw new HttpsError('failed-precondition', 'Someone already marked this session complete.');
  }
  const startedAt = millis(swap.startedAt);
  let whileRunning = false;
  let late = false;
  if (startedAt) {
    if (Date.now() - startedAt > RUNNING_CANCEL_MINUTES * 60000) {
      throw new HttpsError('failed-precondition', `Past ${RUNNING_CANCEL_MINUTES} minutes - mark it complete instead.`);
    }
    whileRunning = true;
  } else if (swap.status === 'accepted') {
    const start = millis(swap.scheduledFor);
    late = start !== null && start - Date.now() < LATE_CANCEL_HOURS * 3600000;
    if (late && !reason) {
      throw new HttpsError('invalid-argument', `A reason is needed when cancelling less than ${LATE_CANCEL_HOURS} hours before the start.`);
    }
  }
  await ref.update({
    status: 'cancelled',
    cancelledBy: uid,
    cancelledAt: FieldValue.serverTimestamp(),
    cancelReason: reason,
    lateCancel: late,
    cancelledWhileRunning: whileRunning,
    pendingReschedule: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (swap.status === 'accepted') await calendarHook('onCancelled', { swapId: ref.id, swap, cancelledBy: uid });
  await notify(
    otherId,
    'session_cancelled',
    `${me} cancelled ${whileRunning ? 'your running session' : 'your session'}${reason ? `: "${reason}"` : ''}`,
    uid,
    me,
    { swapId: ref.id },
  );
  // Frequent cancellers are flagged for admins (never shown to others).
  if (swap.status === 'accepted') {
    const since = Timestamp.fromMillis(Date.now() - CANCEL_FLAG_DAYS * 86400000);
    const recent = await db().collection('swaps')
      .where('cancelledBy', '==', uid)
      .where('cancelledAt', '>=', since)
      .get();
    const count = recent.docs.filter((x) => x.get('status') === 'cancelled').length;
    if (count > CANCEL_FLAG_COUNT) {
      await db().collection('adminFlags').doc(`cancellations_${uid}`).set({
        uid,
        type: 'frequent_cancellations',
        count,
        windowDays: CANCEL_FLAG_DAYS,
        at: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }
  return { ok: true, lateCancel: late };
});

/** The caller's own cancellations in the last CANCEL_FLAG_DAYS - shown only to them. */
exports.myCancellationStats = onCall(async (request) => {
  const uid = requireUid(request);
  const since = Timestamp.fromMillis(Date.now() - CANCEL_FLAG_DAYS * 86400000);
  const recent = await db().collection('swaps')
    .where('cancelledBy', '==', uid)
    .where('cancelledAt', '>=', since)
    .get();
  const docs = recent.docs.filter((x) => x.get('status') === 'cancelled');
  return {
    windowDays: CANCEL_FLAG_DAYS,
    total: docs.length,
    late: docs.filter((x) => x.get('lateCancel') === true).length,
  };
});

// --------------------------------------------------------------- reschedule

exports.requestReschedule = onCall(async (request) => {
  const uid = requireUid(request);
  const d = request.data || {};
  const { ref, swap, otherId, me, other } = await loadSwap(d.swapId, uid);
  if (!OPEN.includes(swap.status)) throw new HttpsError('failed-precondition', 'Only an upcoming session can be moved.');
  if (swap.startedAt || Object.keys(swap.checkIns || {}).length) {
    throw new HttpsError('failed-precondition', 'This session has already started.');
  }
  const planned = d.plannedMinutes === undefined ? Number(swap.plannedMinutes) || LEGACY_PLANNED_MINUTES : plannedOf(d.plannedMinutes);
  const start = startOf(d.scheduledFor);
  const end = start + planned * 60000;
  const warnings = await checkClashes({ uid, otherId, otherName: other.split(' ')[0], start, end, excludeId: ref.id, force: d.force === true, tz: d.tzOffset });
  if (warnings.length) return { needsConfirm: true, warnings };

  // Still just a proposal by the same person: nothing to agree yet, so the
  // time simply changes.
  if (swap.status === 'pending' && swap.createdBy === uid) {
    await ref.update({
      scheduledFor: Timestamp.fromMillis(start),
      plannedMinutes: planned,
      endsAt: Timestamp.fromMillis(end),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await notify(otherId, 'session_rescheduled', `${me} changed the proposed time to ${timeLabel(start, d.tzOffset)}`, uid, me, { swapId: ref.id });
    return { ok: true, applied: true };
  }
  await ref.update({
    pendingReschedule: {
      at: Timestamp.fromMillis(start),
      endsAt: Timestamp.fromMillis(end),
      plannedMinutes: planned,
      by: uid,
      requestedAt: Timestamp.now(),
    },
    updatedAt: FieldValue.serverTimestamp(),
  });
  await notify(otherId, 'session_reschedule_requested', `${me} asked to move your session - tap to accept or keep the current time`, uid, me, { swapId: ref.id });
  return { ok: true, applied: false };
});

exports.respondReschedule = onCall({ secrets: calendar.SECRETS }, async (request) => {
  const uid = requireUid(request);
  const d = request.data || {};
  const { ref, swap, otherId, me } = await loadSwap(d.swapId, uid);
  const r = swap.pendingReschedule;
  if (!r) throw new HttpsError('failed-precondition', 'There is no new time waiting for an answer.');
  if (r.by === uid) throw new HttpsError('permission-denied', 'The other person answers your request.');
  if (d.accept !== true) {
    await ref.update({ pendingReschedule: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
    await notify(otherId, 'session_reschedule_declined', `${me} kept the original time`, uid, me, { swapId: ref.id });
    return { ok: true, applied: false };
  }
  const start = millis(r.at);
  const end = millis(r.endsAt);
  if (start < Date.now()) throw new HttpsError('failed-precondition', 'That new time has passed - ask for another one.');
  await checkClashes({ uid, otherId, otherName: '', start, end, excludeId: ref.id, force: true, tz: d.tzOffset });
  const update = {
    scheduledFor: r.at,
    endsAt: r.endsAt,
    plannedMinutes: r.plannedMinutes,
    pendingReschedule: FieldValue.delete(),
    rescheduledBy: r.by,
    reminderSent: FieldValue.delete(),
    reminderSent15: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.update(update);
  if (swap.status === 'accepted') {
    await calendarHook('onRescheduled', { swapId: ref.id, swap: { ...swap, scheduledFor: r.at, endsAt: r.endsAt, plannedMinutes: r.plannedMinutes } });
  }
  await notify(otherId, 'session_rescheduled', `${me} accepted the new time: ${timeLabel(start, d.tzOffset)}`, uid, me, { swapId: ref.id });
  return { ok: true, applied: true };
});

// --------------------------------------------------------------- busy times

/**
 * Busy blocks for the time picker on [day] (the caller's local day, given as
 * its start in ms): the caller's own sessions with names, and the other
 * person's as plain "busy" blocks - never who or what.
 */
exports.busyTimes = onCall({ secrets: calendar.SECRETS }, async (request) => {
  const uid = requireUid(request);
  const d = request.data || {};
  const from = Number(d.from);
  const to = Number(d.to);
  if (!Number.isFinite(from) || !Number.isFinite(to) || to <= from || to - from > 8 * 86400000) {
    throw new HttpsError('invalid-argument', 'Give a range of up to 8 days.');
  }
  const otherId = clip(d.otherUserId, 128) || null;
  const [mine, theirs] = await Promise.all([
    clashesFor(uid, from, to, clip(d.excludeSwapId, 128)),
    otherId ? clashesFor(otherId, from, to, clip(d.excludeSwapId, 128)) : Promise.resolve([]),
  ]);
  // Google busy blocks: always my own (if I allowed free/busy), and the
  // other person's only if they chose to share them.
  const [myGoogle, theirGoogle] = await Promise.all([
    calendar.googleBusy(uid, from, to, false),
    otherId ? calendar.googleBusy(otherId, from, to, true) : Promise.resolve([]),
  ]);
  return {
    mine: [
      ...mine.map((c) => ({ start: c.start, end: c.end, kind: c.kind, label: `With ${c.withName.split(' ')[0]}` })),
      ...myGoogle.map((b) => ({ start: b.start, end: b.end, kind: 'external', label: 'Google Calendar' })),
    ],
    theirs: [
      ...theirs.map((c) => ({ start: c.start, end: c.end, kind: c.kind })),
      ...theirGoogle.map((b) => ({ start: b.start, end: b.end, kind: 'external' })),
    ],
  };
});

exports._test = { spanOf, clashesFor, timeLabel };
exports.LATE_CANCEL_HOURS = LATE_CANCEL_HOURS;
exports.RUNNING_CANCEL_MINUTES = RUNNING_CANCEL_MINUTES;
