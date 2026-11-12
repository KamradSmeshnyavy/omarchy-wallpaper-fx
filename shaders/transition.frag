#version 440
// Переходы обоев kamradsmeshnyavy.background: один шейдер, эффект выбирает `mode`.
// fromTex — старые обои, toTex — новые, оба уже обрезаны под экран (ShaderEffectSource).
// Сборка: just shaders-wallpaper (qsb → transition.frag.qsb).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;  // 0 → 1
    float mode;      // номер эффекта, см. TransitionEffect.qml
    float angle;     // направление wipe / wave / slide, радианы
    float softness;  // ширина мягкого края, доля экрана
    float aspect;    // ширина / высота
    float seed;      // случайность на каждый переход
    vec2 origin;     // центр круга и волн, 0..1
    // contagion / outline (режимы 23, 24)
    float cell;      // размер клетки фронта, px экрана
    float glow;      // 0..1, сила вспышек и свечения фронта
    float lineW;     // толщина линии контура, px
    float hasMap;    // 1 — карты outline загружены
    float sw;        // размер экрана, px
    float sh;
    float mapW;      // размер карт outline, тексели
    float mapH;
    float mapKind;   // 0 — контур персонажа (есть заливка), 1 — линии картинки (заливки нет)
    vec4 cropTo;     // uv карты = xy + uv экрана * zw (обрезка новых обоев под экран)
    vec4 ember;      // самый яркий цвет новой палитры — вспышки фронта
    vec4 ink;        // самый светлый — линия на тёмном
    vec4 inkDark;    // самый тёмный — линия на светлом
};

layout(binding = 1) uniform sampler2D fromTex;
layout(binding = 2) uniform sampler2D toTex;
// Карты outline (scripts/wallpaper-fx-outline), в пространстве новых обоев:
//   fieldTex R — глубина внутри персонажа (0 на контуре), G — знаковое расстояние до контура
//   (±16 px карты, 0.5 — сам контур, меньше — внутри), B — место на контуре (0 — не контур);
//   growTex R/G — 16-битный порядок, в котором приходит всё снаружи персонажа.
layout(binding = 3) uniform sampler2D fieldTex;
layout(binding = 4) uniform sampler2D growTex;

const float PI = 3.14159265;

float rand(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }

// Плавный шум для «прогорания»: билинейная интерполяция случайных узлов.
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(rand(i), rand(i + vec2(1, 0)), u.x), mix(rand(i + vec2(0, 1)), rand(i + vec2(1, 1)), u.x), u.y);
}

vec4 A(vec2 uv) { return texture(fromTex, clamp(uv, 0.0, 1.0)); }
vec4 B(vec2 uv) { return texture(toTex, clamp(uv, 0.0, 1.0)); }

// d > 0 — уже открыто. Мягкий край шириной softness.
float reveal(float d) {
    float s = max(softness, 0.0008);
    return smoothstep(-s, s, d);
}

// Порог, который за progress проходит отрезок [lo, hi] с запасом под мягкий край.
float sweep(float lo, float hi) {
    float s = max(softness, 0.0008);
    return mix(lo - s, hi + s, progress);
}

// Самое дальнее расстояние от origin до угла экрана (в координатах с учётом aspect).
float farthest(vec2 o) {
    vec2 a = vec2(aspect, 1.0);
    return max(max(length(o * a), length((o - vec2(1, 0)) * a)),
               max(length((o - vec2(0, 1)) * a), length((o - vec2(1, 1)) * a)));
}

// ───────────── contagion / outline ─────────────

float hash2(vec2 p) { return fract(sin(dot(p, vec2(41.37, 289.13)) + seed * 917.3) * 24634.6345); }
float fbm(vec2 p) { return noise(p) * 0.55 + noise(p * 2.13 + 3.7) * 0.3 + noise(p * 4.41 + 9.1) * 0.15; }
float fbm2(vec2 p) { return noise(p) * 0.65 + noise(p * 2.13 + 3.7) * 0.35; }
float easeS(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }
// Зум «камеры» вокруг центра: z > 1 — чуть ближе.
vec2 zoomed(vec2 uv, float z) { return 0.5 + (uv - 0.5) / z; }

// Сетка колоний 3×2, по одной в каждой ячейке со случайным сдвигом: до ближайшей колонии
// никогда не дальше диагонали ячейки, поэтому верхняя граница времени прихода известна заранее
// и к концу перехода гарантированно перевёрнуто всё.
const float LIFE = 0.06;   // сколько «горит» только что перевёрнутая клетка, в долях хода
float contagionBound() { return 0.32 + 1.3 * length(vec2(aspect / 3.0, 0.5)) + 0.08; }
float arrival(vec2 q) {
    vec2 qa = q * vec2(aspect, 1.0);
    vec2 warp = vec2(fbm2(qa * 2.6 + seed * 17.0), fbm2(qa * 2.6 + 31.0 + seed * 11.0)) - 0.5;
    vec2 w = q + warp * vec2(0.09 / aspect, 0.09);
    float rough = 0.7 + 0.6 * fbm(qa * 7.5 + seed * 5.0);
    float a = 1e3;
    for (int i = 0; i < 6; i++) {
        vec2 g = vec2(float(i % 3), float(i / 3));
        vec2 s = (g + 0.12 + 0.76 * vec2(hash2(g + 0.31), hash2(g + 7.77))) / vec2(3.0, 2.0);
        float start = (i == int(seed * 6.0) % 6) ? 0.0 : 0.32 * hash2(g + 2.9);
        a = min(a, start + length((w - s) * vec2(aspect, 1.0)) * rough);
    }
    return a / contagionBound();
}

vec3 contagion(vec2 uv) {
    vec2 px = vec2(sw, sh);
    vec2 grid = px / max(cell, 1.0);
    vec2 id = floor(uv * grid);
    float T = easeS(progress) * (1.0 + LIFE + 0.02) - 0.01;
    float a = arrival((id + 0.5) / grid);
    float flick = hash2(id);
    vec3 hot = mix(ember.rgb, vec3(1.0), 0.2);
    // гладкий фронт — для свечения и кромки (раньше кромку искали 4 лишними arrival у соседей)
    float as_ = arrival(uv);
    vec3 c;
    if (a > T) {
        c = A(uv).rgb;
        float ahead = a - T;                       // искра: одинокая клетка перед фронтом
        if (flick > 0.986 && ahead < 0.025 && T > 0.0)
            c = mix(c, hot, (1.0 - ahead / 0.025) * 0.85 * glow);
    } else {
        c = B(zoomed(uv, 1.0 + 0.02 * (1.0 - easeS(progress)))).rgb;
        float life = clamp((T - a) / LIFE, 0.0, 1.0);
        float edge = 1.0 - smoothstep(0.0, LIFE * 0.4, T - as_);
        float burn = (1.0 - life) * (1.0 - life) * (0.5 + 0.5 * edge);
        c = mix(c, hot, burn * (0.5 + 0.5 * flick) * 0.85 * glow);
    }
    // тонкое свечение вдоль фронта; sin(πp) — ровно ноль в начале и в конце
    return c + ember.rgb * 0.24 * glow * sin(PI * progress) * exp(-abs(as_ - T) / 0.007);
}

float grow16(vec2 muv) {
    vec2 sz = vec2(mapW, mapH);
    vec2 p = muv * sz - 0.5;
    vec2 i = floor(p), f = p - i;
    // байты интерполируются вручную: билинейный фильтр смешал бы старший и младший отдельно
    vec4 v00 = texture(growTex, (clamp(i, vec2(0.0), sz - 1.0) + 0.5) / sz);
    vec4 v10 = texture(growTex, (clamp(i + vec2(1, 0), vec2(0.0), sz - 1.0) + 0.5) / sz);
    vec4 v01 = texture(growTex, (clamp(i + vec2(0, 1), vec2(0.0), sz - 1.0) + 0.5) / sz);
    vec4 v11 = texture(growTex, (clamp(i + vec2(1, 1), vec2(0.0), sz - 1.0) + 0.5) / sz);
    #define D16(v) ((floor(v.r * 255.0 + 0.5) * 256.0 + floor(v.g * 255.0 + 0.5)) / 65535.0)
    return mix(mix(D16(v00), D16(v10), f.x), mix(D16(v01), D16(v11), f.x), f.y);
}

vec3 outline(vec2 uv) {
    if (hasMap < 0.5) return contagion(uv);
    float e = easeS(progress);
    float zIn = 1.0 + 0.035 * (1.0 - e);           // персонаж приезжает чуть ближе фона
    float zOut = 1.0 + 0.015 * (1.0 - e);
    vec2 mIn = cropTo.xy + zoomed(uv, zIn) * cropTo.zw;
    vec4 f = texture(fieldTex, mIn);
    float sdPx = (f.g * 2.0 - 1.0) * 16.0 * sw * zIn / (mapW * cropTo.z);
    float inside = mapKind < 0.5 ? clamp(0.5 - sdPx, 0.0, 1.0) : 0.0;

    // сцена отступает: старые обои темнеют и сереют
    float back = easeS(progress / 0.16) * (1.0 - easeS((progress - 0.9) / 0.1));
    vec3 st = A(uv).rgb;
    st = mix(st, vec3(dot(st, vec3(0.299, 0.587, 0.114))), 0.3 * back) * (1.0 - 0.22 * back);

    // заливка и рост — теми же клетками, что у contagion, но решение по центру клетки
    vec2 grid = vec2(sw, sh) / max(cell, 1.0);
    vec2 cuv = (floor(uv * grid) + 0.5) / grid;
    float Ti = easeS((progress - 0.30) / 0.30) * 1.03 - 0.015;
    float depth = texture(fieldTex, cropTo.xy + zoomed(cuv, zIn) * cropTo.zw).r;
    vec3 cIn = depth <= Ti ? B(zoomed(uv, zIn)).rgb : st;
    float To = easeS((progress - 0.48) / 0.50) * 1.03 - 0.015;
    float order = grow16(cropTo.xy + zoomed(cuv, zOut) * cropTo.zw);
    vec3 cOut = order <= To ? B(zoomed(uv, zOut)).rgb : st;
    vec3 c = mix(cOut, cIn, inside);

    // линия: рисуется пером по месту на контуре, гаснет, когда персонаж залит
    float drawn = easeS((progress - 0.03) / 0.36);
    float fade = 1.0 - easeS((progress - 0.55) / 0.25);
    if (f.b > 0.0 && f.b <= drawn && fade > 0.0) {
        // Цвет — по яркости сцены под линией: светлая на тёмном, тёмная на светлом, и тонкая
        // тень противоположного тона рядом. Так линию видно на любых обоях.
        float w = max(lineW, 1.25) * 0.5;
        float core = clamp(w + 0.5 - abs(sdPx), 0.0, 1.0);
        float halo = clamp(w + 1.5 - abs(sdPx), 0.0, 1.0) - core;
        bool light = dot(st, vec3(0.299, 0.587, 0.114)) > 0.55;
        vec3 pen = light ? inkDark.rgb : ink.rgb;
        vec3 shade = light ? ink.rgb : inkDark.rgb;
        c = mix(c, shade, halo * 0.45 * fade);
        c = mix(c, pen, core * 0.9 * fade);
    }
    return c;
}

// hexreveal (по мотивам Vitreus wptrans/hexreveal.wgsl, MIT): новые обои проступают сквозь соты — каждая
// клетка (острый верх) раскрывается из своей середины, пока не заполнит себя; порядок — волна от origin с
// долей случайности, кромка растущей клетки ловит свет.
vec4 hexreveal(vec2 uv) {
    vec4 a = A(uv), b = B(uv);
    if (progress >= 0.999) return b;
    vec2 px = uv * vec2(sw, sh);
    float r = max(28.0, sw / 30.0);          // радиус клетки (от центра до вершины), px
    const float SQ3 = 1.7320508;
    // Осевые координаты, округление в кубических.
    float qf = (SQ3 / 3.0 * px.x - px.y / 3.0) / r;
    float rf = (2.0 / 3.0 * px.y) / r;
    float yf = -qf - rf;
    float rx = floor(qf + 0.5), ry = floor(yf + 0.5), rz = floor(rf + 0.5);
    float dx = abs(rx - qf), dy = abs(ry - yf), dz = abs(rz - rf);
    if (dx > dy && dx > dz) rx = -ry - rz;
    else if (dy > dz) ry = -rx - rz;
    else rz = -rx - ry;
    vec2 centre = vec2(r * SQ3 * (rx + rz * 0.5), r * 1.5 * rz);
    float reach = length(vec2(sw, sh));
    float wave = clamp(length(centre - origin * vec2(sw, sh)) / reach, 0.0, 1.0);
    float chance = rand(vec2(rx, rz) + seed);
    const float SPAN = 0.35;                 // сколько от всего перехода раскрывается одна клетка
    float delay = mix(chance, wave, 0.7) * (1.0 - SPAN);
    float t = clamp((progress - delay) / SPAN, 0.0, 1.0);
    float ease = t * t * (3.0 - 2.0 * t);
    vec2 q = px - centre;
    float inr = r * SQ3 * 0.5;
    float d = max(abs(q.x), max(abs(dot(q, vec2(0.5, 0.8660254))), abs(dot(q, vec2(-0.5, 0.8660254)))));
    float grown = inr * ease * 1.05;
    if (grown < 1.0) return a;
    float sd = d - grown;
    float cover = 1.0 - smoothstep(-0.9, 0.9, sd);
    float rim = (1.0 - smoothstep(0.0, 5.0, -sd)) * (1.0 - ease);
    vec3 nb = mix(b.rgb, vec3(1.0), 0.28 * rim);
    return vec4(mix(a.rgb, nb, cover), 1.0);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float p = progress;
    int m = int(mode + 0.5);
    vec2 asp = vec2(aspect, 1.0);
    vec2 dir = vec2(cos(angle), sin(angle));
    vec4 c;

    if (m == 1) {            // fade
        c = mix(A(uv), B(uv), smoothstep(0.0, 1.0, p));
    } else if (m == 2) {     // slant — как стоковая шторка: полоса от центра со скосом
        float line = 0.5 + 0.18 * (uv.y - 0.5) / aspect;
        float reach = 0.5 + 0.09 / aspect + 0.01;
        c = mix(A(uv), B(uv), reveal(sweep(0.0, reach) - abs(uv.x - line)));
    } else if (m == 3 || m == 4) {  // wipe, wave
        float r = 0.5 * (abs(dir.x) + abs(dir.y));
        float proj = dot(uv - 0.5, dir);
        if (m == 4) {
            float perp = dot((uv - 0.5) * asp, vec2(-dir.y, dir.x));
            proj += sin(perp * 28.0 + seed * 6.0) * 0.025;
            r += 0.03;
        }
        c = mix(A(uv), B(uv), reveal(sweep(-r, r) - proj));
    } else if (m == 5 || m == 6) {  // grow, outer
        float dist = length((uv - origin) * asp);
        float far = farthest(origin);
        float t = (m == 5) ? reveal(sweep(0.0, far) - dist) : reveal(dist - (far - sweep(0.0, far)));
        c = mix(A(uv), B(uv), t);
    } else if (m == 7) {     // diamond
        vec2 d = abs((uv - origin) * asp);
        float dist = d.x + d.y;
        c = mix(A(uv), B(uv), reveal(sweep(0.0, aspect + 1.0) - dist));
    } else if (m == 8) {     // clock — радиальная развёртка от 12 часов
        vec2 d = (uv - origin) * asp;
        float a = fract(atan(d.x, -d.y) / (2.0 * PI) + 1.0);
        c = mix(A(uv), B(uv), reveal(sweep(0.0, 1.0) - a));
    } else if (m == 9) {     // blinds — 14 горизонтальных жалюзи
        float f = fract(uv.y * 14.0);
        c = mix(A(uv), B(uv), reveal(sweep(0.0, 1.0) - f));
    } else if (m == 10) {    // doors — раскрытие от вертикальной середины
        c = mix(A(uv), B(uv), reveal(sweep(0.0, 1.0) - abs(uv.x - 0.5) * 2.0));
    } else if (m == 11) {    // mosaic — квадраты в случайном порядке
        vec2 cell = floor(uv * vec2(18.0 * aspect / 1.6, 18.0 / 1.6) * 1.6);
        float order = rand(cell + seed);
        c = mix(A(uv), B(uv), step(order, p * 1.02));
    } else if (m == 12) {    // dissolve — пиксельный шум
        float order = rand(floor(uv * vec2(aspect, 1.0) * 540.0) + seed);
        c = mix(A(uv), B(uv), step(order, p));
    } else if (m == 13) {    // pixelize — блоки растут к середине и снова мельчают
        float k = 1.0 - abs(2.0 * p - 1.0);
        vec2 size = vec2(1.0 / aspect, 1.0) * (0.0015 + 0.05 * k * k);
        vec2 q = (floor(uv / size) + 0.5) * size;
        c = mix(A(q), B(q), smoothstep(0.4, 0.6, p));
    } else if (m == 14 || m == 21) {  // ripple (от центра), water-drop (от origin, затухает)
        vec2 o = (m == 14) ? vec2(0.5) : origin;
        vec2 d = (uv - o) * asp;
        float dist = length(d);
        float amp = (m == 14) ? 0.03 * sin(p * PI) : 0.04 * (1.0 - p);
        vec2 off = (dist > 0.0001 ? d / dist : vec2(0.0)) * sin(dist * 45.0 - p * 30.0) * amp / asp;
        float t = (m == 14) ? smoothstep(0.2, 0.8, p) : reveal(sweep(0.0, farthest(o)) - dist);
        c = mix(A(uv + off), B(uv + off), t);
    } else if (m == 15) {    // swirl — закрутка к середине и обратно
        vec2 d = (uv - 0.5) * asp;
        float dist = length(d);
        float k = sin(p * PI) * 6.0 * max(0.0, 1.0 - dist / 0.9);
        float s = sin(k), co = cos(k);
        vec2 r = vec2(d.x * co - d.y * s, d.x * s + d.y * co) / asp + 0.5;
        c = mix(A(r), B(r), smoothstep(0.35, 0.65, p));
    } else if (m == 16) {    // cross-zoom — радиальное размытие к центру
        float k = sin(p * PI) * 0.25;
        vec4 acc = vec4(0.0);
        for (int i = 0; i < 12; i++) {
            float f = float(i) / 11.0;
            vec2 q = 0.5 + (uv - 0.5) * (1.0 - k * f);
            acc += mix(A(q), B(q), smoothstep(0.3, 0.7, p));
        }
        c = acc / 12.0;
    } else if (m == 17) {    // slide — новые выталкивают старые по направлению angle
        vec2 shift = dir * p;
        vec2 qa = uv + shift;
        vec2 qb = uv + shift - dir;
        bool inA = qa.x >= 0.0 && qa.x <= 1.0 && qa.y >= 0.0 && qa.y <= 1.0;
        c = inA ? A(qa) : B(qb);
    } else if (m == 18) {    // zoom — старые улетают вперёд, новые проявляются из глубины
        vec2 qa = 0.5 + (uv - 0.5) / (1.0 + p * 0.6);
        vec2 qb = 0.5 + (uv - 0.5) * (1.25 - 0.25 * p);
        c = mix(A(qa), B(qb), smoothstep(0.0, 1.0, p));
    } else if (m == 19) {    // glitch — рваные полосы, разъезд каналов
        float k = sin(p * PI);
        float band = floor(uv.y * 34.0);
        float step_ = floor(p * 18.0);
        float off = (rand(vec2(band, step_ + seed)) - 0.5) * 0.25 * k * step(0.55, rand(vec2(band * 1.7, step_)));
        vec2 q = vec2(uv.x + off, uv.y);
        float t = step(rand(vec2(band, step_ * 3.1)), p);
        vec2 ch = vec2(0.012 * k, 0.0);
        vec4 a = vec4(A(q + ch).r, A(q).g, A(q - ch).b, 1.0);
        vec4 b = vec4(B(q + ch).r, B(q).g, B(q - ch).b, 1.0);
        c = mix(a, b, t);
    } else if (m == 20) {    // burn — прогорание пятнами с раскалённым краем
        float n = noise(uv * asp * 6.0 + seed * 10.0) * 0.7 + noise(uv * asp * 18.0) * 0.3;
        float edge = sweep(0.0, 1.0) - n;
        float t = reveal(edge);
        float glow = smoothstep(0.08, 0.0, abs(edge)) * (1.0 - t * 0.6);
        c = mix(A(uv), B(uv), t) + vec4(1.0, 0.45, 0.1, 0.0) * glow * 1.2;
    } else if (m == 22) {    // hexagon — соты открываются от центра с разбросом
        vec2 g = uv * asp * 14.0;
        float row = floor(g.y);
        float col = floor(g.x + mod(row, 2.0) * 0.5);
        vec2 cell = vec2(col, row);
        vec2 center = (vec2(col + 0.5 - mod(row, 2.0) * 0.5, row + 0.5) / 14.0) / asp;
        float order = length((center - 0.5) * asp) / farthest(vec2(0.5)) * 0.7 + rand(cell + seed) * 0.3;
        c = mix(A(uv), B(uv), step(order, p * 1.02));
    } else if (m == 25) {    // hexreveal — соты раскрываются каждая из своей середины волной от origin (Vitreus)
        c = hexreveal(uv);
    } else if (m == 23) {    // contagion — колонии клетками прогрызают старые обои
        c = vec4(contagion(uv), 1.0);
    } else if (m == 24) {    // outline — контур персонажа, заливка, мир растёт из него
        c = vec4(outline(uv), 1.0);
    } else {                 // запасной — простое смешивание
        c = mix(A(uv), B(uv), p);
    }

    fragColor = vec4(c.rgb, 1.0) * qt_Opacity;
}
