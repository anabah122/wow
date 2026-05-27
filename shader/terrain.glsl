uniform mat4 viewproj;
uniform Image heightTex;
uniform float heightScale;
uniform vec2  worldOffset;

varying vec2 vUv;

#ifdef VERTEX
vec4 position(mat4 _, vec4 p) {
    vec2 uv = VertexTexCoord.xy;
    vec3 s = Texel(heightTex, uv).rgb;
    float h = (s.r + s.g + s.b) / 3.0 * heightScale;
    vUv = uv;
    return viewproj * vec4(p.x + worldOffset.x, h, p.z + worldOffset.y, 1.0);
}
#endif

#ifdef PIXEL
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
    return Texel(heightTex, vUv);
}
#endif
