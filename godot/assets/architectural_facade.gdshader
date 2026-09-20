shader_type spatial;
render_mode cull_disabled;
uniform sampler2D concrete_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
float random_cell(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
    // Estimated modular facade, not a reconstruction of any named building.
    vec2 module = UV / vec2(3.0, 3.2);
    vec2 cell = fract(module);
    vec2 aa = max(fwidth(module), vec2(.001));
    vec2 inside = smoothstep(vec2(.17, .23), vec2(.17, .23) + aa, cell)
        * (1.0 - smoothstep(vec2(.83, .88) - aa, vec2(.83, .88), cell));
    float window = inside.x * inside.y * step(.5, COLOR.a) * step(.5, UV.y);
    vec2 glass_inside = smoothstep(vec2(.19, .25), vec2(.19, .25) + aa, cell)
        * (1.0 - smoothstep(vec2(.81, .86) - aa, vec2(.81, .86), cell));
    float glass = glass_inside.x * glass_inside.y * window;
    float mullion = 1.0 - smoothstep(.009, .009 + aa.x, abs(cell.x - .5));
    glass *= 1.0 - mullion;
    float variation = random_cell(floor(module));
    vec3 mineral = texture(concrete_texture, UV / 2.0).rgb;
    vec3 wall = mineral * COLOR.rgb * .95;
    vec3 pane = mix(vec3(.075,.12,.15),vec3(.23,.31,.34),variation);
    // Some closed blinds give occupied buildings variation without emissive daytime windows.
    pane = mix(pane, vec3(.42,.43,.40),step(.83,variation));
    ALBEDO = mix(mix(wall, vec3(.20,.22,.22),window),pane,glass);
    ROUGHNESS = mix(.42,.22,glass);
    METALLIC = glass * .1;
    SPECULAR = mix(.25,.65,glass);
}
