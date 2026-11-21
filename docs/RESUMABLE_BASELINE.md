# Cooling and background continuation

The continuation update keeps the pinned MOVD models, Float32 execution, tensor shapes, guidance, and 21-evaluation schedule. It changes how work waits and recovers. It is not a measured inference speed optimization.

## Cooling

At model-operation boundaries, serious or critical thermal state enters an asynchronous wait. The UI shows that the job is cooling; no alert discards the generation. Execution resumes only at nominal thermal state, preventing repeated restart at fair. The loaded Core ML partition is released before a post-prediction wait. In-memory intermediates remain available, so the current operation sequence continues after cooling. Cancellation and memory checks remain enabled. A synchronous Core ML prediction already in progress cannot be interrupted immediately.

## Recovery

The 2-second baseline writes exact Float32 latent and prompt-encoding tensors after each completed motion step, plus an initial state after text encoding. A binary property-list envelope, SHA-256, shape checks, request checks, model revision, and configuration version protect restoration. Atomic replacement keeps the prior checkpoint until a new one is written. Checkpoint storage is local and excluded from backups.

If iOS terminates the process or its background task, reopen Setup and use **Resume saved baseline**. An unfinished motion step may repeat. If decoding was interrupted, the saved final latent allows decoding to restart without repeating diffusion. Before the first checkpoint, text encoding restarts. A successfully exported baseline clears its recovery files. Manual pause retains them; explicit discard removes them after a confirmation. Prior journals remain exportable.

The old build 10 run cannot be resumed retroactively: its diagnostic journal contains timing and memory data, not the tensors required for continuation. One new baseline must start with this update.

### Spatial decoder compatibility policies

The `spatial-attention-cpu-v1` policy requests CPU-only execution for `vae_spatial_part2`, the Float32 spatial-attention partition. All other partition policies, weights, tensor shapes, diffusion steps and guidance remain unchanged. The model revision and checkpoint configuration are intentionally retained: an existing completed step-21 checkpoint can restart decoding directly after an app update. Update the existing installation and choose **Resume saved baseline**; deleting the app or discarding the saved baseline removes recovery data.

The subsequent `spatial-cpu-v2` candidate runs all nine spatial VAE partitions on CPU. Text encoding, transformer execution, temporal decoder placement, precision, weights, shapes, guidance and diffusion steps retain their existing settings. Checkpoint compatibility is unchanged. The full spatial chain is exercised locally with deterministic synthetic input before device validation; this does not establish physical-phone completion, performance or prompt adherence.

Spatial input and each partition output are checked for non-finite values before being passed onward. The check reads the strided buffer without creating a full scalar copy. Journals record shape, strides, finite/zero counts, range and validation duration, plus Core ML input layouts. Tensor contents are not uploaded or added to the public repository. Invalid values produce a recoverable failure and preserve the saved baseline. Finite output alone does not establish visual quality; an all-zero result is recorded rather than presented as a quality pass.

Decoder policy is recorded separately in journals and completed-video metadata. Its change invalidates previous timing-cache estimates so they can be learned again. Frame-append and video-finalization events distinguish decoder interruption from export failure. This is a compatibility candidate requiring physical validation, not a measured speed improvement or confirmed end-to-end fix. The original build-14 source remains the rollback reference.

## Background execution

On iOS 26 or later, a build made with the corresponding SDK registers a continued-processing handler at app launch. A user-started generation checks `BGTaskScheduler.supportedResources` for `.gpu`, requests that resource, and uses the Background GPU Access entitlement. Work begins in the handler once the system grants execution. Requests use the immediate-or-fail strategy; a submission failure, unsupported device, or missing callback falls back to foreground execution. The app reports truthful progress in the system's task UI, including cooling pauses.

On switching apps without a grant, work waits at the next model boundary and continues on returning. iOS can still suspend or terminate the process, end a granted task, or cancel it from the system progress UI. Expiration cancels further work and retains the latest completed-step checkpoint. Force-quitting never guarantees continued execution. A grant is logged but is not by itself evidence of successful background completion.

Apple documents [continued processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados), the [GPU entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.gpu), and the [runtime resource check](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/supportedresources). The current Mac's older SDK exercises the foreground fallback; Cloud builds compile the new API path. Actual GPU eligibility and background survival must be measured on the iPhone.

## Measurement

Journals record pause start/end/reason changes, checkpoint writes/restores, foreground/background transitions, background request/grant/failure/expiration, and per-partition timings. A resumed session has the same baseline job ID and links its preceding journal. Session wall time includes cooling and checkpoint I/O; it must not be presented as an uninterrupted complete-generation time. The report parser labels resumed segments explicitly. Existing app metrics remain readable; new metrics additionally identify paused seconds and the restored step.

## Remaining-time indicator

The indicator learns load-plus-prediction timings locally for each partition, weights recent samples more heavily, and counts the operations remaining in the actual schedule, including restored steps and requested output frames. It may estimate unobserved blocks only within the same transformer family after at least three distinct block observations. It never substitutes transformer timing for unmeasured decoder work. Until every remaining phase has usable timing, it labels a current-phase estimate and says the total finish time is still being estimated. Later runs can use the local timing cache for a full-job estimate. No device-specific timing constants are shipped in source.

The UI and system task progress display approximate minutes. Cooling and foreground waits pause the displayed estimate. Saving and future waits can add time; estimates are not measured generation results. The cache is local, contains model names and timings rather than prompts, and is not included in benchmark exports.

Cache compatibility includes the model, diffusion configuration, decoder execution policy and OS version; timings from a different policy are not reused.

Local validation initially passed 17 unit tests and 2 UI tests plus 5 report-parser tests. ETA tests additionally check partial-versus-full estimates, timing-cache reuse, restored-step accounting, adaptation to slower operations, and cooling labels. These checks establish control and persistence behavior with fixtures, not physical-device diffusion quality or background GPU execution. Cloud and physical follow-up results are recorded in `VALIDATION.md`.
