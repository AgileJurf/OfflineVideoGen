#!/usr/bin/env python3
"""Record the original byte conversion and Pillow Lanczos reference hashes."""
import hashlib
import json
from pathlib import Path
import numpy as np
import PIL
from PIL import Image

width, height = 1024, 640
y, x = np.mgrid[:height, :width]
cases = []
for kind in ["pattern", "gradient", "checker", "black", "white"]:
    if kind == "pattern":
        value = np.stack([(x * 17 + y * 31 + c * 73 + (x ^ y) * 13) % 256 for c in range(3)])
    elif kind == "gradient":
        value = np.stack([x % 256, y % 256, (x + y) % 256])
    elif kind == "checker":
        value = np.repeat((((x + y) % 2) * 255)[None], 3, axis=0)
    else:
        value = np.full((3, height, width), 255 if kind == "white" else 0)
    image = Image.fromarray(value.astype(np.uint8).transpose(1, 2, 0))
    resized = np.ascontiguousarray(np.array(image.resize((width // 2, height // 2), Image.Resampling.LANCZOS)).transpose(2, 0, 1))
    cases.append({"kind": kind, "outputSHA256": hashlib.sha256(resized.tobytes()).hexdigest()})
decoded = np.array([-4, -1.1, -1, -0.5, 0, 0.1, 0.5, 1, 1.1, 4] + [(i + 0.5) / 255 * 2 - 1 for i in range(255)], dtype=np.float32)
pixels = (np.clip(decoded * np.float32(.5) + np.float32(.5), 0, 1) * np.float32(255)).round().astype(np.uint8)
result = {"reference": "diffusers denormalization and numpy_to_pil; Pillow Lanczos", "pillow": PIL.__version__,
          "width": width, "height": height, "cases": cases, "decoded": decoded.tolist(), "pixels": pixels.tolist()}
Path(__file__).with_name("fixtures").joinpath("image-processing-parity.json").write_text(json.dumps(result, indent=2) + "\n")
print("Recorded first-image rounding and five full-resolution Pillow resize cases")
