
varying vec3 vWorldPos;
varying vec3 vNormal;

#ifdef VERTEX

uniform mat4 viewproj;
uniform mat4 transform;

attribute vec3 VertexNormal;
attribute vec3 InstancePos;
attribute vec4 InstanceRot;

vec3 qrot(vec4 q, vec3 v) {
    return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 world = qrot(InstanceRot, vertex_position.xyz) + InstancePos;
    vWorldPos  = world;
    vNormal    = qrot(InstanceRot, VertexNormal);
    return viewproj * transform * vec4(world, 1.0);
}

#endif

#ifdef PIXEL

uniform float min_alpha;

uniform vec3  lightDir;
uniform vec3  lightCol;
uniform vec3  ambient;

uniform vec3  fogColor;
uniform float fogDensity;
uniform vec3  cameraPos;

uniform Image lut;
const float LUT_SIZE = 32.0;

vec3 applyLUT(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    float blue = c.b * (LUT_SIZE - 1.0);
    float b0 = floor(blue);
    float b1 = min(b0 + 1.0, LUT_SIZE - 1.0);
    float t  = blue - b0;

    float W = LUT_SIZE * LUT_SIZE; // ширина PNG
    float halfPx = 0.5 / W;
    float u_in   = (c.r * (LUT_SIZE - 1.0) + 0.5) / W;
    float v      = (c.g * (LUT_SIZE - 1.0) + 0.5) / LUT_SIZE;

    vec2 uv0 = vec2(u_in + b0 / LUT_SIZE, v);
    vec2 uv1 = vec2(u_in + b1 / LUT_SIZE, v);
    return mix(Texel(lut, uv0).rgb, Texel(lut, uv1).rgb, t);
}

vec4 effect(vec4 color, Image tex, vec2 texUv, vec2 screen_coords) {
    vec4 col = Texel(tex, texUv);
    if (col.a < min_alpha || col.rgb == vec3(0,1,1)) discard;

    vec3 N = normalize(mix(normalize(vNormal), vec3(0.0, 1.0, 0.0), 0.7));
    float ndl = dot(N, lightDir) * 0.5 + 0.5; // half-lambert
    vec3 lit = col.rgb * mix(ambient, lightCol, ndl) * 1.2;

    float dist = distance(cameraPos, vWorldPos);
    float fog  = exp(-dist * fogDensity);
    lit = mix(fogColor, lit, clamp(fog, 0.0, 1.0));

    lit = applyLUT(lit);
    return vec4(lit, col.a);
}

#endif

