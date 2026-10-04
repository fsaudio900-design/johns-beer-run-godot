shader_type canvas_item;
// Full-screen intoxication effects, ported from the web build's post shader:
// drunk wobble/blur/double vision, high (zoom pulse, chroma, saturation),
// trip (kaleidoscope swirl, hue rotation, rainbow), peephole fisheye, flash and grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float u_drunk = 0.0;
uniform float u_high = 0.0;
uniform float u_trip = 0.0;
uniform float u_peep = 0.0;
uniform float u_flash = 0.0;
uniform float u_fade = 0.0;
uniform float u_vignette = 0.35;

vec3 hue_rot(vec3 c, float h) {
	const vec3 k = vec3(0.57735);
	float ca = cos(h);
	return c * ca + cross(k, c) * sin(h) + k * dot(k, c) * (1.0 - ca);
}
vec3 samp(vec2 uv, float ca) {
	vec2 d = (uv - 0.5) * ca;
	return vec3(texture(screen_tex, uv + d).r, texture(screen_tex, uv).g, texture(screen_tex, uv - d).b);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float t = TIME, d = u_drunk, h = u_high, tr = u_trip;
	vec2 suv = SCREEN_UV;
	vec2 uv = suv;
	if (u_peep > 0.001) {
		vec2 pp = (uv - 0.5) * vec2(res.x / res.y, 1.0);
		float pr = length(pp);
		uv = 0.5 + (uv - 0.5) * mix(1.0, 0.58 + 0.9 * pr * pr, u_peep);
	}
	if (tr > 0.001) {
		vec2 p = uv - 0.5; float r = length(p), a = atan(p.y, p.x);
		a += sin(r * 12.0 - t * 2.0) * 0.1 * tr + 0.15 * tr * sin(t * 0.31);
		r *= 1.0 + sin(r * 22.0 - t * 4.0) * 0.025 * tr;
		float seg = 6.28318 / 6.0; float ak = abs(mod(a + t * 0.15, seg) - seg * 0.5);
		vec2 pw = vec2(cos(a), sin(a)) * r, pk = vec2(cos(ak), sin(ak)) * r;
		uv = 0.5 + mix(pw, pk, 0.22 * smoothstep(0.5, 1.0, tr) * (0.5 + 0.5 * sin(t * 0.4)));
		uv += vec2(sin(uv.y * 14.0 + t * 3.0), cos(uv.x * 11.0 + t * 2.6)) * 0.006 * tr;
	}
	uv += vec2(sin(uv.y * 9.0 + t * 1.9), cos(uv.x * 7.0 + t * 1.6)) * 0.008 * d;
	vec2 c = uv - 0.5;
	uv = 0.5 + c * (1.0 + sin(t * 0.8) * 0.03 * d - h * 0.015 * (1.0 + sin(t * 9.0)));
	float ca = d * 0.014 + h * 0.022 + tr * 0.012;
	vec3 col = samp(uv, ca);
	if (d > 0.01) {
		vec2 px = (1.5 + d * 5.0) / res; vec3 acc = vec3(0.0);
		for (int i = 0; i < 8; i++) { float a = float(i) * 0.785398; acc += texture(screen_tex, uv + vec2(cos(a), sin(a)) * px).rgb; }
		col = mix(col, acc / 8.0, clamp(d * 0.9, 0.0, 0.9));
	}
	vec2 off = vec2(sin(t * 0.7), cos(t * 0.53)) * (0.012 + 0.02 * d) * d;
	col = mix(col, samp(uv + off, ca), 0.45 * d);
	if (h > 0.01) {
		vec3 acc = vec3(0.0);
		for (int i = 1; i <= 6; i++) acc += texture(screen_tex, 0.5 + (uv - 0.5) * (1.0 - float(i) * 0.014 * h)).rgb;
		col = mix(col, acc / 6.0, 0.55 * h);
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 1.0 + 0.12 * d + 0.55 * h);
	col = (col - 0.5) * (1.0 + 0.3 * h) + 0.5;
	col *= mix(vec3(1.0), vec3(1.04, 0.98, 0.92), d);
	col += h * 0.07 * vec3(0.5 + 0.5 * sin(t * 6.0), 0.5 + 0.5 * sin(t * 6.0 + 2.1), 0.5 + 0.5 * sin(t * 6.0 + 4.2));
	float r = length((suv - 0.5) * vec2(1.0, 0.85));
	float pulse = 0.5 + 0.5 * sin(t * (1.6 + 3.0 * h));
	float vig = 1.0 - smoothstep(0.32 - 0.12 * d - 0.05 * h * pulse, 0.85, r);
	col *= mix(1.0, vig, 0.3 + 0.55 * d + 0.25 * h);
	// warm HUD vignette from the web build (#vignette)
	col *= 1.0 - u_vignette * smoothstep(0.45, 1.0, length((suv - 0.5) * 2.0) * 0.75) * 0.9;
	if (tr > 0.001) {
		float rr = length(suv - 0.5);
		vec3 rainbow = 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67) + t * 0.22 + rr * 1.6 + dot(col, vec3(0.3, 0.6, 0.1)) * 2.2));
		col = hue_rot(col, t * 1.1 + rr * 3.0 * tr);
		col = mix(col, col * rainbow * 1.6, 0.35 * tr);
		float l3 = dot(col, vec3(0.299, 0.587, 0.114)); col = mix(vec3(l3), col, 1.0 + 0.7 * tr);
		col = (col - 0.5) * (1.0 + 0.15 * tr) + 0.5;
	}
	if (u_peep > 0.001) {
		float pr = length((suv - 0.5) * vec2(res.x / res.y, 1.0));
		float m = smoothstep(0.465, 0.44, pr) * (1.0 - 0.6 * smoothstep(0.18, 0.46, pr));
		col = mix(col, col * m * vec3(0.93, 0.98, 1.06), u_peep);
	}
	col += (fract(sin(dot(suv * res + fract(t) * 91.7, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.016;
	col += u_flash;
	col = mix(col, vec3(0.0), u_fade);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
