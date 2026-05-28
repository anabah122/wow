varying vec2 vAlphaUV;
varying vec2 vTexUV;
varying vec3 vNormal;

#ifdef VERTEX
uniform mat4 viewproj;
attribute vec3 VertexNormal;

vec4 position(mat4 _, vec4 vertex) {
    vAlphaUV = VertexTexCoord.xy;
    vTexUV   = VertexTexCoord.zw;
    vNormal  = VertexNormal;
    return viewproj * vertex;
}
#endif

#ifdef PIXEL
uniform Image layer1;
uniform Image layer2;
uniform Image layer3;
uniform Image layer4;
uniform Image alphaMap;
uniform float texTile;
uniform int   nLayers;

void effect() {
    // ТЕСТ: без текстур, плоский цвет + свет
    // vec2 tuv = vTexUV * texTile;
    // vec3 a   = Texel(alphaMap, vAlphaUV).rgb;
    // vec3 col = Texel(layer1, tuv).rgb;
    // if (nLayers > 1) col = mix(col, Texel(layer2, tuv).rgb, a.r);
    // if (nLayers > 2) col = mix(col, Texel(layer3, tuv).rgb, a.g);
    // if (nLayers > 3) col = mix(col, Texel(layer4, tuv).rgb, a.b);
    vec3 col = vec3(0.4, 0.45, 0.3);

    // направленный свет по нормали MCNR + ambient
    vec3  L     = normalize(vec3(0.4, 1.0, 0.3));
    float diff  = max(dot(normalize(vNormal), L), 0.0);
    float light = 0.4 + 0.6 * diff;

    love_Canvases[0] = vec4(col * light, 1.0);
}
#endif
