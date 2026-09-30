/**
 * Swap Web: a user's real skill network, built only from completed,
 * verified sessions.
 *
 * Starting from the caller it walks outward up to three steps: the people
 * they taught / learned from, then who *those* people taught / learned
 * from, and so on. Every link carries the time actually spent (per-session
 * minutes, split evenly between the two directions of a two-way swap, and
 * given in full to a one-way session - the same rule the stats use), so the
 * app can size dots and lines by time together.
 *
 * On the map, two people are joined by ONE line: "mutual" when, across any
 * of their sessions, each has taught the other something, or "oneway" when
 * only one has taught (the line then runs teacher -> learner). The kind is
 * judged from everything between the pair, whatever the direction filter.
 *
 * Privacy: people two or more steps away are shown by first name only,
 * private profiles become "Private member" with no id, and the map is
 * capped so it stays fast and readable.
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const LEGACY_SESSION_MINUTES = 30;
const MAX_NODES = 60;
const MAX_DEPTH = 3;
const SWAPS_PER_PERSON = 300;

const db = () => admin.firestore();
const millis = (ts) => (ts && typeof ts.toMillis === 'function' ? ts.toMillis() : null);

/** Teaching links in one completed swap: [{teacher, learner, skill, minutes}]. */
function linksOf(swap) {
  const [a, b] = swap.participants || [];
  if (!a || !b) return [];
  const organiser = swap.createdBy === b ? b : a;
  const other = organiser === a ? b : a;
  const offered = (swap.skillOffered || '').toString().trim();
  const wanted = (swap.skillWanted || '').toString().trim();
  const minutes = typeof swap.durationMinutes === 'number' ? swap.durationMinutes : LEGACY_SESSION_MINUTES;
  const share = offered && wanted ? minutes / 2 : minutes;
  const out = [];
  if (offered) out.push({ teacher: organiser, learner: other, skill: offered, minutes: share });
  if (wanted) out.push({ teacher: other, learner: organiser, skill: wanted, minutes: share });
  return out;
}

function cleanFilters(raw) {
  const f = raw || {};
  return {
    skill: typeof f.skill === 'string' && f.skill.trim() ? f.skill.trim().toLowerCase() : null,
    direction: ['taught', 'learned', 'both'].includes(f.direction) ? f.direction : 'both',
    minMinutes: Math.max(0, Number(f.minMinutes) || 0),
    sinceMs: Number(f.sinceDays) > 0 ? Date.now() - Number(f.sinceDays) * 86400000 : 0,
    depth: Math.min(MAX_DEPTH, Math.max(1, Math.round(Number(f.depth) || 2))),
    links: ['mutual', 'oneway'].includes(f.links) ? f.links : 'all',
  };
}

async function completedSwapsOf(uid, sinceMs) {
  const snap = await db().collection('swaps')
    .where('participants', 'array-contains', uid)
    .where('status', '==', 'completed')
    .limit(SWAPS_PER_PERSON)
    .get();
  return snap.docs
    .map((d) => d.data())
    .filter((s) => !sinceMs || (millis(s.completedAt) || millis(s.scheduledFor) || 0) >= sinceMs);
}

/**
 * Aggregated links touching [uid]: key "teacher>learner>skill" ->
 * {teacher, learner, skill, minutes, sessions}.
 */
function aggregate(swaps, f) {
  const links = new Map();
  for (const swap of swaps) {
    for (const l of linksOf(swap)) {
      if (f.skill && l.skill.toLowerCase() !== f.skill) continue;
      const key = `${l.teacher}>${l.learner}>${l.skill.toLowerCase()}`;
      const cur = links.get(key) || { teacher: l.teacher, learner: l.learner, skill: l.skill, minutes: 0, sessions: 0 };
      cur.minutes += l.minutes;
      cur.sessions += 1;
      links.set(key, cur);
    }
  }
  return [...links.values()];
}

/**
 * Walks the web outward from [center]. Direction is relative to the chain:
 * "taught" follows skills going outward (me -> them -> onward), "learned"
 * follows them coming in (who taught me, who taught them), "both" follows
 * either way.
 */
async function buildWeb(center, f) {
  const nodes = new Map([[center, { id: center, depth: 0, parent: null, minutes: 0 }]]);
  const edges = [];
  // Every teaching link seen, before the direction / time filters - used to
  // tell mutual pairs from one-way ones.
  const allLinks = new Map();
  let frontier = [center];
  for (let depth = 1; depth <= f.depth && frontier.length && nodes.size < MAX_NODES; depth++) {
    const next = [];
    // Candidates for this ring, best (most time) first so the cap keeps them.
    const candidates = [];
    for (const uid of frontier) {
      const links = aggregate(await completedSwapsOf(uid, f.sinceMs), f);
      for (const l of links) allLinks.set(`${l.teacher}>${l.learner}>${l.skill.toLowerCase()}`, l);
      for (const l of links) {
        const outward = l.teacher === uid;
        const other = outward ? l.learner : l.teacher;
        if (f.direction === 'taught' && !outward) continue;
        if (f.direction === 'learned' && outward) continue;
        if (l.minutes < f.minMinutes) continue;
        if (nodes.has(other)) {
          // Already on the map - still draw the link if both ends are shown,
          // judging its direction from whichever end is nearer the centre
          // (so "taught" doesn't pick up the link back from a learner).
          const tDepth = nodes.get(l.teacher) ? nodes.get(l.teacher).depth : depth;
          const lDepth = nodes.get(l.learner) ? nodes.get(l.learner).depth : depth;
          if (f.direction === 'taught' && tDepth > lDepth) continue;
          if (f.direction === 'learned' && lDepth > tDepth) continue;
          if (!edges.some((e) => e.from === l.teacher && e.to === l.learner && e.skill === l.skill)) {
            edges.push({ from: l.teacher, to: l.learner, skill: l.skill, minutes: l.minutes, sessions: l.sessions });
          }
          continue;
        }
        candidates.push({ parent: uid, other, link: l });
      }
    }
    candidates.sort((x, y) => y.link.minutes - x.link.minutes);
    for (const c of candidates) {
      const l = c.link;
      if (!nodes.has(c.other)) {
        if (nodes.size >= MAX_NODES) break;
        nodes.set(c.other, { id: c.other, depth, parent: c.parent, minutes: 0 });
        next.push(c.other);
      }
      const node = nodes.get(c.other);
      if (node.parent === c.parent) node.minutes += l.minutes;
      if (!edges.some((e) => e.from === l.teacher && e.to === l.learner && e.skill === l.skill)) {
        edges.push({ from: l.teacher, to: l.learner, skill: l.skill, minutes: l.minutes, sessions: l.sessions });
      }
    }
    frontier = next;
  }
  // Only keep links whose two ends are both on the map.
  return {
    nodes,
    edges: edges.filter((e) => nodes.has(e.from) && nodes.has(e.to)),
    allLinks: [...allLinks.values()],
  };
}

const pairKey = (a, b) => (a < b ? `${a}|${b}` : `${b}|${a}`);

/**
 * One line per pair of people on the map. A pair is shown when the
 * direction-filtered walk linked them; its kind comes from all their links.
 * The [links] filter then keeps only mutual or one-way lines, and anyone no
 * longer connected to the centre drops off the map.
 */
function pairUp(center, nodes, edges, allLinks, f) {
  const shown = new Set(edges.map((e) => pairKey(e.from, e.to)));
  const pairs = new Map();
  for (const l of allLinks) {
    if (!nodes.has(l.teacher) || !nodes.has(l.learner)) continue;
    const key = pairKey(l.teacher, l.learner);
    if (!shown.has(key)) continue;
    const p = pairs.get(key) || { a: l.teacher, b: l.learner, ab: [], ba: [] };
    (l.teacher === p.a ? p.ab : p.ba).push({ skill: l.skill, minutes: l.minutes, sessions: l.sessions });
    pairs.set(key, p);
  }
  const depthOf = (id) => nodes.get(id).depth;
  let out = [...pairs.values()].map((p) => {
    const mutual = p.ab.length > 0 && p.ba.length > 0;
    // One-way: from = teacher. Mutual: from = whoever is nearer the centre.
    const flip = mutual ? depthOf(p.b) < depthOf(p.a) : p.ab.length === 0;
    const [from, to, forward, back] = flip ? [p.b, p.a, p.ba, p.ab] : [p.a, p.b, p.ab, p.ba];
    const all = forward.concat(back);
    return {
      from,
      to,
      kind: mutual ? 'mutual' : 'oneway',
      forward,
      back,
      minutes: all.reduce((s, x) => s + x.minutes, 0),
      sessions: all.reduce((s, x) => s + x.sessions, 0),
    };
  });
  if (f.links !== 'all') out = out.filter((p) => p.kind === f.links);
  // Keep only what's still reachable from the centre.
  const reach = new Set([center]);
  let grew = true;
  while (grew) {
    grew = false;
    for (const p of out) {
      if (reach.has(p.from) !== reach.has(p.to)) {
        reach.add(p.from);
        reach.add(p.to);
        grew = true;
      }
    }
  }
  for (const id of [...nodes.keys()]) if (!reach.has(id)) nodes.delete(id);
  return out.filter((p) => reach.has(p.from) && reach.has(p.to));
}

exports.mySwapWeb = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const f = cleanFilters(request.data && request.data.filters);
  const { nodes, edges, allLinks } = await buildWeb(uid, f);
  const pairs = pairUp(uid, nodes, edges, allLinks, f);

  // Public details, with the privacy rules applied.
  const ids = [...nodes.keys()];
  const docs = await Promise.all(ids.map((id) => db().collection('users').doc(id).get()));
  const keyOf = new Map();
  let privateCount = 0;
  const outNodes = ids.map((id, i) => {
    const n = nodes.get(id);
    const u = docs[i].data() || {};
    const isPrivate = id !== uid && (u.privacy || {}).profileVisibility === 'private';
    const key = isPrivate ? `private-${++privateCount}` : id;
    keyOf.set(id, key);
    const full = (u.name || '').toString().trim();
    return {
      key,
      id: isPrivate ? null : id,
      name: isPrivate ? 'Private member' : n.depth >= 2 ? full.split(' ')[0] || 'Member' : full || 'Member',
      photoUrl: isPrivate || n.depth >= 2 ? '' : u.photoUrl || '',
      verified: !isPrivate && u.verified === true,
      depth: n.depth,
      // Map order is breadth-first, so a parent's key is always set first.
      parent: n.parent ? keyOf.get(n.parent) || null : null,
      minutes: Math.round(n.minutes),
    };
  });
  const round = (list) => list.map((x) => ({ skill: x.skill, minutes: Math.round(x.minutes), sessions: x.sessions }));
  const outEdges = pairs.map((p) => ({
    from: keyOf.get(p.from),
    to: keyOf.get(p.to),
    kind: p.kind,
    forward: round(p.forward),
    back: round(p.back),
    minutes: Math.round(p.minutes),
    sessions: p.sessions,
  }));
  const sum = (list) => list.reduce((a, x) => a + x.minutes, 0);
  let taught = 0;
  let learned = 0;
  for (const e of outEdges) {
    if (e.from === uid) {
      taught += sum(e.forward);
      learned += sum(e.back);
    } else if (e.to === uid) {
      taught += sum(e.back);
      learned += sum(e.forward);
    }
  }
  // The totals follow the direction filter even when a line shows both ways.
  if (f.direction === 'taught') learned = 0;
  if (f.direction === 'learned') taught = 0;
  return {
    nodes: outNodes,
    edges: outEdges,
    summary: {
      people: outNodes.length - 1,
      taughtMinutes: taught,
      learnedMinutes: learned,
      capped: nodes.size >= MAX_NODES,
    },
  };
});

exports._test = { linksOf, cleanFilters, pairUp };
