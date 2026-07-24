# KBA Client QA Test Plan

Record each result as Pass, Fail or Not Tested. A failed critical test blocks the final release.

## 1. Installation and launch

- Install the TIPA over a clean device.
- Launch on iOS 16.0 or later without a crash.
- Confirm portrait layout on iPhone 14 Pro Max.
- Relaunch after force-closing; profile and local data remain.
- Install a later test build over the previous build; local data remains intact.

## 2. Onboarding

- Full name and valid email are required.
- UK, USA, UAE and Qatar market selection works.
- All four customer types save correctly.
- Edit Profile updates the displayed customer information.

## 3. Services

- Eight services appear.
- Search returns correct service cards.
- Jurisdiction filter hides unrelated services.
- Every service detail opens and displays included support.
- Request button opens the correct preselected service.

## 4. Requests

- Details under 10 characters cannot be submitted.
- A valid test request receives a unique KBA reference.
- Saved requests appear immediately in My Requests.
- Status filter works.
- Request timeline and details match the submitted values.
- The local-test warning remains visible.

## 5. Documents

- Files picker opens from iCloud Drive, On My iPhone and supported providers.
- PDF, image, text, CSV and generic document files import.
- Multiple selection imports every chosen file.
- Filename, category, date and size display correctly.
- Swipe delete removes both the row and the copied local file.
- Cancelling the picker does not freeze the app.

## 6. Consultations and notifications

- Past date/time cannot be chosen.
- Topic is required.
- Consultation saves and appears in the list.
- Notification permission is requested only after enabling a reminder and saving.
- Reminder is scheduled one hour before a future appointment.

## 7. Contact

- Email opens a mail composer or the configured mail app.
- Phone buttons dial the correct regional numbers.
- WhatsApp buttons open the correct regional conversations.
- Website and privacy links open in the browser.

## 8. Appearance and accessibility

- System, Light and Dark modes work.
- Text remains readable with large Dynamic Type.
- VoiceOver announces buttons and the KBA mark.
- No content is clipped on smaller supported iPhones.

## 9. Data safety

- No test request is transmitted over the network.
- Imported files remain inside the app container.
- Delete All Local Test Data removes profile, requests, consultations and files.
- No personal demo data is included in a clean installation.

## 10. Final regression

Repeat all critical tests after backend integration, branding changes, authentication, analytics, push notifications or release signing changes.
