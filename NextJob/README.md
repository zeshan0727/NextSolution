# Next Job

Next Job is a private iOS 16+ job tracker built for part-time accounting work received from KB Accountants.

## Included in 1.0.2

- Jobs with assigned date, due date, completion date, status, job type, targeted time, actual time and price
- Create missing job types directly from the New Job form
- Dashboard for not started, in progress, waiting for documents, completed and overdue work
- Stable multi-file import and a separate validated complete-folder import
- Folder trees are copied as one attachment and cannot be mixed with surrounding Files items
- Related files and completion documents stored against the correct job
- Completion ZIP names begin with the company name and `Completion Documents`
- Dedicated Email tab with Gmail Direct and Apple Mail Assisted modes
- Gmail OAuth and direct email delivery through the same scheduler architecture used by Next Reminder
- Dedicated AI tab using OpenAI to craft editable emails from the selected job status and details
- One portable `.nextjobbackup` file containing all jobs, settings, files and imported folders
- Google Drive backup/restore through the iOS Files provider, with staged validation and rollback
- Search, filters, custom job types, local deadline notifications and light/dark/system themes
- Background persistence, cached summaries and optimized Release compilation

## Email behavior

Gmail Direct sends through a connected scheduler/Gmail OAuth account. Apple Mail Assisted opens the native Mail composer for review before sending. Direct Gmail attachments are limited to 10 MB each and 18 MB total; Apple Mail can be used for larger packages.

## Google Drive behavior

Install and sign in to the Google Drive iOS app, then enable Google Drive under **Files → Browse → … → Edit**. Next Job uses the iOS document provider so the complete backup can be saved to and restored from Google Drive without storing Google Drive credentials in the app.

## Build

```sh
cd NextJob
brew install xcodegen
xcodegen generate
xcodebuild -project NextJob.xcodeproj -scheme NextJob -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow applies the checked-in source migrations, validates all Swift source, builds the optimized unsigned app and packages `NextJob-1.0.2.tipa`, its checksum and the transformed source archive.
