"""Bounded partitions of the original SSD-1B UNet; no weight or layer changes."""
from dataclasses import dataclass
import torch


class Unary(torch.nn.Module):
    def __init__(self, module):
        super().__init__(); self.module = module
    def forward(self, hidden):
        return self.module(hidden)


class Residual(torch.nn.Module):
    def __init__(self, module):
        super().__init__(); self.module = module
    def forward(self, hidden, time_embedding):
        return self.module(hidden, time_embedding)


class Time(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.time_proj, self.time_embedding = model.time_proj, model.time_embedding
        self.add_time_proj, self.add_embedding = model.add_time_proj, model.add_embedding
    def forward(self, timestep, pooled, time_ids):
        time = self.time_embedding(self.time_proj(timestep))
        added = self.add_time_proj(time_ids.flatten()).reshape(pooled.shape[0], -1)
        return time + self.add_embedding(torch.cat((pooled, added), dim=-1))


class AttentionIn(torch.nn.Module):
    def __init__(self, module):
        super().__init__(); self.norm, self.projection = module.norm, module.proj_in
        if not module.use_linear_projection:
            raise ValueError("SSD-1B reference requires linear projection")
    def forward(self, hidden):
        hidden = self.norm(hidden)
        return self.projection(hidden.flatten(2).transpose(1, 2))


class AttentionBlock(torch.nn.Module):
    def __init__(self, module):
        super().__init__(); self.module = module
    def forward(self, hidden, context):
        return self.module(hidden, encoder_hidden_states=context)


class AttentionOut(torch.nn.Module):
    def __init__(self, module):
        super().__init__(); self.projection = module.proj_out
    def forward(self, hidden, residual):
        return self.projection(hidden).transpose(1, 2).reshape(residual.shape) + residual


class Output(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.norm, self.act, self.projection = model.conv_norm_out, model.conv_act, model.conv_out
    def forward(self, hidden):
        return self.projection(self.act(self.norm(hidden)))


@dataclass
class Step:
    name: str
    module: torch.nn.Module
    mapping: list  # (source checkpoint prefix, module prefix)
    inputs: list
    output: str


def make_plan(model):
    steps = []

    def add(name, module, mapping, inputs=("hidden",), output="hidden"):
        steps.append(Step("ssd_unet_" + name.replace(".", "_"), module.eval(), mapping, list(inputs), output))

    def save(source, target):
        steps.append({"operation": "save", "source": source, "target": target})

    def attention(module, prefix):
        save("hidden", "attention_residual")
        add(prefix + ".in", AttentionIn(module), [(prefix + ".norm.", "norm."), (prefix + ".proj_in.", "projection.")])
        for index, block in enumerate(module.transformer_blocks):
            path = prefix + f".transformer_blocks.{index}"
            add(path, AttentionBlock(block), [(path + ".", "module.")], ("hidden", "context"))
        add(prefix + ".out", AttentionOut(module), [(prefix + ".proj_out.", "projection.")], ("hidden", "attention_residual"))
        steps.append({"operation": "release", "slot": "attention_residual"})

    add("time", Time(model), [("time_embedding.", "time_embedding."), ("add_embedding.", "add_embedding.")],
        ("timestep", "pooled", "time_ids"), "time_embedding")
    add("conv_in", Unary(model.conv_in), [("conv_in.", "module.")], ("sample",))
    skip = 0
    save("hidden", f"skip{skip}")
    for level, block in enumerate(model.down_blocks):
        for index, resnet in enumerate(block.resnets):
            prefix = f"down_blocks.{level}.resnets.{index}"
            add(prefix, Residual(resnet), [(prefix + ".", "module.")], ("hidden", "time_embedding"))
            if hasattr(block, "attentions"):
                attention(block.attentions[index], f"down_blocks.{level}.attentions.{index}")
            skip += 1; save("hidden", f"skip{skip}")
        for index, down in enumerate(block.downsamplers or []):
            prefix = f"down_blocks.{level}.downsamplers.{index}"
            add(prefix, Unary(down), [(prefix + ".", "module.")])
            skip += 1; save("hidden", f"skip{skip}")
    if any(part is not None for part in model.mid_block.attentions):
        raise ValueError("Unexpected attention in SSD-1B's published middle block")
    for index, resnet in enumerate(model.mid_block.resnets):
        prefix = f"mid_block.resnets.{index}"
        add(prefix, Residual(resnet), [(prefix + ".", "module.")], ("hidden", "time_embedding"))
    for level, block in enumerate(model.up_blocks):
        for index, resnet in enumerate(block.resnets):
            steps.append({"operation": "concatenate", "inputs": ["hidden", f"skip{skip}"], "axis": 1, "output": "hidden"})
            steps.append({"operation": "release", "slot": f"skip{skip}"})
            skip -= 1
            prefix = f"up_blocks.{level}.resnets.{index}"
            add(prefix, Residual(resnet), [(prefix + ".", "module.")], ("hidden", "time_embedding"))
            if hasattr(block, "attentions"):
                attention(block.attentions[index], f"up_blocks.{level}.attentions.{index}")
        for index, up in enumerate(block.upsamplers or []):
            prefix = f"up_blocks.{level}.upsamplers.{index}"
            add(prefix, Unary(up), [(prefix + ".", "module.")])
    if skip != -1:
        raise ValueError("SSD-1B skip connection count differs from the reference")
    add("output", Output(model), [("conv_norm_out.", "norm."), ("conv_out.", "projection.")], output="predicted_noise")
    return steps


def materialize(step, weights):
    state = {}
    for prefix, replacement in step.mapping:
        state.update({replacement + key[len(prefix):]: weights.get_tensor(key).float()
                      for key in weights.keys() if key.startswith(prefix)})
    step.module.load_state_dict(state, strict=True, assign=True)
