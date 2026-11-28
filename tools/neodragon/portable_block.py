"""Core ML export form of one Neodragon/Pyramid-Flow joint transformer block.

Adapted from Qualcomm-AI-research/neodragon, pinned in source-lock.json.
Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
BSD-3-Clause-Clear; see LICENSE-Neodragon.txt. The underlying Pyramid-Flow
implementation is MIT-licensed; see the upstream notices.

Only a single pyramid stage/batch is evaluated at a time, as in upstream
inference. Broadcasting replaces padded assignment; two real RoPE inputs replace
a rank-six rotation matrix. Every change requires comparison to the original
block, with its original trained weights, before Core ML conversion.
"""
import torch


class PortableJointBlock(torch.nn.Module):
    def __init__(self, block, attention_head_group_size=0):
        super().__init__()
        self.block = block
        heads = block.attn.heads
        if attention_head_group_size < 0 or (attention_head_group_size and heads % attention_head_group_size):
            raise ValueError("Attention head group size must divide the checkpoint's head count")
        self.attention_head_group_size = attention_head_group_size or heads

    @staticmethod
    def rotate(value, cosine, sine):
        even = value[..., 0::2].float()
        odd = value[..., 1::2].float()
        result = torch.stack((cosine * even - sine * odd, sine * even + cosine * odd), dim=-1)
        return result.flatten(-2).to(value.dtype)

    def forward(self, hidden, context, time_embedding, attention_mask, rope_cos, rope_sin):
        block = self.block
        normal, gate, shift, scale, ff_gate = block.norm1(hidden, emb=time_embedding)
        if block.context_pre_only:
            context_normal = block.norm1_context(context, time_embedding)
        else:
            context_normal, context_gate, context_shift, context_scale, context_ff_gate = block.norm1_context(context, emb=time_embedding)
        attention = block.attn

        def heads(value):
            return value.reshape(1, -1, attention.heads, 64)

        query = heads(attention.to_q(normal))
        key = heads(attention.to_k(normal))
        value = heads(attention.to_v(normal))
        context_query = heads(attention.add_q_proj(context_normal))
        context_key = heads(attention.add_k_proj(context_normal))
        context_value = heads(attention.add_v_proj(context_normal))
        query = attention.norm_q(query)
        key = attention.norm_k(key)
        context_query = attention.norm_add_q(context_query)
        context_key = attention.norm_add_k(context_key)
        query = self.rotate(torch.cat((context_query, query), dim=1), rope_cos, rope_sin)
        key = self.rotate(torch.cat((context_key, key), dim=1), rope_cos, rope_sin)
        value = torch.cat((context_value, value), dim=1)
        query, key, value = query.transpose(1, 2), key.transpose(1, 2), value.transpose(1, 2)
        mask = attention_mask > 0
        if self.attention_head_group_size == attention.heads:
            attended = torch.nn.functional.scaled_dot_product_attention(
                query, key, value, attn_mask=mask, dropout_p=0.0, is_causal=False)
        else:
            # Heads are independent. Keep every token, trained projection, RoPE
            # position and causal mask; only bound each attention workspace.
            # This is an opt-in conversion experiment, never a default update.
            size = self.attention_head_group_size
            attended = torch.cat([
                torch.nn.functional.scaled_dot_product_attention(
                    query[:, start:start + size], key[:, start:start + size], value[:, start:start + size],
                    attn_mask=mask, dropout_p=0.0, is_causal=False)
                for start in range(0, attention.heads, size)
            ], dim=1)
        attended = attended.transpose(1, 2).flatten(2, 3)
        context_attention = attended[:, :128]
        hidden_attention = attention.to_out[1](attention.to_out[0](attended[:, 128:]))
        hidden = hidden + gate[:, None] * hidden_attention
        normalized = block.norm2(hidden) * (1 + scale[:, None]) + shift[:, None]
        hidden = hidden + ff_gate[:, None] * block.ff(normalized)
        if block.context_pre_only:
            return (hidden,)
        context = context + context_gate[:, None] * attention.to_add_out(context_attention)
        normalized_context = block.norm2_context(context) * (1 + context_scale[:, None]) + context_shift[:, None]
        context = context + context_ff_gate[:, None] * block.ff_context(normalized_context)
        return hidden, context
