import QtQuick

// Живые обои «Земля» райса Space — шейдер пейзажа из github.com/elifouts/Dotfiles (Space/wallpaper, GPL-3.0),
// shaders/terrain.frag + shaders/terrain/*.glsl как у него. Здесь — его Terrain.qml без стора Space: параметры земли
// приходят из <обои>.scene.json (config), цвета — оттуда же или из темы (bg, accent, fg, tone).
// pan — сдвиг пейзажа: номер стола (смена стола панорамирует), как его ws - 1.
ShaderEffect {
  id: t

  property var config: ({})
  property color themeBg: "#05070c"
  property color themeAccent: "#7aa2f7"
  property color themeFg: "#d8e2f0"
  property color themeTone: "#24324f"
  property real workspace: 1
  property real screenX: 0
  property bool animate: true  // плавная смена цвета и панорамы (снимок — без)
  property real moonless: 0  // 1 — без луны (второй монитор, как у него)

  function v(k, d) { var x = config && config.land ? config.land[k] : undefined; return x === undefined || x === null ? d : Number(x) }
  function col(k, d) { var c = config && config.colors ? config.colors[k] : undefined; return c ? c : d }
  function mix(a, b, k) { a = Qt.color(a); b = Qt.color(b); return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1) }

  property real pan: (workspace - 1) * (config && config.parallax !== undefined ? Number(config.parallax) : 1) + screenX / 2000
  Behavior on pan { enabled: t.animate; NumberAnimation { duration: 1400; easing.type: Easing.InOutCubic } }
  property real zoom: 1
  property real lift: 0
  property real glow: 0
  property real skyFade: 1
  property real wipe: 0
  property real beneath: -1
  property vector4d view: Qt.vector4d(0, 0, 0, 0)
  property vector4d viewSize: Qt.vector4d(0, 0, 0, 0)
  property real rise: 0
  property real clear: 0
  property real orbit: 1
  property real endR: 0.09
  property vector4d sun: Qt.vector4d(-0.35, 0.6, 0.7, 0)
  property real kind: 0
  property vector4d moonEnd: Qt.vector4d(0, 0, 0, 0)
  property real seed: config && config.seed !== undefined ? Number(config.seed) : 17
  readonly property real aspect: width / Math.max(1, height)

  property color bg: col("bg", themeBg)
  property color accent: col("accent", themeAccent)
  property color fg: col("fg", themeFg)
  property color tone: col("tone", themeTone)
  Behavior on bg { enabled: t.animate; ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }
  Behavior on accent { enabled: t.animate; ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }
  Behavior on fg { enabled: t.animate; ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }
  Behavior on tone { enabled: t.animate; ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }
  property color zenith: mix(bg, "#000000", 0.2)
  property color horizon: mix(accent, bg, 0.25)
  property color warm: mix(accent, "#ffd9b0", 0.6)
  property color far: mix(accent, bg, 0.55)
  property color near: mix(tone, "#0e1528", 0.88)
  property color moon: mix(fg, accent, 0.4)
  property color shade: mix(bg, "#000000", 0.5)

  // его Schema.js LAND: значения по умолчанию
  property real relief: v("relief", 0.4)
  property real landH: v("height", 1)
  property real snow: v("snow", 0.5)
  property real haze: v("haze", 0.5)
  property real flora: v("flora", 1)
  property real treeSize: v("treeSize", 1)
  property real grassy: v("grass", 1.5)
  property real rocks: v("rocks", 0.4)
  property real bases: v("bases", 0.4)
  property real starAmt: v("stars", 1)
  property real starSize: v("starSize", 1)
  property real galaxy: v("galaxy", 0.25)
  property real galaxyTilt: v("galaxyTilt", 20) * Math.PI / 180
  property real dusk: v("dusk", 0.55)
  property real comet: v("comets", 1)
  property real atlas: v("atlas", 0) ? 1 : 0
  property real atlasSize: v("atlasSize", 1)
  property real atlasGlow: v("atlasGlow", 0.8)
  property real ship: v("ship", 1) ? 1 : 0
  property real ships: v("ships", 0.5)
  property real traffic: v("traffic", 1) ? 1 : 0
  property real fleet: v("fleet", 0.7)
  property real variety: v("variety", 0.35)

  fragmentShader: Qt.resolvedUrl("shaders/terrain.frag.qsb")
}
