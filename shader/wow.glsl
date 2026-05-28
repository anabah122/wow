varying vec3 vNormal;
varying vec2 vMaskUV;     // UV чанка в маск-атласе
varying vec2 vTexUV;      // повтор diffuse
varying vec4 vLayers;     // 4 индекса текстур (1-based, 0 = нет)
varying float vNL;
varying float vDist;      // расстояние до камеры (для фога)

#ifdef VERTEX
attribute vec2 iWorldXZ;
attribute vec2 iHeightUV;
attribute vec2 iMaskUV;
attribute vec4 iLayers;
attribute float iNLayers;

uniform mat4  viewproj;
uniform Image heightmap;
uniform float hTexel;     // 1/HATLAS
uniform float hSpan;      // окно чанка высот в UV (8/HATLAS)
uniform float mSpan;      // полезное окно маски: (MASK-1)/MATLAS
uniform float mInset;     // полтекселя: 0.5/MATLAS
uniform float texTile;    // повторов diffuse по чанку

float sampleH(vec2 uv) { return Texel(heightmap, uv).r; }

vec4 position(mat4 _, vec4 vertex) {
    vec2 grid = VertexTexCoord.xy;             // 0..1 по чанку
    vec2 huv  = iHeightUV + grid * hSpan;

    float h  = sampleH(huv);
    float hl = sampleH(huv - vec2(hTexel, 0.0));
    float hr = sampleH(huv + vec2(hTexel, 0.0));
    float hd = sampleH(huv - vec2(0.0, hTexel));
    float hu = sampleH(huv + vec2(0.0, hTexel));
    float sc = 33.33333 / 8.0;
    vNormal = normalize(vec3(hl - hr, 2.0 * sc, hd - hu));

    // маска: инсет полтекселя, чтобы linear на краю окна не тянул соседний чанк
    vMaskUV = iMaskUV + grid * mSpan + mInset;
    vTexUV  = grid * texTile;
    vLayers = iLayers;
    vNL     = iNLayers;

    vec3 world = vec3(iWorldXZ.x + VertexPosition.x, h, iWorldXZ.y + VertexPosition.y);
    vec4 clip = viewproj * vec4(world, 1.0);
    vDist = clip.w;   // ≈ глубина в view-пространстве
    return clip;
}
#endif

#ifdef PIXEL
uniform ArrayImage diffuse;
uniform Image maskmap;

vec3 layerColor(float idx) {
    return Texel(diffuse, vec3(vTexUV, idx - 1.0)).rgb;  // idx 1-based -> слой array
}

void effect() {
    vec3 mask = Texel(maskmap, vMaskUV).rgb;  // R/G/B = альфа слоёв 1/2/3

    vec3 col = layerColor(vLayers.x);                       // base
    if (vNL > 1.5) col = mix(col, layerColor(vLayers.y), mask.r);
    if (vNL > 2.5) col = mix(col, layerColor(vLayers.z), mask.g);
    if (vNL > 3.5) col = mix(col, layerColor(vLayers.w), mask.b);

    vec3  L     = normalize(vec3(0.4, 1.0, 0.3));
    float diff  = max(dot(normalize(vNormal), L), 0.0);
    float light = 0.4 + 0.6 * diff;
    col *= light;

    float fogFar   = 2500.0;
    vec3  fogColor = vec3(0.5, 0.6, 0.75);   // совпадает с LG.clear
    float fog = clamp((vDist - 0.6 * fogFar) / (0.4 * fogFar), 0.0, 1.0);
    col = mix(col, fogColor, fog);

    love_Canvases[0] = vec4(col, 1.0);
}
#endif
