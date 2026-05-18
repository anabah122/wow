
#ifdef VERTEX

uniform mat4 viewproj;
uniform mat4 transform;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    return viewproj * transform * vertex_position;
}

#endif

#ifdef PIXEL

uniform float min_alpha;

vec4 effect(vec4 color, Image tex, vec2 texUv, vec2 screen_coords) {

    vec4 col  = Texel(tex, texUv);
    if (col.a < min_alpha) discard;
    return col;
}

#endif
