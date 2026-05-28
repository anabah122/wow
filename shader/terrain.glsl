uniform mat4 viewproj;
uniform float hScale;
uniform Image heightmap;       // атлас
uniform vec2 atlasTexelSize;   // 1/atlasW, 1/atlasH
uniform vec2 tileUvSize;       // размер тайла в UV атласа (без паддинга)
uniform float cellSize;        // мировое расстояние между соседними сэмплами высоты

#ifdef VERTEX
attribute vec2 iWorldXZ;
attribute vec2 iAtlasUV;
#endif

varying float height;
varying vec3 vNormal;

float sampleH(vec2 uv) { return Texel(heightmap, uv).r; }

#ifdef VERTEX
vec4 position(mat4 _, vec4 p) {
    vec2 localUv = VertexTexCoord.xy;
    vec2 uv = iAtlasUV + localUv * tileUvSize;
    float h = sampleH(uv) * hScale;
    height = h;

    float hL = sampleH(uv - vec2(atlasTexelSize.x, 0.0)) * hScale;
    float hR = sampleH(uv + vec2(atlasTexelSize.x, 0.0)) * hScale;
    float hD = sampleH(uv - vec2(0.0, atlasTexelSize.y)) * hScale;
    float hU = sampleH(uv + vec2(0.0, atlasTexelSize.y)) * hScale;
    vNormal = normalize(vec3(hL - hR, 2.0 * cellSize, hD - hU));

    vec3 pos = vec3(p.x + iWorldXZ.x, p.y + h, p.z + iWorldXZ.y);
    return viewproj * vec4(pos, 1.0);
}
#endif

#ifdef PIXEL
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
    float h = height / hScale;
    vec3 col = mix(vec3(0.1, 0.3, 0.5), vec3(0.9, 0.9, 0.6), h);
    vec3 n = normalize(vNormal);
    float diff = max(dot(n, normalize(vec3(0.4, 1.0, 0.3))), 0.0);
    col *= 0.3 + 0.7 * diff;
    return vec4(col, 1.0);
}
#endif
