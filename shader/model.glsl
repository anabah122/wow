uniform mat4 viewproj;

varying vec3 vNormal;

#ifdef VERTEX
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
    return viewproj * vec4(world, 1.0);
}
#endif

#ifdef PIXEL
vec4 effect(vec4 c, Image tex, vec2 uv, vec2 sc) {
    vec4 col = Texel(tex, uv);
    if (col.a < 0.5) discard;
    vec3 N = normalize(vNormal);
    float diff = max(dot(N, normalize(vec3(0.4, 1.0, 0.3))), 0.0);
    col.rgb *= 0.4 + 0.6 * diff;
    return col;
}
#endif
