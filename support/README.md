# Local Frames model catalog

Static, optional metadata only. The current app uses its bundled, SHA-256-pinned Neodragon manifest and downloads directly from the distribution host. Once installed, generation and styles work offline. This service cannot change the model's inference settings remotely.

`npm test` checks that the catalog's model manifest exactly matches the app. `npm run build` produces static versioned JSON in `public/api/`. No model weights, runtime functions, diagnostics uploader, account authentication, GPU, paid API or database client are included. The retired upload endpoint is absent. Previously stored private reports are not read, published or deleted by this project update.

Reuse the existing Vercel Hobby project. A preview is not a production deployment. Verify the final production catalog and the old endpoint's absence before reporting retirement deployed. No plan changes or paid resources are permitted. Static requests still count toward the host's existing usage allowance; inspect usage before deployment. Full model bandwidth goes to the distribution host, not Vercel.
