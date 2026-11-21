# Third-party code and model provenance

## MOVD native implementation

The engine adapts the native Swift pipeline in [EAI Lab MOVD](https://github.com/eai-lab/MOVD/tree/cc1839814d0e1b0cb01953831a55a557ff6682bf), including the T5, STDiT, rectified-flow, and temporal/spatial VAE sequence. Its root license is MIT, copyright 2025 EAI LAB UNIST. The complete notice is retained at [MOVD-LICENSE](../Packages/VideoEngine/MOVD-LICENSE). Bundled tokenizer JSON resources were copied from that same pinned repository.

## Model weights are separate artifacts

Weights are downloaded directly from the public Google Drive links supplied by MOVD; they are not committed to this repository. The native-code MIT license must not be represented as a blanket license for every upstream model or training source.

The exporters reference [OpenSora STDiT-v3](https://huggingface.co/hpcai-tech/OpenSora-STDiT-v3), [OpenSora VAE-v1.2](https://huggingface.co/hpcai-tech/OpenSora-VAE-v1.2), and `DeepFloyd/t5-v1_1-xxl`. OpenSora model repositories identify Apache-2.0; the [Google T5-v1_1-XXL model](https://huggingface.co/google/t5-v1_1-xxl) also identifies Apache-2.0. The DeepFloyd source is distinct, and its model-card/license provenance needs confirmation before making redistribution or commercial-use assurances for the entire exported bundle.

The MOVD `Modded_Open_Sora/LICENSE` includes Apache-2.0 terms and credits dependencies with other terms, including AGPL and noncommercial components. That Python training/export code is not bundled in this iOS app. A release review must trace the exact exported weights and tokenizer provenance; this repository does not declare all model artifacts MIT or unconditionally cleared for commercial redistribution.

## Swift package dependencies

- [Hugging Face swift-transformers 0.1.9](https://github.com/huggingface/swift-transformers/tree/0.1.9): Apache-2.0; used for local tokenizer parsing. The engine constructs a tokenizer from bundled JSON and does not request a hosted model.
- [ZIPFoundation 0.9.19](https://github.com/weichsel/ZIPFoundation/tree/0.9.19): MIT; used for archive extraction and CRC checks.
- [Apple swift-argument-parser](https://github.com/apple/swift-argument-parser): transitive dependency, Apache-2.0 with Swift Runtime Library Exception. The exact resolved revision is recorded in the Xcode package lockfile.

The app bundles the MOVD, swift-transformers, ZIPFoundation, and swift-argument-parser license texts in `ThirdPartyNotices.txt`. Model weights are downloaded separately; the model-license provenance review above remains necessary before making redistribution or commercial-use assurances for the exported model bundle.
