'use strict';

const fs = require('fs');
const path = require('path');

const serverPath = path.join(__dirname, 'server.js');
let source = fs.readFileSync(serverPath, 'utf8');

const marker = "app.post('/v1/connectors/gmail/restore'";
if (!source.includes(marker)) {
  const insertionPoint = "app.delete('/v1/connectors/gmail/:connectorID', requireAPIKey, (req, res) => {";
  const routes = `app.get('/v1/connectors/gmail/:connectorID/recovery', requireAPIKey, (req, res) => {
  const connectorID = req.params.connectorID;
  const connector = database.connectors[connectorID];
  if (!connector || connector.provider !== 'gmail') {
    return res.status(404).json({ message: 'Gmail connector not found.' });
  }

  try {
    const tokens = decryptJSON(connector.encryptedTokens);
    const recoveryBlob = encryptJSON({
      version: 1,
      provider: 'gmail',
      emailAddress: connector.emailAddress,
      tokens,
    });
    return res.json({
      connectorID,
      emailAddress: connector.emailAddress,
      recoveryBlob,
    });
  } catch (error) {
    console.error('Could not create Gmail recovery package:', error);
    return res.status(500).json({ message: 'Could not create Gmail recovery package.' });
  }
});

app.post('/v1/connectors/gmail/restore', requireAPIKey, async (req, res) => {
  const connectorID = String(req.body?.connectorID || '').trim();
  const recoveryBlob = String(req.body?.recoveryBlob || '').trim();
  if (!connectorID || !recoveryBlob) {
    return res.status(400).json({ message: 'Connector ID and recovery package are required.' });
  }

  try {
    const recovery = decryptJSON(recoveryBlob);
    if (!recovery || recovery.version !== 1 || recovery.provider !== 'gmail') {
      return res.status(400).json({ message: 'Invalid Gmail recovery package.' });
    }
    if (!recovery.tokens || !recovery.tokens.refresh_token) {
      return res.status(400).json({ message: 'Gmail recovery package has no refresh token.' });
    }

    const client = oauthClient();
    client.setCredentials(recovery.tokens);
    const oauth2 = google.oauth2({ version: 'v2', auth: client });
    const profile = await oauth2.userinfo.get();
    const emailAddress = profile.data.email || recovery.emailAddress;
    if (!emailAddress) throw new Error('Google did not return the Gmail address.');

    database.connectors[connectorID] = {
      id: connectorID,
      provider: 'gmail',
      emailAddress,
      encryptedTokens: encryptJSON(recovery.tokens),
      createdAt: database.connectors[connectorID]?.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      restoredAt: new Date().toISOString(),
    };
    saveDatabase();

    return res.json({
      connected: true,
      connectorID,
      emailAddress,
      message: 'Gmail connector restored successfully.',
    });
  } catch (error) {
    console.error('Gmail connector restore failed:', error);
    const message = String(error?.message || 'Gmail connector could not be restored.');
    const lowered = message.toLowerCase();
    const revoked = lowered.includes('invalid_grant')
      || lowered.includes('expired or revoked')
      || lowered.includes('unauthorized_client')
      || lowered.includes('invalid credentials');
    return res.status(revoked ? 409 : 400).json({
      connected: false,
      connectorID,
      message: revoked
        ? 'Google has revoked or expired the Gmail authorization. Reconnect Gmail in Next Reminder.'
        : message,
    });
  }
});

`;

  if (!source.includes(insertionPoint)) {
    throw new Error('Could not find Gmail connector route insertion point in server.js');
  }
  source = source.replace(insertionPoint, routes + insertionPoint);
}

source = source.replace(/version: '1\.3\.8'/g, "version: '1.3.12'");
source = source.replace(/version: '1\.2\.3'/g, "version: '1.3.12'");
source = source.replace(/Scheduler v1\.2\.3/g, 'Scheduler v1.3.12');
fs.writeFileSync(serverPath, source);
console.log('Applied Next Reminder scheduler v1.3.12 Gmail recovery routes.');
