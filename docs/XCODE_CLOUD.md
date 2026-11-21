# Xcode Cloud

The public source repository is [AgileJurf/OfflineVideoGen](https://github.com/AgileJurf/OfflineVideoGen). The shared scheme is **LocalFrames**, the project is **LocalFrames.xcodeproj**, and the app bundle ID is **com.agilejurf.localframes**.

## Configured workflow

**Build and Test** is connected to this repository and App Store Connect's LocalFrames product. It runs a required **Test — iOS** action on an iPhone 17 Pro Max simulator and a required **Analyze — iOS** action for Any iOS Device. The environment follows the latest stable Xcode release (27.2 at setup). Pushes to `main` trigger builds; changes confined to Markdown documentation are excluded. No TestFlight post-action is enabled.

[View builds in App Store Connect](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/groups) (developer-account access required).

**Initial validation completed:** Build 2 passed Test — iOS and Analyze — iOS on source revision `3326475`. Both runs were started manually; the `main` push condition and Markdown exclusion are configured, but automatic triggering has not yet been demonstrated. See the [validation record](VALIDATION.md) for the exact tested revision and remaining real-model gates.

## First workflow

Apple's [first-workflow instructions](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow) start in Xcode. Browser sign-in to Apple Developer or App Store Connect does not configure Xcode's Accounts settings.

1. Sign in to the enrolled Apple Developer account in Xcode → Settings → Accounts.
2. Select that team under Signing & Capabilities for LocalFrames, LocalFramesTests, and LocalFramesUITests. Automatic signing is already enabled.
3. Commit and push the project, shared scheme, and package lockfile.
4. Choose Product/Integrate → Xcode Cloud → Create Workflow. Authorize the new repository and create or select this app's App Store Connect product.
5. Configure a **Test** action for the LocalFrames scheme on an available iPhone simulator. Use the current stable Xcode environment. Add an **Analyze** action if desired. Run on changes to `main`.
6. Start the workflow and inspect both build-for-testing and test results in App Store Connect. Do not treat a queued run or successful build-only action as passing tests.

The `ci_post_clone.sh` hook verifies required project resources. Ordinary cloud builds do not download 14.1 GB of weights or attempt full diffusion. Test fixtures are bundled or generated at runtime, since Xcode Cloud's test phase is separate from its source checkout.

No TestFlight distribution or App Store submission is configured by this document. A distribution workflow can follow once signing, app behavior, licensing, and real-device inference are validated.

## What cloud tests establish

They cover compilation and application/supporting-code behavior on Apple's hosted simulator. They cannot prove iPhone GPU or Neural Engine performance, available memory, battery use, or thermal behavior. See the [validation gates](VALIDATION.md).
