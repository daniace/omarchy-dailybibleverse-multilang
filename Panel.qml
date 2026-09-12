import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Verse-of-the-day popup: a compact, monospace "card" layout (uppercase
// section label, hairline separators, small-caps footer) built entirely
// from the shell's live theme tokens (Color.*/Style.*), so it re-colors
// with whichever Omarchy theme is active — same as every first-party
// panel (weather, clock, network, ...).
Panel {
  id: root
  moduleName: "io.github.daniace.dailybibleverse-multilang"
  ipcTarget: "io.github.daniace.dailybibleverse-multilang"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not
  // this nested panel. See omarchy.weather/omarchy.clock for the same
  // convention this mirrors.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Language & version resolution --------------------------------
  // "language"/"version" settings accept "auto" (default) or an explicit
  // override, e.g. { "id": "io.github.daniace.dailybibleverse-multilang", "version": "nvies" }.
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

  // Full /v1/versions catalogue (fetched once), filtered per language for
  // the version picker.
  property var versionsList: []
  readonly property var languageOptions: Model.languageOptions()
  readonly property var versionOptions: Model.versionOptionsForLanguage(root.versionsList, root.language)

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

  // ---- Fetch chain: one Process, one request at a time -------------------
  //
  // Every fetch goes through this single queue instead of several
  // concurrent Process items: only one curl is ever running for this
  // plugin, which bounds concurrent-request exposure by construction
  // rather than by convention.
  property var fetchQueue: []
  property bool fetchBusy: false

  function enqueueFetch(url, timeoutSeconds, onDone) {
    fetchQueue.push({ url: url, timeoutSeconds: timeoutSeconds, onDone: onDone })
    processFetchQueue()
  }

  function processFetchQueue() {
    if (fetchBusy || fetchQueue.length === 0) return
    var job = fetchQueue.shift()
    fetchBusy = true
    fetchProc.onDone = job.onDone
    fetchProc.command = Model.curlCommand(job.url, job.timeoutSeconds)
    fetchProc.running = true
  }

  // Fixed, verified curl binary + argv only (see Model.curlCommand): no
  // shell, no PATH lookup, no ambient curl config, HTTPS-only including
  // redirects, and bounded time/rate/declared size.
  Process {
    id: fetchProc
    property var onDone: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cb = fetchProc.onDone
        fetchProc.onDone = null
        root.fetchBusy = false
        if (cb) cb(text)
        Qt.callLater(root.processFetchQueue)
      }
    }
  }

  function refresh() {
    retries = 0
    errorMessage = ""
    startVotdFetch()
  }

  function startVotdFetch() {
    loading = true
    var url = "https://api.midvash.com/v1/votd?version=" + encodeURIComponent(root.version)
    enqueueFetch(url, 8, function(text) {
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

      if (root.bookSlug) root.fetchBookName(root.bookSlug, root.language)
      if (root.resolvedVersion) root.fetchVersionMeta(root.resolvedVersion)
    })
  }

  function fetchBookName(bookSlug, language) {
    var url = "https://api.midvash.com/v1/books/" + encodeURIComponent(bookSlug)
    enqueueFetch(url, 8, function(text) {
      root.bookName = Model.parseBookName(text, language, bookSlug)
    })
  }

  function fetchVersionMeta(version) {
    var url = "https://api.midvash.com/v1/versions/" + encodeURIComponent(version)
    enqueueFetch(url, 8, function(text) {
      var meta = Model.parseVersionMeta(text)
      if (meta) {
        root.versionShortName = meta.shortName
        root.attribution = meta.attribution
      }
    })
  }

  function fetchVersionsList() {
    enqueueFetch("https://api.midvash.com/v1/versions", 8, function(text) {
      var list = Model.parseVersionsList(text)
      if (list.length) root.versionsList = list
    })
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

  Timer {
    id: retryTimer
    interval: 3000
    onTriggered: root.startVotdFetch()
  }

  // Re-fetch once the UTC day rolls over; otherwise the same verse simply
  // stays on screen (the API defines it as stable for the whole UTC day).
  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    onTriggered: if (Model.utcDayKey(new Date()) !== root.loadedDayKey) root.refresh()
  }

  Component.onCompleted: {
    refresh()
    fetchVersionsList()
  }

  // ---- Actions -----------------------------------------------------------
  //
  // Fixed, verified binaries invoked as plain argv (no shell string to
  // interpret, so no escaping concerns regardless of verse content),
  // wrapped in `timeout` for a hard duration bound.
  function copyVerse() {
    if (!root.verseText || copyProc.running) return
    var payload = root.verseText + " — " + root.reference
    if (root.versionShortName) payload += " (" + root.versionShortName + ")"
    copyProc.command = [Model.TIMEOUT_BIN, "-k", "1", "5", Model.WL_COPY_BIN, payload]
    copyProc.running = true
  }

  function openSource() {
    // Re-checked here, not just at parse time: never launch a URL opener
    // on anything but an https://midvash.com/... link, no matter how
    // verseUrl got set.
    if (!root.verseUrl || !Model.isAllowedVerseUrl(root.verseUrl) || openProc.running) return
    openProc.command = [Model.TIMEOUT_BIN, "-k", "1", "5", Model.XDG_OPEN_BIN, root.verseUrl]
    openProc.running = true
  }

  Process { id: copyProc }
  Process { id: openProc }

  // Persist a settings patch into this widget's shell.json bar entry (same
  // mechanism omarchy.clock uses for cycleFormat), applied locally first so
  // the UI updates immediately rather than waiting on the file round-trip.
  function persistSettings(patch) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var patchKey in patch) entry[patchKey] = patch[patchKey]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Switching language resets the version to that language's default —
  // the previous version slug almost never exists in the new language.
  function setLanguage(code) {
    if (!code || code === root.languageOverride) return
    persistSettings({ language: code, version: "auto" })
    refresh()
  }

  function setVersion(slug) {
    if (!slug || slug === root.version) return
    persistSettings({ version: slug })
    refresh()
  }

  // The language/version Dropdowns own their `value` after the first user
  // selection (Dropdown assigns it internally on pick), so an external
  // change — e.g. picking a language, which resets the resolved version —
  // needs to be pushed back in explicitly to keep both in sync.
  Connections {
    target: root
    function onLanguageChanged() { languageDropdown.value = root.language }
    function onVersionChanged() { versionDropdown.value = root.version }
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

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  KeyboardPanel {
    id: keyboardPanel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: keyboardPanel.fittedContentWidth(Style.space(440))
    contentHeight: keyboardPanel.fittedContentHeight(cardColumn.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: languageDropdown.popupOpen || versionDropdown.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Column {
        id: cardColumn
        width: parent.width
        spacing: Style.space(12)

        // ---- Header: "VERSE OF THE DAY" + refresh ---------------------
        Item {
          width: parent.width
          height: Math.max(headingText.implicitHeight, refreshButton.implicitHeight)

          PanelSectionHeader {
            id: headingText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.strings.heading
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          PanelActionButton {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: Style.space(22)
            iconText: root.loading ? "…" : "↻"
            tooltipText: root.strings.refresh
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            focusable: true
            onClicked: root.refresh()
          }
        }

        // ---- Date --------------------------------------------------------
        Text {
          width: parent.width
          text: new Date().toLocaleDateString(root.localeObj, Model.dateFormatFor(root.language))
          color: Qt.darker(root.contentForeground, 1.2)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // ---- Reference -----------------------------------------------------
        Text {
          width: parent.width
          text: root.reference || "…"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        // ---- Quote -----------------------------------------------------
        Text {
          width: parent.width
          text: root.errorMessage
            ? root.errorMessage
            : (root.verseText ? ("“" + root.verseText + "”") : root.strings.loading)
          color: root.contentForeground
          wrapMode: Text.WordWrap
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          lineHeight: 1.3
        }

        PanelSeparator {
          foreground: root.contentForeground
        }

        // ---- Language / version pickers -----------------------------
        Row {
          width: parent.width
          spacing: Style.space(10)

          Dropdown {
            id: languageDropdown
            width: (parent.width - parent.spacing) / 2
            showLabel: false
            options: root.languageOptions
            value: root.language
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onChanged: function(v) { root.setLanguage(v) }
          }

          Dropdown {
            id: versionDropdown
            width: (parent.width - parent.spacing) / 2
            showLabel: false
            options: root.versionOptions
            value: root.version
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onChanged: function(v) { root.setVersion(v) }
          }
        }

        PanelSeparator {
          foreground: root.contentForeground
        }

        // ---- Footer row 1: attribution · COPY / ASK -----------------
        Item {
          width: parent.width
          height: Math.max(footerLeft1.implicitHeight, actionsRow.implicitHeight)

          Text {
            id: footerLeft1
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: [root.versionShortName, root.attribution].filter(function(s) { return !!s }).join(" · ")
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
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
              color: copyArea.containsMouse ? Color.accent : Qt.darker(Color.accent, 1.15)
              font.family: root.contentFontFamily
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
              color: askArea.containsMouse ? Color.accent : Qt.darker(Color.accent, 1.15)
              font.family: root.contentFontFamily
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

        // ---- Footer row 2: data credit · plugin version -----------------
        Item {
          width: parent.width
          height: footerLeft2.implicitHeight

          Text {
            id: footerLeft2
            anchors.left: parent.left
            text: root.strings.dataVia + " midvash.com"
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.right: parent.right
            text: "v0.3.0"
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
