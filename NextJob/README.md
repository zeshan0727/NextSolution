# Next Job

Next Job is a private iOS 16+ job tracker built for part-time accounting work received from KB Accountants.

## Included in 1.0.1

- Jobs with assigned date, due date, completion date, status, job type, targeted time, actual time and price
- Dashboard for not started, in progress, waiting for documents, completed and overdue work
- Stable multi-file selection with background copying and a visible import-progress state
- Complete folder import with internal folder structure preserved
- Related-document and completed-work storage inside the app's Documents folder
- Document-request email composer
- Native ZIP package creation for each job, including a job summary and all uploaded files or folders
- Completion email composer with the ZIP attached
- Search, filters, custom job types, local deadline notifications and light/dark/system themes
- JSON backup for job records and settings

## Email behavior

iOS requires the user to review and tap **Send** in the Mail composer. Next Job prepares the recipient, subject, message and ZIP attachment automatically, but it does not silently send email.

## Build

```sh
cd NextJob
brew install xcodegen
xcodegen generate
xcodebuild -project NextJob.xcodeproj -scheme NextJob -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow applies the checked-in 1.0.1 interface patch, builds the unsigned app and packages it as a TrollStore `.tipa`.
