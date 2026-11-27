shader_type canvas_item;
// A váratlan események nagy képe a földgömb fölött (csak szemléltetés, minden képpont számolt).
// Ugyanazon a "játékpixel"-rácson rajzol, mint a gömb, hogy a kettő egy képnek hasson.
// kind: 1 = vulkán, 2 = járvány, 3 = áttörés.

uniform int kind = 0;
uniform float age = 0.0;
uniform float fade = 1.0;
uniform float pixels = 540.0;
uniform vec2 center = vec2(0.5);      // vulkán: a hegy lába (UV)
uniform float rad = 0.43;             // a gömb sugara UV-ban
uniform vec3 pts[8];                  // csoportok: xy = UV, z = az ottani jel kora mp-ben (<= 0: nem látszik)
uniform int npts = 0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash1(float n) { return fract(sin(n * 91.345 + 7.13) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return s;
}

// gomolygó (karfiolszerű) zaj
float bil(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * (1.0 - abs(2.0 * noise(p) - 1.0));
		p = p * 2.1 + vec2(11.0, 5.0);
		a *= 0.5;
	}
	return s;
}

// "fölé" keverés: c = (szín, fedés)
vec4 over(vec4 dst, vec3 col, float a) {
	a = clamp(a, 0.0, 1.0);
	return vec4(mix(dst.rgb, col, a), dst.a + a * (1.0 - dst.a));
}

// fény hozzáadása (izzás)
vec4 glow(vec4 dst, vec3 col, float a) {
	a = clamp(a, 0.0, 1.0);
	return vec4(dst.rgb * (1.0 - a * 0.35) + col * a, max(dst.a, a));
}

// ------------------------------------------------------------------ vulkán
vec4 volcano(vec2 uv) {
	vec2 p = (uv - center) / rad;
	p.y = -p.y;                                        // fölfelé nő
	float t = age;
	float grow = 1.0 - pow(1.0 - clamp(t / 0.9, 0.0, 1.0), 2.0);
	float W = 0.38;
	float H = 0.36 * grow;
	float Hc = H * 0.80;                               // a kráter pereme
	vec2 top = vec2(0.0, Hc);
	float er = clamp((t - 0.9) / 0.5, 0.0, 1.0);       // a kitörés ereje
	float te = max(t - 0.9, 0.0);
	vec4 c = vec4(0.0);

	// izzás a kráter körül
	float dg = length((p - top) * vec2(1.0, 0.8));
	c = glow(c, vec3(1.0, 0.42, 0.08), exp(-dg * dg / 0.035) * er * (0.55 + 0.1 * sin(t * 9.0)));

	// lökéshullám
	float sh = (t - 0.9) / 1.3;
	if (sh > 0.0 && sh < 1.0) {
		float ring = exp(-pow((length(p - top) - sh * 0.95) / 0.018, 2.0));
		c = glow(c, vec3(1.0, 0.9, 0.7), ring * (1.0 - sh) * 0.7);
	}

	// piroklasztikus felhő a hegy lábánál (a hegy mögött és két oldalán)
	float sp = 0.62 * (1.0 - exp(-max(t - 1.6, 0.0) * 0.45));
	if (sp > 0.02) {
		float flow = t * 0.25 * sign(p.x);
		float nn = fbm(vec2(p.x * 7.0 - flow * 3.0, p.y * 11.0 + 3.0));
		float d = length(vec2(p.x / sp, (p.y - 0.05) / (0.10 + 0.08 * nn)));
		float dens = smoothstep(1.0, 0.5, d + (nn - 0.5) * 0.6);
		float lit = fbm(vec2(p.x * 16.0 - flow * 5.0, p.y * 22.0));
		vec3 col = mix(vec3(0.20, 0.18, 0.17), vec3(0.66, 0.61, 0.56), lit * (0.5 + 2.0 * max(p.y, 0.0) / 0.12));
		c = over(c, col, dens * 0.92);
	}

	// hamuoszlop: emelkedik, a szél jobbra hajlítja, fent ernyővé terül
	vec2 q = p - top;
	float Ht = 0.92 * (1.0 - exp(-te * 0.5));
	if (te > 0.0 && q.y > -0.03) {
		float k = clamp(q.y / 0.92, 0.0, 1.2);
		float xc = 0.42 * k * k;
		float umb = smoothstep(Ht * 0.55, Ht * 0.95, q.y);
		float wd = 0.05 + 0.23 * pow(k, 0.7) + 0.26 * umb * clamp(te / 4.0, 0.0, 1.0);
		vec2 adv = vec2(0.0, -t * 0.45);
		float n1 = fbm(q * 5.0 + adv);
		vec2 bq = (q - vec2(xc, 0.0)) * 8.0 + adv * 1.6 + vec2((n1 - 0.5) * 1.2, 0.0);
		float n2 = bil(bq);
		float n3 = fbm(q * 30.0 + adv * 3.0);
		float d = abs(q.x - xc - (n1 - 0.5) * 0.10) / wd;
		float dens = smoothstep(1.0, 0.6, d + (0.55 - n2) * 0.55 + (n3 - 0.5) * 0.12);
		dens *= smoothstep(-0.03, 0.02, q.y);
		dens *= smoothstep(Ht + 0.05, Ht - 0.07, q.y + (n1 - 0.5) * 0.22);
		// árnyékolás: bal fölülről jön a fény, a gomolyok közti rések sötétek
		float nl = bil(bq + vec2(-0.20, 0.24));
		float shade = clamp(0.48 + (n2 - nl) * 2.4 - (q.x - xc) / wd * 0.24, 0.0, 1.0);
		vec3 col = mix(vec3(0.12, 0.105, 0.10), vec3(0.52, 0.48, 0.45), smoothstep(0.05, 0.95, shade));
		col *= 0.72 + 0.28 * smoothstep(0.25, 0.7, n2);
		col *= 0.92 + 0.16 * n3;
		col = mix(col, vec3(0.74, 0.69, 0.64), smoothstep(0.8, 1.0, shade) * 0.5);
		// a kráter fölött belülről izzik
		float hot = exp(-q.y * 7.5) * (0.55 + 0.6 * n2);
		col = mix(col, vec3(1.0, 0.36, 0.06), clamp(hot * 1.25, 0.0, 1.0));
		col = mix(col, vec3(1.0, 0.85, 0.42), clamp(hot * hot * 1.4 * smoothstep(0.6, 0.15, d), 0.0, 1.0));
		// villám a felhő belsejében
		float cyc = t / 1.37;
		if (t > 2.6 && fract(cyc) < 0.10) {
			vec2 lp = vec2(0.42 * 0.3 + (hash1(floor(cyc)) - 0.5) * 0.3, Ht * (0.45 + 0.35 * hash1(floor(cyc) + 3.0)));
			float ld = length(q - lp);
			col += vec3(0.55, 0.65, 1.0) * exp(-ld * ld / 0.02) * 0.9;
			float bolt = abs(q.x - lp.x - (noise(vec2(q.y * 40.0, floor(cyc))) - 0.5) * 0.09);
			col += vec3(1.0) * smoothstep(0.008, 0.0, bolt) * step(abs(q.y - lp.y), 0.11);
		}
		c = over(c, col, dens);
	}

	// a hegy
	float ax = abs(p.x);
	float ridge = (noise(vec2(p.x * 38.0, 2.0)) - 0.5) * 0.018 + (noise(vec2(p.x * 90.0, 7.0)) - 0.5) * 0.008;
	float cone = H * (1.0 - pow(ax / W, 0.72)) + ridge * grow;
	float rim = Hc + 0.012 * smoothstep(0.0, 0.05, ax) + ridge * 0.6;   // a kráter közepe kicsit mélyebb
	float hp = min(cone, rim);
	if (p.y < hp && p.y > -0.012 && ax < W) {
		float u = p.x / max(1.0 - p.y / max(H, 0.001), 0.06);            // a csúcsból lefutó vonalak mentén állandó
		float gul = fbm(vec2(u * 26.0, p.y * 5.0));
		float fine = fbm(vec2(u * 70.0, p.y * 34.0));
		float light = clamp(0.62 - p.x * 1.9, 0.0, 1.0);
		vec3 rock = mix(vec3(0.055, 0.045, 0.05), vec3(0.36, 0.28, 0.23), light * (0.35 + 0.9 * gul));
		rock *= 0.72 + 0.6 * fine;
		rock = mix(rock, vec3(0.42, 0.40, 0.39), smoothstep(0.62, 0.8, gul) * light * 0.35);   // hamuval fedett gerincek
		rock *= 0.55 + 0.45 * smoothstep(-0.01, 0.07, p.y);              // lent sötétebb
		// lávafolyamok
		float s = clamp((Hc - p.y) / max(Hc, 0.001), 0.0, 1.0);          // 0 = fent, 1 = lent
		vec3 lava = vec3(0.0);
		float lsum = 0.0;
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			float uk = (fi - 2.0) * 0.15 + (hash1(fi) - 0.5) * 0.05;
			float prog = clamp((t - 1.2 - fi * 0.38) / 3.4, 0.0, 1.0) * (0.72 + 0.28 * hash1(fi + 4.0));
			float wob = 0.030 * sin(s * 9.0 + fi * 2.3) + 0.010 * sin(s * 27.0 + fi);
			float du = abs(u - uk - wob);
			float w = 0.009 + 0.008 * s;
			float on = smoothstep(prog + 0.02, prog - 0.03, s);
			float core = exp(-du * du / (w * w)) * on;
			float halo = exp(-du * du / (w * w * 9.0)) * on;
			float flowt = noise(vec2(u * 60.0, s * 26.0 - t * 2.2 + fi * 5.0));
			float cool = smoothstep(0.35, 0.75, flowt) * 0.55 * smoothstep(0.1, 0.9, s);   // megszilárduló kéreg
			lava += mix(vec3(0.95, 0.20, 0.03), vec3(1.0, 0.88, 0.42), core * (1.0 - cool)) * core * (1.0 - cool * 0.8);
			lava += vec3(0.85, 0.22, 0.04) * halo * 0.33;
			lsum += core;
		}
		rock += lava * er;
		// izzó kráterperem
		float rg = smoothstep(0.03, 0.0, hp - p.y) * smoothstep(0.11, 0.0, ax) * er;
		rock += vec3(1.0, 0.55, 0.14) * rg;
		c = over(c, rock, smoothstep(-0.012, 0.0, p.y));
	}

	// lávaszökőkút: izzó cseppek ballisztikus pályán, rövid csóvával
	if (te > 0.0) {
		vec3 f = vec3(0.0);
		for (int i = 0; i < 56; i++) {
			float fi = float(i);
			float per = 1.0 + hash1(fi) * 0.9;
			float pt = mod(te - hash1(fi + 50.0) * per, per);
			float ang = (hash1(fi + 9.0) - 0.5) * 1.5;
			float spd = 0.7 + 1.0 * hash1(fi + 3.0);
			vec2 v0 = vec2(sin(ang), cos(ang)) * spd;
			float kk = pt / per;
			for (int j = 0; j < 3; j++) {
				float tj = pt - float(j) * 0.035;
				if (tj < 0.0) { continue; }
				vec2 pos = top + v0 * tj + vec2(0.0, -1.25 * tj * tj);
				float r = (0.012 + 0.009 * hash1(fi + 5.0)) * (1.15 - kk) * (1.0 - float(j) * 0.25);
				float dd = length(p - pos);
				vec3 fc = mix(vec3(1.0, 0.95, 0.6), vec3(0.95, 0.2, 0.03), kk);
				f += fc * exp(-dd * dd / (r * r)) * (1.0 - kk * 0.6) * (1.0 - float(j) * 0.3);
			}
		}
		c = glow(c, f / max(max(f.r, f.g), 1.0), clamp(max(f.r, f.g), 0.0, 1.0));
	}

	// hulló hamu: apró szürke pöttyök sodródnak lefelé a felhő alól
	if (te > 2.0) {
		vec2 g = vec2(p.x * 46.0 + p.y * 9.0, p.y * 46.0 + t * 7.0);
		float hsh = hash(floor(g));
		vec2 fr = fract(g) - 0.5 - (vec2(hash(floor(g) + 1.0), hash(floor(g) + 2.0)) - 0.5) * 0.6;
		float inplume = smoothstep(0.75, 0.25, abs(p.x - 0.22) / 0.55) * step(0.02, p.y) * step(p.y, Hc + Ht * 0.8);
		float dot_ = smoothstep(0.32, 0.1, length(fr)) * step(0.9, hsh) * inplume;
		c = over(c, vec3(0.45, 0.42, 0.4), dot_ * 0.7);
	}
	return c;
}

// ------------------------------------------------------------------ járvány
vec4 virus(vec4 c, vec2 l, float r, float rot, float seed, float alpha) {
	float dist = length(l);
	if (dist > r * 2.6) { return c; }
	float a = atan(l.y, l.x) + rot;
	// fényudvar
	c = glow(c, vec3(1.0, 0.25, 0.5), exp(-dist * dist / (r * r * 2.6)) * 0.42 * alpha);
	// két sor tüske: a hátsó rövidebb és sötétebb
	for (int ring = 0; ring < 2; ring++) {
		float n = ring == 0 ? 9.0 : 13.0;
		float len = ring == 0 ? 1.22 : 1.5;
		float sector = 6.28318 / n;
		float aa = mod(a + (ring == 0 ? sector * 0.5 : 0.0), sector) - sector * 0.5;
		float lat = abs(aa) * dist;                        // távolság a tüske tengelyétől
		float stalk = smoothstep(r * 0.075, r * 0.035, lat) * step(r * 0.9, dist) * step(dist, r * len);
		vec3 sc = ring == 0 ? vec3(0.55, 0.10, 0.22) : vec3(0.90, 0.30, 0.25);
		c = over(c, sc, stalk * alpha);
		float hd = length(vec2(dist - r * len, lat));
		float hr = r * (ring == 0 ? 0.13 : 0.17);
		if (hd < hr) {
			float z = sqrt(1.0 - hd * hd / (hr * hr));
			vec3 hc = (ring == 0 ? vec3(0.75, 0.22, 0.30) : vec3(1.0, 0.55, 0.35)) * (0.55 + 0.6 * z);
			c = over(c, hc, alpha);
		}
	}
	// a test: megvilágított gömb, foltos felszínnel
	if (dist < r) {
		float z = sqrt(1.0 - dist * dist / (r * r));
		vec3 nrm = normalize(vec3(l / r, z));
		float light = clamp(dot(nrm, normalize(vec3(-0.5, -0.6, 0.65))), 0.0, 1.0);
		vec2 sp = nrm.xy / (0.6 + nrm.z) * 3.2 + seed;      // a gömbre feszített minta
		float cells = noise(sp * 2.6 + rot * 0.3);
		float bumps = fbm(sp * 6.0);
		vec3 base = mix(vec3(0.36, 0.05, 0.20), vec3(0.96, 0.30, 0.50), light);
		base = mix(base, vec3(0.50, 0.08, 0.30), smoothstep(0.52, 0.66, cells) * 0.75);   // sötétebb foltok
		base *= 0.8 + 0.4 * bumps;
		base += vec3(1.0, 0.85, 0.9) * pow(light, 14.0) * 0.6;                            // csillanás
		base = mix(base, vec3(0.22, 0.02, 0.12), smoothstep(0.75, 1.0, dist / r) * 0.6);  // sötét perem
		c = over(c, base, alpha);
	}
	return c;
}

vec4 pandemic(vec2 uv) {
	vec4 c = vec4(0.0);
	vec2 g = (uv - vec2(0.5)) / rad;
	float gd = length(g);
	float t = age;
	// fertőzött pára a Föld fölött: lassan erősödik, majd a tiszta hullám eltörli
	float cl = (t - 5.2) / 2.2;
	if (gd < 1.0) {
		float haze = fbm(g * 3.2 + vec2(t * 0.07, 0.0)) * fbm(g * 9.0 - vec2(0.0, t * 0.11));
		float k = smoothstep(0.6, 4.5, t) * (cl > 0.0 ? smoothstep(cl + 0.02, cl - 0.12, gd) : 1.0);
		k *= smoothstep(1.0, 0.8, gd);
		c = glow(c, vec3(0.95, 0.22, 0.45), smoothstep(0.16, 0.42, haze) * 0.38 * k);
	}
	// a vírus minden csoport fölött, apró kísérőkkel
	for (int i = 0; i < npts; i++) {
		float pa = pts[i].z;
		if (pa <= 0.0) { continue; }
		vec2 l = (uv - pts[i].xy) / rad;
		float pop = 1.0 - pow(1.0 - clamp(pa / 0.5, 0.0, 1.0), 2.0) + 0.14 * sin(clamp(pa, 0.0, 0.9) / 0.9 * 3.14159);
		float r = 0.085 * pop * (1.0 + 0.04 * sin(t * 3.5 + float(i)));
		// táguló gyűrűk
		for (int k = 0; k < 2; k++) {
			float ra = fract(pa * 0.55 + float(k) * 0.5);
			float ring = exp(-pow((length(l) - r * (1.3 + 2.4 * ra)) / 0.006, 2.0));
			c = glow(c, vec3(1.0, 0.4, 0.62), ring * (1.0 - ra) * 0.6);
		}
		for (int j = 0; j < 5; j++) {
			float fj = float(j) + float(i) * 7.0;
			float oa = t * (0.35 + 0.3 * hash1(fj)) + fj * 1.9;
			vec2 off = vec2(cos(oa), sin(oa) * 0.8) * r * (2.0 + 0.9 * hash1(fj + 2.0)) * clamp(pa - 0.4, 0.0, 1.0);
			c = virus(c, l - off, r * (0.16 + 0.1 * hash1(fj + 5.0)), -t * 0.8 + fj, fj, 0.9);
		}
		c = virus(c, l, r, t * 0.35 + float(i), float(i) * 3.7, 1.0);
	}
	// a lezárások után kitisztul a levegő: világos hullám fut végig a Földön
	if (cl > 0.0 && cl < 1.0 && gd < 1.0) {
		float band = exp(-pow((gd - cl) / 0.035, 2.0));
		float soft = smoothstep(cl, cl - 0.35, gd) * step(gd, cl);
		c = glow(c, vec3(0.75, 0.96, 1.0), (band * 0.8 + soft * 0.12) * (1.0 - cl));
	}
	return c;
}

// ------------------------------------------------------------------ áttörés
vec4 breakthrough(vec2 uv) {
	vec4 c = vec4(0.0);
	vec2 g = (uv - vec2(0.5)) / rad;
	float gd = length(g);
	float t = age;
	if (gd < 1.0) {
		// arany fényhullám söpör végig a Földön
		float sweep = (t - 0.4) / 3.2;
		float band = exp(-pow((g.x + 1.2 - sweep * 2.4 + 0.15 * sin(g.y * 5.0 + t)) / 0.16, 2.0));
		c = glow(c, vec3(1.0, 0.86, 0.4), band * 0.42 * smoothstep(1.0, 0.85, gd));
		// csillanások
		vec2 cell = floor(g * 26.0);
		float hsh = hash(cell);
		if (hsh > 0.93) {
			vec2 fr = fract(g * 26.0) - 0.5;
			float tw = pow(0.5 + 0.5 * sin(t * (2.0 + 3.0 * hash(cell + 3.0)) + hsh * 40.0), 10.0) * smoothstep(0.5, 2.0, t);
			float star = max(smoothstep(0.07, 0.0, abs(fr.x)) * smoothstep(0.45, 0.0, abs(fr.y)), smoothstep(0.07, 0.0, abs(fr.y)) * smoothstep(0.45, 0.0, abs(fr.x)));
			c = glow(c, vec3(1.0, 0.95, 0.7), star * tw * 0.95);
		}
	}
	// felkelő nap minden csoport mögött: korong, fényudvar, sugarak
	for (int i = 0; i < npts; i++) {
		float pa = pts[i].z;
		if (pa <= 0.0) { continue; }
		float s = 1.0 - pow(1.0 - clamp(pa / 0.7, 0.0, 1.0), 2.0);
		vec2 l = (uv - pts[i].xy) / rad - vec2(-0.085, -0.17 * s);
		float d = length(l);
		float a = atan(l.y, l.x);
		float rays = 0.5 + 0.5 * sin(a * 14.0 + t * 0.9 + float(i));
		rays = pow(rays, 3.0) * (0.6 + 0.4 * sin(a * 5.0 - t * 0.6));
		float rr = 0.052 * s;
		c = glow(c, vec3(1.0, 0.78, 0.25), exp(-d / 0.07) * 0.5 * s);
		c = glow(c, vec3(1.0, 0.86, 0.4), rays * exp(-d / 0.085) * 0.75 * s * smoothstep(rr * 0.8, rr * 1.3, d));
		if (d < rr) {
			float z = sqrt(1.0 - d * d / (rr * rr));
			vec3 sun = mix(vec3(1.0, 0.62, 0.12), vec3(1.0, 0.97, 0.75), z);
			c = over(c, sun, 1.0);
		}
	}
	return c;
}

void fragment() {
	vec2 uv = (floor(UV * pixels) + 0.5) / pixels;
	vec4 c = vec4(0.0);
	if (kind == 1) {
		c = volcano(uv);
	} else if (kind == 2) {
		c = pandemic(uv);
	} else if (kind == 3) {
		c = breakthrough(uv);
	}
	COLOR = vec4(c.rgb, clamp(c.a, 0.0, 1.0) * fade);
}
