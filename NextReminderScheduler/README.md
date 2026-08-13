# Next Reminder Scheduler v1.2.1

This service provides the server-side part required by **Next Reminder → Email Automations → Gmail — Automatic**.

It supports:

- Google OAuth sign-in from the iPhone app
- Encrypted storage of Gmail refresh tokens
- Exact-time scheduled Gmail sending while the iPhone app is closed
- Test emails
- Cancellation and rescheduling
- Three automatic retries for temporary failures
- A persistent JSON database on an attached server disk

## 1. Create Google OAuth credentials

1. Open Google Cloud Console.
2. Create or select a project.
3. Enable **Gmail API**.
4. Configure the OAuth consent screen.
5. Create an OAuth client of type **Web application**.
6. Add this authorized redirect URI:

```text
https://YOUR-SCHEDULER-DOMAIN/oauth/google/callback
```

7. Copy the client ID and client secret.

The OAuth consent screen needs the Gmail send scope:

```text
https://www.googleapis.com/auth/gmail.send
```

During testing, add your Gmail address as an OAuth test user. Google may require verification before other users can connect.

## 2. Deploy

The included `render.yaml` and `Dockerfile` can be deployed on Render or another Docker host.

Required environment variables:

```text
API_KEY=<long random key used by the iPhone app>
ENCRYPTION_KEY=<different long random encryption secret>
GOOGLE_CLIENT_ID=<Google OAuth web client ID>
GOOGLE_CLIENT_SECRET=<Google OAuth client secret>
GOOGLE_REDIRECT_URI=https://YOUR-SCHEDULER-DOMAIN/oauth/google/callback
DATA_FILE=/data/next-reminder.json
```

Use a persistent disk mounted at `/data`; otherwise connections and scheduled jobs will be lost after a server restart.

## 3. Configure the iPhone app

1. Open **Next Reminder → Automations**.
2. Open **Automation Connections**.
3. Enter the deployed HTTPS server URL, such as:

```text
https://next-reminder-scheduler.example.com
```

4. Enter the same `API_KEY` configured on the server.
5. Save and test the scheduler connection.
6. Open **Email Reminder Automations**.
7. Select **Gmail — Automatic**.
8. Tap **Connect Gmail Account**.
9. Sign in with Google and approve email sending.
10. The connected Gmail address and connector ID are filled automatically.
11. Enter the fixed recipient and save.
12. Use **Test Configuration**.

## Security

- The iPhone app never receives or stores your Gmail password.
- Google OAuth refresh tokens are encrypted with AES-256-GCM on the server.
- The app stores only the connected email address and connector ID.
- Keep `API_KEY`, `ENCRYPTION_KEY`, and Google client secret private.
- Use HTTPS only.

## Run locally

```bash
cp .env.example .env
npm install
npm start
```

Google OAuth cannot redirect to the iPhone from a plain HTTP production endpoint; use a public HTTPS URL for device testing.
