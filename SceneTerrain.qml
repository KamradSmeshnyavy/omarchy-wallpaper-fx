import QtQuick
import QtQuick.Window

// Живые обои «Земля» райса Space — шейдер пейзажа из github.com/elifouts/Dotfiles (Space/wallpaper, GPL-3.0),
// shaders/terrain.frag + shaders/terrain/*.glsl как у него. Здесь — его Terrain.qml без стора Space: параметры земли
// приходят из <обои>.scene.json (config), цвета — оттуда же или из темы (bg, accent, fg, tone).
// pan — сдвиг пейзажа: номер стола (смена стола панорамирует), как его ws - 1.
Item {
  id: root

  property var config: ({})
  property color themeBg: "#05070c"
  property color themeAccent: "#7aa2f7"
  property color themeFg: "#d8e2f0"
  property color themeTone: "#24324f"
  property real workspace: 1
  property real screenX: 0
  property bool animate: true  // плавная смена цвета и панорамы (снимок — без)
  property real moonless: 0  // 1 — без луны (второй монитор, как у него)

  // pan — куда смотрит пейзаж; panTo — куда он едет (стол). Едет он не Behavior'ом на частоте экрана, а шагами
  // panFps раз в секунду: каждый кадр обоев заставляет Hyprland заново размыть всё, что над ними (бар, виджеты,
  // прозрачные окна), — на 120 Гц это ~170 размытий всего экрана за смену стола. 40 кадров в секунду для медленной
  // панорамы на глаз неотличимы, а работы втрое меньше. Анимация окон Hyprland при этом остаётся на 120 Гц.
  readonly property real panTo: (workspace - 1) * (config && config.parallax !== undefined ? Number(config.parallax) : 1) + screenX / 2000
  property real pan: 0
  Component.onCompleted: pan = panTo
  property int panFps: 30
  property int panDuration: 1400
  property real panFrom: 0
  property real panStart: 0
  onPanToChanged: {
    if (!animate || !visible) { panTicker.stop(); pan = panTo; return }
    panFrom = pan
    panStart = Date.now()
    panTicker.restart()
  }
  Timer {
    id: panTicker
    interval: Math.round(1000 / Math.max(1, root.panFps))
    repeat: true
    onTriggered: {
      var k = Math.min(1, (Date.now() - root.panStart) / root.panDuration)
      var e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2  // InOutCubic, как у него
      root.pan = root.panFrom + (root.panTo - root.panFrom) * e
      if (k >= 1) stop()
      frame.scheduleUpdate()
    }
  }

  // Экономия (как его Wallpaper.qml: layer + RenderScale): шейдер рисуется в текстуру, а окно обоев показывает её.
  // В покое текстура полная и перерисовывается только при изменениях. Пока пейзаж едет, шейдер считается в
  // уменьшенную текстуру (motionScale от физических пикселей: на 2880×1800 вчетверо меньше работы, на движении не
  // видно) и только по шагу панорамы (scheduleUpdate) — layer.enabled здесь давал по два кадра на шаг. В конце — один
  // полный кадр.
  property real motionScale: 0.5
  readonly property bool moving: panTicker.running || fading.running
  ShaderEffectSource {
    id: frame
    anchors.fill: parent
    sourceItem: t
    hideSource: true
    live: !root.moving
    smooth: true
    textureSize: root.moving ? Qt.size(Math.ceil(root.width * Screen.devicePixelRatio * root.motionScale), Math.ceil(root.height * Screen.devicePixelRatio * root.motionScale)) : Qt.size(0, 0)
  }

  ShaderEffect {
    id: t
    anchors.fill: parent
    property real pan: root.pan
    property real moonless: root.moonless

    function v(k, d) { var x = root.config && root.config.land ? root.config.land[k] : undefined; return x === undefined || x === null ? d : Number(x) }
    function col(k, d) { var c = root.config && root.config.colors ? root.config.colors[k] : undefined; return c ? c : d }
    function mix(a, b, k) { a = Qt.color(a); b = Qt.color(b); return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1) }

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
    property real seed: root.config && root.config.seed !== undefined ? Number(root.config.seed) : 17
    readonly property real aspect: width / Math.max(1, height)

    property color bg: col("bg", root.themeBg)
    property color accent: col("accent", root.themeAccent)
    property color fg: col("fg", root.themeFg)
    property color tone: col("tone", root.themeTone)
    Behavior on bg { enabled: root.animate; ColorAnimation { id: fading; duration: 900; easing.type: Easing.InOutSine } }
    Behavior on accent { enabled: root.animate; ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }
    Behavior on fg { enabled: root.animate; ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }
    Behavior on tone { enabled: root.animate; ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }
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

    // во время смены цвета источник не живой — обновлять по шагу цвета
    onBgChanged: if (root.moving) frame.scheduleUpdate()
    onAccentChanged: if (root.moving) frame.scheduleUpdate()

    fragmentShader: Qt.resolvedUrl("shaders/terrain.frag.qsb")
  }

}
