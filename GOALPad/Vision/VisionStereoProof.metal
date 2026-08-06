#include <metal_stdlib>

using namespace metal;

struct VisionStereoProofVertex {
  float3 position;
  float3 color;
};

struct VisionStereoProofUniforms {
  float4x4 model;
  float4x4 view_projection;
};

struct VisionStereoProofVertexOut {
  float4 position [[position]];
  float3 color;
};

vertex VisionStereoProofVertexOut vision_stereo_proof_vertex(
    uint vertex_id [[vertex_id]],
    constant VisionStereoProofVertex* vertices [[buffer(0)]],
    constant VisionStereoProofUniforms& uniforms [[buffer(1)]]) {
  VisionStereoProofVertexOut out;
  const VisionStereoProofVertex proof_vertex = vertices[vertex_id];
  const float4 world_position = uniforms.model * float4(proof_vertex.position, 1.0);
  out.position = uniforms.view_projection * world_position;
  out.color = proof_vertex.color;
  return out;
}

fragment float4 vision_stereo_proof_fragment(VisionStereoProofVertexOut in [[stage_in]]) {
  return float4(in.color, 1.0);
}
