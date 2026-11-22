#!/usr/bin/env python3
"""Export Neodragon's CLIP encoders in bounded groups, with real-prompt parity.

Both pooled and penultimate embeddings are retained: the video transformer and
SSD-1B consume different outputs. A different encoder is never silently reused.
"""
import argparse
import gc
import json
from pathlib import Path
import platform
import resource
import sys
import time

import coremltools as ct
import numpy as np
import torch
from safetensors import safe_open
from transformers import CLIPTextConfig, CLIPTextModel, CLIPTextModelWithProjection, CLIPTokenizer
from transformers.models.clip.modeling_clip import CLIPTextEmbeddings, CLIPEncoderLayer

from fetch_weights import verify
from probe_conversion import PROMPTS, compare

TOKENIZERS = {"text_encoder": "tokenizer", "text_encoder_2": "tokenizer_2",
              "ssd_1b_text_encoder": "ssd_1b_tokenizer", "ssd_1b_text_encoder_2": "ssd_1b_tokenizer_2"}


class Embedding(torch.nn.Module):
    def __init__(self, config):
        super().__init__()
        self.embedding = CLIPTextEmbeddings(config)

    def forward(self, input_ids):
        return self.embedding(input_ids=input_ids)


class EncoderGroup(torch.nn.Module):
    def __init__(self, config, count):
        super().__init__()
        self.layers = torch.nn.ModuleList([CLIPEncoderLayer(config) for _ in range(count)])
        self.register_buffer("causal_mask", torch.triu(torch.full((1, 1, 77, 77), torch.finfo(torch.float32).min), diagonal=1), persistent=False)

    def forward(self, hidden):
        for layer in self.layers:
            hidden = layer(hidden, attention_mask=None, causal_attention_mask=self.causal_mask)[0]
        return hidden


class Pool(torch.nn.Module):
    def __init__(self, config, projection):
        super().__init__()
        self.norm = torch.nn.LayerNorm(config.hidden_size, eps=config.layer_norm_eps)
        self.projection = torch.nn.Linear(config.hidden_size, config.projection_dim, bias=False) if projection else torch.nn.Identity()
        self.eos = config.eos_token_id

    def forward(self, hidden, input_ids):
        hidden = self.norm(hidden)
        if self.eos == 2:  # Original CLIP compatibility behavior from transformers.
            index = input_ids.to(torch.int32).argmax(dim=-1)
        else:
            index = (input_ids == self.eos).to(torch.int32).argmax(dim=-1)
        pooled = hidden[torch.arange(hidden.shape[0]), index]
        return self.projection(pooled)


def load_weights(module, source, mapping):
    state = {}
    for prefix, replacement in mapping:
        for key in source.keys():
            if not key.startswith(prefix):
                continue
            value = source.get_tensor(key)
            # transformers 4.46 reconstructs this as a non-persistent buffer.
            # Some source exports contain stale, noncanonical position IDs.
            # The embedding below copies the actual reference runtime buffer;
            # matching source weights alone is insufficient for this case.
            if key == "text_model.embeddings.position_ids":
                if value.shape != (1, 77) or value.dtype != torch.int64:
                    raise ValueError("Unexpected legacy CLIP position ID layout")
                continue
            state[key.replace(prefix, replacement, 1)] = value.float()
    module.load_state_dict(state, strict=True)


def export(module, inputs, names, output_name, path, precision):
    module.eval()
    with torch.inference_mode():
        traced = torch.jit.trace(module, inputs)
    policy = ct.precision.FLOAT32 if precision == "float32" else ct.transform.FP16ComputePrecision(
        op_selector=lambda op: op.op_type in {"linear", "matmul", "gather"})
    converted = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                           compute_precision=policy,
                           inputs=[ct.TensorType(name=n, shape=tuple(t.shape), dtype=t.numpy().dtype) for n, t in zip(names, inputs)],
                           outputs=[ct.TensorType(name=output_name, dtype=np.float32)], skip_model_load=True)
    converted.save(str(path))
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("component", choices=TOKENIZERS)
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--precision", choices=["mixed", "float32"], default="mixed")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    args.output.mkdir(parents=True)
    torch.set_num_threads(4)
    torch.manual_seed(42)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    report = {"status": "started", "component": args.component, "precision": args.precision,
              "weightsRevision": lock["weightsRevision"], "torch": torch.__version__, "coremltools": ct.__version__,
              "host": platform.platform(), "scope": "Mac component parity for fixed prompts, not iPhone/video validation",
              "deviceValidated": False, "prompts": PROMPTS, "gate": "finite, matching shape, relative L2 <= 0.01"}
    try:
        required = {args.component, TOKENIZERS[args.component]}
        for entry in lock["files"]:
            if entry["path"].split("/")[0] in required and not verify(args.weights / entry["path"], entry):
                raise ValueError("Unverified source: " + entry["path"])
        directory = args.weights / args.component
        config = CLIPTextConfig.from_pretrained(directory, local_files_only=True)
        config._attn_implementation = "eager"
        projected = args.component != "ssd_1b_text_encoder"
        cls = CLIPTextModelWithProjection if projected else CLIPTextModel
        print("Loading reference CLIP encoder", flush=True)
        original = cls.from_pretrained(directory, config=config, torch_dtype=torch.float32,
                                       local_files_only=True, low_cpu_mem_usage=True).eval()
        reference_positions = original.text_model.embeddings.position_ids.detach().clone()
        report["runtimePositionIDs"] = reference_positions.tolist()[0]
        tokenizer = CLIPTokenizer.from_pretrained(args.weights / TOKENIZERS[args.component], local_files_only=True)
        tokens, refs, pooled = [], [], []
        for prompt in PROMPTS:
            if len(tokenizer.encode(prompt)) > 77:
                raise ValueError("Prompt exceeds CLIP token limit")
            ids = tokenizer(prompt, max_length=77, padding="max_length", truncation=False, return_tensors="pt").input_ids.to(torch.int32)
            with torch.inference_mode():
                result = original(ids, output_hidden_states=True)
            tokens.append(ids)
            refs.append([value.numpy().copy() for value in result.hidden_states])
            pooled.append((result.text_embeds if projected else result.pooler_output).numpy().copy())
        (args.output / "tokenizer-fixtures.json").write_text(json.dumps({"prompts": PROMPTS,
            "inputIDs": [ids.tolist()[0] for ids in tokens], "padTokenID": tokenizer.pad_token_id,
            "eosTokenID": tokenizer.eos_token_id, "maximumLength": 77}, indent=2) + "\n")
        del original, result
        gc.collect()
        manifest = []
        report["partitions"] = []
        current = [None for _ in tokens]
        with safe_open(directory / "model.safetensors", framework="pt") as weights:
            module = Embedding(config)
            module.embedding.position_ids = reference_positions
            load_weights(module, weights, [("text_model.embeddings.", "embedding.")])
            # Create each group lazily; never retain all conversion graphs.
            groups = [(begin, min(begin + 4, config.num_hidden_layers - 1)) for begin in range(0, config.num_hidden_layers - 1, 4)]
            for part_index in range(len(groups) + 3):
                if part_index == 0:
                    name, inputs, input_names, output_name, reference_index = "embedding", (tokens[0],), ["input_ids"], "hidden", 0
                elif part_index <= len(groups):
                    begin, end = groups[part_index - 1]
                    module = EncoderGroup(config, end - begin)
                    load_weights(module, weights, [(f"text_model.encoder.layers.{i}.", f"layers.{i - begin}.") for i in range(begin, end)])
                    name, inputs, input_names, output_name, reference_index = f"layers_{begin:02}_{end - 1:02}", (torch.from_numpy(refs[0][begin]),), ["hidden"], "hidden_out", end
                elif part_index == len(groups) + 1:
                    begin = config.num_hidden_layers - 1
                    module = EncoderGroup(config, 1)
                    load_weights(module, weights, [(f"text_model.encoder.layers.{begin}.", "layers.0.")])
                    name, inputs, input_names, output_name, reference_index = "last_layer", (torch.from_numpy(refs[0][begin]),), ["hidden"], "hidden_out", config.num_hidden_layers
                else:
                    module = Pool(config, projected)
                    mapping = [("text_model.final_layer_norm.", "norm.")]
                    if projected:
                        mapping.append(("text_projection.", "projection."))
                    load_weights(module, weights, mapping)
                    name, inputs, input_names, output_name, reference_index = "pool", (torch.from_numpy(refs[0][-1]), tokens[0]), ["hidden", "input_ids"], "pooled", None
                print(f"Converting {args.component}/{name}", flush=True)
                path = args.output / f"{args.component}_{name}.mlpackage"
                started = time.monotonic()
                size = export(module, tuple(inputs), input_names, output_name, path, args.precision)
                del module
                gc.collect()
                runtime = ct.models.MLModel(str(path), compute_units=ct.ComputeUnit.CPU_ONLY)
                comparisons = []
                for index, ids in enumerate(tokens):
                    values = {"input_ids": ids.numpy()} if part_index == 0 else {"hidden": current[index]}
                    if reference_index is None:
                        values["input_ids"] = ids.numpy()
                    result = runtime.predict(values)[output_name]
                    expected = pooled[index] if reference_index is None else refs[index][reference_index]
                    comparisons.append(compare(result, expected))
                    current[index] = result
                    if reference_index == config.num_hidden_layers - 1 or reference_index is None:
                        label = "pooled" if reference_index is None else "penultimate"
                        np.save(args.output / f"{label}-{index}.npy", result, allow_pickle=False)
                report["partitions"].append({"name": path.stem, "packageBytes": size, "conversionAndCheckSeconds": time.monotonic() - started, "cases": comparisons})
                manifest.append({"name": path.stem, "inputs": input_names, "output": output_name})
                del runtime
                gc.collect()
                if not all(item["passed"] for item in comparisons):
                    raise ValueError(f"Accumulated CLIP parity failed at {name}")
        (args.output / "pipeline.json").write_text(json.dumps({"component": args.component,
            "hiddenSize": config.hidden_size, "projectionSize": config.projection_dim if projected else config.hidden_size,
            "penultimatePartition": manifest[-3]["name"], "partitions": manifest}, indent=2) + "\n")
        report["status"] = "passed-component-parity"
    except Exception as error:
        import traceback
        traceback.print_exc()
        report["status"] = "failed"
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        report["processLifetimeMaxRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        (args.output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
        print(json.dumps(report, indent=2, allow_nan=False), flush=True)
    return 0 if report["status"] == "passed-component-parity" else 1


if __name__ == "__main__":
    sys.exit(main())
