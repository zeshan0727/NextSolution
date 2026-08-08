'use strict';

const fs = require('fs');
const path = require('path');

const serverPath = path.join(__dirname, 'server.js');
let source = fs.readFileSync(serverPath, 'utf8');

const marker = "app.get('/v1/connectors/gmail/:connectorID/status'";
if (!source.includes(marker)) {
  const insertionPoint = "app.delete('/v1/connectors/gmail/:connectorID', requireAPIKey, (req, res) => {";
  const route = `app.get('/v1/connectors/gmail/:connectorID/status', requireAPIKey, async (req, res) => {
  const connectorID = req.params.connectorID;
  const connector = database.connectors[connectorID];
  if (!connector || connector.provider !== 'gmail') {
    return res.status(404).json({
      connected: false,
      connectorID,
      emailAddress: null,
      message: 'Gmail connector not found. Reconnect Gmail in Next Reminder.',
    });
  }

  try {
    const { gmail } = await gmailClientForConnector(connectorID);
    await gmail.users.getProfile({ userId: 'me' });
    return res.json({
      connected: true,
      connectorID,
      emailAddress: connector.emailAddress,
      message: 'Gmail connection is healthy.',
    });
  } catch (error) {
    const message = String(error?.message || 'Gmail health check failed.');
    const lowered = message.toLowerCase();
    const disconnected = lowered.includes('invalid_grant')
      || lowered.includes('expired or revoked')
      || lowered.includes('unauthorized_client')
      || lowered.includes('gmail connector not found')
      || lowered.includes('invalid credentials');

    if (disconnected) {
      return res.status(409).json({
        connected: false,
        connectorID,
        emailAddress: connector.emailAddress,
        message: 'Gmail authorization is no longer valid. Reconnect Gmail in Next Reminder.',
      });
    }

    console.error('Gmail health check failed:', error);
    return res.status(503).json({
      connected: null,
      connectorID,
      emailAddress: connector.emailAddress,
      message: 'Gmail connection could not be checked right now.',
    });
  }
});

`;

  if (!source.includes(insertionPoint)) {
    throw new Error('Could not find Gmail connector route insertion point in server.js');
  }
  source = source.replace(insertionPoint, route + insertionPoint);
}

source = source.replace("version: '1.2.1'", "version: '1.3.8'");
fs.writeFileSync(serverPath, source);
console.log('Applied Next Reminder scheduler v1.3.8 Gmail health route.');
