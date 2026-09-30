/**
 * Curated skill list.
 *
 * Skills on profiles must come from the catalog (the admin-managed `skills`
 * collection, seeded from skill_catalog.json). That's what makes matching
 * work - "ML", "machine learning" and "Machine Learning" are one skill - and
 * it's what the per-skill hours and levels are keyed on.
 *
 *  - syncSkillCatalog: seeds / upgrades the catalog from the bundled JSON and
 *    maps existing profiles' skills onto it. Idempotent; the app calls it
 *    when it finds the catalog missing or older than it expects.
 *  - canonicalizeUserSkills: on every profile write, rewrites skill names to
 *    their catalog spelling and moves anything unknown into a skill request.
 *  - requestSkill / resolveSkillRequest: users ask for a missing skill; an
 *    admin approves it (added to the catalog and to the requesters' profiles)
 *    or rejects it.
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const bundled = require('./skill_catalog.json');

const db = () => admin.firestore();

function slug(name) {
  return name.toLowerCase().replace(/\+/g, 'plus').replace(/#/g, 'sharp')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'skill';
}

let cache = null;
let cacheAt = 0;

/** lowercase name/alias -> canonical name, from the live `skills` collection. */
async function catalogIndex(force = false) {
  if (!force && cache && Date.now() - cacheAt < 5 * 60 * 1000) return cache;
  const snap = await db().collection('skills').get();
  const index = new Map();
  for (const doc of snap.docs) {
    const d = doc.data();
    const name = (d.name || '').toString().trim();
    if (!name) continue;
    index.set(name.toLowerCase(), name);
    for (const alias of d.aliases || []) {
      const a = alias.toString().trim().toLowerCase();
      if (a && !index.has(a)) index.set(a, name);
    }
  }
  cache = index;
  cacheAt = Date.now();
  return index;
}

/** Splits a skill list into catalog names (deduped) and unknown entries. */
function resolveList(list, index) {
  const known = [];
  const unknown = [];
  for (const raw of Array.isArray(list) ? list : []) {
    const value = (raw || '').toString().trim();
    if (!value) continue;
    const hit = index.get(value.toLowerCase());
    if (hit) {
      if (!known.includes(hit)) known.push(hit);
    } else if (!unknown.some((u) => u.toLowerCase() === value.toLowerCase())) {
      unknown.push(value);
    }
  }
  return { known, unknown };
}

const sameList = (a, b) => Array.isArray(a) && a.length === b.length && a.every((v, i) => v === b[i]);

async function fileRequest(name, uid, side) {
  const ref = db().collection('skillRequests').doc(slug(name));
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : null;
    const requesters = data ? data.requesters || {} : {};
    if (requesters[uid] === side && data && data.status === 'pending') return;
    tx.set(ref, {
      name: data ? data.name : name,
      status: 'pending',
      requesters: { [uid]: side },
      count: Object.keys({ ...requesters, [uid]: side }).length,
      updatedAt: FieldValue.serverTimestamp(),
      ...(data ? {} : { createdAt: FieldValue.serverTimestamp() }),
    }, { merge: true });
  });
}

exports.syncSkillCatalog = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const metaRef = db().collection('meta').doc('skillCatalog');
  const meta = await metaRef.get();
  if (meta.exists && (meta.data().version || 0) >= bundled.version) {
    return { version: meta.data().version, updated: false };
  }

  let order = 0;
  let batch = db().batch();
  let ops = 0;
  for (const category of bundled.categories) {
    for (const [name, aliases] of category.skills) {
      batch.set(db().collection('skills').doc(slug(name)), {
        name,
        category: category.name,
        aliases,
        order: order++,
        source: 'catalog',
      }, { merge: true });
      if (++ops >= 400) {
        await batch.commit();
        batch = db().batch();
        ops = 0;
      }
    }
  }
  await batch.commit();

  // Map existing profiles onto the catalog. Unknown legacy skills are left
  // in place here (never silently deleted) - they're resolved the next time
  // that user edits their skills.
  const index = await catalogIndex(true);
  const users = await db().collection('users').get();
  let migrated = 0;
  for (const doc of users.docs) {
    const d = doc.data();
    const update = {};
    for (const field of ['skillsOffered', 'skillsWanted']) {
      if (!Array.isArray(d[field])) continue;
      const { known, unknown } = resolveList(d[field], index);
      const next = [...known, ...unknown];
      if (!sameList(d[field], next)) update[field] = next;
    }
    if (Object.keys(update).length) {
      await doc.ref.update(update);
      migrated++;
    }
  }

  await metaRef.set({ version: bundled.version, syncedAt: FieldValue.serverTimestamp() });
  return { version: bundled.version, updated: true, migrated };
});

exports.canonicalizeUserSkills = onDocumentWritten('users/{uid}', async (event) => {
  const after = event.data && event.data.after && event.data.after.data();
  if (!after) return;
  const before = (event.data.before && event.data.before.data()) || {};
  const changed = ['skillsOffered', 'skillsWanted'].filter(
    (f) => JSON.stringify(before[f] || []) !== JSON.stringify(after[f] || []),
  );
  if (!changed.length) return;

  let index = await catalogIndex();
  if (index.size === 0) return; // catalog not seeded yet - nothing to enforce against
  // A cached catalog can be a few minutes old; re-read it before treating
  // anything as unknown, so a skill an admin just approved isn't stripped.
  const anyUnknown = changed.some((f) => resolveList(after[f], index).unknown.length);
  if (anyUnknown) index = await catalogIndex(true);
  const update = {};
  for (const field of changed) {
    const previous = new Set((before[field] || []).map((s) => (s || '').toString().toLowerCase()));
    const { known, unknown } = resolveList(after[field], index);
    // Only newly added unknown entries become requests; legacy ones the
    // user already had stay until a catalog match exists for them.
    const fresh = unknown.filter((u) => !previous.has(u.toLowerCase()));
    const kept = unknown.filter((u) => previous.has(u.toLowerCase()));
    const next = [...known, ...kept];
    if (!sameList(after[field], next)) update[field] = next;
    for (const name of fresh) {
      await fileRequest(name, event.params.uid, field === 'skillsOffered' ? 'offered' : 'wanted');
    }
  }
  if (Object.keys(update).length) await event.data.after.ref.update(update);
});

exports.requestSkill = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const name = ((request.data && request.data.name) || '').toString().trim().replace(/\s+/g, ' ');
  const side = request.data && request.data.side === 'wanted' ? 'wanted' : 'offered';
  if (name.length < 2 || name.length > 40) {
    throw new HttpsError('invalid-argument', 'Skill names are 2 to 40 characters.');
  }
  const index = await catalogIndex();
  const hit = index.get(name.toLowerCase());
  if (hit) return { canonical: hit, requested: false };
  await fileRequest(name, uid, side);
  return { canonical: null, requested: true };
});

exports.resolveSkillRequest = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const me = await db().collection('users').doc(uid).get();
  if (!me.exists || me.data().isAdmin !== true) {
    throw new HttpsError('permission-denied', 'Admins only.');
  }
  const { requestId, approve } = request.data || {};
  if (typeof requestId !== 'string' || !requestId) {
    throw new HttpsError('invalid-argument', 'A requestId is required.');
  }
  const ref = db().collection('skillRequests').doc(requestId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Request not found.');
  const req = snap.data();
  const name = ((request.data.name || req.name) || '').toString().trim();
  const category = ((request.data.category || 'Other') || '').toString().trim();

  if (approve) {
    const index = await catalogIndex(true);
    const canonical = index.get(name.toLowerCase()) || name;
    if (!index.has(name.toLowerCase())) {
      await db().collection('skills').doc(slug(name)).set({
        name,
        category,
        aliases: req.name && req.name.toLowerCase() !== name.toLowerCase() ? [req.name] : [],
        order: 10000,
        source: 'request',
      }, { merge: true });
      cache = null;
    }
    for (const [requester, side] of Object.entries(req.requesters || {})) {
      const field = side === 'wanted' ? 'skillsWanted' : 'skillsOffered';
      await db().collection('users').doc(requester).update({ [field]: FieldValue.arrayUnion(canonical) })
        .catch(() => {});
      await db().collection('notifications').add({
        userId: requester,
        type: 'skill_request',
        message: `"${canonical}" was added to the skill list and to your profile`,
        timestamp: FieldValue.serverTimestamp(),
        read: false,
        senderName: 'Swapnio',
        senderPhoto: '',
      });
    }
  }
  await ref.set({
    status: approve ? 'approved' : 'rejected',
    resolvedBy: uid,
    resolvedAt: FieldValue.serverTimestamp(),
    ...(approve ? { approvedName: name, category } : {}),
  }, { merge: true });
  return { ok: true };
});
