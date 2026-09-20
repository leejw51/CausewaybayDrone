shader_type spatial;
render_mode cull_disabled;
uniform sampler2D ground_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform sampler2D paving_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool paving = false;
uniform bool mixed_city = false;
uniform float tile_metres = 2.0;
varying vec3 world_position;
varying vec3 terrain_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    terrain_normal = normalize((MODEL_MATRIX * vec4(NORMAL,0.0)).xyz);
    if (terrain_normal.y < 0.0) { terrain_normal = -terrain_normal; }
}
void fragment() {
    NORMAL = normalize((VIEW_MATRIX * vec4(terrain_normal,0.0)).xyz);
    vec2 uv = world_position.xz / tile_metres;
    vec3 fine = mix(texture(ground_texture, uv).rgb, texture(ground_texture, mat2(vec2(.8,.6),vec2(-.6,.8)) * uv * .73 + vec2(.31,.67)).rgb, .5);
    if (paving) { fine = texture(ground_texture, uv).rgb; }
    float distance_blend = smoothstep(12.0, 65.0, distance(world_position, CAMERA_POSITION_WORLD));
    fine = mix(fine, textureLod(ground_texture, vec2(.5), 11.0).rgb, distance_blend * (paving ? .3 : .7));
    vec3 broad = textureLod(ground_texture, uv * .013 + vec2(.37,.61), 5.0).rgb;
    vec3 surface = fine * surface_tint.rgb * mix(.93,1.05,clamp(dot(broad,vec3(.3,.5,.2))*1.8,0.0,1.0));
    float grass = step(.5,COLOR.a);
    ALBEDO = mixed_city ? mix(texture(paving_texture, world_position.xz / 4.0).rgb * .85, surface, grass) : surface;
    ROUGHNESS = .94;
    SPECULAR = .22;
}
