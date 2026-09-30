/**
 * Swap session timer, time tracking and the badges built on it.
 *
 * A session only counts once both participants have checked in and at least
 * MIN_SESSION_MINUTES have passed, and it becomes `completed` only when BOTH
 * confirm it - there is no automatic confirmation. The one still to confirm
 * is reminded (see remindUnconfirmed); a genuine dispute goes through the
 * report flow to an admin. All of that happens here with admin privileges - the security
 * rules stop clients from writing `status: 'completed'` or any timing field
 * themselves, which is what makes the time on a Skill Passport "verified".
 *
 * Per-user stats (teaching / learning minutes, streaks, reliability, reviews)
 * and the badges derived from them are recomputed from the user's full
 * history rather than incremented, so they are always consistent and users
 * who swapped before this existed are backfilled the first time anything
 * recomputes them.
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const streaks = require('./streaks');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const MIN_SESSION_MINUTES = 30;
const MAX_COUNTED_MINUTES = 120;
const CHECKIN_EARLY_MINUTES = 15;
const CONFIRM_REMINDERS = [[1, 'confirmReminder1h'], [24, 'confirmReminder24h']];
// Sessions completed before the timer existed have no recorded length. They
// were real, agreed sessions, so they count as the minimum a session can now
// be - never more.
const LEGACY_SESSION_MINUTES = MIN_SESSION_MINUTES;

// Badge families: [statKey, [[badgeId, threshold], ...]]. Thresholds for the
// hour families are in minutes. Mirrors kBadgeCatalog in the app.
const BADGE_FAMILIES = [
  ['teachMinutes', [['teach_10h', 600], ['teach_50h', 3000], ['teach_100h', 6000]]],
  ['learnMinutes', [['learn_5h', 300], ['learn_25h', 1500], ['learn_50h', 3000]]],
  ['bestWeekStreak', [['streak_4w', 4], ['streak_12w', 12], ['streak_26w', 26]]],
  ['bestReliabilityStreak', [['reliable_10', 10], ['reliable_25', 25], ['reliable_50', 50]]],
  ['fiveStarReviews', [['five_star_5', 5], ['five_star_15', 15], ['five_star_30', 30]]],
  ['skillsTaught3h', [['breadth_2', 2], ['breadth_3', 3], ['breadth_5', 5]]],
];

const db = () => admin.firestore();
const now = () => Timestamp.now();
const millis = (ts) => (ts && typeof ts.toMillis === 'function' ? ts.toMillis() : null);

function requireUid(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function requireSwapId(request) {
  const swapId = request.data && request.data.swapId;
  if (typeof swapId !== 'string' || !swapId) {
    throw new HttpsError('invalid-argument', 'A swapId is required.');
  }
  return swapId;
}

function partnerOf(swap, uid) {
  return (swap.participants || []).find((p) => p && p !== uid) || null;
}

function nameOf(swap, uid) {
  return ((swap.participantNames || {})[uid] || 'Your swap partner').toString();
}

async function notify(userId, type, message, sender, senderName, swapId) {
  if (!userId) return;
  await db().collection('notifications').add({
    userId,
    type,
    message,
    timestamp: FieldValue.serverTimestamp(),
    read: false,
    senderId: sender || '',
    senderName: senderName || 'Swapnio',
    senderPhoto: '',
    ...(swapId ? { swapId } : {}),
  });
}

/** Fields that flip a session to completed once everyone has confirmed. */
function completionFields(confirmations, at) {
  return {
    status: 'completed',
    completedAt: at,
    goalAchieved: Object.values(confirmations).every((c) => c && c.goalAchieved !== false),
  };
}

/**
 * Checks the caller in to an accepted session. When the last participant
 * checks in, the session's clock starts (`startedAt`).
 */
exports.checkInSession = onCall(async (request) => {
  const uid = requireUid(request);
  const swapId = requireSwapId(request);
  const ref = db().collection('swaps').doc(swapId);

  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Session not found.');
    const swap = snap.data();
    const participants = (swap.participants || []).filter(Boolean);
    if (!participants.includes(uid)) {
      throw new HttpsError('permission-denied', 'This is not your session.');
    }
    if (swap.status !== 'accepted') {
      throw new HttpsError('failed-precondition', 'Only an accepted session can be started.');
    }
    const scheduled = millis(swap.scheduledFor);
    if (scheduled && Date.now() < scheduled - CHECKIN_EARLY_MINUTES * 60000) {
      throw new HttpsError(
        'failed-precondition',
        `Check-in opens ${CHECKIN_EARLY_MINUTES} minutes before the session starts.`,
      );
    }

    const checkIns = { ...(swap.checkIns || {}) };
    if (checkIns[uid]) {
      return { swap, started: Boolean(swap.startedAt), changed: false };
    }
    const at = now();
    checkIns[uid] = at;
    const update = {
      [`checkIns.${uid}`]: at,
      updatedAt: FieldValue.serverTimestamp(),
    };
    const started = participants.every((p) => checkIns[p]);
    if (started && !swap.startedAt) update.startedAt = at;
    tx.update(ref, update);
    return { swap, started, changed: true };
  });

  if (result.changed) {
    const partner = partnerOf(result.swap, uid);
    const me = nameOf(result.swap, uid);
    await notify(
      partner,
      'session_checkin',
      result.started
        ? `${me} checked in - your session has started`
        : `${me} checked in and is waiting for you to join`,
      uid,
      me,
      swapId,
    );
  }
  await streaks.recordActivity(uid);
  return { started: result.started };
});

/**
 * Records the caller's confirmation that the session happened. The first
 * confirmation fixes the end time and the minutes counted; the session is
 * completed once every participant has confirmed.
 */
exports.completeSwapSession = onCall(async (request) => {
  const uid = requireUid(request);
  const swapId = requireSwapId(request);
  const goalAchieved = request.data && request.data.goalAchieved !== false;
  const notes = typeof (request.data && request.data.notes) === 'string'
    ? request.data.notes.trim().slice(0, 1000)
    : '';
  const ref = db().collection('swaps').doc(swapId);

  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Session not found.');
    const swap = snap.data();
    const participants = (swap.participants || []).filter(Boolean);
    if (!participants.includes(uid)) {
      throw new HttpsError('permission-denied', 'This is not your session.');
    }
    if (swap.status === 'completed') return { swap, completed: true, changed: false };
    if (swap.status !== 'accepted') {
      throw new HttpsError('failed-precondition', 'Only an accepted session can be completed.');
    }
    const startedAt = millis(swap.startedAt);
    if (!startedAt) {
      throw new HttpsError(
        'failed-precondition',
        'Both of you need to check in before the session can be completed.',
      );
    }

    const confirmations = { ...(swap.completionConfirmations || {}) };
    if (confirmations[uid]) return { swap, completed: false, changed: false };

    const at = now();
    const elapsed = (at.toMillis() - startedAt) / 60000;
    if (!swap.endedAt && elapsed < MIN_SESSION_MINUTES) {
      const left = Math.ceil(MIN_SESSION_MINUTES - elapsed);
      throw new HttpsError(
        'failed-precondition',
        `Sessions count after ${MIN_SESSION_MINUTES} minutes - ${left} min to go.`,
      );
    }

    confirmations[uid] = { at, goalAchieved };
    const update = {
      [`completionConfirmations.${uid}`]: { at, goalAchieved },
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (notes) {
      update[`sessionNotesBy.${uid}`] = notes;
      if (!swap.sessionNotes) update.sessionNotes = notes;
    }
    if (!swap.endedAt) {
      update.endedAt = at;
      update.durationMinutes = Math.min(MAX_COUNTED_MINUTES, Math.floor(elapsed));
    }
    const completed = participants.every((p) => confirmations[p]);
    if (completed) Object.assign(update, completionFields(confirmations, at));
    tx.update(ref, update);
    return { swap, completed, changed: true };
  });

  if (result.changed && !result.completed) {
    const me = nameOf(result.swap, uid);
    await notify(
      partnerOf(result.swap, uid),
      'session_confirm',
      `${me} marked your session as done - confirm it so it counts for both of you`,
      uid,
      me,
      swapId,
    );
  }
  await streaks.recordActivity(uid);
  return { completed: result.completed };
});

/**
 * Reminds whoever hasn't confirmed a session their partner already marked
 * done - an hour after, then a day after. Nothing is confirmed for them.
 */
exports.remindUnconfirmed = async () => {
  for (const [hours, flag] of CONFIRM_REMINDERS) {
    const cutoff = Timestamp.fromMillis(Date.now() - hours * 3600 * 1000);
    const snap = await db().collection('swaps')
      .where('status', '==', 'accepted')
      .where('endedAt', '<=', cutoff)
      .limit(200)
      .get();
    for (const doc of snap.docs) {
      const swap = doc.data();
      if (swap[flag]) continue;
      const confirmations = swap.completionConfirmations || {};
      const done = Object.keys(confirmations);
      if (done.length === 0) continue;
      const waiting = (swap.participants || []).filter((p) => p && !confirmations[p]);
      await doc.ref.update({ [flag]: true });
      for (const uid of waiting) {
        const partner = done[0];
        await notify(
          uid,
          'session_confirm',
          `${nameOf(swap, partner)} marked your session as done - confirm it so it counts for both of you`,
          partner,
          nameOf(swap, partner),
          doc.id,
        );
      }
    }
  }
};

// ------------------------------------------------------------------ stats

/** Monday-based week number since the epoch, for streaks. */
function weekIndex(ms) {
  const days = Math.floor(ms / 86400000);
  // 1970-01-01 was a Thursday; shift so weeks start on Monday.
  return Math.floor((days + 3) / 7);
}

/**
 * Minutes each side taught and learned in one completed session. A swap is
 * an exchange, so when both skills are set the time is split evenly; a
 * one-way session gives the whole time to its single direction.
 */
function sessionSplit(swap, uid) {
  const minutes = typeof swap.durationMinutes === 'number'
    ? swap.durationMinutes
    : LEGACY_SESSION_MINUTES;
  const offered = (swap.skillOffered || '').toString().trim();
  const wanted = (swap.skillWanted || '').toString().trim();
  const organiser = swap.createdBy === uid;
  const teach = organiser ? offered : wanted;
  const learn = organiser ? wanted : offered;
  const share = teach && learn ? minutes / 2 : minutes;
  return {
    teachSkill: teach,
    teachMinutes: teach ? share : 0,
    learnMinutes: learn ? share : 0,
  };
}

async function computeStats(uid) {
  const [swapSnap, ratingSnap] = await Promise.all([
    db().collection('swaps').where('participants', 'array-contains', uid).limit(1000).get(),
    db().collection('ratings').where('toUserId', '==', uid).limit(1000).get(),
  ]);

  let teachMinutes = 0;
  let learnMinutes = 0;
  const taughtBySkill = {};
  const weeks = new Set();
  // Attendance events in time order, for the no-no-show run.
  const events = [];

  for (const doc of swapSnap.docs) {
    const swap = doc.data();
    const when = millis(swap.completedAt) || millis(swap.scheduledFor) || millis(swap.createdAt) || 0;
    if (swap.status === 'completed') {
      const split = sessionSplit(swap, uid);
      teachMinutes += split.teachMinutes;
      learnMinutes += split.learnMinutes;
      if (split.teachSkill) {
        taughtBySkill[split.teachSkill] = (taughtBySkill[split.teachSkill] || 0) + split.teachMinutes;
      }
      if (when) weeks.add(weekIndex(when));
      events.push({ when, attended: true });
    } else if (swap.status === 'no_show') {
      // The reporter turned up; everyone else is the one who didn't.
      events.push({ when, attended: swap.noShowReportedBy === uid });
    }
  }

  events.sort((a, b) => a.when - b.when);
  let run = 0;
  let bestReliabilityStreak = 0;
  for (const e of events) {
    run = e.attended ? run + 1 : 0;
    bestReliabilityStreak = Math.max(bestReliabilityStreak, run);
  }

  const sortedWeeks = [...weeks].sort((a, b) => a - b);
  let weekRun = 0;
  let bestWeekStreak = 0;
  for (let i = 0; i < sortedWeeks.length; i++) {
    weekRun = i > 0 && sortedWeeks[i] === sortedWeeks[i - 1] + 1 ? weekRun + 1 : 1;
    bestWeekStreak = Math.max(bestWeekStreak, weekRun);
  }
  // The current streak only survives if the latest active week is this
  // week or last week.
  const thisWeek = weekIndex(Date.now());
  const last = sortedWeeks[sortedWeeks.length - 1];
  const currentWeekStreak = last !== undefined && thisWeek - last <= 1 ? weekRun : 0;

  let fiveStarReviews = 0;
  for (const doc of ratingSnap.docs) {
    const r = doc.data();
    if (Number(r.rating) >= 5 && typeof r.review === 'string' && r.review.trim()) {
      fiveStarReviews++;
    }
  }

  return {
    teachMinutes: Math.round(teachMinutes),
    learnMinutes: Math.round(learnMinutes),
    taughtMinutesBySkill: Object.fromEntries(
      Object.entries(taughtBySkill).map(([k, v]) => [k, Math.round(v)]),
    ),
    skillsTaught3h: Object.values(taughtBySkill).filter((m) => m >= 180).length,
    bestWeekStreak,
    currentWeekStreak,
    bestReliabilityStreak,
    currentReliabilityStreak: run,
    fiveStarReviews,
  };
}

/**
 * Recomputes one user's stats and grants any badge they now qualify for.
 * Badges are never taken away once earned.
 */
async function refreshStatsAndBadges(uid) {
  if (!uid) return null;
  const stats = await computeStats(uid);
  const earned = [];
  for (const [key, tiers] of BADGE_FAMILIES) {
    for (const [badgeId, threshold] of tiers) {
      if ((stats[key] || 0) >= threshold) earned.push(badgeId);
    }
  }
  const ref = db().collection('gamification').doc(uid);
  await db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const badges = doc.exists ? doc.data().badges || [] : [];
    const merged = [...badges];
    for (const b of earned) if (!merged.includes(b)) merged.push(b);
    tx.set(
      ref,
      { stats: { ...stats, updatedAt: FieldValue.serverTimestamp() }, badges: merged },
      { merge: true },
    );
  });
  return stats;
}

exports.refreshStatsAndBadges = refreshStatsAndBadges;

/** Lets a user backfill their own stats (e.g. when opening their passport). */
exports.refreshMyStats = onCall(async (request) => {
  const uid = requireUid(request);
  const stats = await refreshStatsAndBadges(uid);
  return { stats };
});

/** Written reviews feed the five-star badge family. */
exports.statsOnRating = onDocumentCreated('ratings/{ratingId}', async (event) => {
  const rating = event.data && event.data.data();
  if (!rating) return;
  await refreshStatsAndBadges(rating.toUserId);
  // Leaving a review keeps the reviewer's daily streak.
  await streaks.recordActivity(rating.fromUserId);
});

exports.MIN_SESSION_MINUTES = MIN_SESSION_MINUTES;
