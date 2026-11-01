#include <metal_stdlib>
using namespace metal;

#if defined(GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE)

// Resolves one native per-eye color/depth pair into its matching compositor view. The native pass
// already used that eye's optical projection and physical view transform; this pass only preserves
// its pixels, reverse-Z depth, and PCRTC fade across the compositor's mapped viewport.

struct VisionImmersiveViewportUniforms {
  float4x4 clip_from_quad;
  float fade;
};

struct VisionImmersiveScreenVertex {
  float4 position [[position]];
  float2 uv;
};

struct VisionImmersiveResolveOutput {
  float4 color [[color(0)]];
  float depth [[depth(any)]];
};

vertex VisionImmersiveScreenVertex vision_immersive_screen_vertex(
    uint vid [[vertex_id]],
    constant VisionImmersiveViewportUniforms& uniforms [[buffer(0)]]) {
  float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
  VisionImmersiveScreenVertex out;
  out.position = uniforms.clip_from_quad * float4(corner, 0.0, 1.0);
  // Texture row 0 is the top of the game frame, exactly as in the present pass.
  out.uv = float2((corner.x + 1.0) * 0.5, (1.0 - corner.y) * 0.5);
  return out;
}

static float3 vision_immersive_srgb_to_linear(float3 encoded) {
  float3 low = encoded / 12.92;
  float3 high = pow((encoded + 0.055) / 1.055, 2.4);
  return select(high, low, encoded <= 0.04045);
}

fragment VisionImmersiveResolveOutput vision_immersive_screen_fragment(
    VisionImmersiveScreenVertex in [[stage_in]],
    texture2d<float> game_color [[texture(0)]],
    depth2d<float> game_depth [[texture(1)]],
    constant VisionImmersiveViewportUniforms& uniforms [[buffer(0)]]) {
  constexpr sampler color_sampler(mag_filter::linear, min_filter::linear,
                                  address::clamp_to_edge);
  constexpr sampler depth_sampler(mag_filter::nearest, min_filter::nearest,
                                  address::clamp_to_edge);
  float3 encoded = saturate(game_color.sample(color_sampler, in.uv).rgb * uniforms.fade);
  float native_depth = saturate(game_depth.sample(depth_sampler, in.uv));

  VisionImmersiveResolveOutput out;
  out.color = float4(vision_immersive_srgb_to_linear(encoded), 1.0);
  // Exact reverse-Z zero is a valid far-sky value. Its behavior at the boundary of opaque
  // compositor reprojection is not established, so conservatively nudge only that boundary while
  // preserving every positive native depth value.
  out.depth = max(native_depth, 1.0f / 1048576.0f);
  return out;
}

// Shows the conventional composed frame on the menu plane. The plane's own raster depth, not the
// game's depth, reaches the compositor, so both eyes place the menu at the chosen distance.
fragment float4 vision_immersive_menu_plane_fragment(
    VisionImmersiveScreenVertex in [[stage_in]],
    texture2d<float> game_color [[texture(0)]],
    constant VisionImmersiveViewportUniforms& uniforms [[buffer(0)]]) {
  constexpr sampler color_sampler(mag_filter::linear, min_filter::linear,
                                  address::clamp_to_edge);
  float3 encoded = saturate(game_color.sample(color_sampler, in.uv).rgb * uniforms.fade);
  return float4(vision_immersive_srgb_to_linear(encoded), 1.0);
}

struct VisionImmersiveSampleRegion {
  // Pixel-space origin x/y and width/height.
  float4 region;
  // Output offset, array slice, reserved, reserved.
  uint4 parameters;
};

kernel void vision_immersive_sample_2d(
    texture2d<float, access::sample> color [[texture(0)]],
    depth2d<float, access::sample> depth [[texture(1)]],
    device float4* samples [[buffer(0)]],
    constant VisionImmersiveSampleRegion& uniforms [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]) {
  if (any(gid >= uint2(8))) {
    return;
  }
  constexpr sampler nearest(mag_filter::nearest, min_filter::nearest,
                            address::clamp_to_edge);
  float2 local = (float2(gid) + 0.5) / 8.0;
  float2 pixel = uniforms.region.xy + local * uniforms.region.zw;
  float2 uv = pixel / float2(color.get_width(), color.get_height());
  uint index = uniforms.parameters.x + gid.y * 8 + gid.x;
  samples[index] = float4(color.sample(nearest, uv).rgb,
                          depth.sample(nearest, uv));
}

kernel void vision_immersive_sample_2d_array(
    texture2d_array<float, access::sample> color [[texture(0)]],
    depth2d_array<float, access::sample> depth [[texture(1)]],
    device float4* samples [[buffer(0)]],
    constant VisionImmersiveSampleRegion& uniforms [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]) {
  if (any(gid >= uint2(8))) {
    return;
  }
  constexpr sampler nearest(mag_filter::nearest, min_filter::nearest,
                            address::clamp_to_edge);
  float2 local = (float2(gid) + 0.5) / 8.0;
  float2 pixel = uniforms.region.xy + local * uniforms.region.zw;
  float2 uv = pixel / float2(color.get_width(), color.get_height());
  uint slice = uniforms.parameters.y;
  uint index = uniforms.parameters.x + gid.y * 8 + gid.x;
  samples[index] = float4(color.sample(nearest, uv, slice).rgb,
                          depth.sample(nearest, uv, slice));
}

#endif
