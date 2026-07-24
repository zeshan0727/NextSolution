# Next Job

Next Job is a private iOS 16+ job tracker built for part-time accounting work received from KB Accountants.

## Included in 1.0.4

- Jobs with assigned date, due date, completion date, status, job type, targeted time, actual time and price
- Create missing job types directly from the New Job or Edit Job form
- Job Types management removed from Settings
- Dashboard for not started, in progress, waiting for documents, completed and overdue work
- Dedicated Pending Payments section and Jobs filter for completed work not marked received
- Stable multi-file import and a separate validated complete-folder import
- Folder trees are copied as one attachment and cannot be mixed with surrounding Files items
- Related files and completion documents stored against the correct job
- Completion ZIP names begin with the company name and `Completion Documents`
- Professional completion emails include the exact recorded completion date/time, job notes and completion notes
- Payment Pending and Payment Received tracking for completed jobs
- Standard numbered PDF invoice generation for pending payments
- Dedicated Email tab with Gmail Direct and Apple Mail Assisted modes
- Gmail stale-connector recovery ported from Next Reminder 1.2.4
- Reconnect Gmail, disconnect, and local Forget Saved Connection actions
- Connector-not-found errors automatically clear the obsolete local connector
- Dedicated AI tab using the OpenAI Responses API to craft editable emails from the selected job status and details
- Explicit handling for incomplete responses, refusals, API errors and token-usage reporting
- Recommended complimentary-token-eligible GPT-5 and GPT-4.1 model snapshots
- One portable `.nextjobbackup` file containing all jobs, payment records, invoice metadata, settings, files and imported folders
- Google Drive backup/restore through the iOS Files provider, with staged validation and rollback
- Background persistence, cached summaries and optimized Release compilation

## Gmail recovery behavior

If the scheduler was restarted, redeployed, or lost its connector database, an older connector ID may no longer exist. Next Job detects `Gmail connector not found`, clears the false connected state, and asks for a fresh connection. Email Setup also provides Reconnect Gmail Account and Forget Saved Connection so the app cannot remain trapped in an obsolete connection.

## Email behavior

Gmail Direct sends through a connected scheduler/Gmail OAuth account. Apple Mail Assisted opens the native Mail composer for review before sending. Direct Gmail attachments are limited to 10 MB each and 18 MB total; Apple Mail can be used for larger packages.

## OpenAI behavior

The app uses the Responses API with structured output, a larger output allowance, low reasoning effort for GPT-5 models, clear incomplete/refusal errors and visible token usage. Complimentary tokens depend on OpenAI account eligibility, enabled input/output data sharing and a positive API balance; the models are not universally free.

## Google Drive behavior

Install and sign in to the Google Drive iOS app, then enable Google Drive under **Files → Browse → … → Edit**. Next Job uses the iOS document provider so the complete backup can be saved to and restored from Google Drive without storing Google Drive credentials in the app.

## Build

```sh
cd NextJob
brew install xcodegen
xcodegen generate
xcodebuild -project NextJob.xcodeproj -scheme NextJob -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow applies the checked-in source migrations, validates all Swift source, builds the optimized unsigned app and packages `NextJob-1.0.4.tipa`, its checksum and the transformed source archive.
