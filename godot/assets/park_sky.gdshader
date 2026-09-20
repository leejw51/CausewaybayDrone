shader_type sky;

// Seamless directional skybox: cloud projection has no panorama seam.
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
float cloud_noise(vec2 p) {
	return noise2(p)*.58+noise2(p*2.03)*.27+noise2(p*4.07)*.15;
}
void sky() {
	float elevation=max(EYEDIR.y,0.0);
	vec3 blue=mix(vec3(.52,.78,.96),vec3(.075,.30,.75),pow(elevation,.45));
	vec2 p=EYEDIR.xz/max(EYEDIR.y+.10,.06)*2.3;
	// Static cloud field keeps sky lighting stable during fleet rendering.
	float n=cloud_noise(p);
	float clouds=smoothstep(.59,.73,n)*smoothstep(.015,.13,elevation);
	vec3 cloud_color=mix(vec3(.64,.78,.92),vec3(1.0,.98,.91),smoothstep(.52,.73,n));
	vec3 color=mix(blue,cloud_color,clouds*.96);
	vec3 sun_dir=normalize(vec3(.40,.55,-.73));
	float sun=dot(EYEDIR,sun_dir);
	color += vec3(1.0,.77,.40)*pow(max(sun,0.0),80.0)*.18;
	color=mix(color,vec3(1.0,.94,.73),smoothstep(.9992,.9997,sun));
	COLOR=mix(vec3(.30,.43,.29),color,smoothstep(-.06,.01,EYEDIR.y));
}
