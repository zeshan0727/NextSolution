# Final Publication Checklist

## Gate A — Product approval

- [ ] App name, icon, colours, wording and all eight service descriptions approved by KBA.
- [ ] UK, USA, UAE and Qatar office contacts verified directly by KBA.
- [ ] Required customer fields and service request workflow approved.
- [ ] Client status stages and response-time expectations approved.

## Gate B — Secure backend

- [ ] Customer authentication implemented.
- [ ] Email/phone verification and account recovery implemented.
- [ ] Requests sent through authenticated TLS APIs.
- [ ] Documents encrypted in transit and at rest.
- [ ] File type, size, malware and access controls implemented server-side.
- [ ] Status updates come from the KBA backend.
- [ ] Audit logging, retention and deletion procedures approved.
- [ ] Production and testing environments are separated.

## Gate C — Privacy and legal

- [ ] Final privacy policy URL exists and matches actual app data processing.
- [ ] Terms of service approved.
- [ ] Data controller, processor and regional retention responsibilities documented.
- [ ] App privacy disclosures completed accurately.
- [ ] Tax/accounting disclaimer and professional engagement wording approved.
- [ ] User consent and account deletion flows implemented.

## Gate D — Quality verification

- [ ] Every item in `QA_TEST_PLAN.md` passed on iOS 16, 17, 18 and current iOS.
- [ ] Clean install, upgrade install and data migration tested.
- [ ] Slow network, offline, expired session and server error states tested.
- [ ] Accessibility review completed.
- [ ] Crash and performance review completed.
- [ ] No placeholder, demo or personal data remains.
- [ ] Local test banner is removed only after live backend verification.

## Gate E — Distribution

- [ ] Final bundle identifier and Apple team selected.
- [ ] Production signing, entitlements and capabilities reviewed.
- [ ] App Store screenshots, description, keywords, support URL and privacy URL approved.
- [ ] TestFlight internal and external testing completed.
- [ ] Final release candidate checksum recorded.
- [ ] KBA provides explicit approval to publish the verified release candidate.
