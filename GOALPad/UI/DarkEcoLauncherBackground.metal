#include <metal_stdlib>
using namespace metal;

static float dark_eco_hash(float2 point) {
    float3 value = fract(float3(point.xyx) * float3(0.1031f, 0.1030f, 0.0973f));
    value += dot(value, value.yzx + 33.33f);
    return fract((value.x + value.y) * value.z);
}

static float dark_eco_noise(float2 point) {
    float2 cell = floor(point);
    float2 offset = fract(point);
    float2 blend = offset * offset * (3.0f - 2.0f * offset);

    float lower = mix(dark_eco_hash(cell),
                      dark_eco_hash(cell + float2(1.0f, 0.0f)),
                      blend.x);
    float upper = mix(dark_eco_hash(cell + float2(0.0f, 1.0f)),
                      dark_eco_hash(cell + float2(1.0f, 1.0f)),
                      blend.x);
    return mix(lower, upper, blend.y);
}

static float dark_eco_fbm(float2 point) {
    const float2x2 turn = float2x2(float2(0.80f, -0.60f),
                                   float2(0.60f, 0.80f));
    float value = 0.0f;
    float weight = 0.55f;
    float totalWeight = 0.0f;

    for (int octave = 0; octave < 3; ++octave) {
        value += dark_eco_noise(point) * weight;
        totalWeight += weight;
        point = turn * point * 2.03f + 11.7f;
        weight *= 0.5f;
    }

    return value / totalWeight;
}

[[ stitchable ]] half4 darkEcoLauncherBackground(float2 position,
                                                  half4 sourceColor,
                                                  float2 size,
                                                  float time) {
    float2 safeSize = max(size, float2(1.0f));
    float2 uv = (position - safeSize * 0.5f) / safeSize.y;
    float distanceFromCenter = length(uv);

    float curl = distanceFromCenter * 0.12f + sin(time * 0.055f) * 0.035f;
    float curlSine = sin(curl);
    float curlCosine = cos(curl);
    float2 liquidUV = float2(curlCosine * uv.x - curlSine * uv.y,
                             curlSine * uv.x + curlCosine * uv.y);

    float2 domain = liquidUV * float2(3.65f, 3.05f)
        + float2(-time * 0.022f, time * 0.031f);
    float flowX = dark_eco_noise(domain * 0.68f + float2(time * 0.015f, -2.3f));
    float flowY = dark_eco_noise(domain * 0.81f + float2(8.7f, -time * 0.018f));
    float2 warped = domain + (float2(flowX, flowY) - 0.5f) * 1.35f;

    float body = dark_eco_fbm(warped + float2(time * 0.009f, -time * 0.018f));
    float detail = dark_eco_noise(warped * 2.45f + float2(time * 0.021f, 5.4f));
    float liquid = body * 0.82f + detail * 0.18f;

    float waveA = sin(warped.x * 2.85f + warped.y * 0.66f
        + body * 3.8f + time * 0.18f);
    float waveB = sin(warped.y * 3.10f - warped.x * 0.52f
        - flowY * 3.1f - time * 0.14f);
    float waveC = sin(warped.x * 1.85f - warped.y * 1.72f
        + detail * 2.6f + time * 0.11f);
    float ribbonA = pow(smoothstep(0.58f, 0.98f, 1.0f - abs(waveA)), 2.6f);
    float ribbonB = pow(smoothstep(0.64f, 0.99f, 1.0f - abs(waveB)), 3.0f);
    float ribbonC = pow(smoothstep(0.72f, 0.995f, 1.0f - abs(waveC)), 3.4f);
    float wavyEnergy = max(ribbonA * 0.78f, max(ribbonB * 0.68f, ribbonC * 0.56f));
    float diffuseWave = clamp(ribbonA * 0.55f + ribbonB * 0.48f + ribbonC * 0.38f,
                              0.0f,
                              1.0f);
    float submergedVein = smoothstep(0.08f, 0.66f, diffuseWave);
    float hotVein = smoothstep(0.68f, 0.96f, wavyEnergy);

    float foldedDetail = 1.0f - abs(detail * 2.0f - 1.0f);
    float oilySheen = pow(smoothstep(0.44f, 0.94f, foldedDetail), 5.0f);
    float pulse = 0.88f + 0.12f * sin(time * 0.62f + liquid * 14.0f);

    const float3 blackInk = float3(0.003f, 0.001f, 0.008f);
    const float3 blackPurple = float3(0.032f, 0.006f, 0.065f);
    const float3 deepViolet = float3(0.125f, 0.018f, 0.255f);
    const float3 chargedViolet = float3(0.45f, 0.12f, 0.82f);
    const float3 coldGlint = float3(0.22f, 0.32f, 0.68f);
    const float3 gradientViolet = float3(0.050f, 0.008f, 0.105f);

    float depth = smoothstep(0.12f, 0.92f, liquid);
    float lowerVat = smoothstep(-0.58f, 0.70f, uv.y + (flowY - 0.5f) * 0.12f);
    float offCenterGlow = exp(-dot(uv - float2(-0.24f, 0.16f),
                                   uv - float2(-0.24f, 0.16f)) * 2.8f);
    float vatGradient = clamp(lowerVat * 0.62f + offCenterGlow * 0.24f, 0.0f, 1.0f);
    float3 color = mix(blackInk,
                       blackPurple,
                       clamp(depth * 0.48f + vatGradient * 0.44f, 0.0f, 1.0f));
    color = max(color, mix(blackInk, gradientViolet, vatGradient));
    color += deepViolet * submergedVein * (0.14f + 0.19f * depth);
    color += chargedViolet * hotVein * (0.13f + 0.29f * pulse);
    color += coldGlint * oilySheen * hotVein * 0.075f;

    float vignetteDistance = length(uv * float2(0.72f, 1.0f));
    float edgeLight = 1.0f - smoothstep(0.34f, 0.82f, vignetteDistance);
    color *= 0.72f + 0.28f * edgeLight;

    color = clamp(color, 0.0f, 1.0f);
    return half4(half3(color), sourceColor.a);
}
