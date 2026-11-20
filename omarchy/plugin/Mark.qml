import QtQuick
import QtQuick.Effects
import qs.Commons as Commons

// The Crossroads signpost in one color, so it follows the theme like the
// bar's other icons. The artwork is a PNG mask because Qt's SVG renderer
// can't cut the gaps that assets/logo-mono.svg cuts with an SVG mask.
Item {
  id: root

  property color color: Commons.Color.foreground
  property real size: 16
  readonly property real aspectRatio: 196 / 172

  width: size * aspectRatio
  height: size
  implicitWidth: width
  implicitHeight: height

  Image {
    id: art
    anchors.fill: parent
    source: Qt.resolvedUrl("mark.png")
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    // Kept as a hidden layer so the effect can sample it as a texture.
    visible: false
    layer.enabled: true
  }

  // Paint the color through the artwork's alpha, as the bar's tray does.
  Rectangle {
    anchors.fill: art
    color: root.color
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: art
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
  }
}
