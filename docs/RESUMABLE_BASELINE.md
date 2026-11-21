# Cooling and background continuation

The continuation update keeps the pinned MOVD models, Float32 execution, tensor shapes, guidance, and 21-evaluation schedule. It changes how work waits and recovers. It is not a measured inference speed optimization.

## Cooling

At model-operation boundaries, serious or critical thermal state enters an asynchronous wait. The UI shows that the job is cooling; no alert discards the generation. Execution resumes only at nominal thermal state, preventing repeated restart at fair. The loaded Core ML partition is released before a post-prediction wait. In-memory intermediates remain available, so the current operation sequence continues after cooling. Cancellation and memory checks remain enabled. A synchronous Core ML prediction already in progress cannot be interrupted immediately.

## Recovery

The 2-second baseline writes exact Float32 latent and prompt-encoding tensors after each completed motion step, plus an initial state after text encoding. A binary property-list envelope, SHA-256, shape checks, request checks, model revision, and configuration version protect restoration. Atomic replacement keeps the prior checkpoint until a new one is written. Checkpoint storage is local and excluded from backups.

If iOS terminates the process or its background task, reopen Setup and use **Resume saved baseline**. An unfinished motion step may repeat. If decoding was interrupted, the saved final latent allows decoding to restart without repeating diffusion. Before the first checkpoint, text encoding restarts. A successfully exported baseline clears its recovery files. Manual pause retains them; explicit discard removes them after a confirmation. Prior journals remain exportable.

The old build 10 run cannot be resumed retroactively: its diagnostic journal contains timing and memory data, not the tensors required for continuation. One new baseline must start with this update.

## Background execution

On iOS 26 or later, a build made with the corresponding SDK registers a continued-processing handler at app launch. A user-started generation checks `BGTaskScheduler.supportedResources` for `.gpu`, requests that resource, and uses the Background GPU Access entitlement. Work begins in the handler once the system grants execution. Requests use the immediate-or-fail strategy; a submission failure, unsupported device, or missing callback falls back to foreground execution. The app reports truthful progress in the system's task UI, including cooling pauses.

On switching apps without a grant, work waits at the next model boundary and continues on returning. iOS can still suspend or terminate the process, end a granted task, or cancel it from the system progress UI. Expiration cancels further work and retains the latest completed-step checkpoint. Force-quitting never guarantees continued execution. A grant is logged but is not by itself evidence of successful background completion.

Apple documents [continued processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados), the [GPU entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.gpu), and the [runtime resource check](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/supportedresources). The current Mac's older SDK exercises the foreground fallback; Cloud builds compile the new API path. Actual GPU eligibility and background survival must be measured on the iPhone.

## Measurement

Journals record pause start/end/reason changes, checkpoint writes/restores, foreground/background transitions, background request/grant/failure/expiration, and per-partition timings. A resumed session has the same baseline job ID and links its preceding journal. Session wall time includes cooling and checkpoint I/O; it must not be presented as an uninterrupted complete-generation time. The report parser labels resumed segments explicitly. Existing app metrics remain readable; new metrics additionally identify paused seconds and the restored step.

Local validation: 17 unit tests and 2 UI tests pass; 5 report-parser tests pass. These checks establish control and persistence behavior with fixtures, not physical-device diffusion quality or background GPU execution. Cloud and physical follow-up results are recorded in `VALIDATION.md`.
