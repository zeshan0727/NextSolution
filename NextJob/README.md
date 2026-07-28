# Next Job

Next Job is a private iOS 16+ job tracker built for part-time accounting work received from KB Accountants.

## Included in 1.0.6

- Jobs with assigned date, due date, completion date, status, job type, targeted time, actual time and price
- Create missing job types directly from the New Job form
- Dashboard for not started, in progress, waiting for documents, completed and overdue work
- Stable multi-file import and a separate validated complete-folder import
- Related files and completion documents stored against the correct job
- Professional completion emails with exact recorded completion time, job notes and completion notes
- Automatic Gmail sending from Job Details after a confirmation popup
- Payment Pending and Payment Received tracking, pending-payment filters and PDF invoices
- OpenAI email drafting with explicit error handling and visible token usage
- Complete job backup and restore through the iOS Files provider

## Secure Logins vault

The dedicated **Logins** tab stores website and service credentials with:

- Service, website, login email or user ID, password, notes and automatically recorded dates
- User-created categories that are added automatically when a login is saved
- Search across service, website, login, category and notes
- Category chips, favourites-only filtering and multiple sort modes
- Detail, edit, favourite, copy and delete actions
- Strong-password generation
- Attachments from Camera, Photos/screenshots and Files
- Quick Look preview and share/save controls for attachments

Passwords are stored separately in the iPhone Keychain using a device-only, unlocked-device accessibility class. Password reveal, copying and editing require Face ID or the device passcode. Vault metadata and attachments use iOS complete file protection in the app's private Application Support directory. Plaintext passwords are not written into the normal Next Job JSON database or portable backup.

## Email behaviour

Gmail Direct sends through a connected scheduler/Gmail OAuth account. Job Details email actions show a confirmation popup and record email history only after scheduler acceptance. Apple Mail assisted sending remains available from the Email tab.

## Google Drive behaviour

Install and sign in to the Google Drive iOS app, then enable Google Drive under **Files → Browse → … → Edit**. Next Job uses the iOS document provider so complete job backups can be saved to and restored from Google Drive without storing Google Drive credentials in the app.

## Build

```sh
cd NextJob
brew install xcodegen
xcodegen generate
xcodebuild -project NextJob.xcodeproj -scheme NextJob -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow applies all checked-in migrations, validates every Swift source file, builds the optimised unsigned iPhone app and packages `NextJob-1.0.6.tipa`, its checksum and the transformed source archive.
