'use strict';

require('dotenv').config();

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const { google } = require('googleapis');

const PORT = Number(process.env.PORT || 3000);
const API_KEY = process.env.API_KEY || '';
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '';
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET || '';
const GOOGLE_REDIRECT_URI = process.env.GOOGLE_REDIRECT_URI || '';
const DATA_FILE = process.env.DATA_FILE || path.join(__dirname, 'data', 'next-reminder.json');
const ENCRYPTION_KEY = crypto
  .createHash('sha256')
  .update(process.env.ENCRYPTION_KEY || 'change-this-encryption-key')
  .digest();

const MAX_SINGLE_ATTACHMENT_BYTES = 10_000_000;
const MAX_TOTAL_ATTACHMENT_BYTES = 18_000_000;
const MAX_ATTACHMENT_COUNT = 10;

if (!API_KEY) console.warn('WARNING: API_KEY is empty. Configure it before public deployment.');
if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REDIRECT_URI) {
  console.warn('WARNING: Google OAuth environment variables are incomplete.');
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '30mb' }));

function emptyDatabase() {
  return { connectors: {}, oauthSessions: {}, emailJobs: {} };
}

function ensureDataDirectory() {
  fs.mkdirSync(path.dirname(DATA_FILE), { recursive: true });
}

function loadDatabase() {
  ensureDataDirectory();
  if (!fs.existsSync(DATA_FILE)) return emptyDatabase();
  try {
    return { ...emptyDatabase(), ...JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')) };
  } catch (error) {
    console.error('Could not read database:', error);
    return emptyDatabase();
  }
}

let database = loadDatabase();

function saveDatabase() {
  ensureDataDirectory();
  const temporary = `${DATA_FILE}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(database, null, 2));
  fs.renameSync(temporary, DATA_FILE);
}

function encryptJSON(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', ENCRYPTION_KEY, iv);
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify(value), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, encrypted]).toString('base64');
}

function decryptJSON(value) {
  const payload = Buffer.from(value, 'base64');
  const iv = payload.subarray(0, 12);
  const tag = payload.subarray(12, 28);
  const encrypted = payload.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', ENCRYPTION_KEY, iv);
  decipher.setAuthTag(tag);
  return JSON.parse(Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8'));
}

function requireAPIKey(req, res, next) {
  const header = req.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  const expected = Buffer.from(API_KEY);
  const received = Buffer.from(token);
  const valid = expected.length > 0
    && expected.length === received.length
    && crypto.timingSafeEqual(expected, received);
  if (!valid) return res.status(401).json({ message: 'Invalid scheduler API key.' });
  next();
}

function oauthClient() {
  return new google.auth.OAuth2(
    GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET,
    GOOGLE_REDIRECT_URI,
  );
}

function validateCallbackScheme(value) {
  return typeof value === 'string' && /^[A-Za-z][A-Za-z0-9+.-]{1,40}$/.test(value);
}

function base64url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function encodeHeader(value) {
  return `=?UTF-8?B?${Buffer.from(String(value || ''), 'utf8').toString('base64')}?=`;
}

function sanitizeHeader(value) {
  return String(value || '').replace(/[\r\n]+/g, ' ').trim();
}

function sanitizeFileName(value) {
  const cleaned = sanitizeHeader(value).replace(/["\\]/g, '_').slice(0, 180);
  return cleaned || 'attachment';
}

function sanitizeMimeType(value) {
  const cleaned = sanitizeHeader(value).toLowerCase();
  return /^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+$/.test(cleaned)
    ? cleaned
    : 'application/octet-stream';
}

function wrapBase64(value) {
  return String(value || '').replace(/\s+/g, '').match(/.{1,76}/g)?.join('\r\n') || '';
}

function createRawMessage({ to, subject, body, from, attachments = [] }) {
  const recipients = Array.isArray(to) ? to.join(', ') : String(to || '');
  const commonHeaders = [
    `To: ${sanitizeHeader(recipients)}`,
    from ? `From: ${sanitizeHeader(from)}` : null,
    `Subject: ${encodeHeader(subject)}`,
    'MIME-Version: 1.0',
  ].filter(Boolean);

  if (!attachments.length) {
    const headers = [
      ...commonHeaders,
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: 8bit',
    ];
    return base64url(`${headers.join('\r\n')}\r\n\r\n${String(body || '')}`);
  }

  const boundary = `NextReminder_${crypto.randomBytes(16).toString('hex')}`;
  const lines = [
    ...commonHeaders,
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    '',
    `--${boundary}`,
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: 8bit',
    '',
    String(body || ''),
  ];

  for (const attachment of attachments) {
    const fileName = sanitizeFileName(attachment.fileName);
    const mimeType = sanitizeMimeType(attachment.mimeType);
    lines.push(
      `--${boundary}`,
      `Content-Type: ${mimeType}; name="${fileName}"`,
      'Content-Transfer-Encoding: base64',
      `Content-Disposition: attachment; filename="${fileName}"`,
      '',
      wrapBase64(attachment.base64),
    );
  }

  lines.push(`--${boundary}--`, '');
  return base64url(lines.join('\r\n'));
}

async function gmailClientForConnector(connectorID) {
  const connector = database.connectors[connectorID];
  if (!connector || connector.provider !== 'gmail') {
    throw new Error('Gmail connector not found. Reconnect the Gmail account in the app.');
  }

  const client = oauthClient();
  const storedTokens = decryptJSON(connector.encryptedTokens);
  client.setCredentials(storedTokens);
  client.on('tokens', (tokens) => {
    const merged = { ...storedTokens, ...tokens };
    connector.encryptedTokens = encryptJSON(merged);
    connector.updatedAt = new Date().toISOString();
    saveDatabase();
  });

  return {
    gmail: google.gmail({ version: 'v1', auth: client }),
    connector,
  };
}

async function sendEmailJob(job) {
  const { gmail, connector } = await gmailClientForConnector(job.remoteConnectorID);
  const raw = createRawMessage({
    to: job.recipients || job.recipient,
    subject: job.subject,
    body: job.body,
    from: connector.emailAddress,
    attachments: job.attachments || [],
  });
  const result = await gmail.users.messages.send({
    userId: 'me',
    requestBody: { raw },
  });
  return result.data.id || null;
}

function isValidEmail(value) {
  const cleaned = String(value || '').trim();
  return cleaned.length <= 254
    && !cleaned.includes(' ')
    && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleaned);
}

function normalizeEmailPayload(body) {
  const required = ['localID', 'recipient', 'remoteConnectorID', 'subject', 'body', 'scheduledAt'];
  for (const key of required) {
    if (!body || typeof body[key] !== 'string' || !body[key].trim()) {
      throw new Error(`Missing required field: ${key}`);
    }
  }
  if (!isValidEmail(body.recipient)) throw new Error('Invalid recipient email address.');
  const scheduledDate = new Date(body.scheduledAt);
  if (Number.isNaN(scheduledDate.getTime())) throw new Error('Invalid scheduledAt value.');
  return {
    localID: body.localID.trim(),
    recipient: body.recipient.trim(),
    provider: 'gmail',
    remoteConnectorID: body.remoteConnectorID.trim(),
    senderLabel: String(body.senderLabel || '').trim(),
    subject: String(body.subject).slice(0, 500),
    body: String(body.body).slice(0, 100_000),
    scheduledAt: scheduledDate.toISOString(),
    timeZone: String(body.timeZone || 'UTC'),
    reminderTitle: String(body.reminderTitle || ''),
    reminderTime: String(body.reminderTime || body.scheduledAt),
    deadline: body.deadline || null,
    testOnly: Boolean(body.testOnly),
  };
}

function normalizeFileSharePayload(body) {
  if (!body || !Array.isArray(body.recipients) || body.recipients.length === 0) {
    throw new Error('Add at least one recipient.');
  }
  const recipients = body.recipients
    .map((value) => String(value || '').trim())
    .filter(Boolean);
  if (!recipients.length || recipients.length > 20 || !recipients.every(isValidEmail)) {
    throw new Error('One or more recipient email addresses are invalid.');
  }

  const remoteConnectorID = String(body.remoteConnectorID || '').trim();
  if (!remoteConnectorID) throw new Error('Gmail connector ID is missing.');
  if (!database.connectors[remoteConnectorID]) {
    throw new Error('Gmail connector not found. Reconnect Gmail in Next Reminder.');
  }

  const subject = String(body.subject || '').trim();
  if (!subject) throw new Error('Email subject is required.');

  if (!Array.isArray(body.attachments) || body.attachments.length === 0) {
    throw new Error('Attach at least one file.');
  }
  if (body.attachments.length > MAX_ATTACHMENT_COUNT) {
    throw new Error(`A maximum of ${MAX_ATTACHMENT_COUNT} attachments is allowed.`);
  }

  let totalBytes = 0;
  const attachments = body.attachments.map((item, index) => {
    const fileName = sanitizeFileName(item?.fileName || `attachment-${index + 1}`);
    const mimeType = sanitizeMimeType(item?.mimeType);
    const base64 = String(item?.base64 || '').replace(/\s+/g, '');
    if (!base64) throw new Error(`${fileName} has no file data.`);
    const bytes = Buffer.from(base64, 'base64');
    if (!bytes.length) throw new Error(`${fileName} could not be decoded.`);
    if (bytes.length > MAX_SINGLE_ATTACHMENT_BYTES) {
      throw new Error(`${fileName} is larger than 10 MB.`);
    }
    totalBytes += bytes.length;
    return { fileName, mimeType, base64 };
  });

  if (totalBytes > MAX_TOTAL_ATTACHMENT_BYTES) {
    throw new Error('The combined attachments are larger than 18 MB.');
  }

  return {
    recipients,
    remoteConnectorID,
    senderLabel: String(body.senderLabel || '').trim(),
    subject: subject.slice(0, 500),
    body: String(body.body || '').slice(0, 100_000),
    attachments,
  };
}

app.get('/healthz', (req, res) => {
  res.json({ ok: true, service: 'Next Reminder Scheduler', version: '1.2.3' });
});

app.get('/v1/health', requireAPIKey, (req, res) => {
  res.json({
    ok: true,
    message: 'Connection successful',
    service: 'Next Reminder Scheduler',
    version: '1.2.3',
    gmailOAuthConfigured: Boolean(GOOGLE_CLIENT_ID && GOOGLE_CLIENT_SECRET && GOOGLE_REDIRECT_URI),
    fileSharingEnabled: true,
  });
});

app.post('/v1/connectors/gmail/start', requireAPIKey, (req, res) => {
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REDIRECT_URI) {
    return res.status(503).json({ message: 'Google OAuth is not configured on the scheduler.' });
  }

  const callbackScheme = req.body?.callbackScheme;
  if (!validateCallbackScheme(callbackScheme)) {
    return res.status(400).json({ message: 'Invalid callback scheme.' });
  }

  const sessionID = crypto.randomUUID();
  const state = crypto.randomBytes(32).toString('hex');
  database.oauthSessions[state] = {
    sessionID,
    callbackScheme,
    createdAt: new Date().toISOString(),
    status: 'pending',
  };
  saveDatabase();

  const client = oauthClient();
  const authorizationURL = client.generateAuthUrl({
    access_type: 'offline',
    prompt: 'consent',
    include_granted_scopes: true,
    scope: [
      'https://www.googleapis.com/auth/gmail.send',
      'https://www.googleapis.com/auth/userinfo.email',
      'openid',
    ],
    state,
  });

  res.json({ authorizationURL, sessionID });
});

app.get('/oauth/google/callback', async (req, res) => {
  const { state, code, error } = req.query;
  const session = database.oauthSessions[state];
  if (!session) return res.status(400).send('Invalid or expired OAuth state.');

  if (error || !code) {
    session.status = 'failed';
    session.message = String(error || 'Google did not return an authorization code.');
    saveDatabase();
    return res.redirect(`${session.callbackScheme}://gmail-connected?error=${encodeURIComponent(session.message)}`);
  }

  try {
    const client = oauthClient();
    const { tokens } = await client.getToken(String(code));
    client.setCredentials(tokens);
    const oauth2 = google.oauth2({ version: 'v2', auth: client });
    const profile = await oauth2.userinfo.get();
    const emailAddress = profile.data.email;
    if (!emailAddress) throw new Error('Google did not return the Gmail address.');
    if (!tokens.refresh_token) {
      throw new Error('Google did not return a refresh token. Remove the app from Google Account access and connect again.');
    }

    const connectorID = `gmail_${crypto.randomUUID()}`;
    database.connectors[connectorID] = {
      id: connectorID,
      provider: 'gmail',
      emailAddress,
      encryptedTokens: encryptJSON(tokens),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    session.status = 'connected';
    session.connectorID = connectorID;
    session.emailAddress = emailAddress;
    saveDatabase();

    const redirect = `${session.callbackScheme}://gmail-connected?connector_id=${encodeURIComponent(connectorID)}&email=${encodeURIComponent(emailAddress)}`;
    res.redirect(redirect);
  } catch (callbackError) {
    console.error('Google OAuth callback failed:', callbackError);
    session.status = 'failed';
    session.message = callbackError.message;
    saveDatabase();
    res.redirect(`${session.callbackScheme}://gmail-connected?error=${encodeURIComponent(callbackError.message)}`);
  }
});

app.get('/v1/connectors/gmail/status', requireAPIKey, (req, res) => {
  const sessionID = String(req.query.session_id || '');
  const session = Object.values(database.oauthSessions).find((item) => item.sessionID === sessionID);
  if (!session) return res.status(404).json({ message: 'Connection session not found.' });
  res.json({
    connected: session.status === 'connected',
    connectorID: session.connectorID || null,
    emailAddress: session.emailAddress || null,
    message: session.message || null,
  });
});

app.delete('/v1/connectors/gmail/:connectorID', requireAPIKey, (req, res) => {
  const connectorID = req.params.connectorID;
  if (!database.connectors[connectorID]) {
    return res.status(404).json({ message: 'Gmail connector not found.' });
  }
  delete database.connectors[connectorID];
  for (const [jobID, job] of Object.entries(database.emailJobs)) {
    if (job.remoteConnectorID === connectorID && job.status === 'scheduled') {
      delete database.emailJobs[jobID];
    }
  }
  saveDatabase();
  res.json({ message: 'Gmail account disconnected.' });
});

app.post('/v1/email-reminders', requireAPIKey, (req, res) => {
  try {
    const payload = normalizeEmailPayload(req.body);
    if (!database.connectors[payload.remoteConnectorID]) {
      return res.status(400).json({ message: 'Gmail connector not found. Use Connect Gmail in the app.' });
    }
    database.emailJobs[payload.localID] = {
      ...payload,
      status: 'scheduled',
      attempts: 0,
      createdAt: database.emailJobs[payload.localID]?.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    saveDatabase();
    res.json({ id: payload.localID, message: 'Email reminder scheduled.' });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
});

app.post('/v1/email-reminders/test', requireAPIKey, async (req, res) => {
  try {
    const payload = normalizeEmailPayload({ ...req.body, scheduledAt: new Date().toISOString() });
    const gmailMessageID = await sendEmailJob(payload);
    res.json({ id: gmailMessageID, message: 'Test email sent.' });
  } catch (error) {
    console.error('Test email failed:', error);
    res.status(400).json({ message: error.message });
  }
});

app.post('/v1/email-reminders/cancel', requireAPIKey, (req, res) => {
  const localID = String(req.body?.localID || '');
  if (localID) delete database.emailJobs[localID];
  saveDatabase();
  res.json({ message: 'Email reminder cancelled.' });
});

app.post('/v1/file-shares', requireAPIKey, async (req, res) => {
  try {
    const payload = normalizeFileSharePayload(req.body);
    const gmailMessageID = await sendEmailJob(payload);
    res.json({ id: gmailMessageID, message: 'Email sent successfully.' });
  } catch (error) {
    console.error('File sharing failed:', error);
    res.status(400).json({ message: error.message });
  }
});

app.post('/v1/automations', requireAPIKey, (req, res) => {
  res.status(501).json({ message: 'This scheduler currently implements Gmail email and file-sharing automations.' });
});

app.post('/v1/automations/publish', requireAPIKey, (req, res) => {
  res.status(501).json({ message: 'This scheduler currently implements Gmail email and file-sharing automations.' });
});

async function processDueEmailJobs() {
  const now = Date.now();
  const dueJobs = Object.values(database.emailJobs)
    .filter((job) => job.status === 'scheduled' && new Date(job.scheduledAt).getTime() <= now)
    .sort((a, b) => new Date(a.scheduledAt) - new Date(b.scheduledAt));

  for (const job of dueJobs) {
    job.status = 'processing';
    job.updatedAt = new Date().toISOString();
    saveDatabase();

    try {
      const gmailMessageID = await sendEmailJob(job);
      job.status = 'sent';
      job.gmailMessageID = gmailMessageID;
      job.sentAt = new Date().toISOString();
      job.updatedAt = job.sentAt;
    } catch (error) {
      console.error(`Email job ${job.localID} failed:`, error);
      job.attempts = Number(job.attempts || 0) + 1;
      job.lastError = error.message;
      job.updatedAt = new Date().toISOString();
      if (job.attempts >= 3) {
        job.status = 'failed';
      } else {
        job.status = 'scheduled';
        job.scheduledAt = new Date(Date.now() + job.attempts * 60_000).toISOString();
      }
    }
    saveDatabase();
  }
}

setInterval(() => {
  processDueEmailJobs().catch((error) => console.error('Scheduler loop failed:', error));
}, 15_000).unref();

setInterval(() => {
  const cutoff = Date.now() - 30 * 60 * 1000;
  for (const [state, session] of Object.entries(database.oauthSessions)) {
    if (new Date(session.createdAt).getTime() < cutoff) delete database.oauthSessions[state];
  }
  saveDatabase();
}, 10 * 60 * 1000).unref();

app.use((error, req, res, next) => {
  if (error?.type === 'entity.too.large') {
    return res.status(413).json({ message: 'The selected attachments are too large.' });
  }
  console.error(error);
  res.status(500).json({ message: 'Unexpected scheduler error.' });
});

app.listen(PORT, () => {
  console.log(`Next Reminder Scheduler v1.2.3 listening on port ${PORT}`);
});
