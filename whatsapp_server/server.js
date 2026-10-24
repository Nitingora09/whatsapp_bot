import express from 'express';
import cors from 'cors';
import fs from 'fs';
import makeWASocket, {
  useMultiFileAuthState,
  makeCacheableSignalKeyStore,
  DisconnectReason,
  fetchLatestBaileysVersion,
  Browsers,
} from '@whiskeysockets/baileys';
import { Boom } from '@hapi/boom';
import pino from 'pino';
import qrcode from 'qrcode';
import qrcodeTerminal from 'qrcode-terminal';

const app = express();
const PORT = process.env.PORT || 3000;

// Prevent Node process crash from transient Baileys connection drops (428/Bad MAC)
process.on('uncaughtException', (err) => {
  console.error('[UNCAUGHT EXCEPTION CAUGHT]', err?.message || err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[UNHANDLED REJECTION CAUGHT]', reason?.message || reason);
});

app.use(cors());
app.use(express.json());

let sock = null;
let isConnected = false;
let currentQr = null;
let connectedUser = null;
let isConnecting = false;
let reconnectTimer = null;
// Read saved phone number from creds.json if available
function readSavedUser() {
  try {
    if (fs.existsSync('auth_session/creds.json')) {
      const data = JSON.parse(fs.readFileSync('auth_session/creds.json', 'utf8'));
      if (data?.me?.id) {
        return data.me.id.split(':')[0];
      }
    }
  } catch (_) {}
  return null;
}

// Strict validator: ONLY true 10-13 digit phone numbers allowed (eliminates 14-16 digit LIDs)
function isRealPhoneNumber(str) {
  if (!str) return false;
  const s = String(str).trim();
  // Reject internal encrypted IDs, newsletters, group JIDs, broadcast
  if (s.includes('@lid') || s.includes('@newsletter') || s.includes('@g.us') || s.includes('broadcast')) {
    return false;
  }
  const digits = s.replace(/\D/g, '');
  // Standard phone numbers are 10 to 13 digits (India: 10 or 12 digits with 91)
  if (digits.length < 10 || digits.length > 13) return false;

  // Reject fake/dummy numbers (like 9876543210, 9812345678, etc.)
  const dummyNumbers = ['9876543210', '9812345678', '9823456789', '9834567890', '9845678901', '1234567890'];
  if (dummyNumbers.some((d) => digits === d || digits === `91${d}`)) return false;

  // Reject bot's own phone number
  const myNum = connectedUser || readSavedUser();
  if (myNum && (digits === myNum || digits.endsWith(myNum))) return false;

  return true;
}

const contactsStore = new Map();
const CONTACTS_FILE = 'contacts.json';

function scanRealChatsFromSession() {
  try {
    if (fs.existsSync('auth_session')) {
      const files = fs.readdirSync('auth_session');
      for (const f of files) {
        const match = f.match(/^session-(\d{10,15})\.0\.json$/);
        if (match) {
          const phone = match[1];
          if (isRealPhoneNumber(phone)) {
            const id = `${phone}@s.whatsapp.net`;
            if (!contactsStore.has(id)) {
              contactsStore.set(id, {
                id,
                phone,
                name: `+${phone}`,
                source: 'chat'
              });
            }
          }
        }
      }
    }
  } catch (err) {
    console.error('Error scanning session chats:', err.message);
  }
}

function cleanContactsStore() {
  for (const [id, item] of contactsStore.entries()) {
    if (!isRealPhoneNumber(item.phone || item.id)) {
      contactsStore.delete(id);
    }
  }
  scanRealChatsFromSession();
}

function loadSavedContacts() {
  try {
    if (fs.existsSync(CONTACTS_FILE)) {
      const data = JSON.parse(fs.readFileSync(CONTACTS_FILE, 'utf8'));
      if (Array.isArray(data)) {
        for (const item of data) {
          const phone = String(item.phone || item.id || '');
          if (isRealPhoneNumber(phone)) {
            const clean = phone.replace(/\D/g, '');
            const id = `${clean}@s.whatsapp.net`;
            contactsStore.set(id, {
              id,
              phone: clean,
              name: item.name || `+${clean}`,
              source: item.source || 'saved'
            });
          }
        }
      }
    }
  } catch (err) {
    console.error('Error loading saved contacts:', err.message);
  }
  cleanContactsStore();
  saveContactsToDisk();
  console.log(`[CONTACTS] Loaded ${contactsStore.size} genuine contacts from ${CONTACTS_FILE}`);
}

function saveContactsToDisk() {
  try {
    const list = Array.from(contactsStore.values()).filter(c => isRealPhoneNumber(c.phone));
    fs.writeFileSync(CONTACTS_FILE, JSON.stringify(list, null, 2), 'utf8');
  } catch (err) {
    console.error('Error saving contacts to disk:', err.message);
  }
}

loadSavedContacts();

// Cleanly dispose previous socket
function cleanupSocket() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (sock) {
    try {
      sock.ev?.removeAllListeners();
      sock.ws?.removeAllListeners();
      sock.ws?.close();
      sock.end?.(undefined);
    } catch (_) {}
    sock = null;
  }
}

// Schedule reconnect with delay to prevent loops
function scheduleReconnect(delayMs = 3000, reason = '') {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
  }
  console.log(`[RECONNECT] Scheduling reconnect in ${delayMs / 1000}s (${reason})...`);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    startWhatsApp();
  }, delayMs);
}

async function startWhatsApp() {
  if (isConnecting) {
    console.log('[START] Connection attempt already in progress, skipping duplicate.');
    return;
  }
  isConnecting = true;
  cleanupSocket();

  try {
    const { state, saveCreds } = await useMultiFileAuthState('auth_session');
    const { version } = await fetchLatestBaileysVersion();

    if (state.creds?.me?.id) {
      connectedUser = state.creds.me.id.split(':')[0];
    } else {
      connectedUser = readSavedUser();
    }

    const logger = pino({ level: 'fatal' });

    sock = makeWASocket({
      version,
      auth: {
        creds: state.creds,
        keys: makeCacheableSignalKeyStore(state.keys, logger),
      },
      logger,
      printQRInTerminal: false,
      syncFullHistory: false,
      markOnlineOnConnect: true,
      generateHighQualityLinkPreview: false,
      browser: Browsers.macOS('Desktop'),
      connectTimeoutMs: 60000,
      keepAliveIntervalMs: 25000,
      defaultQueryTimeoutMs: 60000,
      getMessage: async () => undefined,
    });

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('messaging-history.set', ({ contacts, chats }) => {
      if (Array.isArray(contacts)) {
        for (const c of contacts) {
          if (c.id && isRealPhoneNumber(c.id)) {
            const cleanPhone = c.id.replace(/\D/g, '');
            const id = `${cleanPhone}@s.whatsapp.net`;
            const name = c.name || c.notify || c.verifiedName || `+${cleanPhone}`;
            contactsStore.set(id, { id, phone: cleanPhone, name, source: 'whatsapp' });
          }
        }
      }
      if (Array.isArray(chats)) {
        for (const ch of chats) {
          if (ch.id && isRealPhoneNumber(ch.id)) {
            const cleanPhone = ch.id.replace(/\D/g, '');
            const id = `${cleanPhone}@s.whatsapp.net`;
            const name = ch.name || `+${cleanPhone}`;
            if (!contactsStore.has(id)) {
              contactsStore.set(id, { id, phone: cleanPhone, name, source: 'chat' });
            }
          }
        }
      }
      saveContactsToDisk();
    });

    sock.ev.on('contacts.set', ({ contacts }) => {
      if (Array.isArray(contacts)) {
        for (const c of contacts) {
          if (c.id && isRealPhoneNumber(c.id)) {
            const cleanPhone = c.id.replace(/\D/g, '');
            const id = `${cleanPhone}@s.whatsapp.net`;
            const name = c.name || c.notify || c.verifiedName || `+${cleanPhone}`;
            contactsStore.set(id, { id, phone: cleanPhone, name, source: 'whatsapp' });
          }
        }
        saveContactsToDisk();
      }
    });

    sock.ev.on('contacts.upsert', (contacts) => {
      if (Array.isArray(contacts)) {
        for (const c of contacts) {
          if (c.id && isRealPhoneNumber(c.id)) {
            const cleanPhone = c.id.replace(/\D/g, '');
            const id = `${cleanPhone}@s.whatsapp.net`;
            const name = c.name || c.notify || c.verifiedName || `+${cleanPhone}`;
            contactsStore.set(id, { id, phone: cleanPhone, name, source: 'whatsapp' });
          }
        }
        saveContactsToDisk();
      }
    });

    sock.ev.on('chats.upsert', (chats) => {
      if (Array.isArray(chats)) {
        for (const ch of chats) {
          if (ch.id && isRealPhoneNumber(ch.id)) {
            const cleanPhone = ch.id.replace(/\D/g, '');
            const id = `${cleanPhone}@s.whatsapp.net`;
            const name = ch.name || `+${cleanPhone}`;
            if (!contactsStore.has(id)) {
              contactsStore.set(id, { id, phone: cleanPhone, name, source: 'chat' });
            }
          }
        }
        saveContactsToDisk();
      }
    });

    sock.ev.on('messages.upsert', ({ messages }) => {
      if (Array.isArray(messages)) {
        for (const m of messages) {
          const jid = m.key?.remoteJid;
          if (jid && isRealPhoneNumber(jid)) {
            const cleanPhone = jid.replace(/\D/g, '');
            const id = `${cleanPhone}@s.whatsapp.net`;
            const name = m.pushName || (contactsStore.get(id)?.name) || `+${cleanPhone}`;
            contactsStore.set(id, { id, phone: cleanPhone, name, source: 'chat' });
            saveContactsToDisk();
          }
        }
      }
    });

    sock.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        console.log('\n=======================================');
        console.log('SCAN THIS QR CODE IN YOUR WHATSAPP APP:');
        console.log('=======================================');
        qrcodeTerminal.generate(qr, { small: true });

        try {
          currentQr = await qrcode.toDataURL(qr);
        } catch (e) {
          currentQr = null;
        }
      }

      if (connection === 'open') {
        isConnected = true;
        currentQr = null;
        if (sock?.user?.id) {
          connectedUser = sock.user.id.split(':')[0];
        }
        console.log('\n=================================================');
        console.log(`[WHATSAPP READY] Logged in successfully as: +${connectedUser}`);
        console.log('=================================================\n');
      } else if (connection === 'close') {
        isConnected = false;
        const statusCode = (lastDisconnect?.error instanceof Boom)
          ? lastDisconnect.error.output?.statusCode
          : (lastDisconnect?.error?.code || null);

        console.log(`[Connection Closed] Status Code: ${statusCode}`);

        if (statusCode === DisconnectReason.loggedOut || statusCode === 401 || statusCode === 403) {
          console.log('[LOGGED OUT] Session was logged out from WhatsApp. Cleaning credentials...');
          connectedUser = null;
          currentQr = null;
          try {
            fs.rmSync('auth_session', { recursive: true, force: true });
          } catch (_) {}
          scheduleReconnect(2000, 'Logged out - getting fresh QR');
        } else if (statusCode === DisconnectReason.connectionReplaced || statusCode === 440) {
          console.log('[Connection Replaced (440)] Backing off 8s before reconnecting...');
          scheduleReconnect(8000, 'Connection replaced (440)');
        } else if (statusCode === DisconnectReason.restartRequired || statusCode === 515) {
          scheduleReconnect(1000, 'Restart required (515)');
        } else {
          scheduleReconnect(3000, `Network transient (${statusCode})`);
        }
      }
    });
  } catch (err) {
    console.error('[START ERROR]', err);
    scheduleReconnect(5000, 'Startup exception');
  } finally {
    isConnecting = false;
  }
}

// 1. Connection Status API
app.get('/api/status', (req, res) => {
  const hasCreds = fs.existsSync('auth_session/creds.json');
  const user = connectedUser || readSavedUser();
  const isLoggedIn = !!user && hasCreds;

  res.json({
    connected: isConnected,
    isLoggedIn: isLoggedIn,
    user: user,
    hasQr: !isLoggedIn && !!currentQr,
    qrDataUrl: !isLoggedIn ? currentQr : null,
  });
});

// 1b. Request Pairing Code (Link with phone number without scanning QR)
app.post('/api/pair', async (req, res) => {
  try {
    if (isConnected) {
      return res.json({ success: true, alreadyConnected: true, user: connectedUser });
    }
    let { phone, countryCode = '91' } = req.body;
    if (!phone) {
      return res.status(400).json({ success: false, error: 'Phone number is required' });
    }
    let cleanPhone = String(phone).replace(/\D/g, '');
    let cleanCode = String(countryCode).replace(/\D/g, '');
    if (!cleanCode) cleanCode = '91';

    if (cleanPhone.length === 10) {
      cleanPhone = `${cleanCode}${cleanPhone}`;
    }

    if (!sock) {
      return res.status(500).json({ success: false, error: 'WhatsApp socket not initialized' });
    }

    if (!sock.authState.creds.registered) {
      const code = await sock.requestPairingCode(cleanPhone);
      console.log(`\n=======================================================`);
      console.log(`[PAIRING CODE] Generated code for +${cleanPhone}: ${code}`);
      console.log(`=======================================================\n`);
      return res.json({ success: true, code, phone: cleanPhone });
    } else {
      return res.json({ success: false, error: 'Already registered or connected' });
    }
  } catch (err) {
    console.error('Pairing code error:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// 1c. Logout / Reset Session Endpoint (User explicitly clicks to unlink)
app.post('/api/logout', async (req, res) => {
  try {
    console.log('\n[LOGOUT] User explicitly requested logout / unlinking...');
    isConnected = false;
    connectedUser = null;
    currentQr = null;

    cleanupSocket();

    if (fs.existsSync('auth_session')) {
      fs.rmSync('auth_session', { recursive: true, force: true });
    }
    scheduleReconnect(1500, 'Manual logout');
    return res.json({ success: true, message: 'Logged out successfully' });
  } catch (e) {
    return res.status(500).json({ success: false, error: e.message });
  }
});

app.post('/api/reset-session', async (req, res) => {
  try {
    console.log('\n[RESET] User requested session reset...');
    isConnected = false;
    connectedUser = null;
    currentQr = null;

    cleanupSocket();

    if (fs.existsSync('auth_session')) {
      fs.rmSync('auth_session', { recursive: true, force: true });
    }
    scheduleReconnect(1500, 'Session reset');
    return res.json({ success: true, message: 'Session reset successfully' });
  } catch (e) {
    return res.status(500).json({ success: false, error: e.message });
  }
});

// 2. Simple Web View for QR Code
app.get('/qr-page', (req, res) => {
  if (isConnected) {
    return res.send(`
      <html>
        <head><title>WhatsApp Connected</title></head>
        <body style="font-family:sans-serif;text-align:center;padding:50px;background:#f0fdf4;">
          <h1 style="color:#15803d;">✅ WhatsApp Connected!</h1>
          <p style="font-size:18px;">Logged in as: <strong>+${connectedUser}</strong></p>
          <p>You can now send bulk messages from your Flutter App with 1 click.</p>
        </body>
      </html>
    `);
  }

  if (!currentQr) {
    return res.send(`
      <html>
        <head><meta http-equiv="refresh" content="2"><title>Waiting for QR</title></head>
        <body style="font-family:sans-serif;text-align:center;padding:50px;">
          <h2>Generating QR Code... Please wait.</h2>
          <p>This page will reload automatically in 2 seconds.</p>
        </body>
      </html>
    `);
  }

  res.send(`
    <html>
      <head><meta http-equiv="refresh" content="5"><title>Scan WhatsApp QR</title></head>
      <body style="font-family:sans-serif;text-align:center;padding:40px;background:#f9fafb;">
        <h2 style="color:#111827;">Scan with your WhatsApp App</h2>
        <p style="color:#4b5563;">Open WhatsApp > Linked Devices > Link a Device</p>
        <div style="margin:20px auto;display:inline-block;padding:20px;background:white;border-radius:16px;box-shadow:0 4px 12px rgba(0,0,0,0.1);">
          <img src="${currentQr}" alt="Scan QR" style="width:280px;height:280px;" />
        </div>
        <p style="font-size:13px;color:#9ca3af;">Page auto-refreshes every 5 seconds until connected.</p>
      </body>
    </html>
  `);
});

function getJid(raw) {
  const str = String(raw).trim();
  if (str.endsWith('@g.us') || str.endsWith('@s.whatsapp.net') || str.endsWith('@lid')) {
    return str;
  }
  if (str.includes('-') || (str.startsWith('120363') && str.length >= 16)) {
    return `${str}@g.us`;
  }
  const clean = str.replace(/\D/g, '');
  return `${clean}@s.whatsapp.net`;
}

// 2b. Fetch WhatsApp Groups the user is a member of
app.get('/api/groups', async (req, res) => {
  try {
    if (!sock) {
      return res.status(503).json({ success: false, error: 'WhatsApp is not connected' });
    }
    const groups = await sock.groupFetchAllParticipating();
    const list = Object.values(groups).map((g) => ({
      id: g.id,
      name: g.subject || 'Unnamed Group',
      participantsCount: g.participants?.length || 0,
    }));
    return res.json({ success: true, groups: list });
  } catch (err) {
    console.error('Error fetching groups:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// 2c. Fetch Distinct Verified WhatsApp Contacts & Leads (Guaranteed 100% Unique)
app.get('/api/contacts', (req, res) => {
  try {
    cleanContactsStore();
    const seen = new Set();
    const uniqueContacts = [];
    for (const c of contactsStore.values()) {
      if (isRealPhoneNumber(c.phone)) {
        const clean = c.phone.replace(/\D/g, '');
        if (!seen.has(clean)) {
          seen.add(clean);
          uniqueContacts.push(c);
        }
      }
    }
    return res.json({
      success: true,
      count: uniqueContacts.length,
      contacts: uniqueContacts,
    });
  } catch (err) {
    console.error('Error fetching contacts:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// 2d. Fetch members of a specific WhatsApp group (Cleanly indexed, no repeating identical rows)
app.get('/api/group-members', async (req, res) => {
  try {
    if (!sock) return res.status(503).json({ success: false, error: 'WhatsApp is not connected' });
    const { groupId } = req.query;
    const groups = await sock.groupFetchAllParticipating();
    const myLid = sock.authState?.creds?.me?.lid?.split(':')[0];
    const myPn = connectedUser || readSavedUser();

    const members = [];
    const seen = new Set();

    const targetGroups = groupId
      ? Object.values(groups).filter((g) => g.id === groupId)
      : Object.values(groups);

    for (const g of targetGroups) {
      if (Array.isArray(g.participants)) {
        let memberIdx = 1;
        const groupTitle = g.subject || 'Group';
        for (const p of g.participants) {
          const rawId = p.id;
          if (!rawId || seen.has(rawId)) continue;

          const cleanDigits = rawId.replace(/\D/g, '');
          if (rawId === myLid || cleanDigits === myPn || (myPn && cleanDigits.endsWith(myPn))) {
            continue;
          }

          seen.add(rawId);
          const isLid = rawId.endsWith('@lid');

          members.push({
            id: rawId,
            phone: isLid ? rawId : cleanDigits,
            name: isLid ? `${groupTitle} • Member #${memberIdx}` : `+${cleanDigits} (${groupTitle})`,
            groupName: groupTitle,
            source: 'group_member',
          });
          memberIdx++;
        }
      }
    }

    return res.json({ success: true, count: members.length, members });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

// 2d. Fetch ONLY Direct 1-to-1 WhatsApp Chats
app.get('/api/contacts/direct', (req, res) => {
  try {
    cleanContactsStore();
    const directList = Array.from(contactsStore.values()).filter((c) => isRealPhoneNumber(c.phone));
    return res.json({ success: true, count: directList.length, contacts: directList });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

// 2e. Clear All Contacts (Reset list)
app.post('/api/contacts/clear', (req, res) => {
  try {
    contactsStore.clear();
    saveContactsToDisk();
    return res.json({ success: true, message: 'All contacts cleared' });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

// 2e. Import Bulk Numbers or Leads
app.post('/api/import-contacts', (req, res) => {
  try {
    const { contacts } = req.body;
    if (!Array.isArray(contacts)) {
      return res.status(400).json({ success: false, error: 'contacts array is required' });
    }
    let added = 0;
    for (const c of contacts) {
      const rawPhone = String(c.phone || c.number || '');
      if (isRealPhoneNumber(rawPhone)) {
        const phone = rawPhone.replace(/\D/g, '');
        const id = `${phone}@s.whatsapp.net`;
        const name = (c.name && c.name.trim().length > 0) ? c.name.trim() : `+${phone}`;
        contactsStore.set(id, { id, phone, name, source: 'imported' });
        added++;
      }
    }
    saveContactsToDisk();
    const list = Array.from(contactsStore.values()).filter((c) => isRealPhoneNumber(c.phone));
    return res.json({ success: true, count: list.length, added });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

// 3. Send Single Message API (Supports numbers and groups)
app.post('/api/send', async (req, res) => {
  try {
    if (!sock) {
      return res.status(503).json({
        success: false,
        error: 'WhatsApp is not connected. Please scan the QR code first.',
      });
    }

    const { phone, message } = req.body;
    if (!phone || !message) {
      return res.status(400).json({ success: false, error: 'phone/groupId and message are required' });
    }

    const jid = getJid(phone);
    const result = await sock.sendMessage(jid, { text: message });
    return res.json({
      success: true,
      target: jid,
      messageId: result?.key?.id,
    });
  } catch (err) {
    console.error('Error sending message:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Broadcast control state
let isBroadcastRunning = false;
let shouldStopBroadcast = false;

// 4b. Stop Active Broadcast API
app.post('/api/stop-broadcast', (req, res) => {
  if (isBroadcastRunning) {
    shouldStopBroadcast = true;
    console.log('\n[STOP] Stop signal received from user! Aborting broadcast...');
    return res.json({ success: true, message: 'Broadcast stop initiated' });
  }
  return res.json({ success: true, message: 'No active broadcast running' });
});

// 4. Send Bulk Messages API (Supports individual contacts AND groups + Instant Stop)
app.post('/api/send-bulk', async (req, res) => {
  try {
    if (!sock) {
      return res.status(503).json({
        success: false,
        error: 'WhatsApp is not connected. Please scan the QR code first.',
      });
    }

    const { recipients, messageTemplate, delayMs = 2000, repeatCount = 1 } = req.body;
    if (!Array.isArray(recipients) || recipients.length === 0) {
      return res.status(400).json({ success: false, error: 'recipients list is required' });
    }

    const repeats = Math.max(1, parseInt(repeatCount) || 1);

    // Safety deduplication: ensure each recipient/target is unique in a single broadcast list
    const uniqueRecipients = [];
    const seenJids = new Set();
    for (const item of recipients) {
      const rawTarget = typeof item === 'string' ? item : (item.phone || item.id);
      if (!rawTarget) continue;
      const jid = getJid(rawTarget);
      if (!seenJids.has(jid)) {
        seenJids.add(jid);
        uniqueRecipients.push(item);
      }
    }

    if (uniqueRecipients.length === 0) {
      return res.status(400).json({ success: false, error: 'No valid recipient numbers found' });
    }

    const totalMessages = uniqueRecipients.length * repeats;
    const results = [];
    let messageIndex = 0;
    let wasStopped = false;

    isBroadcastRunning = true;
    shouldStopBroadcast = false;

    console.log(`\n[BOOSTER LAUNCH] Targets: ${uniqueRecipients.length} | Repeats: ${repeats}x | Total Messages: ${totalMessages}`);

    try {
      for (let round = 1; round <= repeats; round++) {
        if (shouldStopBroadcast) {
          wasStopped = true;
          console.log(`[BROADCAST STOPPED] Stopped before round ${round}.`);
          break;
        }

        for (let i = 0; i < uniqueRecipients.length; i++) {
          if (shouldStopBroadcast) {
            wasStopped = true;
            console.log(`[BROADCAST STOPPED] Stopped at message ${messageIndex}.`);
            break;
          }

          messageIndex++;
          const item = uniqueRecipients[i];
          const rawTarget = typeof item === 'string' ? item : (item.phone || item.id);
          const name = (typeof item === 'object' && item.name) ? item.name : 'Client';

          const jid = getJid(rawTarget);
          const isGroup = jid.endsWith('@g.us');
          const cleanPhone = jid.replace('@s.whatsapp.net', '').replace('@g.us', '');

          const personalized = messageTemplate
            .replace(/{name}/g, name)
            .replace(/{number}/g, cleanPhone);

          try {
            const sent = await sock.sendMessage(jid, { text: personalized });
            results.push({
              phone: rawTarget,
              targetJid: jid,
              name,
              isGroup,
              round,
              success: true,
              messageId: sent?.key?.id,
            });
            console.log(`[${messageIndex}/${totalMessages}] (Round ${round}/${repeats}) Sent to ${isGroup ? 'Group: ' : '+'}${name} (${jid})`);
          } catch (err) {
            results.push({
              phone: rawTarget,
              targetJid: jid,
              name,
              isGroup,
              round,
              success: false,
              error: err.message,
            });
            console.error(`[${messageIndex}/${totalMessages}] (Round ${round}/${repeats}) Failed to send to ${name} (${jid}):`, err.message);
          }

          // Safe delay between messages with rapid 100ms stop-check intervals
          if (messageIndex < totalMessages && delayMs > 0) {
            const step = 100;
            let elapsed = 0;
            while (elapsed < delayMs) {
              if (shouldStopBroadcast) {
                wasStopped = true;
                break;
              }
              await new Promise((resolve) => setTimeout(resolve, step));
              elapsed += step;
            }
          }
        }
      }
    } finally {
      isBroadcastRunning = false;
      shouldStopBroadcast = false;
    }

    return res.json({
      success: true,
      stopped: wasStopped,
      total: totalMessages,
      repeats,
      sentCount: results.filter((r) => r.success).length,
      failedCount: results.filter((r) => !r.success).length,
      results,
    });
  } catch (err) {
    console.error('Bulk send error:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

app.listen(PORT, async () => {
  console.log(`\n======================================================`);
  console.log(`  WhatsApp Gateway Server running on port ${PORT}`);
  console.log(`  Status API: http://localhost:${PORT}/api/status`);
  console.log(`======================================================\n`);
  await startWhatsApp();
});
