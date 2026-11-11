import QtQuick
import qs.Commons

// fx: переход между двумя кадрами обоев (shaders/transition.frag). Используют
// Background.qml и превью Wallpaper FX в Customizer. fromItem / toItem — любые
// Item (обычно Image с PreserveAspectCrop): их отрисовка снимается в текстуры,
// поэтому обрезка под экран уже учтена.
ShaderEffect {
  id: fx

  property Item fromItem: null
  property Item toItem: null
  property string effect: "fade"
  property real progress: 0
  property real angleDegrees: 0
  property real softness: 0.02
  property real seed: Math.random()
  property point origin: Qt.point(0.5, 0.5)
  // Прятать исходные кадры, пока эффект их показывает.
  property bool hideSources: visible

  // Имена эффектов → номер в шейдере. none и random решает тот, кто запускает переход.
  readonly property var modes: ({
    "fade": 1, "slant": 2, "wipe": 3, "wave": 4, "grow": 5, "outer": 6, "diamond": 7, "clock": 8,
    "blinds": 9, "doors": 10, "mosaic": 11, "dissolve": 12, "pixelize": 13, "ripple": 14, "swirl": 15,
    "crosszoom": 16, "slide": 17, "zoom": 18, "glitch": 19, "burn": 20, "waterdrop": 21, "hexagon": 22,
    "contagion": 23, "outline": 24
  })
  // Эффекты-«сцены»: живут дольше обычных (durationScene) и идут линейно — кривые внутри шейдера.
  readonly property var sceneEffects: ["contagion", "outline"]
  readonly property var effectNames: Object.keys(modes)

  readonly property real mode: modes[effect] !== undefined ? modes[effect] : 1
  readonly property real angle: angleDegrees * Math.PI / 180
  readonly property real aspect: width / Math.max(1, height)

  // contagion / outline. Идея — переходы diegoMalagrida/pocket-dots, реализация своя.
  property real cell: 6            // клетка фронта, px
  property real glow: 0.9          // сила вспышек и свечения
  property real lineW: 1.5         // линия контура, px
  property real sw: width
  property real sh: height
  // Карты outline (scripts/wallpaper-fx-outline map): пусто — outline играет как contagion.
  property string fieldPath: ""
  property string growPath: ""
  // char — контур персонажа (с заливкой), edge — линии картинки (без заливки)
  property string mapType: "char"
  readonly property real mapKind: mapType === "edge" ? 1 : 0
  readonly property bool mapReady: fieldPath !== "" && fieldImg.status === Image.Ready && growImg.status === Image.Ready
  readonly property bool mapFailed: fieldPath !== "" && (fieldImg.status === Image.Error || growImg.status === Image.Error)
  readonly property real hasMap: mapReady ? 1 : 0
  readonly property real mapW: Math.max(1, fieldImg.implicitWidth)
  readonly property real mapH: Math.max(1, fieldImg.implicitHeight)
  // Обрезка новых обоев под экран (PreserveAspectCrop по центру): карты лежат в координатах картинки.
  readonly property vector4d cropTo: {
    var it = fx.toItem
    var iw = Math.max(1, it && it.implicitWidth ? it.implicitWidth : width)
    var ih = Math.max(1, it && it.implicitHeight ? it.implicitHeight : height)
    var s = Math.max(width / iw, height / ih)
    var w = width / (iw * s), h = height / (ih * s)
    return Qt.vector4d((1 - w) / 2, (1 - h) / 2, w, h)
  }
  property color ember: "#ff9a3c"
  property color ink: "white"
  property color inkDark: "black"

  // Цвета снимаются один раз в начале перехода, не биндингом: тема меняется посреди
  // перехода, а фронт не должен перекрашиваться на ходу.
  function capturePalette() {
    var pal = [Color.accent, Color.urgent, Color.foreground, Color.muted, Color.background]
    var chroma = function(c) { return c.hslSaturation * (1 - Math.abs(2 * c.hslLightness - 1)) }
    var luma = function(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
    var vivid = pal.reduce(function(a, b) { return chroma(b) > chroma(a) ? b : a })
    // тёмный акцент не светится — поднимаем светлоту и насыщенность
    ember = Qt.hsla(vivid.hslHue < 0 ? 0.08 : vivid.hslHue, Math.max(vivid.hslSaturation, 0.55),
                    Math.min(Math.max(vivid.hslLightness, 0.6), 0.8), 1)
    ink = pal.reduce(function(a, b) { return luma(b) > luma(a) ? b : a })
    inkDark = pal.reduce(function(a, b) { return luma(b) < luma(a) ? b : a })
  }

  property variant fromTex: fromSource
  property variant toTex: toSource

  // Числа, а не цвета: без alpha (Qt премультиплицировал бы) и без кэша (файл перезаписывается).
  Image { id: fieldImg; visible: false; asynchronous: true; cache: false; smooth: true
    source: fx.fieldPath ? "file://" + fx.fieldPath : "" }
  Image { id: growImg; visible: false; asynchronous: true; cache: false; smooth: false
    source: fx.growPath ? "file://" + fx.growPath : "" }
  // Сэмплер нельзя оставить пустым: без карт подставляем новые обои, шейдер их не читает.
  property variant fieldTex: mapReady ? fieldImg : toSource
  property variant growTex: mapReady ? growImg : toSource

  ShaderEffectSource {
    id: fromSource
    sourceItem: fx.fromItem
    hideSource: fx.hideSources
    visible: false
  }
  ShaderEffectSource {
    id: toSource
    sourceItem: fx.toItem
    hideSource: fx.hideSources
    visible: false
  }

  fragmentShader: Qt.resolvedUrl("shaders/transition.frag.qsb")
}
