#!/usr/bin/env python3
"""Offline screening of a COPY of one original MOVD Core ML partition.

This never updates the app manifest or installed weights. Float16 conversion uses
coremltools 8.3's internal MIL-proto reader and is an investigation, not a supported
replacement for re-exporting the original PyTorch checkpoint. Original Float32
input/output contracts must match. A synthetic pass cannot qualify a device preset.
"""
import argparse
import hashlib
import json
import platform
import resource
import time
from pathlib import Path

import coremltools as ct
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--model', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--mode', choices=['fp16', 'mixed', 'int8'], required=True)
parser.add_argument('--input', type=Path)
parser.add_argument('--reference', type=Path)
args = parser.parse_args()
if ct.__version__ not in ('8.3', '8.3.0'):
    raise SystemExit('This experimental conversion is pinned to coremltools 8.3')
if args.output.exists() or args.output.resolve() == args.model.resolve():
    raise SystemExit('Use a new output directory; originals and previous candidates are never overwritten')
args.output.mkdir(parents=True)


def tree_digest(path):
    digest = hashlib.sha256()
    size = 0
    for item in sorted(path.rglob('*')):
        if not item.is_file():
            continue
        digest.update(item.relative_to(path).as_posix().encode())
        with item.open('rb') as stream:
            while data := stream.read(1024 * 1024):
                size += len(data)
                digest.update(data)
    return {'bytes': size, 'treeSHA256': digest.hexdigest()}


report = {'mode': args.mode, 'partition': args.model.stem, 'coremltools': ct.__version__,
          'numpy': np.__version__, 'os': platform.platform(), 'machine': platform.machine(),
          'scope': 'Mac synthetic partition screening; not iPhone speed, memory, reference parity, or video quality',
          'original': tree_digest(args.model), 'deviceValidated': False,
          'predeclaredScreen': 'matching IO contract; finite output; relative L2 <= 0.01; full-model/device tests still required'}
try:
    started = time.monotonic()
    original = ct.models.MLModel(str(args.model), skip_model_load=True)
    spec = original.get_spec()
    if args.mode == 'int8':
        config = ct.optimize.coreml.OpLinearQuantizerConfig(mode='linear_symmetric', dtype='int8',
                                                          granularity='per_channel', weight_threshold=2048)
        candidate = ct.optimize.coreml.linear_quantize_weights(original,
            config=ct.optimize.coreml.OptimizationConfig(op_type_configs={key: config for key in ['conv', 'linear', 'matmul']}))
        report['computePrecision'] = 'Original Float32 operations; only selected weights are compressed'
    else:
        from coremltools.converters.mil.frontend.milproto.load import load
        program = load(spec, specification_version=spec.specificationVersion, file_weights_dir=original.weights_dir)
        inputs = []
        for item in spec.description.input:
            array = item.type.multiArrayType
            if array.dataType != ct.proto.FeatureTypes_pb2.ArrayFeatureType.FLOAT32:
                raise ValueError('This screening script only accepts original Float32 inputs')
            if array.enumeratedShapes.shapes:
                shape = ct.EnumeratedShapes(shapes=[list(s.shape) for s in array.enumeratedShapes.shapes], default=list(array.shape))
            elif array.shapeRange.sizeRanges:
                shape = tuple(ct.RangeDim(lower_bound=r.lowerBound, upper_bound=r.upperBound, default=array.shape[i])
                              if r.lowerBound != r.upperBound else r.lowerBound
                              for i, r in enumerate(array.shapeRange.sizeRanges))
            else:
                shape = tuple(array.shape)
            inputs.append(ct.TensorType(name=item.name, shape=shape, dtype=np.float32))
        precision = ct.precision.FLOAT16 if args.mode == 'fp16' else ct.transform.FP16ComputePrecision(
            op_selector=lambda op: op.op_type in {'conv', 'linear', 'matmul'})
        candidate = ct.convert(program, source='milinternal', convert_to='mlprogram',
            minimum_deployment_target=ct.target.iOS18, compute_precision=precision,
            inputs=inputs,
            outputs=[ct.TensorType(name=item.name, dtype=np.float32) for item in spec.description.output],
            skip_model_load=True)
        report['computePrecision'] = 'Float16 where supported' if args.mode == 'fp16' else 'Float16 conv/linear/matmul; remaining operations Float32'
    candidate_spec = candidate.get_spec()
    before = [item.SerializeToString() for item in [*spec.description.input, *spec.description.output]]
    after = [item.SerializeToString() for item in [*candidate_spec.description.input, *candidate_spec.description.output]]
    report['sameIOContract'] = before == after
    if before != after:
        report['originalIO'] = [str(item) for item in [*spec.description.input, *spec.description.output]]
        report['candidateIO'] = [str(item) for item in [*candidate_spec.description.input, *candidate_spec.description.output]]
        raise ValueError('Conversion changed names, types, shapes or flexible ranges; candidate rejected')
    target = args.output / (args.model.stem + '.mlpackage')
    candidate.save(str(target))
    report['conversionSeconds'] = time.monotonic() - started
    report['candidate'] = tree_digest(target)
    report['originalUnchanged'] = tree_digest(args.model) == report['original']
    if not report['originalUnchanged']:
        raise RuntimeError('Original package integrity changed')
    if args.input:
        if not args.reference:
            raise ValueError('--reference is required for numerical screening')
        values = np.load(args.input, allow_pickle=False)
        report['inputSHA256'] = hashlib.sha256(np.ascontiguousarray(values).tobytes()).hexdigest()
        started = time.monotonic()
        runtime = ct.models.MLModel(str(target), compute_units=ct.ComputeUnit.CPU_ONLY)
        report['macLoadSeconds'] = time.monotonic() - started
        started = time.monotonic()
        prediction = runtime.predict({spec.description.input[0].name: values})
        result = np.asarray(prediction[spec.description.output[0].name])
        report['macPredictionSeconds'] = time.monotonic() - started
        np.save(args.output / 'output.npy', result, allow_pickle=False)
        baseline = np.load(args.reference, allow_pickle=False)
        report['outputShape'] = list(result.shape)
        report['finite'] = bool(np.isfinite(result).all())
        report['sameOutputShape'] = result.shape == baseline.shape
        report['passesSyntheticScreen'] = False
        if report['finite'] and report['sameOutputShape']:
            delta = result.astype(np.float64) - baseline.astype(np.float64)
            report['maxAbsoluteError'] = float(np.abs(delta).max())
            report['rmse'] = float(np.sqrt(np.mean(delta ** 2)))
            report['relativeL2'] = float(np.linalg.norm(delta.ravel()) / max(np.linalg.norm(baseline.astype(np.float64).ravel()), 1e-30))
            report['passesSyntheticScreen'] = report['relativeL2'] <= 0.01
        report['outputSHA256'] = hashlib.sha256(np.ascontiguousarray(result).tobytes()).hexdigest()
    report['status'] = 'screened' if args.input else 'converted-not-executed'
except Exception as error:
    report['status'] = 'failed'
    report['error'] = str(error)
finally:
    report['processLifetimeMaxRSSBytes'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    (args.output / 'report.json').write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print(json.dumps(report, indent=2, allow_nan=False))
raise SystemExit(1 if report['status'] == 'failed' else 0)
