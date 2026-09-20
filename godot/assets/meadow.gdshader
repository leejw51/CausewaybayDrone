shader_type spatial;
render_mode cull_disabled;
varying float height;
void vertex() {
    height = clamp(VERTEX.y / .10,0.0,1.0);
    vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    VERTEX.y *= 1.0 - smoothstep(18.0, 38.0, distance(world, CAMERA_POSITION_WORLD));
    VERTEX.x += sin(world.x*.7 + world.z*.5 + TIME*1.7) * .035 * height * height;
}
void fragment() {
    ALBEDO = COLOR.rgb * mix(.5,1.0,height);
    ROUGHNESS = .93;
    SPECULAR = .15;
    NORMAL = normalize((VIEW_MATRIX * vec4(0.0,1.0,0.0,0.0)).xyz);
}
