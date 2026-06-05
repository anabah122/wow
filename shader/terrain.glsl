// размеры статичны (dims.lua): CHUNK=64, BLOCK=10, SIZE=640, карта высот/весов = SIZE+1
#define CHUNK  64.0
#define BLOCK  10.0
#define SIZE   640.0
#define HSIZE  641.0
#define HTEXEL (1.0 / HSIZE)

uniform mat4 viewproj;
uniform vec2 uBlockOrigin;     // смещение блока в мире (ячейки)
uniform Image heightmap;       // карта высот блока (R), SIZE+1
uniform Image materialmap;     // веса 4 материалов (RGBA), SIZE+1
uniform Image matIndexMap;     // 1 пиксель = чанк, RGBA = 4 индекса / total
uniform float uMatCount;       // всего материалов (для разворота индексов)

// крайние вершины блока -> центры крайних текселей
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
    vTileUV = blockXZ;                              // 1 плитка на ячейку; повтор через wrap

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

vec3 tileColor(float norm) {
    float idx = floor(norm * uMatCount + 0.5);
    return Texel(tiles, vec3(vTileUV, idx - 1.0)).rgb;
}

vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
    // веса: UV зажат в кусок СВОЕГО чанка (half-texel внутрь) -> linear не лезет к соседу
    vec2 lo = (vChunk * CHUNK + 0.5) * HTEXEL;
    vec2 hi = (vChunk * CHUNK + CHUNK - 0.5) * HTEXEL;
    vec3 w  = Texel(materialmap, clamp(vUV, lo, hi)).rgb;

    vec4 idx = Texel(matIndexMap, vUV);            // индексы per-chunk, nearest
    float base = 1.0 - (w.r + w.g + w.b);
    vec3 col = tileColor(idx.r) * base
             + tileColor(idx.g) * w.r
             + tileColor(idx.b) * w.g
             + tileColor(idx.a) * w.b;

    vec3 n = normalize(vNormal);
    float diff = max(dot(n, normalize(vec3(0.4, 1.0, 0.3))), 0.0);
    col *= 0.3 + 0.7 * diff;
    return vec4(col, 1.0);
}
#endif
