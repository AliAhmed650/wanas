import { createRemoteJWKSet, jwtVerify } from 'jose';
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

// بيبعت إشعار (رسالة جديدة / مكالمة واردة) للطرف التاني عن طريق FCM.
// التطبيق بينادي عليه بعد ما يكتب الرسالة أو المكالمة في Firestore.
// الأمان: بنتأكد من هوية المرسل (Firebase ID token)، وبنقرأ النص والأسماء من
// Firestore نفسه مش من اللي جاي في الطلب، عشان محدش يقدر يبعت إشعار مزيّف.

const PROJECT_ID = (process.env.FIREBASE_PROJECT_ID || 'wanas-chat-ali').trim();

const jwks = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com')
);

function getApp() {
  if (getApps().length) return getApps()[0];
  const raw = (process.env.FIREBASE_SERVICE_ACCOUNT || '').trim();
  if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is not set');
  return initializeApp({ credential: cert(JSON.parse(raw)) });
}

const UID_RE = /^[A-Za-z0-9]{1,128}$/;
const ID_RE = /^[A-Za-z0-9_-]{1,200}$/;

export default async function handler(req, res) {
  if (req.method === 'GET') {
    const ok = !!(process.env.FIREBASE_SERVICE_ACCOUNT || '').trim();
    return res.status(200).send(`wanas notify ok | serviceAccount=${ok ? 'set' : 'MISSING'}`);
  }
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method not allowed' });
  }

  let uid;
  try {
    const h = req.headers.authorization || '';
    if (!h.startsWith('Bearer ')) throw new Error('missing token');
    const { payload } = await jwtVerify(h.slice(7), jwks, {
      issuer: `https://securetoken.google.com/${PROJECT_ID}`,
      audience: PROJECT_ID,
    });
    uid = payload.sub;
  } catch (e) {
    console.error('auth', e.message);
    return res.status(401).json({ error: 'unauthorized' });
  }

  try {
    getApp();
    const db = getFirestore();
    const { type, toUid, chatId, callId } = req.body || {};

    if (!UID_RE.test(String(toUid || '')) || toUid === uid) {
      return res.status(400).json({ error: 'bad toUid' });
    }

    const [senderSnap, targetSnap] = await Promise.all([
      db.collection('users').doc(uid).get(),
      db.collection('users').doc(toUid).get(),
    ]);
    const senderName = (senderSnap.data()?.name || 'ونس').toString();
    const tokens = (targetSnap.data()?.fcmTokens || []).filter((t) => typeof t === 'string');
    if (!tokens.length) return res.status(200).json({ sent: 0, reason: 'no tokens' });

    let notification;
    let data;
    let channelId;
    let tag;
    let ttl;

    if (type === 'message') {
      if (!ID_RE.test(String(chatId || ''))) return res.status(400).json({ error: 'bad chatId' });
      const chat = (await db.collection('chats').doc(chatId).get()).data();
      const parts = chat?.participants || [];
      if (!parts.includes(uid) || !parts.includes(toUid) || chat?.lastSenderId !== uid) {
        return res.status(403).json({ error: 'not allowed' });
      }
      const body = String(chat.lastMessage || 'رسالة جديدة').slice(0, 140);
      notification = { title: senderName, body };
      data = { type: 'message', chatId, fromUid: uid };
      channelId = 'messages';
      tag = chatId;
      ttl = '86400s';
    } else if (type === 'call') {
      if (!ID_RE.test(String(callId || ''))) return res.status(400).json({ error: 'bad callId' });
      const call = (await db.collection('calls').doc(callId).get()).data();
      if (!call || call.callerId !== uid || call.calleeId !== toUid || call.status !== 'ringing') {
        return res.status(403).json({ error: 'not allowed' });
      }
      notification = {
        title: senderName,
        body: call.video ? 'مكالمة فيديو واردة 📹' : 'مكالمة صوتية واردة 📞',
      };
      data = { type: 'call', callId, fromUid: uid };
      channelId = 'calls';
      tag = `call_${callId}`;
      ttl = '45s'; // المكالمة بتنتهي بعد 60 ثانية، فمفيش داعي نوصّلها متأخر
    } else {
      return res.status(400).json({ error: 'bad type' });
    }

    const result = await getMessaging().sendEachForMulticast({
      tokens,
      notification,
      data,
      android: {
        priority: 'high',
        ttl: parseInt(ttl, 10) * 1000,
        notification: { channelId, tag },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default' } },
      },
    });

    // نمسح التوكنات الميتة (جهاز اتمسح منه التطبيق مثلًا)
    const dead = [];
    result.responses.forEach((r, i) => {
      const code = r.error?.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        dead.push(tokens[i]);
      } else if (r.error) {
        console.error('fcm', code, r.error.message);
      }
    });
    if (dead.length) {
      await db.collection('users').doc(toUid).update({ fcmTokens: FieldValue.arrayRemove(...dead) });
    }

    return res.status(200).json({ sent: result.successCount, failed: result.failureCount });
  } catch (e) {
    console.error('notify', e.message);
    return res.status(500).json({ error: 'server error' });
  }
}
