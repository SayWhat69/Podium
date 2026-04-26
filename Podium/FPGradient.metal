//
//  FPGradient.metal
//
//  Inverse-distance weighted multicolor gradient for FullscreenPlayerView.
//  Add this file to your Xcode target (it will be compiled into the default Metal library).
//
//  Algorithm: each pixel's color is the weighted average of 8 control points,
//  where weight = 1 / (bias + dist ^ power).  bias=0.05, power=2.5.
//  A small noise term dithers positions slightly to break up banding.
//
//  The uniforms struct layout must match FP_Uniforms in FullscreenPlayerView.swift exactly.

#include <metal_stdlib>
using namespace metal;

// --- Uniforms ---------------------------------------------------------------
// Flat layout so Swift can fill it with a plain memcpy via Shader.Argument.data.
// 8 positions (float2 each) followed by 8 colors (float4 each).

struct FPUniforms {
    float2 points[8];
    float4 colors[8];
};

// --- Noise helper ------------------------------------------------------------

float2 fp_hash23(float3 p) {
    p = fract(p * float3(443.897f, 441.423f, 0.0973f));
    p += dot(p, p.yzx + 19.19f);
    return fract((p.xx + p.yz) * p.zy);
}

// --- Main shader -------------------------------------------------------------

[[ stitchable ]] half4 fp_gradient(
    float2 position,       // pixel position in view-space
    half4  currentColor,   // unused but required by the stitchable signature
    float4 box,            // bounding rect: (x, y, width, height)
    device const FPUniforms& u [[ buffer(0) ]],
    int    bufferSize      // unused
) {
    float2 size = box.zw;

    // Cheap spatial noise — breaks up any colour banding
    float2 noise = fp_hash23(float3(position / float2(size.x, size.x), 0.0f));
    float2 uv = (position
        + float2(sin(noise.x * 2.0f * M_PI_F),
                 sin(noise.y * 2.0f * M_PI_F)) * 2.0f)
        / float2(size.x, size.x);   // normalise by width (aspect-correct, same as original)

    const float bias  = 0.05f;
    const float power = 2.5f;

    float  totalW = 0.0f;
    float  weights[8];

    for (int i = 0; i < 8; i++) {
        // Aspect-correct point position
        float2 pt  = u.points[i] * float2(1.0f, size.y / size.x);
        float  d   = length(uv - pt);
        float  w   = u.colors[i].a / (bias + pow(d, power));
        weights[i] = w;
        totalW    += w;
    }

    float3 col = float3(0.0f);
    float  inv = 1.0f / totalW;
    for (int i = 0; i < 8; i++) {
        col += weights[i] * inv * u.colors[i].rgb;
    }

    return half4(half3(col), 1.0h);
}
