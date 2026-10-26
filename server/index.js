import express from 'express';
import { RtcTokenBuilder, RtcRole } from 'agora-token';
import { createRemoteJWKSet, jwtVerify } from 'jose';

const {
  AGORA_APP_ID,
  AGORA_APP_CERTIFICATE,
  FIREBASE_PROJECT_ID = 'wanas-chat-ali',
  PORT = 3000,
} = process.env;

if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE) {
  console.error('Missing AGORA_APP_ID or AGORA_APP_CERTIFICATE');
  process.exit(1);
}

const jwks = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com')
);

// بنتأكد إن اللي بيطلب token مسجّل دخول فعلاً في ونس
async function verifyUser(req) {
  const h = req.headers.authorization || '';
  if (!h.startsWith('Bearer ')) throw new Error('missing token');
  const { payload } = await jwtVerify(h.slice(7), jwks, {
    issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
    audience: FIREBASE_PROJECT_ID,
  });
  return payload.sub;
}

const app = express();
app.use(express.json());

app.get('/', (_req, res) => res.send('wanas token server ok'));

app.post('/token', async (req, res) => {
  try {
    await verifyUser(req);
    const channel = String(req.body?.channel || '');
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(channel)) {
      return res.status(400).json({ error: 'bad channel' });
    }
    const expire = Math.floor(Date.now() / 1000) + 3600;
    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channel,
      0,
      RtcRole.PUBLISHER,
      expire,
      expire
    );
    res.json({ token });
  } catch (e) {
    console.error(e.message);
    res.status(401).json({ error: 'unauthorized' });
  }
});

app.listen(PORT, () => console.log(`listening on ${PORT}`));