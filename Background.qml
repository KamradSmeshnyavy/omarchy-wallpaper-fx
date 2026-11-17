import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  // fx: переход из ~/.config/omarchy/wallpaper-transition.json (TransitionEffect.qml).
  //   type      none | random | одно из TransitionEffect.modes (по умолчанию slant — как в стоке)
  //   duration  мс, easing — имя кривой (InOutCubic, OutExpo, …)
  //   angle     градусы для wipe / wave / slide, origin — center | cursor | random
  //   softness  ширина мягкого края (доля экрана)
  //   contagion / outline: durationScene (мс), cell (px клетки), frontGlow (0..1), lineWidth (px),
  //   outlineWait — сколько ждать карту outline (мс), потом contagion
  property var fxConfig: ({})
  readonly property string fxType: String(fxConfig.type || "slant")
  readonly property int fxDuration: Math.max(80, Math.min(5000, Number(fxConfig.duration) || 420))
  readonly property string fxEasing: String(fxConfig.easing || "InOutCubic")
  readonly property real fxAngle: Number(fxConfig.angle !== undefined ? fxConfig.angle : 0)
  readonly property real fxSoftness: Number(fxConfig.softness !== undefined ? fxConfig.softness : 0.02)
  readonly property string fxOrigin: String(fxConfig.origin || "center")
  readonly property int fxDurationScene: Math.max(300, Math.min(8000, Number(fxConfig.durationScene) || 1900))
  readonly property real fxCell: Math.max(2, Math.min(32, Number(fxConfig.cell) || 6))
  readonly property real fxGlow: Math.max(0, Math.min(1, fxConfig.frontGlow !== undefined ? Number(fxConfig.frontGlow) : 0.9))
  readonly property real fxLineWidth: Math.max(0.5, Math.min(6, Number(fxConfig.lineWidth) || 1.5))
  readonly property int fxOutlineWait: Math.max(500, Math.min(30000, Number(fxConfig.outlineWait) || 3000))
  readonly property bool fxOutline: fxActive === "outline" || fxActive === "outline-cut"
  readonly property bool fxScene: fxActive === "contagion" || fxOutline
  // fx: живые обои (видео, GIF) рисует owe, а не мы: он прячет оболочку через setSuspended.
  property bool suspended: false
  // owe зовёт setSuspended только при смене обоев, а перезапуск оболочки это состояние теряет — и неподвижные
  // обои оболочки ложатся поверх видео (слой создан позже). Поэтому при старте и после смены обоев
  // спрашиваем owe сами: engine "renderer" — рисует он, наши обои прячем.
  Process {
    id: oweProbe
    command: ["bash", "-c", "command -v owe >/dev/null && owe status 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var st = JSON.parse(String(text || "{}"))
          if (st.status === "ok") root.suspended = st.engine === "renderer" && st.render_alive === true
        } catch (e) {}
      }
    }
  }
  Timer { id: oweProbeTimer; interval: 1500; onTriggered: if (!oweProbe.running) oweProbe.running = true }
  onCurrentBackgroundChanged: oweProbeTimer.restart()
  function isLive(path) { return /\.(mp4|m4v|mov|webm|mkv|avi|gif)$/i.test(String(path || "")) }
  // Переходы с живыми обоями: сначала кадры «откуда / куда» (scripts/wallpaper-fx-still — текущий кадр
  // owe и первый кадр нового видео), переход идёт между ними, а слой не прячется, пока он не доиграет
  // (stillHold) — потом под ним уже играет видео owe.
  readonly property string stillScript: String(Qt.resolvedUrl("scripts/wallpaper-fx-still")).replace(/^file:\/\//, "")
  property bool stillPending: false
  readonly property bool stillHold: stillPending || (incomingBackground !== "" && revealProgress < 1)
  Process {
    id: stillProc
    property int version: -1
    stdout: StdioCollector {
      onStreamFinished: {
        root.stillPending = false
        if (stillProc.version !== root.backgroundVersion) return
        var lines = String(text || "").split("\n")
        var from = (lines[0] || "").trim(), to = (lines[1] || "").trim()
        if (!from || !to || root.isLive(to) || root.isLive(from)) {
          root.displayedBackground = root.isLive(root.currentBackground) ? (to || root.currentBackground) : root.currentBackground
          root.revealProgress = 1
          return
        }
        root.fxPrepare(to)
        root.oldBackground = from
        root.incomingBackground = to
        root.revealProgress = 0
      }
    }
    onExited: function(code) { if (code !== 0) root.stillPending = false }
  }
  // outline: карты для новых обоев (scripts/wallpaper-fx-outline). Пока ищем — переход ждёт.
  readonly property string outlineScript: String(Qt.resolvedUrl("scripts/wallpaper-fx-outline")).replace(/^file:\/\//, "")
  property bool outlinePending: false
  property string outlineField: ""
  property string outlineGrow: ""
  property int outlineVersion: -1
  property string outlineKind: "char"
  property int fxPaletteTick: 0
  // Что играет текущий переход (random разрешается в конкретный эффект на старте).
  property string fxActive: "slant"
  property real fxSeed: 0
  property point fxRandomOrigin: Qt.point(0.5, 0.5)
  property var fxCursor: null
  readonly property var fxEffects: ["slant", "fade", "wipe", "wave", "grow", "outer", "diamond", "clock",
    "blinds", "doors", "mosaic", "dissolve", "pixelize", "ripple", "swirl", "crosszoom", "slide", "zoom",
    "glitch", "burn", "waterdrop", "hexagon", "hexreveal", "dotwave", "contagion"]

  function fxEasingType(name) {
    var map = {
      "Linear": Easing.Linear, "InOutQuad": Easing.InOutQuad, "InOutCubic": Easing.InOutCubic,
      "InOutQuart": Easing.InOutQuart, "InOutSine": Easing.InOutSine, "InOutExpo": Easing.InOutExpo,
      "OutCubic": Easing.OutCubic, "OutExpo": Easing.OutExpo, "OutQuint": Easing.OutQuint,
      "OutBack": Easing.OutBack, "OutBounce": Easing.OutBounce, "OutElastic": Easing.OutElastic,
      "InCubic": Easing.InCubic, "InExpo": Easing.InExpo
    }
    return map[name] !== undefined ? map[name] : Easing.InOutCubic
  }

  // Подготовить эффект к очередному переходу.
  function fxPrepare(path) {
    fxActive = fxType === "random" ? fxEffects[Math.floor(Math.random() * fxEffects.length)] : fxType
    outlineProc.running = false
    outlineWaitTimer.stop()
    outlinePending = false
    outlineField = ""
    outlineGrow = ""
    if (fxOutline && path) {
      outlineVersion = backgroundVersion
      outlinePending = true
      outlineProc.out = ""
      // outline — только линии картинки; outline-cut — контур персонажа (пока не вырезан — линии)
      outlineProc.command = [outlineScript, "map", path].concat(fxActive === "outline" ? ["--lines"] : [])
      outlineProc.running = true
      outlineWaitTimer.restart()
    }
    fxSeed = Math.random()
    fxRandomOrigin = Qt.point(0.15 + Math.random() * 0.7, 0.15 + Math.random() * 0.7)
    if (fxOrigin === "cursor" && !cursorProc.running) cursorProc.running = true
  }

  FileView {
    path: root.home + "/.config/omarchy/wallpaper-transition.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var v = JSON.parse(text())
        root.fxConfig = v && typeof v === "object" ? v : ({})
      } catch (e) {
        console.warn("wallpaper-transition.json: " + e)
      }
    }
    onLoadFailed: root.fxConfig = ({})
  }

  // scene: живые обои-сцена. Рядом с картинкой лежит <имя>.scene.json — тогда поверх неё рисуется сцена
  // (SceneTerrain.qml — «Земля» райса Space: пейзаж панорамирует при смене стола). Картинка остаётся снимком той же
  // сцены (scripts/scene-shot.qml) — для пикера, лока и переходов. {"scene": "terrain", "seed", "land", "colors"}.
  property var sceneConfig: null
  // dynamic-тема (omarchy-rice-dynamic) перекрашивается под обои — тогда цвета сцены из темы, а не из файла
  property bool themeDynamic: false
  FileView {
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeDynamic = /^dynamic/.test(String(text()).trim())
    onLoadFailed: root.themeDynamic = false
  }
  function sceneFor(cfg) {
    if (!cfg || !root.themeDynamic) return cfg || ({})
    var c = Object.assign({}, cfg)
    delete c.colors
    return c
  }
  function sceneSidecar(path) {
    var p = String(path || "")
    return /\.(png|jpe?g|webp)$/i.test(p) ? p.replace(/\.[^.\/]+$/, ".scene.json") : ""
  }
  FileView {
    path: root.sceneSidecar(root.displayedBackground)
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var v = JSON.parse(text())
        root.sceneConfig = v && v.scene === "terrain" ? v : null
      } catch (e) {
        console.warn("scene.json: " + e)
        root.sceneConfig = null
      }
    }
    onLoadFailed: root.sceneConfig = null
    onPathChanged: if (!path) root.sceneConfig = null
  }

  // look: вид обоев из ~/.config/omarchy/wallpaper-look.json (пишет picker в стиле glyph, см. image-picker/glyph):
  //   look  color (как есть) | mono (серое фото в тон темы) | dots (матрица точек-светодиодов) — glyph-rice
  //   pitch шаг точек, px; bright 10…100 — от фона до картинки. color при bright 100 — без эффекта.
  //   Живые обои (видео) рисует owe поверх — на них вид не действует.
  property var lookConfig: ({})
  readonly property int lookMode: ({ "dots": 0, "mono": 1 })[String(lookConfig.look)] ?? 2
  readonly property real lookPitch: Math.max(4, Math.min(32, Number(lookConfig.pitch) || 10))
  readonly property real lookBright: Math.max(0.1, Math.min(1, (Number(lookConfig.bright) || 100) / 100))
  readonly property bool lookOn: lookMode < 2 || lookBright < 1
  FileView {
    path: root.home + "/.config/omarchy/wallpaper-look.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var v = JSON.parse(text())
        root.lookConfig = v && typeof v === "object" ? v : ({})
      } catch (e) {
        console.warn("wallpaper-look.json: " + e)
      }
    }
    onLoadFailed: root.lookConfig = ({})
  }

  // Ответ почти мгновенный: карта персонажа из кэша, иначе карта линий картинки (меньше секунды),
  // а сами обои скрипт ставит в очередь на вырезку единственному фоновому воркеру. contagion —
  // только если карту вообще не на чем построить (нет cv2 и venv).
  // Пути приходят в stdout, а он может дочитаться и до, и после выхода процесса: успех решает
  // stdout, провал — код выхода (1 — персонажа нет, 2 — модели нет).
  Process {
    id: outlineProc
    property string out: ""
    stdout: StdioCollector {
      onStreamFinished: {
        outlineProc.out = String(text || "").trim()
        var parts = outlineProc.out.split(/\s+/)
        if (parts.length >= 2 && root.outlinePending && root.outlineVersion === root.backgroundVersion)
          root.outlineDone(parts[0], parts[1], parts[2] || "char")
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.outlinePending && root.outlineVersion === root.backgroundVersion)
        root.outlineDone("", "", "")
    }
  }
  Timer {
    id: outlineWaitTimer
    interval: root.fxOutlineWait
    onTriggered: if (root.outlinePending) root.outlineDone("", "", "")
  }
  function outlineDone(field, grow, kind) {
    outlineWaitTimer.stop()
    outlineKind = kind === "edge" ? "edge" : "char"
    outlineField = field
    outlineGrow = grow
    if (!field) fxActive = "contagion"
    outlinePending = false
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.fxCursor = JSON.parse(text) } catch (e) { root.fxCursor = null }
      }
    }
  }

  // fx: replay — показать следующие обои темы и снова открыть текущие эффектом.
  Process {
    id: replayProc
    property string current: ""
    command: ["bash", "-c", "cur=$(readlink -f \"$1\"); dir=$(dirname \"$cur\"); " +
      "find -L \"$dir\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) " +
      "| sort | grep -vxF \"$cur\" | head -n 1; echo \"$cur\"", "_", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var cur = lines[lines.length - 1]
        var other = lines.length > 1 ? lines[0] : cur
        if (!cur) return
        // Сначала мгновенно поставить соседние обои, потом обычный переход к текущим:
        // так incomingBackground и кадр base меняются и цепочка reveal отрабатывает как
        // при настоящей смене (переход «в те же обои» застревал на старом кадре).
        root.setBackground(other, true)
        Qt.callLater(function() { root.transitionBackground("", cur, cur, false, true) })
      }
    }
  }

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    currentBackground = finalPath
    // fx: динамическая тема райса (omarchy-rice-dynamic) перекрашивается под новые обои; не dynamic-* — ничего не делает.
    Quickshell.execDetached(["sh", "-c", "command -v omarchy-rice-dynamic >/dev/null && exec omarchy-rice-dynamic on-wallpaper \"$1\"", "sh", finalPath])
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false
    // fx: эффект выбирается на каждый переход; none — без анимации.
    stillPending = false
    fxPrepare(instant || isLive(path) || isLive(fromPath || displayedBackground) ? "" : path)

    // Видео и GIF — через неподвижные кадры (wallpaper-fx-still): переход между ними, видео рисует owe.
    var fromSrc = fromPath || displayedBackground
    if (!instant && displayedBackground && fxType !== "none" && (isLive(path) || isLive(fromSrc))) {
      oldBackground = ""
      incomingBackground = ""
      stillPending = true
      stillProc.running = false
      stillProc.version = backgroundVersion
      stillProc.command = [stillScript, fromSrc, path]
      stillProc.running = true
      return
    }
    if (instant || !displayedBackground || fxType === "none" || isLive(path) || isLive(displayedBackground)) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Commons.Color.loadColors(pendingColorsRaw)
    // Commons.Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Commons.Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    fxPaletteTick += 1
    revealAnimation.restart()
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }

    // fx: проиграть текущий эффект ещё раз (для превью в Customizer).
    function replay(): void {
      if (!replayProc.running) replayProc.running = true
    }

    // fx: как в стоке — owe прячет обои оболочки, пока сам показывает видео.
    function setSuspended(value: string): void {
      root.suspended = value === "true"
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    // fx: длительность и кривая из wallpaper-transition.json.
    duration: root.fxScene ? root.fxDurationScene : root.fxDuration
    easing.type: root.fxScene ? Easing.Linear : root.fxEasingType(root.fxEasing)
    onFinished: {
      if (root.incomingBackground) {
        // Живые обои: на базе остаётся их первый кадр (видео поверх рисует owe, когда слой спрячется).
        root.displayedBackground = root.isLive(root.currentBackground) ? root.incomingBackground
          : (root.currentBackground || root.incomingBackground)
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: { refreshBackground(); oweProbeTimer.restart() }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping && (!root.suspended || root.stillHold)
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false

      // outline ждёт свои карты: путь от скрипта и загруженные текстуры.
      function fxReady() {
        if (!root.fxOutline) return true
        if (root.outlinePending) return false
        return root.outlineField === "" || fxView.mapReady || fxView.mapFailed
      }

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready || !fxReady()) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready || !fxReady()) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // look: всё, что рисует обои (и переход), — одним слоем через шейдер вида (shaders/look.frag).
      Item {
        id: scene
        anchors.fill: parent
        layer.enabled: root.lookOn
        layer.effect: ShaderEffect {
          readonly property size size: Qt.size(scene.width, scene.height)
          readonly property color lo: Commons.Color.background.hslLightness > 0.5 ? Commons.Color.foreground : Commons.Color.background
          readonly property color hi: Commons.Color.background.hslLightness > 0.5 ? Commons.Color.background : Commons.Color.foreground
          readonly property color bg: Commons.Color.background
          readonly property real pitch: root.lookPitch
          readonly property real bright: root.lookBright
          property real dots: root.lookMode === 0 ? 1 : 0
          property real mono: root.lookMode < 2 ? 1 : 0
          Behavior on dots { NumberAnimation { duration: 700; easing.type: Easing.OutQuart } }
          Behavior on mono { NumberAnimation { duration: 700 } }
          fragmentShader: Qt.resolvedUrl("shaders/look.frag.qsb")
        }

        Image {
          id: base
          anchors.fill: parent
          source: root.imageUrl(root.displayedBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          onStatusChanged: {
            if (status === Image.Ready && root.finishingTransition) {
              root.incomingBackground = ""
              root.oldBackground = ""
              root.finishingTransition = false
            }
          }
        }

        // scene: живая сцена поверх снимка; во время перехода — снимки (картинки)
        SceneTerrain {
          id: sceneView
          anchors.fill: parent
          visible: root.sceneConfig !== null && root.revealProgress >= 1 && root.incomingBackground === ""
          config: root.sceneFor(root.sceneConfig)
          workspace: Hyprland.monitorFor(panel.modelData)?.activeWorkspace?.id ?? 1
          screenX: panel.modelData ? panel.modelData.x : 0
          themeBg: Commons.Color.background
          themeAccent: Commons.Color.accent
          themeFg: Commons.Color.foreground
          themeTone: Qt.rgba(Commons.Color.accent.r * 0.35 + 0.08, Commons.Color.accent.g * 0.35 + 0.12, Commons.Color.accent.b * 0.35 + 0.2, 1)
        }

        Image {
          id: oldFrame
          anchors.fill: parent
          source: root.imageUrl(root.oldBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          visible: root.oldBackground !== "" && root.revealProgress < 1
          onStatusChanged: panel.maybeStartReveal()
        }

        Item {
          id: incomingLayer
          anchors.fill: parent
          visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
          // fx: маску-шторку заменил TransitionEffect ниже (slant рисует шейдер).
          layer.enabled: false
          layer.smooth: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: revealMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.02
          }

          Image {
            id: incomingFrame
            anchors.fill: parent
            source: root.imageUrl(root.incomingBackground)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            onStatusChanged: panel.maybeStartReveal()
          }
        }

        Item {
          id: revealMask
          anchors.fill: parent
          visible: false
          layer.enabled: true

          readonly property real slant: -0.18
          readonly property real centerTop: width / 2 - slant * height / 2
          readonly property real centerBottom: width / 2 + slant * height / 2
          readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
          readonly property real spread: reach * root.revealProgress

          Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: "white"
              strokeColor: "transparent"
              startX: revealMask.centerTop - revealMask.spread; startY: 0
              PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
              PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
              PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
              PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
            }
          }
        }

        // fx: переход — шейдер поверх старого и нового кадра.
        TransitionEffect {
          id: fxView
          anchors.fill: parent
          visible: root.incomingBackground !== "" && panel.maskReady && root.revealProgress < 1
            && incomingFrame.status === Image.Ready
          fromItem: oldFrame
          toItem: incomingFrame
          progress: root.revealProgress
          effect: root.fxActive
          angleDegrees: root.fxAngle
          softness: root.fxSoftness
          seed: root.fxSeed
          cell: root.fxCell
          glow: root.fxGlow
          lineW: root.fxLineWidth
          fieldPath: root.fxOutline ? root.outlineField : ""
          growPath: root.fxOutline ? root.outlineGrow : ""
          mapType: root.outlineKind
          onMapReadyChanged: panel.maybeStartReveal()
          onMapFailedChanged: panel.maybeStartReveal()
          origin: {
            if (root.fxOrigin === "random") return root.fxRandomOrigin
            var c = root.fxCursor
            var sc = panel.modelData
            if (root.fxOrigin === "cursor" && c && sc && sc.width > 0)
              return Qt.point(Math.max(0, Math.min(1, (c.x - sc.x) / sc.width)), Math.max(0, Math.min(1, (c.y - sc.y) / sc.height)))
            return Qt.point(0.5, 0.5)
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
        function onOutlinePendingChanged() { panel.maybeStartReveal() }
        function onFxPaletteTickChanged() { fxView.capturePalette() }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
