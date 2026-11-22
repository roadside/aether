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
uniform sampler2D anomaly_map : source_color, filter_linear, repeat_enable;  // mai hőmérséklet-eltérés (Climate Pulse)
uniform float anomaly_mix = 0.0;       // 0 = normál Föld, 1 = eltérés-térkép
uniform sampler2D low_map : filter_linear, repeat_enable;   // alacsony partvidék: 1 = 0 m, 0 = 10 m vagy magasabb
uniform float sea_rise = 0.0;          // 0–1: a veszélyeztetett alacsony partok kiemelésének erőssége
uniform float heat = 0.0;              // melegedés szemléltetése: 0 = ma, 1 = kb. +2 °C a mához képest
// A terved hatása (SZEMLÉLTETÉS a modell nettó CO2-sorából, lásd globe.gd clean_of):
uniform float smog = 0.0;              // 0 = nincs pára; 1 = a mai kibocsátás: barnás pára a sűrűn lakott vidékek fölött
uniform float clean = 0.0;             // 0 = mai energia (meleg, narancsos városfény); 1 = nulla kibocsátás (tiszta, hideg fény)
uniform float regrow = 0.0;            // 0–1: nettó CO2-kivonás – a növényzet visszazöldül

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

		// melegedés szemléltetése (heat: 0 = ma, 1 = kb. +2 °C a mához képest).
		// SZEMLÉLTETÉS, NEM regionális előrejelzés: csak a fő irányokat mutatja.
		// – a mai száraz övek (szubtrópus, Mediterráneum, Száhel, Ausztrália, DNy-USA) PEREMÉN
		//   kiszárad a növényzet, terjed a száraz táj; a magas északi szárazföld nem sivatagosodik;
		// – a trópusi esőerdő fakul, de megmarad;
		// – a sarki tengeri jég nagy melegedésnél szinte eltűnik;
		// – Grönland és az Antarktisz jégtakarója 2100-ig megmarad, csak a széle húzódik vissza;
		//   az alacsonyabb szélességű hófoltok, hegyi gleccserek fogynak.
		float lum = dot(albedo, vec3(0.333));
		// a festett térkép eredeti zöldje (a melegedés előtt): ebből tudjuk, hol volt növényzet
		float green0 = clamp((albedo.g - max(albedo.r, albedo.b)) * 6.0 + 0.25, 0.0, 1.0);
		if (heat > 0.0) {
			float alat = abs(lat);
			// foltos, természetes szélű terjedéshez: a felhőzaj két léptéke
			float nz = texture(cloud_map, fract(tex * vec2(6.0, 3.0) + vec2(0.21, 0.57))).r * 0.65
				+ texture(cloud_map, fract(tex * vec2(17.0, 9.0) + vec2(0.63, 0.12))).r * 0.35;
			if (data.r > 0.5) {
				bool ice = lum > 0.72 && albedo.b >= albedo.r * 0.95;
				if (ice) {
					// jég és hó: az alacsonyabb szélességeken (hófoltok, gleccserek) fogy; a nagy
					// jégtakarók (Grönland, Antarktisz belseje) megmaradnak, csak a szélük húzódik vissza
					float edge = 0.98 + heat * 0.24;
					float keep = smoothstep(edge, edge + 0.06, alat + (nz - 0.5) * 0.16);
					albedo = mix(mix(vec3(0.33, 0.35, 0.24), vec3(0.44, 0.41, 0.31), nz), albedo, keep);
				} else {
					// a környék szárazsága: mennyi nem zöld (száraz) felszín van a közelben → a mai
					// sivatagok pereme felől terjed
					vec2 d = vec2(0.012, 0.0);
					float neigh = 0.0;
					for (int k = 0; k < 4; k++) {
						vec2 o = k == 0 ? d.xy : (k == 1 ? -d.xy : (k == 2 ? d.yx * 1.6 : -d.yx * 1.6));
						vec3 a2 = texture(albedo_map, tex + o).rgb;
						neigh += 1.0 - clamp((a2.g - max(a2.r, a2.b)) * 6.0 + 0.25, 0.0, 1.0);
					}
					neigh *= 0.25;
					float green = clamp((albedo.g - max(albedo.r, albedo.b)) * 6.0 + 0.25, 0.0, 1.0);
					// szubtrópusi–mérsékelt száraz sáv; az egyenlítőnél és északon (> kb. 55°) nincs
					float dry_band = smoothstep(0.10, 0.30, alat) * (1.0 - smoothstep(0.72, 0.96, alat));
					float score = dry_band * 0.40 + neigh * 0.38 + (1.0 - green) * 0.10 + nz * 0.18;
					float thr = 1.0 - heat * 0.9;
					// csak a növényzet változik; a mai sivatag a saját festett színét megtartja
					float veg = clamp(0.15 + green * 1.8, 0.0, 1.0);
					float savanna = smoothstep(thr, thr + 0.05, score) * dry_band * (0.5 + 0.5 * veg);
					float desert = smoothstep(thr + 0.09, thr + 0.14, score) * dry_band * veg;
					// a festett textúra világossága megmarad (domborzat, folyóvölgyek), csak a szín változik
					float shade = 0.72 + 0.6 * clamp(lum, 0.0, 0.8);
					albedo = mix(albedo, vec3(0.58, 0.49, 0.27) * shade, savanna * 0.95);
					albedo = mix(albedo, vec3(0.76, 0.61, 0.38) * shade, desert * 0.88);
					// a megmaradó növényzet (esőerdő is) fakóbb, olajzöldebb
					albedo = mix(albedo, vec3(dot(albedo, vec3(0.4, 0.45, 0.15))) * vec3(1.15, 1.0, 0.62), heat * 0.7 * green);
				}
			} else if (lum > 0.6) {
				// tengeri jég: nagy melegedésnél (nyáron) szinte eltűnik, nyílt tenger lesz a helyén
				float edge = 1.08 + heat * 0.46;
				float keep = smoothstep(edge, edge + 0.06, alat + (nz - 0.5) * 0.14);
				albedo = mix(vec3(0.08, 0.24, 0.42), albedo, keep);
			}
		}
		// Visszazöldülés (regrow): ha a világ több CO2-t von ki, mint amennyit kibocsát, ahol eredetileg
		// növényzet volt, ott a táj újra zöldebb, élénkebb lesz (a melegedés fakítását részben visszafordítja).
		// A mai sivatag és a jég nem változik. Csak szemléltetés.
		if (regrow > 0.0 && data.r > 0.5 && lum < 0.72) {
			float was_veg = smoothstep(0.30, 0.65, green0);
			vec3 lush = vec3(0.20, 0.42, 0.16) * (0.75 + 0.6 * clamp(lum, 0.0, 0.8));
			albedo = mix(albedo, lush, regrow * was_veg * 0.55);
		}
		// Tengerszint-emelkedés: a veszélyeztetett ALACSONY PARTOK kiemelése. 2100-ig a tenger
		// kb. 0,4–0,8 métert emelkedik (IPCC AR6). A mai tengerszint fölött legfeljebb 10 m-en fekvő
		// partvidékek (NOAA ETOPO1) itt NEM kerülnek víz alá (ezt sem az emelkedés mértéke, sem az
		// adat függőleges pontossága nem indokolná), hanem figyelmeztető, lassan pulzáló, kék-fehér
		// csíkozást kapnak, ami a tengerszinttel erősödik: „alacsony part, itt a legnagyobb a veszély”
		// (ide ér el egyre gyakrabban a vihardagály és a dagály). Lásd tools/alacsony_partok.py.
		if (sea_rise > 0.0 && data.r > 0.5) {
			float low = texture(low_map, tex).r;
			if (low > 0.02) {
				float stripe = step(0.5, fract((cell.x + cell.y) / 4.0));
				float pulse = 0.65 + 0.35 * sin(TIME * 2.4);
				float k = clamp(sea_rise * 1.6, 0.0, 1.0) * smoothstep(0.02, 0.3, low);
				albedo = mix(albedo, vec3(0.70, 0.93, 1.0), stripe * k * pulse);
				albedo = mix(albedo, albedo * vec3(0.85, 0.95, 1.1), (1.0 - stripe) * k * 0.4);
			}
		}
		float ndl = dot(n, L);
		float light = clamp(ndl * 0.95 + 0.12, 0.0, 1.0);
		vec3 col = albedo * (0.25 + light * 0.95);

		// Pára (smog): a sűrűn lakott, iparosodott vidékek (ahol éjjel sok a fény) fölött barnás-szürke
		// pára a kibocsátással arányosan; ahogy a terved szerint csökken a kibocsátás, kitisztul.
		// Csak szemléltetés (az égetéssel járó szennyezés a CO2-vel együtt csökken).
		if (smog > 0.0) {
			vec2 o = vec2(0.006, 0.0);
			float lights = 0.0;
			lights += dot(texture(night_map, tex).rgb, vec3(0.333));
			lights += dot(texture(night_map, tex + o.xy * 2.0).rgb, vec3(0.333));
			lights += dot(texture(night_map, tex - o.xy * 2.0).rgb, vec3(0.333));
			lights += dot(texture(night_map, tex + o.yx * 3.0).rgb, vec3(0.333));
			lights += dot(texture(night_map, tex - o.yx * 3.0).rgb, vec3(0.333));
			lights *= 0.2;
			float hz = clamp(smog, 0.0, 1.0) * (smoothstep(0.02, 0.22, lights) * 0.42 + 0.05);
			vec3 haze_col = vec3(0.66, 0.58, 0.46) * (0.25 + light * 0.95);
			col = mix(col, haze_col, hz * step(-0.05, ndl));
		}

		// napcsillogás a vízen
		if (data.r < 0.5) {
			vec3 h = normalize(L + vec3(0.0, 0.0, 1.0));
			// visszafogott csillogás: a tavak a Nap alatt ne világítsanak hófehéren
			col += vec3(1.0, 0.95, 0.84) * pow(max(dot(n, h), 0.0), 140.0) * 0.55 * step(0.0, ndl);
		}

		// felhők és árnyékuk
		vec2 ctex = vec2(fract(tex.x + cloud_drift), tex.y);
		// finomabb részlet: a nagy felhőfoltok szélét egy sűrűbb, elmozdított minta tördeli,
		// így nem egyszínű „papírkivágás”, hanem gomolyos, festményszerű felhő lesz
		float fine = texture(cloud_map, fract(ctex * vec2(3.0, 2.0) + vec2(0.37, 0.11))).r;
		float c = texture(cloud_map, ctex).r * 0.78 + fine * 0.22;
		float cs = texture(cloud_map, ctex + vec2(0.006, 0.004)).r;
		if (cs > 0.55 && c <= 0.52) {
			col *= 0.78;
		}
		float cv = clamp((c - 0.48) / 0.18, 0.0, 1.0);
		// vastagabb felhő fehérebb, a vékony széle kékesebb és áttetszőbb
		vec3 cloud_col = mix(vec3(0.70, 0.79, 0.90), vec3(0.94, 0.97, 1.0), cv) * max(0.1, light);
		// 5 lépcsős, ditherelt felhőszél: lágy, de pixeles marad
		col = mix(col, cloud_col, min(1.0, floor(cv * 5.0 + d) / 5.0) * 0.9);

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
		// a városfény színe: mai energia (meleg, narancsos) → nulla kibocsátás (tiszta, hideg fehér)
		vec3 city = texture(night_map, tex).rgb;
		city = mix(city, vec3(dot(city, vec3(0.333))) * vec3(1.25, 1.50, 1.85), clamp(clean, 0.0, 1.0));
		col = mix(col, dark_side + city * (1.0 - cv * 0.8), night);

		// Mai hőmérséklet-eltérés (Copernicus Climate Pulse, ERA5): a színes térkép a felszínre
		// kerül; az éjszakai oldal is látszik, csak kicsit sötétebb, hogy a gömb térbeli maradjon.
		if (anomaly_mix > 0.0) {
			vec3 an = texture(anomaly_map, tex).rgb;
			float shade = 0.55 + 0.45 * clamp(ndl * 1.5 + 0.5, 0.0, 1.0);
			vec3 anc = an * shade + vec3(0.43, 0.75, 1.0) * rim * 0.25;
			// partvonalak, hogy látszódjon, melyik ország hol van
			vec2 e = vec2(1.0 / 2048.0, 0.0);
			float land = texture(data_map, tex).r;
			float edge = abs(land - texture(data_map, tex + e.xy).r) + abs(land - texture(data_map, tex + e.yx * 2.0).r);
			anc = mix(anc, vec3(0.12, 0.14, 0.2), clamp(edge, 0.0, 1.0) * 0.8);
			col = mix(col, anc, anomaly_mix);
		}

		COLOR = vec4(posterize(clamp(col, 0.0, 1.0), d), 1.0);
	}
}
