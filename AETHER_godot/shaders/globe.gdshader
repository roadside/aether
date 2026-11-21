// AETHER – festett pixeles földgömb (canvas_item shader, Godot 4)
// A gömböt alacsony "pixel-felbontáson" számolja (pixels), rendezett
// (Bayer) dither-rel posztereli, így festett pixelgrafika hatású.
shader_type canvas_item;

uniform sampler2D albedo_map : source_color, filter_nearest, repeat_enable;  // nappali színek (NASA Blue Marble, festett pixeles feldolgozás)
uniform sampler2D data_map : filter_nearest, repeat_enable;                  // R: szárazföld, G: sekély víz
uniform sampler2D night_map : source_color, filter_nearest, repeat_enable;   // városfények
uniform sampler2D cloud_map : filter_linear, repeat_enable;                  // felhőzaj

uniform float pixels = 360.0;          // a gömb átmérője "játékpixelben"
uniform float radius = 0.86;           // a gömb sugara a téglalaphoz képest (a többi a légkör)
uniform float spin = 0.0;              // forgás (fordulat), a GDScript állítja
uniform float tilt = 0.35;             // dőlés radiánban
uniform vec3 sun_dir = vec3(-0.62, -0.38, 0.69);
uniform float levels = 9.0;            // színszintek csatornánként (poszterizálás)
uniform float cloud_drift = 0.0;       // felhők elmozdulása (fordulat)
uniform vec3 atmosphere = vec3(0.39, 0.95, 0.89);
uniform float zoom = 1.0;              // nagyítás (1 = egész gömb)
uniform float heat = 0.0;              // melegedés szemléltetése: 0 = ma, 1 = kb. +2 °C a mához képest

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float bayer(vec2 cell) {
	int x = int(mod(cell.x, 4.0));
	int y = int(mod(cell.y, 4.0));
	return (BAYER[y * 4 + x] + 0.5) / 16.0;
}

vec3 posterize(vec3 c, float d) {
	return floor(c * levels + d) / levels;
}

void fragment() {
	vec2 cell = floor(UV * pixels);
	vec2 uv = (cell + 0.5) / pixels;
	vec2 q = uv * 2.0 - 1.0;
	// nagyításkor kör alakú "nagyító": vékony fénylő perem, kívül átlátszó
	// (a fragment()-ben nem lehet return, ezért elágazás)
	bool lens = zoom > 1.001 && dot(q, q) > 0.97;
	vec2 p = q / (radius * zoom);
	float r2 = dot(p, p);
	float d = bayer(cell);
	vec3 L = normalize(sun_dir);

	if (lens) {
		COLOR = dot(q, q) < 1.0 ? vec4(atmosphere, 0.8) : vec4(0.0);
	} else if (r2 > 1.0) {
		// légkör-perem a gömbön kívül
		float dist = sqrt(r2);
		float k = 1.0 - (dist - 1.0) / 0.09;
		if (k <= 0.0) {
			COLOR = vec4(0.0);
		} else {
			vec2 dir = p / dist;
			float lit = clamp(-(dir.x * L.x + dir.y * L.y) * 0.9 + 0.45, 0.15, 1.0);
			float a = pow(k, 2.2) * lit * 0.75;
			a = floor(a * 6.0 + d) / 6.0;
			COLOR = vec4(mix(vec3(0.24, 0.55, 1.0), atmosphere, k), a);
		}
	} else {
		vec3 n = vec3(p.x, p.y, sqrt(max(0.0, 1.0 - r2)));
		float ct = cos(tilt);
		float st = sin(tilt);
		float ny2 = n.y * ct - n.z * st;
		float nz2 = n.y * st + n.z * ct;
		float lat = -asin(clamp(ny2, -1.0, 1.0));
		float lon = atan(n.x, nz2) + spin * TAU;
		vec2 tex = vec2(fract(lon / TAU + 0.5), 0.5 - lat / PI);

		vec3 albedo = texture(albedo_map, tex).rgb;
		vec4 data = texture(data_map, tex);

		// melegedés szemléltetése (nem pontos regionális előrejelzés!)
		float lum = dot(albedo, vec3(0.333));
		if (heat > 0.0) {
			if (data.r > 0.5) {
				// a nem jeges szárazföld szárazabb, sárgásabb árnyalatot kap
				if (lum < 0.7) {
					float band = smoothstep(0.0, 0.6, 1.0 - abs(lat) / 1.2);
					albedo = mix(albedo, vec3(0.62, 0.50, 0.30), heat * 0.35 * band);
				}
			} else if (lum > 0.82 && abs(lat) < 1.05 + heat * 0.25) {
				// a tengeri jég széle a sark felé húzódik
				albedo = vec3(0.10, 0.27, 0.45);
			}
		}
		float ndl = dot(n, L);
		float light = clamp(ndl * 0.95 + 0.12, 0.0, 1.0);
		vec3 col = albedo * (0.25 + light * 0.95);

		// napcsillogás a vízen
		if (data.r < 0.5) {
			vec3 h = normalize(L + vec3(0.0, 0.0, 1.0));
			col += vec3(1.0, 0.95, 0.84) * pow(max(dot(n, h), 0.0), 140.0) * 1.1 * step(0.0, ndl);
		}

		// felhők és árnyékuk
		vec2 ctex = vec2(fract(tex.x + cloud_drift), tex.y);
		float c = texture(cloud_map, ctex).r;
		float cs = texture(cloud_map, ctex + vec2(0.006, 0.004)).r;
		if (cs > 0.55 && c <= 0.55) {
			col *= 0.72;
		}
		float cv = clamp((c - 0.52) / 0.12, 0.0, 1.0);
		vec3 cloud_col = vec3(0.9, 0.95, 1.0) * max(0.1, light);
		col = mix(col, cloud_col, cv > 0.6 ? 1.0 : (cv > 0.3 ? 0.6 : cv));

		// naplemente-sáv és perem-pára
		// keskeny, halvány alkonysáv a nappal-éjszaka határán
		if (ndl > -0.03 && ndl < 0.07) {
			col = mix(col, vec3(1.0, 0.55, 0.31), 0.10 * (1.0 - abs(ndl - 0.02) / 0.05));
		}
		float rim = pow(1.0 - n.z, 3.0);
		col = mix(col, vec3(0.43, 0.75, 1.0), min(0.55, rim * 0.9 * (0.4 + max(0.0, ndl))) * step(-0.1, ndl));

		// éjszakai oldal: városfények
		float night = smoothstep(0.02, -0.12, ndl);
		// éjjel a felszín szinte sötét (kékes árnyalat), csak a városfények világítanak
		vec3 dark_side = col * 0.12 + vec3(0.01, 0.02, 0.05);
		col = mix(col, dark_side + texture(night_map, tex).rgb * (1.0 - cv * 0.8), night);

		COLOR = vec4(posterize(clamp(col, 0.0, 1.0), d), 1.0);
	}
}
