import * as agoraPkg from 'agora-token';
import { createRemoteJWKSet, jwtVerify } from 'jose';

// يشتغل سواء المكتبة CommonJS أو ES Module
const agora = agoraPkg.default ?? agoraPkg;
const { RtcTokenBuilder, RtcRole } = agora;

const PROJECT_ID = (process.env.FIREBASE_PROJECT_ID || 'wanas-chat-ali').trim();

const jwks = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com')
);

export default async function handler(req, res) {
  const appId = (process.env.AGORA_APP_ID || '').trim();
  const cert = (process.env.AGORA_APP_CERTIFICATE || '').trim();

  // فحص آمن: بيعرض أول 4 حروف من الـ App ID وأطوال القيم بس، من غير ما يكشف الـ Certificate
  if (req.method === 'GET') {
    return res
      .status(200)
      .send(`wanas token server ok | appId=${appId.slice(0, 4)}.. len=${appId.length} | certLen=${cert.length}`);
  }
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method not allowed' });
  }

  if (!appId || !cert) {
    return res.status(500).json({ error: 'server not configured' });
  }

  try {
    // نتأكد إن اللي بيطلب token مسجّل دخول في ونس
    const h = req.headers.authorization || '';
    if (!h.startsWith('Bearer ')) throw new Error('missing token');
    await jwtVerify(h.slice(7), jwks, {
      issuer: `https://securetoken.google.com/${PROJECT_ID}`,
      audience: PROJECT_ID,
    });

    const channel = String(req.body?.channel || '');
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(channel)) {
      return res.status(400).json({ error: 'bad channel' });
    }

    const expire = Math.floor(Date.now() / 1000) + 3600;
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId, cert, channel, 0, RtcRole.PUBLISHER, expire, expire
    );
    return res.status(200).json({ token });
  } catch (e) {
    console.error(e.message);
    return res.status(401).json({ error: 'unauthorized' });
  }
}