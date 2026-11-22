"""Unchanged SSD-1B image VAE decoder, split at existing module boundaries."""
import json
from accelerate import init_empty_weights
from diffusers import AutoencoderKL
import torch
from ssd_unet_parts import Step, Unary


def empty_vae(directory):
    with init_empty_weights():
        model = AutoencoderKL.from_config(json.loads((directory / "config.json").read_text()))
    return model.float().eval()


class Scale(torch.nn.Module):
    def __init__(self, factor):
        super().__init__(); self.factor = factor
    def forward(self, latent):
        return latent / self.factor


class Residual(torch.nn.Module):
    def __init__(self, module):
        super().__init__(); self.module = module
    def forward(self, hidden):
        return self.module(hidden, None)


class Output(torch.nn.Module):
    def __init__(self, decoder):
        super().__init__(); self.norm, self.act, self.projection = decoder.conv_norm_out, decoder.conv_act, decoder.conv_out
    def forward(self, hidden):
        return self.projection(self.act(self.norm(hidden)))


def make_plan(model):
    steps = [Step("ssd_vae_scale", Scale(model.config.scaling_factor), [], ["latent"], "hidden")]
    def add(path, module, output="hidden"):
        steps.append(Step("ssd_vae_" + path.replace(".", "_"), module.eval(), [(path + ".", "module.")], ["hidden"], output))
    add("post_quant_conv", Unary(model.post_quant_conv))
    add("decoder.conv_in", Unary(model.decoder.conv_in))
    middle = model.decoder.mid_block
    add("decoder.mid_block.resnets.0", Residual(middle.resnets[0]))
    for index, (attention, resnet) in enumerate(zip(middle.attentions, middle.resnets[1:])):
        if attention is not None:
            add(f"decoder.mid_block.attentions.{index}", Unary(attention))
        add(f"decoder.mid_block.resnets.{index+1}", Residual(resnet))
    for level, block in enumerate(model.decoder.up_blocks):
        for index, resnet in enumerate(block.resnets):
            add(f"decoder.up_blocks.{level}.resnets.{index}", Residual(resnet))
        for index, upsample in enumerate(block.upsamplers or []):
            add(f"decoder.up_blocks.{level}.upsamplers.{index}", Unary(upsample))
    steps.append(Step("ssd_vae_output", Output(model.decoder).eval(),
                      [("decoder.conv_norm_out.", "norm."), ("decoder.conv_out.", "projection.")], ["hidden"], "decoded_image"))
    return steps
