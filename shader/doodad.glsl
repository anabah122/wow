// forward-рендер doodad-инстансов на террейне: quat-поворот инстанса + альфа-тест + фог
varying vec3 vNormal;
varying float vDist;

#ifdef VERTEX
uniform mat4 viewproj;
uniform float uDepthOffset;   // статичный сдвиг глубины в NDC: 0 обычно, -0.05 для WMO (рисуются «глубже»)

attribute vec3 VertexNormal;
attribute vec3 InstancePos;
attribute vec4 InstanceRot;
attribute float InstanceScale;

vec3 qrot(vec4 q, vec3 v) {
    return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

vec4 position(mat4 _, vec4 vertex) {
    vec3 world = qrot(InstanceRot, vertex.xyz * InstanceScale) + InstancePos;
    vNormal = qrot(InstanceRot, VertexNormal);
    vec4 clip = viewproj * vec4(world, 1.0);
    vDist = clip.w;
    clip.z += uDepthOffset * clip.w;   // статичный сдвиг в NDC (умножаем на w против перспективного деления)
    return clip;
}
#endif

#ifdef PIXEL
uniform Image MainTex;
uniform float uAlphaMode;   // 0 = opaque (альфа игнор), 1 = cutout (alpha-test), 2 = blend, см. doc/render.md

void effect() {
    vec4 col = Texel(MainTex, VaryingTexCoord.xy);
    if (uAlphaMode > 0.5 && uAlphaMode < 1.5 && col.a < 0.8) discard;   // cutout: альфа-тест для листвы/травы

    vec3  L     = normalize(vec3(0.4, 1.0, 0.3));
    float diff  = max(dot(normalize(vNormal), L), 0.0);
    vec3  lit   = col.rgb * (0.4 + 0.6 * diff);

    float fogFar = 1500.0;
    vec3  fogColor = vec3(0.5, 0.6, 0.75);
    float fog = clamp((vDist - 0.6 * fogFar) / (0.4 * fogFar), 0.0, 1.0);
    lit = mix(lit, fogColor, fog);

    float a = (uAlphaMode > 1.5) ? col.a : 1.0;     // только blend-пасс уважает альфу; opaque/cutout твёрдые
    love_Canvases[0] = vec4(lit, a);
}
#endif
