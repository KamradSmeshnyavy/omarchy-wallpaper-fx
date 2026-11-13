#version 440
// Вид обоев (wallpaper-look.json) — из glyph-rice, components/shaders/wall.frag (GPL-3.0), без волны смены: её
// играет переход dotwave в transition.frag. Картинка матрицей точек-светодиодов (dots 1) или фото (dots 0),
// mono — в тон темы (lo…hi), иначе цвет; bright — от фона до картинки.
// Сборка: just shaders-wallpaper.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;    // px
    vec4 lo;      // тёмный конец тона
    vec4 hi;      // светлый
    vec4 bg;
    float pitch;  // шаг точек, px
    float dots;   // 0 фото … 1 точки
    float mono;   // 0 цвет … 1 тон
    float bright; // 0 … 1
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 c = (floor(p / pitch) + 0.5) * pitch;
    // между своим пикселем и центром клетки — плавная пикселизация при смене вида
    vec2 uv = mix(p, c, dots) / size;
    vec4 t = texture(source, uv);
    vec3 rgb = t.rgb + bg.rgb * (1.0 - t.a);
    float l = dot(rgb, vec3(0.299, 0.587, 0.114));
    vec3 col = mix(bg.rgb, mix(rgb, mix(lo.rgb, hi.rgb, l), mono), bright);
    // точка: радиус от «вся клетка» (фото) до .3 шага
    float r = pitch * mix(0.75, 0.3, dots);
    float m = 1.0 - smoothstep(r - 0.6, r + 0.6, distance(p, c));
    fragColor = vec4(mix(bg.rgb, col, m), 1.0) * qt_Opacity;
}
