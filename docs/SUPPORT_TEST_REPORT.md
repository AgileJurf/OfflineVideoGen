# Optional connected support — implementation and acceptance

Date: 21 November 2026. This report covers software verification, not a new physical-device performance benchmark. The earlier successful local video generation satisfied the prerequisite for backend implementation. Private device evidence remains outside this public repository.

## Implemented

- Separate Vercel service in `support/`: versioned static configuration and model manifest, plus bounded, consent-gated diagnostic intake into private Blob storage with a 30-day expiration.
- Optional iOS support screen; disabled by default. Enabling the setting alone makes no request. Catalog checks and individual report uploads are manual and Wi-Fi only.
- Validated, atomic local configuration cache with bundled fallback. Existing local inference never waits for support connectivity. Invalid, incompatible or older configuration cannot replace a valid cache.
- Manifest contains minimum app version, model revision, versions, URLs, exact byte lengths, SHA-256 hashes and partition inventory. Remote manifests cannot change the app-pinned weights or unvalidated inference settings.
- Installation keeps URLSession resume data, verifies length and SHA-256, stages compiled models, and retains a previous installation for explicit rollback. Switching a source URL invalidates incompatible resume data.
- Reports show their exact payload before per-report consent. The app and server allowlist only structured versions, timing, sampled memory, thermal state, partition counts and typed errors. Prompts, seeds, videos, identifiers, raw journals and arbitrary error strings are excluded. No automatic report queue or retry.
- Original model, 21-evaluation sampler, decoder compute policy, duration controls, local library, export, baseline recovery and style/crop features remain in place. No optimized weights or new performance preset is enabled.

## Verification

| Check | Result |
| --- | --- |
| Local Xcode 16.4 / iOS 18.4 simulator | 43 unit tests and 5 UI tests passed; `LocalFrames-SupportRegression2.xcresult` |
| Backend Node 24.22.3 local runner | 10 tests passed; deployment targets Node 22 |
| Privacy serialization / server validation | Unknown fields, arbitrary strings, malformed values, absent consent and oversized reports rejected |
| Offline cache behavior | Relaunch and toggle cause no requests; failed refresh retains valid cache |
| Inference compatibility | Changed hashes, inventory, hosts, unsupported minimum app version and unapproved step count rejected |
| Model rollback | Filesystem fixture activates candidate while preserving original, then restores original |
| Report concurrency / retention | Mocked create-only storage allows one report per two-hour slot; verifies provider expiration metadata |
| Live Vercel service | Pending deployment and synthetic endpoint verification |
| Xcode Cloud / TestFlight | Pending this source revision |
| Physical iPhone support and Airplane Mode regression | Pending installation of the new build; simulator tests are not physical-device validation |

The first UI pass failed because the test tapped the label instead of the native switch. The corrected test taps the switch and asserts its value before checking the enabled state; the complete suite then passed. A general final error no longer replaces a more specific Core ML partition failure in the report.

## Acceptance still required

Verify the deployed manifest against the bundled model, reject a POST without consent, reject unknown fields, store one synthetic report privately with expiration, and reject a second report in the same slot. Do not upload real device evidence for these tests.

On the iPhone, check the catalog over Wi-Fi, relaunch with Airplane Mode enabled, and complete the fixed two-second baseline with the installed model. Review a diagnostic payload and send it only by explicit choice. A fresh full model transfer, interruption/resume, and staged model replacement require separate physical acceptance; no new host or replacement weights are offered in this release.

## Performance and limits

No inference speed, memory or video-quality improvement is claimed. The service supports diagnosing bottlenecks and distributing future models/settings after physical validation. It cannot add compute capacity to offline inference. The next optimization remains a measured model/sampler experiment against the preserved baseline, not a remote setting guessed to be faster.

Hobby hosting and Blob quotas are shared with the account's other projects. The service caps stored payloads, does not proxy model files, and tolerates quota exhaustion. See [deployment, retention, free-tier and Hugging Face details](../support/README.md). Exact T5 redistribution provenance remains unresolved, so the existing source URLs are retained and no Hugging Face mirror is published.
