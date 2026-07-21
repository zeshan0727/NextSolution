# Next Reminder Gmail Scheduler

This branch is a standalone production scheduler for **Next Reminder v1.2.1**. It enables exact-time Gmail sending while the iPhone app is closed.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/zeshan0727/NextSolution/tree/next-reminder-scheduler-production)

## Beginner setup

### 1. Deploy to Render

1. Click **Deploy to Render** above.
2. Sign in to Render and connect GitHub when requested.
3. Review the service named `next-reminder-zeshan-0727`.
4. Enter the requested private values:
   - `API_KEY`
   - `ENCRYPTION_KEY`
   - `GOOGLE_CLIENT_ID`
   - `GOOGLE_CLIENT_SECRET`
   - `GOOGLE_REDIRECT_URI`
5. Approve the Starter service and persistent disk.

The expected service address is:

```text
https://next-reminder-zeshan-0727.onrender.com
```

The Google redirect URI must be:

```text
https://next-reminder-zeshan-0727.onrender.com/oauth/google/callback
```

If Render assigns a different address, use that exact address instead.

### 2. Google Cloud setup

1. Create or select a Google Cloud project.
2. Enable **Gmail API**.
3. Configure the Google Auth consent screen.
4. Add the Gmail account that will send messages as a test user while the app is in testing.
5. Create an OAuth client of type **Web application**.
6. Add the exact authorized redirect URI shown above.
7. Copy the Client ID and Client Secret into the matching Render environment fields.
8. Redeploy the Render service after saving the values.

The scheduler requests only these Google permissions:

```text
https://www.googleapis.com/auth/gmail.send
https://www.googleapis.com/auth/userinfo.email
openid
```

### 3. Connect the iPhone app

1. Open **Next Reminder → Settings → Social Automations → Accounts & Scheduler**.
2. Enter the Render HTTPS address.
3. Enter the same `API_KEY` used in Render.
4. Save and test the scheduler connection.
5. Open **Automations → Email Automations**.
6. Select **Gmail — Automatic**.
7. Tap **Connect Gmail Account** and approve Google access.
8. Set the fixed recipient and use **Test Configuration**.

## Security

- Gmail passwords are never entered or stored in the app.
- Google OAuth refresh tokens are encrypted with AES-256-GCM on the server.
- The private API key, encryption key, and Google Client Secret must only be stored in Render environment variables.
- The persistent disk keeps connected Gmail tokens and scheduled jobs after restarts.
