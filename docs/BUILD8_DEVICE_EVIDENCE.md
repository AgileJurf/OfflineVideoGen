# Local Frames device benchmark report

This report describes supplied measurements only. Incomplete or simulator runs do not establish physical-device feasibility.

GPU utilization and observed Neural Engine placement require an Instruments trace. Compute-plan records are estimates. Memory samples can miss short-lived peaks; the OS lifetime high-water mark includes earlier activity in the same process. CPU percentages use process CPU time, can exceed 100% across cores, and exclude separate Core ML service processes. All timings include instrumentation effects.

## 1-generation-52A232F6-5FEC-4F84-AE6F-6124ABE5FE15.jsonl

| Field | Observed value |
| --- | --- |
| kind | generation |
| startedAt | 2026-11-21T08:10:22Z |
| executionEnvironment | physical-device |
| hardware | iPhone18,2 |
| os | Version 27.3 (Build 24C5037i) |
| appVersion | 0.1.0 |
| appBuild | 8 |
| sourceRevision | fd113f2c1cbbd724247406c587fe1826fac90a68 |
| modelRevision | cc1839814d0e1b0cb01953831a55a557ff6682bf |
| manifestSHA256 | 6c7f5eb70c180bb9b89a0c8165bbd8b9baca5458b58d2bbe853a4a1a6c06b469 |
| configuration | baseline-fp32-stdit-vae-t5-int8 |
| prompt | A small sailboat glides across a calm lake at sunrise. |
| seed | 42 |
| schedule | 30 points; leap index 20; 21 predictions; TDTM first 10; CFG 7; latent frames 20 |
| cacheCondition | uncontrolled OS cache; record first/repeat run separately; process is not restarted automatically |
| sampleIntervalSeconds | 0.25 |
| Outcome | INCOMPLETE — no terminal event |
| Observed log span (seconds) | 14.255 |
| Sampled process footprint maximum (MiB) | 3226.3 |
| Process-lifetime footprint high-water mark (MiB) | 3226.3 |
| Lowest recorded available app memory (MiB, advisory) | Not measured |
| Recorded memory warnings | 1 |
| Mean process CPU utilization (% of one core) | 50.2 |
| Thermal states | nominal |
| GPU utilization | Not measured |
| Actual Neural Engine execution | Not measured |

Unfinished operation: **stdit3_TDTM_0 / predict**, begun at 13.715 seconds. No completion or error event was recorded for it. This locates the interruption but does not establish the OS termination reason.

Recorded memory warnings:

- 14.124 seconds: stdit3_TDTM_0 / predict; process footprint 2708.6 MiB.

Successful partition prediction coverage: **27/102**.

Exported video SHA-256 verified: **no**. Visual quality, motion consistency, and prompt adherence require inspection of that actual video.

Unreached or unsuccessful partitions: stdit3_ST_0, stdit3_ST_1, stdit3_ST_10, stdit3_ST_11, stdit3_ST_12, stdit3_ST_13, stdit3_ST_14, stdit3_ST_15, stdit3_ST_16, stdit3_ST_17, stdit3_ST_18, stdit3_ST_19, stdit3_ST_2, stdit3_ST_20, stdit3_ST_21, stdit3_ST_22, stdit3_ST_23, stdit3_ST_24, stdit3_ST_25, stdit3_ST_26, stdit3_ST_27, stdit3_ST_3, stdit3_ST_4, stdit3_ST_5, stdit3_ST_6, stdit3_ST_7, stdit3_ST_8, stdit3_ST_9, stdit3_TDTM_0, stdit3_TDTM_1, stdit3_TDTM_10, stdit3_TDTM_11, stdit3_TDTM_12, stdit3_TDTM_13, stdit3_TDTM_14, stdit3_TDTM_15, stdit3_TDTM_16, stdit3_TDTM_17, stdit3_TDTM_18, stdit3_TDTM_19, stdit3_TDTM_2, stdit3_TDTM_20, stdit3_TDTM_21, stdit3_TDTM_22, stdit3_TDTM_23, stdit3_TDTM_24, stdit3_TDTM_25, stdit3_TDTM_26, stdit3_TDTM_27, stdit3_TDTM_3, stdit3_TDTM_4, stdit3_TDTM_5, stdit3_TDTM_6, stdit3_TDTM_7, stdit3_TDTM_8, stdit3_TDTM_9, stdit3_part2, vae_spatial_part1, vae_spatial_part2, vae_spatial_part3_1, vae_spatial_part3_2, vae_spatial_part3_3, vae_spatial_part3_4_1, vae_spatial_part3_4_2, vae_spatial_part3_4_3, vae_spatial_part4, vae_temporal_part1, vae_temporal_part2_1, vae_temporal_part2_2, vae_temporal_part2_3_1, vae_temporal_part2_3_2, vae_temporal_part2_3_3, vae_temporal_part2_3_4, vae_temporal_part2_4, vae_temporal_part3.

| Partition | Loads | Load total s | Load median s | Predictions | Predict total s | Predict median s | Predict p95 s | Compile total s | Active sampled footprint MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| stdit3_ST_0 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_10 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_11 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_12 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_13 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_14 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_15 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_16 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_17 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_18 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_19 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_20 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_21 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_22 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_23 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_24 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_25 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_26 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_27 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_5 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_6 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_7 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_8 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_9 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_0 | 1 | 0.394 | 0.394 | 0 | Not measured | Not measured | Not measured | Not measured | 3226.3 |
| stdit3_TDTM_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_10 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_11 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_12 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_13 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_14 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_15 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_16 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_17 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_18 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_19 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_20 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_21 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_22 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_23 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_24 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_25 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_26 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_27 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_5 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_6 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_7 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_8 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_9 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_part1 | 1 | 0.195 | 0.195 | 1 | 0.064 | 0.064 | 0.064 | Not measured | 601.3 |
| stdit3_part2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| t5block-layer0 | 1 | 1.401 | 1.401 | 1 | 1.882 | 1.882 | 1.882 | Not measured | 833.5 |
| t5block-layer1 | 1 | 0.265 | 0.265 | 1 | 0.160 | 0.160 | 0.160 | Not measured | 979.3 |
| t5block-layer10 | 1 | 0.246 | 0.246 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 922.8 |
| t5block-layer11 | 1 | 0.245 | 0.245 | 1 | 0.108 | 0.108 | 0.108 | Not measured | 938.8 |
| t5block-layer12 | 1 | 0.242 | 0.242 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 938.8 |
| t5block-layer13 | 1 | 0.260 | 0.260 | 1 | 0.108 | 0.108 | 0.108 | Not measured | 938.8 |
| t5block-layer14 | 1 | 0.248 | 0.248 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 938.8 |
| t5block-layer15 | 1 | 0.247 | 0.247 | 1 | 0.108 | 0.108 | 0.108 | Not measured | 938.8 |
| t5block-layer16 | 1 | 0.259 | 0.259 | 1 | 0.108 | 0.108 | 0.108 | Not measured | 938.7 |
| t5block-layer17 | 1 | 0.291 | 0.291 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 938.7 |
| t5block-layer18 | 1 | 0.252 | 0.252 | 1 | 0.110 | 0.110 | 0.110 | Not measured | 938.8 |
| t5block-layer19 | 1 | 0.255 | 0.255 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 938.8 |
| t5block-layer2 | 1 | 0.260 | 0.260 | 1 | 0.110 | 0.110 | 0.110 | Not measured | 971.8 |
| t5block-layer20 | 1 | 0.268 | 0.268 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 938.8 |
| t5block-layer21 | 1 | 0.271 | 0.271 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 938.8 |
| t5block-layer22 | 1 | 0.281 | 0.281 | 1 | 0.110 | 0.110 | 0.110 | Not measured | 938.8 |
| t5block-layer23 | 1 | 0.258 | 0.258 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 938.8 |
| t5block-layer3 | 1 | 0.250 | 0.250 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 949.8 |
| t5block-layer4 | 1 | 0.256 | 0.256 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 904.3 |
| t5block-layer5 | 1 | 0.251 | 0.251 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 944.3 |
| t5block-layer6 | 1 | 0.245 | 0.245 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 944.3 |
| t5block-layer7 | 1 | 0.346 | 0.346 | 1 | 0.109 | 0.109 | 0.109 | Not measured | 944.3 |
| t5block-layer8 | 1 | 0.247 | 0.247 | 1 | 0.108 | 0.108 | 0.108 | Not measured | 944.3 |
| t5block-layer9 | 1 | 0.240 | 0.240 | 1 | 0.110 | 0.110 | 0.110 | Not measured | 944.3 |
| t5embed-tokens | 1 | 0.763 | 0.763 | 1 | 0.168 | 0.168 | 0.168 | Not measured | 589.1 |
| t5final-layer-norm | 1 | 0.015 | 0.015 | 1 | 0.001 | 0.001 | 0.001 | Not measured | 734.1 |
| vae_spatial_part1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_4_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_4_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_4_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_3_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_3_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_3_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_3_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |

Footprint values describe the whole process while that partition was active, not exclusive per-partition allocations. Prediction percentiles combine different call shapes/stages; use the raw inputShapes and begin/end events to compare like-for-like calls.

Largest observed combined load/predict totals:

- t5block-layer0: 3.283 seconds.
- t5embed-tokens: 0.930 seconds.
- t5block-layer7: 0.455 seconds.
- t5block-layer1: 0.425 seconds.
- t5block-layer17: 0.400 seconds.

## 2-installation-98DEC195-E171-4EBD-9CB0-1CDD6961F948.jsonl

| Field | Observed value |
| --- | --- |
| kind | installation |
| startedAt | 2026-11-21T08:06:22Z |
| executionEnvironment | physical-device |
| hardware | iPhone18,2 |
| os | Version 27.3 (Build 24C5037i) |
| appVersion | 0.1.0 |
| appBuild | 8 |
| sourceRevision | fd113f2c1cbbd724247406c587fe1826fac90a68 |
| modelRevision | cc1839814d0e1b0cb01953831a55a557ff6682bf |
| manifestSHA256 | 6c7f5eb70c180bb9b89a0c8165bbd8b9baca5458b58d2bbe853a4a1a6c06b469 |
| sampleIntervalSeconds | 0.25 |
| Outcome | succeeded |
| Observed log span (seconds) | 236.257 |
| Sampled process footprint maximum (MiB) | 105.1 |
| Process-lifetime footprint high-water mark (MiB) | 106.0 |
| Lowest recorded available app memory (MiB, advisory) | Not measured |
| Recorded memory warnings | 0 |
| Mean process CPU utilization (% of one core) | 59.8 |
| Thermal states | nominal |
| GPU utilization | Not measured |
| Actual Neural Engine execution | Not measured |

| Partition | Loads | Load total s | Load median s | Predictions | Predict total s | Predict median s | Predict p95 s | Compile total s | Active sampled footprint MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| STDiT-TDTM.zip | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| T5.zip | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| VAE.zip | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_0 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.054 | 105.1 |
| stdit3_ST_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.035 | 63.6 |
| stdit3_ST_10 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.035 | 63.7 |
| stdit3_ST_11 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.034 | 63.8 |
| stdit3_ST_12 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.034 | 63.8 |
| stdit3_ST_13 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.033 | 63.8 |
| stdit3_ST_14 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.034 | 63.8 |
| stdit3_ST_15 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.033 | 63.8 |
| stdit3_ST_16 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.035 | 63.8 |
| stdit3_ST_17 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.045 | 63.9 |
| stdit3_ST_18 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.041 | 63.9 |
| stdit3_ST_19 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.033 | 63.9 |
| stdit3_ST_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.034 | 63.9 |
| stdit3_ST_20 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.035 | 63.9 |
| stdit3_ST_21 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.036 | 63.9 |
| stdit3_ST_22 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.034 | 63.9 |
| stdit3_ST_23 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.034 | 63.9 |
| stdit3_ST_24 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.039 | 63.9 |
| stdit3_ST_25 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.039 | 64.0 |
| stdit3_ST_26 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.034 | 64.1 |
| stdit3_ST_27 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.035 | 64.1 |
| stdit3_ST_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.032 | 64.1 |
| stdit3_ST_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.032 | 64.2 |
| stdit3_ST_5 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.034 | 64.2 |
| stdit3_ST_6 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.033 | 64.2 |
| stdit3_ST_7 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.033 | 64.2 |
| stdit3_ST_8 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.033 | 64.2 |
| stdit3_ST_9 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.033 | 64.2 |
| stdit3_TDTM_0 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.8 |
| stdit3_TDTM_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.8 |
| stdit3_TDTM_10 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.044 | 66.8 |
| stdit3_TDTM_11 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.042 | 66.9 |
| stdit3_TDTM_12 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.9 |
| stdit3_TDTM_13 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.042 | 66.9 |
| stdit3_TDTM_14 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.8 |
| stdit3_TDTM_15 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.044 | 66.8 |
| stdit3_TDTM_16 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.8 |
| stdit3_TDTM_17 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.044 | 66.8 |
| stdit3_TDTM_18 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.9 |
| stdit3_TDTM_19 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.044 | 66.9 |
| stdit3_TDTM_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.9 |
| stdit3_TDTM_20 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.9 |
| stdit3_TDTM_21 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.044 | 66.9 |
| stdit3_TDTM_22 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 66.9 |
| stdit3_TDTM_23 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.042 | 66.9 |
| stdit3_TDTM_24 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.042 | 66.9 |
| stdit3_TDTM_25 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.042 | 66.9 |
| stdit3_TDTM_26 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 64.0 |
| stdit3_TDTM_27 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 64.0 |
| stdit3_TDTM_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.042 | 64.0 |
| stdit3_TDTM_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.042 | 64.0 |
| stdit3_TDTM_5 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 64.0 |
| stdit3_TDTM_6 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 64.0 |
| stdit3_TDTM_7 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 64.0 |
| stdit3_TDTM_8 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 64.0 |
| stdit3_TDTM_9 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.043 | 64.0 |
| stdit3_part1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.027 | 64.1 |
| stdit3_part2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.023 | 64.1 |
| t5block-layer0 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.024 | 81.4 |
| t5block-layer1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.5 |
| t5block-layer10 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 81.5 |
| t5block-layer11 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.6 |
| t5block-layer12 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 81.6 |
| t5block-layer13 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.023 | 81.6 |
| t5block-layer14 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 81.6 |
| t5block-layer15 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.6 |
| t5block-layer16 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.6 |
| t5block-layer17 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.023 | 81.6 |
| t5block-layer18 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.6 |
| t5block-layer19 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.6 |
| t5block-layer2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.023 | 81.6 |
| t5block-layer20 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.6 |
| t5block-layer21 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.6 |
| t5block-layer22 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.7 |
| t5block-layer23 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 81.7 |
| t5block-layer3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.7 |
| t5block-layer4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.7 |
| t5block-layer5 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.7 |
| t5block-layer6 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.023 | 81.7 |
| t5block-layer7 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 81.7 |
| t5block-layer8 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 81.7 |
| t5block-layer9 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 81.7 |
| t5embed-tokens | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 81.7 |
| t5final-layer-norm | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.019 | 81.7 |
| vae_spatial_part1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 37.3 |
| vae_spatial_part2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.025 | 38.0 |
| vae_spatial_part3_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.025 | 38.1 |
| vae_spatial_part3_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.025 | 38.1 |
| vae_spatial_part3_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.026 | 38.1 |
| vae_spatial_part3_4_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.021 | 38.1 |
| vae_spatial_part3_4_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.020 | 38.1 |
| vae_spatial_part3_4_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.020 | 38.1 |
| vae_spatial_part4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.020 | 38.1 |
| vae_temporal_part1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.035 | 39.4 |
| vae_temporal_part2_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.035 | 39.5 |
| vae_temporal_part2_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.033 | 39.5 |
| vae_temporal_part2_3_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 39.5 |
| vae_temporal_part2_3_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 39.5 |
| vae_temporal_part2_3_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.022 | 39.6 |
| vae_temporal_part2_3_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.024 | 39.6 |
| vae_temporal_part2_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.032 | 39.6 |
| vae_temporal_part3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | 0.020 | 39.6 |

Footprint values describe the whole process while that partition was active, not exclusive per-partition allocations. Prediction percentiles combine different call shapes/stages; use the raw inputShapes and begin/end events to compare like-for-like calls.

## 3-generation-32140C6B-305F-4B2E-813E-23003F73563E.jsonl

| Field | Observed value |
| --- | --- |
| kind | generation |
| startedAt | 2026-11-21T08:11:02Z |
| executionEnvironment | physical-device |
| hardware | iPhone18,2 |
| os | Version 27.3 (Build 24C5037i) |
| appVersion | 0.1.0 |
| appBuild | 8 |
| sourceRevision | fd113f2c1cbbd724247406c587fe1826fac90a68 |
| modelRevision | cc1839814d0e1b0cb01953831a55a557ff6682bf |
| manifestSHA256 | 6c7f5eb70c180bb9b89a0c8165bbd8b9baca5458b58d2bbe853a4a1a6c06b469 |
| configuration | baseline-fp32-stdit-vae-t5-int8 |
| prompt | A small sailboat glides across a calm lake at sunrise. |
| seed | 42 |
| schedule | 30 points; leap index 20; 21 predictions; TDTM first 10; CFG 7; latent frames 20 |
| cacheCondition | uncontrolled OS cache; record first/repeat run separately; process is not restarted automatically |
| sampleIntervalSeconds | 0.25 |
| Outcome | INCOMPLETE — no terminal event |
| Observed log span (seconds) | 9.008 |
| Sampled process footprint maximum (MiB) | 3038.4 |
| Process-lifetime footprint high-water mark (MiB) | 3038.4 |
| Lowest recorded available app memory (MiB, advisory) | Not measured |
| Recorded memory warnings | 1 |
| Mean process CPU utilization (% of one core) | 47.9 |
| Thermal states | nominal |
| GPU utilization | Not measured |
| Actual Neural Engine execution | Not measured |

Unfinished operation: **stdit3_TDTM_0 / predict**, begun at 8.376 seconds. No completion or error event was recorded for it. This locates the interruption but does not establish the OS termination reason.

Recorded memory warnings:

- 8.885 seconds: stdit3_TDTM_0 / predict; process footprint 2723.0 MiB.

Successful partition prediction coverage: **27/102**.

Exported video SHA-256 verified: **no**. Visual quality, motion consistency, and prompt adherence require inspection of that actual video.

Unreached or unsuccessful partitions: stdit3_ST_0, stdit3_ST_1, stdit3_ST_10, stdit3_ST_11, stdit3_ST_12, stdit3_ST_13, stdit3_ST_14, stdit3_ST_15, stdit3_ST_16, stdit3_ST_17, stdit3_ST_18, stdit3_ST_19, stdit3_ST_2, stdit3_ST_20, stdit3_ST_21, stdit3_ST_22, stdit3_ST_23, stdit3_ST_24, stdit3_ST_25, stdit3_ST_26, stdit3_ST_27, stdit3_ST_3, stdit3_ST_4, stdit3_ST_5, stdit3_ST_6, stdit3_ST_7, stdit3_ST_8, stdit3_ST_9, stdit3_TDTM_0, stdit3_TDTM_1, stdit3_TDTM_10, stdit3_TDTM_11, stdit3_TDTM_12, stdit3_TDTM_13, stdit3_TDTM_14, stdit3_TDTM_15, stdit3_TDTM_16, stdit3_TDTM_17, stdit3_TDTM_18, stdit3_TDTM_19, stdit3_TDTM_2, stdit3_TDTM_20, stdit3_TDTM_21, stdit3_TDTM_22, stdit3_TDTM_23, stdit3_TDTM_24, stdit3_TDTM_25, stdit3_TDTM_26, stdit3_TDTM_27, stdit3_TDTM_3, stdit3_TDTM_4, stdit3_TDTM_5, stdit3_TDTM_6, stdit3_TDTM_7, stdit3_TDTM_8, stdit3_TDTM_9, stdit3_part2, vae_spatial_part1, vae_spatial_part2, vae_spatial_part3_1, vae_spatial_part3_2, vae_spatial_part3_3, vae_spatial_part3_4_1, vae_spatial_part3_4_2, vae_spatial_part3_4_3, vae_spatial_part4, vae_temporal_part1, vae_temporal_part2_1, vae_temporal_part2_2, vae_temporal_part2_3_1, vae_temporal_part2_3_2, vae_temporal_part2_3_3, vae_temporal_part2_3_4, vae_temporal_part2_4, vae_temporal_part3.

| Partition | Loads | Load total s | Load median s | Predictions | Predict total s | Predict median s | Predict p95 s | Compile total s | Active sampled footprint MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| stdit3_ST_0 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_10 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_11 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_12 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_13 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_14 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_15 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_16 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_17 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_18 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_19 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_20 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_21 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_22 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_23 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_24 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_25 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_26 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_27 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_5 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_6 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_7 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_8 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_ST_9 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_0 | 1 | 0.491 | 0.491 | 0 | Not measured | Not measured | Not measured | Not measured | 3038.4 |
| stdit3_TDTM_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_10 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_11 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_12 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_13 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_14 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_15 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_16 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_17 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_18 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_19 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_20 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_21 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_22 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_23 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_24 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_25 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_26 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_27 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_5 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_6 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_7 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_8 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_TDTM_9 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| stdit3_part1 | 1 | 0.182 | 0.182 | 1 | 0.063 | 0.063 | 0.063 | Not measured | 575.1 |
| stdit3_part2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| t5block-layer0 | 1 | 0.445 | 0.445 | 1 | 0.978 | 0.978 | 0.978 | Not measured | 383.0 |
| t5block-layer1 | 1 | 0.107 | 0.107 | 1 | 0.110 | 0.110 | 0.110 | Not measured | 928.6 |
| t5block-layer10 | 1 | 0.117 | 0.117 | 1 | 0.139 | 0.139 | 0.139 | Not measured | 893.6 |
| t5block-layer11 | 1 | 0.121 | 0.121 | 1 | 0.140 | 0.140 | 0.140 | Not measured | 894.3 |
| t5block-layer12 | 1 | 0.119 | 0.119 | 1 | 0.131 | 0.131 | 0.131 | Not measured | 894.3 |
| t5block-layer13 | 1 | 0.117 | 0.117 | 1 | 0.141 | 0.141 | 0.141 | Not measured | 894.3 |
| t5block-layer14 | 1 | 0.121 | 0.121 | 1 | 0.150 | 0.150 | 0.150 | Not measured | 894.3 |
| t5block-layer15 | 1 | 0.119 | 0.119 | 1 | 0.133 | 0.133 | 0.133 | Not measured | 894.3 |
| t5block-layer16 | 1 | 0.119 | 0.119 | 1 | 0.139 | 0.139 | 0.139 | Not measured | 894.3 |
| t5block-layer17 | 1 | 0.124 | 0.124 | 1 | 0.118 | 0.118 | 0.118 | Not measured | 894.3 |
| t5block-layer18 | 1 | 0.124 | 0.124 | 1 | 0.117 | 0.117 | 0.117 | Not measured | 887.3 |
| t5block-layer19 | 1 | 0.123 | 0.123 | 1 | 0.119 | 0.119 | 0.119 | Not measured | 887.3 |
| t5block-layer2 | 1 | 0.107 | 0.107 | 1 | 0.108 | 0.108 | 0.108 | Not measured | 928.6 |
| t5block-layer20 | 1 | 0.135 | 0.135 | 1 | 0.123 | 0.123 | 0.123 | Not measured | 887.5 |
| t5block-layer21 | 1 | 0.123 | 0.123 | 1 | 0.145 | 0.145 | 0.145 | Not measured | 887.6 |
| t5block-layer22 | 1 | 0.120 | 0.120 | 1 | 0.115 | 0.115 | 0.115 | Not measured | 877.7 |
| t5block-layer23 | 1 | 0.115 | 0.115 | 1 | 0.119 | 0.119 | 0.119 | Not measured | 877.7 |
| t5block-layer3 | 1 | 0.106 | 0.106 | 1 | 0.107 | 0.107 | 0.107 | Not measured | 928.6 |
| t5block-layer4 | 1 | 0.106 | 0.106 | 1 | 0.111 | 0.111 | 0.111 | Not measured | 928.6 |
| t5block-layer5 | 1 | 0.108 | 0.108 | 1 | 0.108 | 0.108 | 0.108 | Not measured | 928.6 |
| t5block-layer6 | 1 | 0.125 | 0.125 | 1 | 0.114 | 0.114 | 0.114 | Not measured | 893.3 |
| t5block-layer7 | 1 | 0.124 | 0.124 | 1 | 0.125 | 0.125 | 0.125 | Not measured | 893.3 |
| t5block-layer8 | 1 | 0.119 | 0.119 | 1 | 0.116 | 0.116 | 0.116 | Not measured | 893.3 |
| t5block-layer9 | 1 | 0.118 | 0.118 | 1 | 0.147 | 0.147 | 0.147 | Not measured | 893.3 |
| t5embed-tokens | 1 | 0.296 | 0.296 | 1 | 0.018 | 0.018 | 0.018 | Not measured | 82.6 |
| t5final-layer-norm | 1 | 0.005 | 0.005 | 1 | 0.001 | 0.001 | 0.001 | Not measured | 671.0 |
| vae_spatial_part1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_4_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_4_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part3_4_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_spatial_part4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_3_1 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_3_2 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_3_3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_3_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part2_4 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |
| vae_temporal_part3 | 0 | Not measured | Not measured | 0 | Not measured | Not measured | Not measured | Not measured | Not measured |

Footprint values describe the whole process while that partition was active, not exclusive per-partition allocations. Prediction percentiles combine different call shapes/stages; use the raw inputShapes and begin/end events to compare like-for-like calls.

Largest observed combined load/predict totals:

- t5block-layer0: 1.422 seconds.
- stdit3_TDTM_0: 0.491 seconds.
- t5embed-tokens: 0.314 seconds.
- t5block-layer14: 0.271 seconds.
- t5block-layer21: 0.268 seconds.

## Optimization decision

No speedup or quality improvement is inferred from these logs alone. Before testing an optimization, require a completed physical iPhone baseline, all 102 successful partition predictions, a verified exported MP4, and visual review. Compare matched prompts/seeds, device/OS, model hashes, thermal/cache conditions, and instrumentation. Separate first-run and repeated-run results.

Float16 conversion, Neural Engine placement changes, and sampler/step reductions remain experimental until paired output and timing measurements pass. Preserve the baseline tag and model manifest. Choose the next experiment using the measured load/predict bottleneck table; missing measurements are not zero-cost operations.
