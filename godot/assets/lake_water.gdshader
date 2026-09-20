shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.20, 0.76, 0.78);
uniform vec3 deep_color : source_color = vec3(0.035, 0.35, 0.62);
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.23;
uniform float absorption : hint_range(0.01, 4.0) = 0.72;
uniform float surface_roughness : hint_range(0.01, 1.0) = 0.20;
uniform float animation_speed : hint_range(0.0, 3.0) = 1.0;
varying vec3 water_world;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise2(vec2 p) {
	vec2 i=floor(p),f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void vertex() {
	// Leave the surveyed XY footprint and water levels intact. Ripples perturb normals.
	water_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	float t=TIME*animation_speed;
	vec2 p=water_world.xz;
	p+=vec2(noise2(p*.13+vec2(t*.025,0.0)),noise2(p*.16-vec2(0.0,t*.018)))*1.8;
	float a=dot(p,vec2(.83,.56))*2.1+t*1.15;
	float b=dot(p,vec2(-.38,.93))*3.7-t*.92;
	float c=dot(p,vec2(.97,-.24))*8.3+t*1.65;
	vec2 slope=vec2(.83,.56)*cos(a)*.34+vec2(-.38,.93)*cos(b)*.23+vec2(.97,-.24)*cos(c)*.09;
	vec3 world_normal=normalize(vec3(-slope.x*ripple_strength,1.0,-slope.y*ripple_strength));
	NORMAL=normalize((VIEW_MATRIX*vec4(world_normal,0.0)).xyz);
	if (!FRONT_FACING) { NORMAL=-NORMAL; }
	float fresnel=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),4.0);
	float depth_sample=texture(scene_depth,SCREEN_UV).r;
	vec3 ndc=vec3(SCREEN_UV*2.0-1.0,depth_sample);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc.z=depth_sample*2.0-1.0;
	#endif
	vec4 scene_view=INV_PROJECTION_MATRIX*vec4(ndc,1.0);
	scene_view/=max(abs(scene_view.w),0.000001);
	vec3 scene_world=(INV_VIEW_MATRIX*scene_view).xyz;
	float thickness=clamp(water_world.y-scene_world.y,0.0,40.0);
	float absorbed=1.0-exp(-thickness*absorption);
	float edge=smoothstep(0.0,.18,thickness);
	float foam_band=(1.0-smoothstep(.04,.55,thickness))*edge;
	float foam_breakup=smoothstep(.48,.72,noise2(p*2.2+vec2(t*.1,-t*.08)));
	float foam=foam_band*foam_breakup*.65;
	float wave_line = pow(max(0.0,sin(a*.42 + sin(b*.23))),32.0);
	float glint = wave_line * smoothstep(.65,.9,noise2(p*.34)) * .16;
	ALBEDO=mix(shallow_color,deep_color,absorbed);
	ALBEDO=mix(ALBEDO,vec3(.80,.96,1.0),clamp(foam+glint,0.0,1.0));
	METALLIC=0.0;
	SPECULAR=0.75;
	ROUGHNESS=mix(surface_roughness,.55,foam);
	// Real alpha blending exposes the lake bed near shore; deeper/grazing water is denser.
	ALPHA=clamp((.22+absorbed*.64+fresnel*.22+foam*.25)*edge,0.0,.94);
}
