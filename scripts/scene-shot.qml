import QtQuick
import QtQuick.Window
import ".."

// Снимок живых обоев в PNG (для тем и превью): qml scene-shot.qml -- '<json сцены>' <out.png> [ширина высота]
Window {
  id: w
  readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  width: Number(args[2] || 2880); height: Number(args[3] || 1800)
  visible: true
  color: "black"
  property var cfg: ({})
  Component.onCompleted: {
    cfg = JSON.parse(args[0])
    shot.start()
  }
  SceneTerrain { id: scene; anchors.fill: parent; animate: false; config: w.cfg; workspace: Number(w.cfg.workspace || 1) }
  Timer {
    id: shot; interval: 600
    onTriggered: scene.grabToImage(function(r) { r.saveToFile(w.args[1]); Qt.quit() }, Qt.size(w.width, w.height))
  }
}
