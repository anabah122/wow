// шейдер РЕДАКТОРА террейна. модель весов отличается от игрового terrain.glsl:
// веса материалов — ArrayImage (слой = глобальный индекс материала), читаются по vUV без
// зажима в чанк -> на стыке чанков тот же слой -> бесшовная интерполяция.
// per-chunk хранятся лишь 4 индекса материалов (валидатор ≤4); композитинг по ним.
#define CHUNK  64.0
#define BLOCK  10.0
#define SIZE   640.0
#define HSIZE  641.0
#define HTEXEL (1.0 / HSIZE)

uniform mat4 viewproj;
uniform vec2 uBlockOrigin;     // смещение блока в мире (ячейки)
uniform Image heightmap;       // карта высот блока (R), SIZE+1
uniform ArrayImage weights;    // веса материалов: слой = глобальный индекс материала, HSIZE
uniform Image matIndexMap;     // 1 пиксель = чанк, RGBA = 4 индекса / total
uniform float uMatCount;       // всего материалов (для разворота индексов)

vec2 inset(vec2 uv) { return uv * (1.0 - HTEXEL) + HTEXEL * 0.5; }

#ifdef VERTEX
attribute vec2 iChunkXZ;       // смещение чанка в блоке (ячейки)
#endif

varying vec2 vUV;              // UV блока 0..1
varying vec2 vChunk;          // индекс чанка (cx,cy)
varying vec2 vTileUV;         // мировые ячейки для повтора плитки
varying vec3 vNormal;

float sampleH(vec2 uv) { return Texel(heightmap, uv).r; }

#ifdef VERTEX
vec4 position(mat4 _, vec4 p) {
    vec2 blockXZ = iChunkXZ + VertexPosition.xy;
    vUV = blockXZ / SIZE;
    vChunk = iChunkXZ / CHUNK;
    vTileUV = blockXZ;

    vec2 huv = inset(vUV);
    float h = sampleH(huv);

    float hL = sampleH(huv - vec2(HTEXEL, 0.0));
    float hR = sampleH(huv + vec2(HTEXEL, 0.0));
    float hD = sampleH(huv - vec2(0.0, HTEXEL));
    float hU = sampleH(huv + vec2(0.0, HTEXEL));
    vNormal = normalize(vec3(hL - hR, 2.0 * HTEXEL * SIZE, hD - hU));

    vec3 world = vec3(uBlockOrigin.x + blockXZ.x, h, uBlockOrigin.y + blockXZ.y);
    return viewproj * vec4(world, 1.0);
}
#endif

#ifdef PIXEL
uniform ArrayImage tiles;      // текстуры материалов (слой = индекс материала)

vec3 tileColor(float idx) {
    return Texel(tiles, vec3(vTileUV, idx - 1.0)).rgb;
}

// вес материала с глобальным индексом idx из его слоя ArrayImage (по vUV — бесшовно).
float matWeight(float idx) {
    return Texel(weights, vec3(inset(vUV), idx - 1.0)).r;
}

vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
    vec4 idx = Texel(matIndexMap, vUV);            // 4 индекса материалов чанка (nearest)
    vec4 gi = floor(idx * uMatCount + 0.5);        // развёрнутые глобальные индексы (0 = пусто)

<<<<<<< HEAD
    // слот 1 (gi.r) — база чанка (фон, без альфы). пусто (0) -> дефолтный материал 1.
    // слоты 2..4 — накладки, альфа-композитинг (over): кроют нижнее по своей альфе.
    vec3 col = tileColor(gi.r > 0.5 ? gi.r : 1.0);
=======
    // слот 1 (gi.r) — база чанка (фон), слоты 2..4 — накладки. альфа-композитинг (over):
    // каждая накладка кроет нижнее по своей альфе. независимые веса -> нет проступающей базы.
    vec3 col = tileColor(gi.r);
>>>>>>> 5dea7a51be442304df25c2e81bf34b7059ba6cb0
    if (gi.g > 0.5) col = mix(col, tileColor(gi.g), matWeight(gi.g));
    if (gi.b > 0.5) col = mix(col, tileColor(gi.b), matWeight(gi.b));
    if (gi.a > 0.5) col = mix(col, tileColor(gi.a), matWeight(gi.a));

    vec3 n = normalize(vNormal);
    float diff = max(dot(n, normalize(vec3(0.4, 1.0, 0.3))), 0.0);
    col *= 0.3 + 0.7 * diff;
    return vec4(col, 1.0);
}
#endif
