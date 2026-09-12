import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Verse-of-the-day popup: a self-contained "terminal card" look (own dark
// palette + neon border) rather than the system theme, by design — this is
// meant to read the same regardless of which Omarchy theme is active.
Panel {
  id: root
  moduleName: "io.github.daniace.bibleverse"
  ipcTarget: "io.github.daniace.bibleverse"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not
  // this nested panel. See omarchy.weather/omarchy.clock for the same
  // convention this mirrors.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Language & version resolution --------------------------------
  // "language"/"version" settings accept "auto" (default) or an explicit
  // override, e.g. { "id": "io.github.daniace.bibleverse", "version": "nvies" }.
  readonly property string languageOverride: setting("language", "auto")
  readonly property string versionOverride: setting("version", "auto")
  readonly property string language: Model.resolveLanguage(languageOverride, Qt.locale().name)
  readonly property string version: Model.resolveVersion(versionOverride, language)
  readonly property var strings: Model.stringsFor(language)
  readonly property var localeObj: Qt.locale(Model.localeTagFor(language))

  // ---- Verse state -----------------------------------------------------
  property string verseText: ""
  property string verseUrl: ""
  property string bookName: ""
  property string bookSlug: ""
  property var chapter: null
  property var verseStart: null
  property var verseEnd: null
  property string resolvedVersion: ""
  property string versionShortName: ""
  property string attribution: ""
  property string loadedDayKey: ""
  property bool loading: false
  property string errorMessage: ""
  property int retries: 0

  readonly property string reference: Model.buildReference(bookName, chapter, verseStart, verseEnd)
  // Short label for the bar pill: falls back through loading/error states
  // so the pill always shows something sensible.
  readonly property string shortLabel: verseText !== "" ? reference : ""
  readonly property string tooltipText: verseText !== "" ? verseText : (errorMessage || "")

  function open() {
    root.controller.show()
  }

  function openFromHotkey() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // ---- Fetch chain: votd -> localized book name + version attribution --
  function refresh() {
    retries = 0
    errorMessage = ""
    startVotdFetch()
  }

  function startVotdFetch() {
    if (votdProc.running) return
    loading = true
    var url = "https://api.midvash.com/v1/votd?version=" + encodeURIComponent(root.version)
    votdProc.command = ["curl", "-fsS", "--max-time", "8", url]
    votdProc.running = true
  }

  function scheduleVotdRetry() {
    if (retries >= 3) {
      loading = false
      errorMessage = strings.error
      return
    }
    retries++
    retryTimer.restart()
  }

  Process {
    id: votdProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseVotd(text)
        if (!parsed) {
          root.scheduleVotdRetry()
          return
        }
        root.loading = false
        root.errorMessage = ""
        root.retries = 0
        root.loadedDayKey = Model.utcDayKey(new Date())
        root.verseText = parsed.text
        root.verseUrl = parsed.url
        root.bookSlug = parsed.bookSlug
        root.chapter = parsed.chapter
        root.verseStart = parsed.verseStart
        root.verseEnd = parsed.verseEnd
        root.resolvedVersion = parsed.version || root.version

        if (root.bookSlug) {
          bookProc.command = ["curl", "-fsS", "--max-time", "8", "https://api.midvash.com/v1/books/" + encodeURIComponent(root.bookSlug)]
          bookProc.running = true
        }
        if (root.resolvedVersion) {
          versionMetaProc.command = ["curl", "-fsS", "--max-time", "8", "https://api.midvash.com/v1/versions/" + encodeURIComponent(root.resolvedVersion)]
          versionMetaProc.running = true
        }
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 3000
    onTriggered: root.startVotdFetch()
  }

  Process {
    id: bookProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.bookName = Model.parseBookName(text, root.language, root.bookSlug)
      }
    }
  }

  Process {
    id: versionMetaProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var meta = Model.parseVersionMeta(text)
        if (meta) {
          root.versionShortName = meta.shortName
          root.attribution = meta.attribution
        }
      }
    }
  }

  // Re-fetch once the UTC day rolls over; otherwise the same verse simply
  // stays on screen (the API defines it as stable for the whole UTC day).
  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    onTriggered: if (Model.utcDayKey(new Date()) !== root.loadedDayKey) root.refresh()
  }

  Component.onCompleted: refresh()

  // ---- Actions -----------------------------------------------------------
  function copyVerse() {
    if (!root.verseText) return
    var payload = root.verseText + " — " + root.reference
    if (root.versionShortName) payload += " (" + root.versionShortName + ")"
    if (root.bar) root.bar.run("wl-copy " + Model.shellQuote(payload))
  }

  function openSource() {
    if (!root.verseUrl || !root.bar) return
    root.bar.run("xdg-open " + Model.shellQuote(root.verseUrl))
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  // ---- Palette: a fixed "terminal card" look, independent of the active
  //      Omarchy theme, matching the plugin's reference design.
  QtObject {
    id: palette
    readonly property color background: "#0b0f1e"
    readonly property color border: "#4c6ef5"
    readonly property color heading: "#7d879c"
    readonly property color date: "#8b93a7"
    readonly property color reference: "#eef0f6"
    readonly property color quote: "#c9cfe0"
    readonly property color separator: "#26304a"
    readonly property color muted: "#6b7280"
    readonly property color accent: "#8aa2ff"
    readonly property color accentHover: "#b9c6ff"
  }

  readonly property int cardMargin: Style.space(20)

  KeyboardPanel {
    id: keyboardPanel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: 0
    borderSpec: Border.flat(palette.border, Math.max(1, Style.space(2)))
    contentWidth: keyboardPanel.fittedContentWidth(Style.space(440))
    contentHeight: keyboardPanel.fittedContentHeight(cardColumn.implicitHeight + root.cardMargin * 2, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Rectangle {
        id: cardBackground
        anchors.fill: parent
        color: palette.background
        radius: Style.cornerRadius

        Column {
          id: cardColumn
          anchors.fill: parent
          anchors.margins: root.cardMargin
          spacing: Style.space(10)

          // ---- Header: "VERSE OF THE DAY" + refresh -------------------
          Item {
            width: parent.width
            height: headingText.implicitHeight

            Text {
              id: headingText
              text: root.strings.heading
              color: palette.heading
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 1.5
            }

            Text {
              id: refreshGlyph
              anchors.right: parent.right
              anchors.verticalCenter: headingText.verticalCenter
              text: root.loading ? "…" : "↻"
              color: refreshArea.containsMouse ? palette.accentHover : palette.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body

              MouseArea {
                id: refreshArea
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }
          }

          // ---- Date ----------------------------------------------------
          Text {
            width: parent.width
            text: new Date().toLocaleDateString(root.localeObj, Model.dateFormatFor(root.language))
            color: palette.date
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          // ---- Reference -------------------------------------------------
          Text {
            width: parent.width
            text: root.reference || "…"
            color: palette.reference
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          // ---- Quote -----------------------------------------------------
          Text {
            width: parent.width
            text: root.errorMessage
              ? root.errorMessage
              : (root.verseText ? ("“" + root.verseText + "”") : root.strings.loading)
            color: palette.quote
            wrapMode: Text.WordWrap
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            lineHeight: 1.3
          }

          // ---- Separator ---------------------------------------------
          Rectangle {
            width: parent.width
            height: 1
            color: palette.separator
          }

          // ---- Footer row 1: version/attribution · COPY / ASK -----------
          Item {
            width: parent.width
            height: Math.max(footerLeft1.implicitHeight, actionsRow.implicitHeight)

            Text {
              id: footerLeft1
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: [root.versionShortName, root.attribution].filter(function(s) { return !!s }).join(" · ")
              color: palette.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: Math.min(implicitWidth, parent.width - actionsRow.implicitWidth - Style.space(12))
            }

            Row {
              id: actionsRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(16)

              Text {
                text: root.strings.copy
                color: copyArea.containsMouse ? palette.accentHover : palette.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true

                MouseArea {
                  id: copyArea
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  enabled: root.verseText !== ""
                  onClicked: root.copyVerse()
                }
              }

              Text {
                text: root.strings.ask
                color: askArea.containsMouse ? palette.accentHover : palette.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true

                MouseArea {
                  id: askArea
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  enabled: root.verseUrl !== ""
                  onClicked: root.openSource()
                }
              }
            }
          }

          // ---- Footer row 2: data credit · plugin version ---------------
          Item {
            width: parent.width
            height: footerLeft2.implicitHeight

            Text {
              id: footerLeft2
              anchors.left: parent.left
              text: root.strings.dataVia + " midvash.com"
              color: palette.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.right: parent.right
              text: "v0.1.0"
              color: palette.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
