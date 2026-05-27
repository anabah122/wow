
#ifdef VERTEX

uniform vec3 posOffset;
uniform mat4 viewproj;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 vpos = vertex_position.xyz + posOffset ;
    return viewproj * vec4(vpos,1.0);
}
#endif

#ifdef PIXEL

uniform float min_alpha;
uniform vec3 skyTint;

vec4 effect(vec4 color, Image tex, vec2 texUv, vec2 screen_coords) {
    vec4 col = Texel(tex, texUv);
    if (col.a < min_alpha || col.rgb == vec3(0,1,1)) discard;
    col.rgb *= skyTint;
    return col;
}

#endif
