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
uniform vec2  hGrid;      // размер атласа высот в текселях (GRID,GRID)
uniform vec2  mGrid;      // размер маск-атласа в текселях (MTILE,MTILE)
uniform float mChunk;     // окно маски на чанк в текселях (MASK)
uniform float texTile;    // повторов diffuse по чанку

float sampleH(vec2 uv) { return Texel(heightmap, uv).r; }   // R32F: реальная Z в ярдах

vec4 position(mat4 _, vec4 vertex) {
    vec2 grid = VertexTexCoord.xy;             // 0..1 по чанку

    // вершина чанка -> ровно в центр своего текселя высот.
    // iHeightUV — база вершины в текселях (cx*8); +grid*8 -> вершина атласа 0..128; центр = (+0.5)/GRID.
    vec2 vtex = iHeightUV + grid * 8.0;
    vec2 huv  = (vtex + 0.5) / hGrid;
    vec2 hTexel = 1.0 / hGrid;

    float h  = sampleH(huv);
    float hl = sampleH(huv - vec2(hTexel.x, 0.0));
    float hr = sampleH(huv + vec2(hTexel.x, 0.0));
    float hd = sampleH(huv - vec2(0.0, hTexel.y));
    float hu = sampleH(huv + vec2(0.0, hTexel.y));
    float sc = 33.33333 / 8.0;
    vNormal = normalize(vec3(hl - hr, 2.0 * sc, hd - hu));

    // маска: крайние вершины чанка -> центры крайних текселей окна (0.5 и MASK-0.5)
    vec2 mtex = iMaskUV + grid * (mChunk - 1.0);
    vMaskUV = (mtex + 0.5) / mGrid;
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
    // отсутствующие слои -> альфа 0 (как Noggit: alpha.x = 0 при layer_count < n)
    if (vNL < 1.5) mask.r = 0.0;
    if (vNL < 2.5) mask.g = 0.0;
    if (vNL < 3.5) mask.b = 0.0;

    // взвешенная сумма (формула WoW/Noggit, НЕ последовательный mix):
    // база весит 1-(a0+a1+a2), слои аддитивны.
    vec3 col = layerColor(vLayers.x) * (1.0 - (mask.r + mask.g + mask.b))
             + layerColor(vLayers.y) * mask.r
             + layerColor(vLayers.z) * mask.g
             + layerColor(vLayers.w) * mask.b;

    vec3  L     = normalize(vec3(0.4, 1.0, 0.3));
    float diff  = max(dot(normalize(vNormal), L), 0.0);
    float light = 0.4 + 0.6 * diff;
    col *= light;

    float fogFar   = 1500.0;
    vec3  fogColor = vec3(0.5, 0.6, 0.75);   // совпадает с LG.clear
    float fog = clamp((vDist - 0.6 * fogFar) / (0.4 * fogFar), 0.0, 1.0);
    col = mix(col, fogColor, fog);

    love_Canvases[0] = vec4(col, 1.0);
}
#endif
