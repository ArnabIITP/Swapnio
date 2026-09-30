/**
 * Swap requests: the server side of "someone wants to swap with you" and
 * accepting it.
 *
 * Accepting used to happen on the phone - it created the chat room, a
 * "matched" system message and the sender's notification directly. That
 * meant the security rules had to let any user create a chat room with
 * anyone, post messages as 'system' and write notifications for anyone,
 * which is how strangers could message people without a match and send
 * fake "Swapnio Support" alerts. Now only this code does those writes; the
 * rules allow none of them from the app.
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const streaks = require('./streaks');

const db = () => admin.firestore();

/** Same id the app uses: both uids, sorted, joined with '_'. */
function roomIdFor(a, b) {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

async function isBlockedEitherWay(a, b) {
  const [ab, ba] = await Promise.all([
    db().collection('blocks').where('userId', '==', a).where('blockedUserId', '==', b).limit(1).get(),
    db().collection('blocks').where('userId', '==', b).where('blockedUserId', '==', a).limit(1).get(),
  ]);
  return !ab.empty || !ba.empty;
}

async function profileOf(uid) {
  const snap = await db().collection('users').doc(uid).get();
  const data = snap.exists ? snap.data() : {};
  return {
    name: (data.name || 'Swapnio member').toString(),
    photo: (data.photoUrl || '').toString(),
  };
}

/**
 * A new swap request: fix the sender's name and photo from their real
 * profile (the app supplies them, so they could otherwise be anything),
 * notify the recipient, and count it for the sender's daily streak.
 * Requests to yourself or across a block are dropped.
 */
async function onRequestCreated(event) {
  const snap = event.data;
  if (!snap) return;
  const req = snap.data() || {};
  const from = req.fromUserId;
  const to = req.toUserId;
  if (!from || !to || from === to || (await isBlockedEitherWay(from, to))) {
    await snap.ref.delete();
    return;
  }
  const sender = await profileOf(from);
  await snap.ref.update({ fromName: sender.name, fromPhoto: sender.photo });
  await db().collection('notifications').add({
    userId: to,
    type: 'swap_request',
    message: `${sender.name} wants to swap skills with you`,
    timestamp: FieldValue.serverTimestamp(),
    read: false,
    senderId: from,
    senderName: sender.name,
    senderPhoto: sender.photo,
  });
  await streaks.recordActivity(from);
}

exports.onRequestCreated = onRequestCreated;

/**
 * Accepts a swap request addressed to the caller: opens (or reopens) the
 * chat room, posts the "matched" message, notifies the sender and clears
 * the request plus any reverse one. Returns the chat room id.
 */
exports.acceptSwapRequest = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const requestId = request.data && request.data.requestId;
  if (typeof requestId !== 'string' || !requestId) {
    throw new HttpsError('invalid-argument', 'A requestId is required.');
  }
  const reqRef = db().collection('swipeRequests').doc(requestId);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) throw new HttpsError('not-found', 'This request is no longer available.');
  const req = reqSnap.data();
  if (req.toUserId !== uid) throw new HttpsError('permission-denied', 'This request is not for you.');
  const other = req.fromUserId;
  if (!other || other === uid) throw new HttpsError('failed-precondition', 'This request is not valid.');
  if (await isBlockedEitherWay(uid, other)) {
    await reqRef.delete();
    throw new HttpsError('permission-denied', "You can't match with this member.");
  }

  const [me, them] = await Promise.all([profileOf(uid), profileOf(other)]);
  const roomId = roomIdFor(uid, other);
  const roomRef = db().collection('chatRooms').doc(roomId);
  const reverse = await db().collection('swipeRequests')
    .where('fromUserId', '==', uid)
    .where('toUserId', '==', other)
    .get();

  const batch = db().batch();
  batch.set(roomRef, {
    users: [uid, other],
    userNames: { [uid]: me.name, [other]: them.name },
    userPhotos: { [uid]: me.photo, [other]: them.photo },
    lastMessage: 'Swap request accepted! You can start chatting now.',
    lastMessageTime: FieldValue.serverTimestamp(),
    lastMessageSenderId: uid,
    unreadCount: { [uid]: 0, [other]: 1 },
    unmatched: false,
  }, { merge: true });
  batch.set(roomRef.collection('messages').doc(), {
    senderId: 'system',
    type: 'system',
    text: `Skill swap matched! ${me.name} accepted the swap request.`,
    timestamp: FieldValue.serverTimestamp(),
  });
  batch.set(db().collection('notifications').doc(), {
    userId: other,
    type: 'request_accepted',
    message: `${me.name} accepted your skill swap request!`,
    timestamp: FieldValue.serverTimestamp(),
    read: false,
    senderId: uid,
    senderName: me.name,
    senderPhoto: me.photo,
  });
  batch.delete(reqRef);
  for (const doc of reverse.docs) batch.delete(doc.ref);
  await batch.commit();

  await streaks.recordActivity(uid);
  return { chatRoomId: roomId };
});

exports.roomIdFor = roomIdFor;
