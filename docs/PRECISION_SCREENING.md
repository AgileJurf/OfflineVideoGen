# Precision screening — synthetic Mac partition tests

These results screen copied model partitions on an Intel Mac with macOS 15.8.3, coremltools 8.3.0 and NumPy 2.5.5. They do not measure iPhone latency, memory or video quality. The app still installs and executes the original weights. T5 is unchanged.

The predeclared numerical screen requires identical input/output contracts, matching output shape, finite output and relative L2 error at most 1% against the original Float32 partition. This is a rejection screen, not a quality acceptance criterion.

| Partition / candidate | Original bytes | Candidate bytes | Relative L2 error | Result |
| --- | ---: | ---: | ---: | --- |
| VAE spatial 3_1 / FP16 | 66,139,710 | 33,092,266 | 0.00122827 (0.122827%) | Passed this single-input screen |
| VAE spatial 3_1 / mixed | 66,139,710 | 33,107,062 | 0.000608226 (0.060823%) | Passed this single-input screen |
| VAE spatial 3_1 / INT8 weights | 66,139,710 | 16,610,082 | 0.0304919 (3.04919%) | Rejected: exceeds 1% threshold |
| STDiT ST_0 / FP16 | 170,108,047 | 85,088,698 | Not evaluated | Converted only; not executed |
| STDiT ST_0 / mixed | 170,108,047 | 85,130,470 | Not evaluated | Converted only; not executed |

Mixed precision converts only convolution/linear/matmul operations, retaining other operations in Float32. INT8 compresses selected weights while keeping Float32 computation; it is not an INT8 activation pipeline. All five candidates preserve declared I/O contracts and original package tree hashes. The VAE tests produced finite `[4, 512, 64, 64]` outputs. Their synthetic input SHA-256 was `7d7c6b6173d088036575d47bdf6a862d4982f68f96bf74c9b6e842466db6e7f4`.

Use `scripts/probe_precision_candidate.py` and the commands in [OPTIMIZATION_PHASE2.md](OPTIMIZATION_PHASE2.md) to reproduce the probes. Reports and candidate copies are retained under the ignored `build/PrecisionProbes/` directory. The probe uses an internal MIL reader pinned to coremltools 8.3.0; this is experimental conversion tooling, not a production installer. An initial FP16 attempt that changed flexible I/O constraints was rejected and retained before the corrected candidates were screened.

Candidate load/prediction timings were captured, but cache state was uncontrolled and probes overlapped. They are not used to claim acceleration. Process lifetime RSS is not equivalent to a matched inference peak. Package-size reduction is the only storage improvement measured here; complete-model compiled size and phone memory effects are unknown.

Next: run mixed and FP16 candidates across representative intermediate tensors, then a complete copied decoder chain and full transformer chain. Preserve finite-value checks and assess error accumulation. Only after reference correctness is established should an explicitly optional device candidate be prepared. Compare fresh fixed-prompt/seed generations on the iPhone before promoting a precision preset. Do not deploy the INT8 candidate that failed this screen.
