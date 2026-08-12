# Next Solution content automation

This directory contains the safe, metadata-only foundation for monitoring iOS
jailbreak repositories. The first workflow is intentionally a dry run: it reads
APT `Packages` indexes, produces a report artifact, and cannot modify the live
website.

The second workflow runs once per day and can generate one draft bundle from a
new eligible release or, when that queue is empty, one undrafted package from
the verified-source evergreen catalog. It uses the OpenAI Responses API only when
`OPENAI_API_KEY` exists as an encrypted repository secret. The model produces
strict structured text; trusted Python code escapes and renders the HTML. A
second model call and deterministic quality gates must both approve the draft.
If either rejects the first result, one bounded corrective rewrite receives the
exact rejection reasons and must pass the same deterministic gates plus a fresh
independent verification. A second failure stops the run rather than weakening
the checks or spending through an unbounded retry loop.
The bundle remains a GitHub Actions artifact and is never published by this
workflow.

## Safety and editorial rules

- Never download, unpack, mirror, or execute third-party `.deb` files.
- Only a `verified` source can produce a future publication candidate.
- `observe` sources appear in health reports but always require a provenance
  decision before publication. `excluded` sources are not fetched.
- Conflicting SHA-256 values, a changed binary under an unchanged version,
  incomplete factual metadata, and piracy/game-cheat language block a candidate.
- A future writer must use only feed facts and linked developer/marketplace
  information. It must not invent compatibility, testing results, rankings, or
  personal experience.
- Automatic publishing will be limited to one substantial article per day, with
  version updates applied to an existing URL instead of creating near-duplicates.
- ShrinkMe may only be offered as a clearly labelled, optional ad-supported link.
  The official source/developer page must remain available directly.
- No automated clicks, impressions, views, subscriptions, watch time, or other
  fake engagement are permitted.
- A release is marked drafted only after the article, SEO metadata, discovery
  fragments and 8–12 minute video-script bundle pass every gate. This prevents
  repeated API spending on the same version.
- Draft markers are shared between the new-release queue and evergreen catalog,
  so architecture variants and later scans cannot repeat the same version.

## Run locally

```bash
python3 -m unittest discover -s automation/tests -v
python3 -m automation.scanner --require-verified 0
python3 -m automation.scanner --only chariz,nextsolution --tiers verified
python3 -m automation.draft_pipeline \
  --state automation/tests/fixtures/editorial-state.json \
  --fixture-article automation/tests/fixtures/article-draft.json
```

Reports are written to `automation/out/` and ignored by Git. The committed state
file remains unchanged unless `--write-state` is explicitly supplied. The
scheduled workflow stores runtime state in a GitHub Actions cache, not in the
repository. Every source is baselined on its first successful scan so historical
catalog entries—or entries from a source recovering later—cannot be mistaken for
new releases.

## Rollout gates

1. **Dry-run scanner (current):** verify source health, parsing, deduplication,
   change detection, and safety blockers.
2. **Baseline:** approve the source report once and save the current package
   snapshot so only future releases are treated as new.
3. **Draft writer:** use the OpenAI API to create a factual HTML draft and quality
   report; do not publish it yet.
4. **Limited publisher:** publish at most one qualified article per day, update
   navigation/RSS/sitemap, and keep an audit log plus an automatic kill switch.
5. **Video assist:** create a script and asset bundle for original videos. Uploads
   stay private until the channel workflow and YouTube policy review are proven.
