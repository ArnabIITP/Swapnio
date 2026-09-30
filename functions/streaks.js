/**
 * Daily streaks, Duolingo-style.
 *
 * A day counts when the user does something real on Swapnio - sends a chat
 * message or a swap request, proposes or accepts a session, checks in,
 * confirms one, or leaves a review. Opening the app is not enough. Every one
 * of those actions is already recorded by the server (a callable or a
 * Firestore trigger), which calls recordActivity here, so a streak can't be
 * written by the client: `gamification/{uid}` is admin-write only.
 *
 * Days follow the user's own clock (users/{uid}.tzOffsetMinutes, written by
 * the app on launch). A missed day is covered by a streak freeze if one is
 * left: everyone starts with one, earns another every 7 days of streak, and
 * holds at most two. Milestones grant a badge and bonus points, and a
 * reminder goes out in the evening of a day the streak hasn't been kept yet.
 *
 * State lives in gamification/{uid}.dailyStreak:
 *   { current, best, lastDay, freezes, days: [dayNo], frozen: [dayNo] }
 * where a dayNo is whole days since the epoch in the user's time zone, and
 * `days`/`frozen` keep the last few weeks for the app's calendar strip.
 */
const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const DAY_MS = 86400000;
const START_FREEZES = 1;
const MAX_FREEZES = 2;
const FREEZE_EVERY = 7;
const HISTORY_DAYS = 42;
const REMIND_HOUR = 20;
// Most of Swapnio's users are in India; used until the app reports a zone.
const DEFAULT_TZ_MINUTES = 330;

// [days, badgeId, bonus points]. Mirrors the day_streak family in the app's
// kBadgeCatalog.
const MILESTONES = [
  [3, 'day_streak_3', 5],
  [7, 'day_streak_7', 15],
  [30, 'day_streak_30', 50],
  [100, 'day_streak_100', 100],
  [365, 'day_streak_365', 250],
];

const db = () => admin.firestore();

function tzOffsetOf(user) {
  const raw = user && user.tzOffsetMinutes;
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return DEFAULT_TZ_MINUTES;
  return Math.max(-720, Math.min(840, Math.round(raw)));
}

/** Whole days since the epoch on the user's clock. */
function dayNumber(ms, tz) {
  return Math.floor((ms + tz * 60000) / DAY_MS);
}

/** When that local day starts, as epoch ms. */
function dayStartMs(day, tz) {
  return day * DAY_MS - tz * 60000;
}

/**
 * The streak after an activity on `today`. Pure, so it can be tested
 * without Firestore. Returns null when today already counted.
 */
function advance(prev, today) {
  const s = prev || {};
  if (typeof s.lastDay === 'number' && today <= s.lastDay) return null;

  const before = s.current || 0;
  let freezes = typeof s.freezes === 'number' ? s.freezes : START_FREEZES;
  let current = 1;
  let freezesUsed = 0;
  let lost = 0;
  const newlyFrozen = [];

  if (typeof s.lastDay === 'number' && before > 0) {
    const missed = today - s.lastDay - 1;
    if (missed === 0) {
      current = before + 1;
    } else if (missed <= freezes) {
      // Frozen days keep the streak alive but don't add to it.
      freezes -= missed;
      freezesUsed = missed;
      for (let d = s.lastDay + 1; d < today; d++) newlyFrozen.push(d);
      current = before + 1;
    } else {
      lost = before;
    }
  }

  let freezeEarned = false;
  if (current % FREEZE_EVERY === 0 && freezes < MAX_FREEZES) {
    freezes += 1;
    freezeEarned = true;
  }

  const keep = (d) => d > today - HISTORY_DAYS;
  return {
    streak: {
      current,
      best: Math.max(s.best || 0, current),
      lastDay: today,
      freezes,
      days: [...(s.days || []).filter(keep), today],
      frozen: [...(s.frozen || []), ...newlyFrozen].filter(keep),
    },
    freezesUsed,
    freezeEarned,
    lost,
  };
}

async function notify(userId, message) {
  await db().collection('notifications').add({
    userId,
    type: 'streak',
    message,
    timestamp: FieldValue.serverTimestamp(),
    read: false,
    senderId: 'system',
    senderName: 'Swapnio',
    senderPhoto: '',
  });
}

/**
 * Counts today for `uid`. Never throws - a streak must not be able to break
 * the action that earned it.
 */
async function recordActivity(uid) {
  if (!uid || uid === 'system') return null;
  try {
    const userSnap = await db().collection('users').doc(uid).get();
    if (!userSnap.exists) return null;
    const tz = tzOffsetOf(userSnap.data());
    const today = dayNumber(Date.now(), tz);
    const ref = db().collection('gamification').doc(uid);

    const outcome = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.exists ? snap.data() : {};
      const next = advance(data.dailyStreak, today);
      if (!next) return null;

      const badges = [...(data.badges || [])];
      const earned = [];
      let bonus = 0;
      for (const [days, badgeId, points] of MILESTONES) {
        if (next.streak.best >= days && !badges.includes(badgeId)) {
          badges.push(badgeId);
          earned.push({ days, badgeId, points });
          bonus += points;
        }
      }
      const points = (data.points || 0) + bonus;
      tx.set(
        ref,
        {
          dailyStreak: next.streak,
          stats: {
            bestDayStreak: next.streak.best,
            currentDayStreak: next.streak.current,
          },
          badges,
          points,
          level: 1 + Math.floor(points / 100),
          // The evening of the next day, in case they haven't kept it by
          // then; dropped once the reminder has gone out.
          streakRemindAt: Timestamp.fromMillis(
            dayStartMs(today + 1, tz) + REMIND_HOUR * 3600000,
          ),
          streakEndsAt: Timestamp.fromMillis(dayStartMs(today + 2, tz)),
        },
        { merge: true },
      );
      return { ...next, earned };
    });
    if (!outcome) return null;

    const { streak, freezesUsed, freezeEarned, lost, earned } = outcome;
    for (const e of earned) {
      await notify(uid, `🔥 ${e.days}-day streak! You earned a new badge (+${e.points} points)`);
    }
    if (freezesUsed > 0) {
      await notify(
        uid,
        `❄️ ${freezesUsed === 1 ? 'A streak freeze' : `${freezesUsed} streak freezes`} saved your streak - you're on day ${streak.current}`,
      );
    } else if (lost >= 3) {
      await notify(uid, `Your ${lost}-day streak ended. Day 1 of a new one starts today 🔥`);
    }
    if (freezeEarned) {
      await notify(uid, `❄️ ${streak.current} days in a row - you earned a streak freeze`);
    }
    return streak;
  } catch (e) {
    console.error('recordActivity', uid, e);
    return null;
  }
}

/**
 * Evening reminders for streaks not yet kept today (runs with the
 * 15-minute session reminders).
 */
async function remindStreaks() {
  const nowMs = Date.now();
  const snap = await db().collection('gamification')
    .where('streakRemindAt', '<=', Timestamp.fromMillis(nowMs))
    .limit(300)
    .get();
  for (const doc of snap.docs) {
    const data = doc.data();
    await doc.ref.update({ streakRemindAt: FieldValue.delete() });
    const s = data.dailyStreak || {};
    const ends = data.streakEndsAt && data.streakEndsAt.toMillis();
    if (!s.current || !ends || nowMs >= ends) continue;
    const freezes = s.freezes || 0;
    await notify(
      doc.id,
      `🔥 Your ${s.current}-day streak ends at midnight - send a message or book a session to keep it` +
        (freezes > 0 ? ` (a freeze will cover one miss)` : ''),
    );
  }
}

module.exports = {
  advance,
  dayNumber,
  recordActivity,
  remindStreaks,
  MILESTONES,
};
