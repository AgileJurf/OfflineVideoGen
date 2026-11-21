# LOCAL FRAMES optional support service

This service distributes small versioned configuration/manifest JSON documents and accepts explicitly consented, structured diagnostic reports. It never performs inference, receives prompts/videos, or proxies the 14.1 GB model download. Installed generation does not depend on its availability.

## Deploy

Use the existing **agilejurf Hobby** team, a separate **localframes-support** project, repository `AgileJurf/OfflineVideoGen`, root directory `support`, framework Other, Node 22, build `npm run build`, output `public`. Keep paid upgrades, trials, marketplace integrations, analytics and paid compute disabled. The deployment contains no model weights or private device evidence.

`npm ci --ignore-scripts`, `npm test` and `npm run build` validate/build the service. `package-lock.json` pins the dependency tree. The public endpoints are:

- `GET /api/v1/config.json`: schema/configuration version, compatible models and locally approved inference profiles.
- `GET /api/v1/models/movd-v1.json`: manifest/model version, minimum compatible app version, model revision, archive sizes, immutable SHA-256 values, source URLs and partition inventory.
- `POST /api/v1/diagnostics`: JSON only, 32 KiB maximum, exact allowlisted keys and enum values, explicit `X-LocalFrames-Consent: report-v1`. No CORS allowance or public read endpoint.

Diagnostics fail closed unless `DIAGNOSTICS_ENABLED=true` and the project has a **private** Blob store connected through the server-only `BLOB_READ_WRITE_TOKEN`. Never copy that token into iOS, public files, Git or screenshots. Connecting a store grants the project access to that store; keep it separate from other apps. The token is not needed for public catalog requests.

## Free usage and retention

Vercel documents Hobby as personal/noncommercial, capped rather than automatically billed on overage. Its current allowances include 100 GB fast transfer, one million function invocations, four active CPU hours and 360 GB-hours of function memory. Check the account because allowances are shared with existing projects. This service uses static files for catalog checks; only report intake invokes a 10-second function. [Hobby terms and limits](https://vercel.com/docs/plans/hobby).

Blob's Hobby allowance is 1 GB-month, 2,000 advanced operations, 10,000 simple operations and 10 GB transfer. Overages disable Blob access without additional charges. One global create-only slot per two hours allows at most 372 stored reports in 31 days, or about 12 MiB of payload. Each accepted upload plus its TTL uses two advanced operations, and expiry verification uses a metadata read. Failed attempts and dashboard activity also consume quota, so the slot cap is not a guarantee against quota exhaustion. Clients handle 429/503 without automatic retries or background queues. Keep Hobby; switching to Pro would change the billing behavior. [Blob pricing](https://vercel.com/docs/vercel-blob/usage-and-pricing).

Every report uses `access: private`, `allowOverwrite: false`, `addRandomSuffix: false` and `ttlDays: 30`. A separate `head()` request verifies persisted expiration. Expiration is rounded to UTC midnight and deletion is processed daily; allow about 32 days. A successful response exposes no storage URL. No report body or request headers are logged by application code. Hosting still processes request metadata such as IP addresses. [TTL API](https://vercel.com/docs/vercel-blob/using-blob-sdk#expire-blobs-automatically).

## App behavior and model updates

Online support defaults off. Enabling it alone makes no request. The user chooses a manual Wi-Fi catalog check or reviews and consents to one diagnostic report. The app keeps an atomically written, validated config+manifest snapshot. Failed, malformed, oversized, redirected, incompatible or older catalog responses retain the last valid snapshot. Relaunch and generation do not contact this service.

The manifest can relocate the approved archives to an immutable Hugging Face revision, but cannot replace their app-pinned hashes, sizes or partition inventory. New weights require an app compatibility update and physical validation before publication. Configuration cannot alter current sampler arithmetic, precision or saved generation settings. Only the original 21-evaluation profile is listed; its reference duration is two seconds. Existing 2–5-second controls remain unchanged. There is no advertised speed/quality improvement.

Installation is explicit, resumable and length/SHA-256 verified before extraction. New compiled files are staged before activation; replacing an existing installation retains `RollbackInstalled`. Another replacement cannot overwrite that rollback copy. The app can restore a compatible previous model. Local video storage and diffusion checkpoints are independent of support caching.

## Hugging Face investigation

Public Hub storage is best-effort, not guaranteed unlimited hosting; larger public repositories should provide community value. Current guidance recommends files under 200 GB, so the existing three archives fit, but distribution acceptance and end-to-end resume reliability still need host-specific tests. [Storage policy](https://huggingface.co/docs/hub/en/storage-limits).

Resolver rate limits are documented per five-minute window, with 3,000 anonymous-IP and 5,000 free-account requests; limits may change. A complete current model transfer is 14,133,836,614 bytes before retries. Do not embed a developer Hub token in the app, assume unlimited bandwidth, or use mutable `main` URLs for a mirror. [Rate limits](https://huggingface.co/docs/hub/en/rate-limits).

This deployment retains the original working source URLs and hashes; no mirror has been uploaded. STDiT-v3 and VAE model cards declare Apache-2.0, but the referenced DeepFloyd T5 repository has no model card or displayed license. The exact encoder/tokenizer and converted-weight redistribution provenance must be resolved before republishing the entire bundle. This does not block the support API or existing direct-source installer. [T5 source](https://huggingface.co/DeepFloyd/t5-v1_1-xxl), [existing notices](../docs/THIRD_PARTY_NOTICES.md).

## Operational verification

Use only synthetic, nonpersonal fixtures for deployment tests. Verify static manifest equality with the bundled hashes; POST without consent must fail; unknown fields must fail; one valid synthetic report must store privately with TTL; a second in the same slot must return 429. Do not upload real device reports on the user's behalf without explicit report-specific consent. Public deployment endpoints are independent from the app's offline generation tests.

Production is live at [localframes-support.vercel.app](https://localframes-support.vercel.app). All nine acceptance checks passed on 21 November 2026. Run `node scripts/verify-deployment.mjs` for the non-storage checks; add `--store-synthetic` only when intentionally reserving the current two-hour slot with fabricated data. See [acceptance report](../docs/SUPPORT_TEST_REPORT.md).

The existing deployment uses Vercel's Active CPU configuration, which ignores the legacy `memory` value in `vercel.json`. Do not interpret that field as a measured or enforced 1 GB process limit. The ten-second function limit and request-body cap are separate controls.
