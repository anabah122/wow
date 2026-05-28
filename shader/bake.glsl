#define N 8
uniform Image tiles[N];
uniform vec2 tileOrigin[N];  // мировой origin тайла (левый-нижний угол, метры)
uniform vec2 cameraXZ;
uniform float R;             // полу-сторона квадрата покрытия в мире
uniform float k;             // крутизна деформации
uniform float chunkSize;

vec2 warp(vec2 c) {
    return vec2(sign(c.x) * pow(abs(c.x), k + 1.0),
                sign(c.y) * pow(abs(c.y), k + 1.0));
}

vec4 effect(vec4 _c, Image _t, vec2 uv, vec2 _sc) {
    vec2 c = uv * 2.0 - 1.0;
    vec2 world = cameraXZ + warp(c) * R;
    for (int i = 0; i < N; i++) {
        vec2 local = (world - tileOrigin[i]) / chunkSize;
        if (local.x >= 0.0 && local.y >= 0.0 && local.x < 1.0 && local.y < 1.0) {
            float r = 0.0;
            if      (i == 0) r = Texel(tiles[0], local).r;
            else if (i == 1) r = Texel(tiles[1], local).r;
            else if (i == 2) r = Texel(tiles[2], local).r;
            else if (i == 3) r = Texel(tiles[3], local).r;
            else if (i == 4) r = Texel(tiles[4], local).r;
            else if (i == 5) r = Texel(tiles[5], local).r;
            else if (i == 6) r = Texel(tiles[6], local).r;
            else if (i == 7) r = Texel(tiles[7], local).r;
            return vec4(r, r, r, 1.0);
        }
    }
    discard;
}
