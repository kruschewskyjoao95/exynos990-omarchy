import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Cellular status of the r8s S5123 modem. s5123-ril.py rewrites /run/s5123/status.json every 2 s
// (and r8s-modem.service writes off/booting/failed); this widget only reads it.
BarWidget {
  id: root
  moduleName: "r8s.cellular"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var info: ({ modem: "off" })
  property bool stale: false
  property bool popupOpen: false
  function close() { popupOpen = false }

  readonly property bool airplane: info.airplane === true
  readonly property bool dataEnabled: info.data_enabled !== false
  readonly property bool dataActive: info.data === true

  // Fixed command lines only: nothing from the status file reaches the shell.
  function setAirplane(on) { if (root.bar) root.bar.run(on ? "r8s-modem-ctl airplane on" : "r8s-modem-ctl airplane off") }
  function setData(on) { if (root.bar) root.bar.run(on ? "r8s-modem-ctl data on" : "r8s-modem-ctl data off") }

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // The file is root's but world-readable; its text is still treated as untrusted input.
  function clean(value, pattern, max) {
    var s = String(value === undefined || value === null ? "" : value)
    return s.replace(pattern, "").slice(0, max)
  }

  function parse(text) {
    try {
      var doc = JSON.parse(text)
      root.info = (doc && typeof doc === "object") ? doc : { modem: "off" }
    } catch (e) {
      root.info = { modem: "off" }
    }
    root.checkStale()
  }

  function checkStale() {
    var t = Number(root.info.updated || 0)
    root.stale = root.info.modem === "online" && t > 0 && (Date.now() / 1000 - t) > 15
  }

  readonly property string modemState: clean(info.modem, /[^a-z]/g, 12)
  readonly property string reg: clean(info.registration, /[^a-z]/g, 12)
  readonly property string operatorName: clean(info.operator, /[^A-Za-z0-9 ]/g, 16)
  readonly property string ratName: clean(info.rat, /[^A-Za-z0-9 +?]/g, 8)
  readonly property int bars: Math.max(0, Math.min(5, Number(info.bars) || 0))
  readonly property bool inService: modemState === "online" && !stale && (reg === "home" || reg === "roaming")

  readonly property string glyph: {
    if (modemState === "online" && airplane) return "\u{f001d}"        // md-airplane
    if (modemState !== "online" || stale) return "\u{f0783}"            // md-signal_off
    if (clean(info.sim, /[^a-z]/g, 8) === "absent") return "\u{f04a9}"  // md-sim_off
    if (!inService) return "\u{f08bf}"                                  // md-signal_cellular_outline
    if (bars <= 1) return "\u{f08bc}"
    if (bars === 2) return "\u{f08bd}"
    return "\u{f08be}"
  }

  readonly property string tooltip: {
    if (stale) return strings.t("stale")
    if (modemState === "booting") return strings.t("booting")
    if (modemState === "failed") return strings.t("failed")
    if (modemState !== "online") return strings.t("off")
    if (airplane) return strings.t("airplaneMode")
    if (clean(info.sim, /[^a-z]/g, 8) === "absent") return strings.t("noSim")
    if (reg === "searching") return strings.t("searching")
    if (reg === "emergency") return strings.t("emergency")
    if (!inService) return strings.t("noService")
    var dbm = Number(info.dbm)
    return strings.t(reg === "roaming" ? "roaming" : "registered")
      .arg(operatorName || "?").arg(ratName || "?").arg(isFinite(dbm) ? dbm : "?")
  }

  FileView {
    id: statusFile
    path: "/run/s5123/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.info = { modem: "off" }
  }

  // The daemon writes every 2 s: a file older than 15 s means it stopped without saying so.
  Timer {
    interval: 10000
    running: root.modemState === "online"
    repeat: true
    onTriggered: root.checkStale()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.inService && root.ratName ? root.glyph + " " + root.ratName.split(" ")[0] : root.glyph
    tooltipText: root.popupOpen ? "" : root.tooltip
    onPressed: function(mouseButton) { root.popupOpen = !root.popupOpen }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      width: parent.width
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: strings.t("title")
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: root.tooltip
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Toggle {
        width: parent.width
        enabled: root.modemState === "online" && !root.airplane
        opacity: enabled ? 1 : 0.5
        label: strings.t("data")
        description: !root.dataEnabled ? strings.t("dataOff")
          : root.dataActive ? strings.t("dataOn").arg(root.ratName || "?") : strings.t("dataReady")
        checked: root.dataEnabled
        onClicked: root.setData(!root.dataEnabled)
      }
      Toggle {
        width: parent.width
        enabled: root.modemState === "online"
        opacity: enabled ? 1 : 0.5
        label: strings.t("airplane")
        description: root.airplane ? strings.t("airplaneOn") : strings.t("airplaneOff")
        checked: root.airplane
        onClicked: root.setAirplane(!root.airplane)
      }
    }
  }
}
