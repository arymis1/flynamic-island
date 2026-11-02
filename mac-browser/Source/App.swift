import AppKit
import SwiftUI
import Combine
import QuartzCore

struct AirPlayOutput: Identifiable {
    let id: String
    let name: String
    let selected: Bool
    let available: Bool
    let symbol: String
}

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var safeTop: CGFloat = 32
    @Published var collapsedWidth: CGFloat = 179
    @Published var showingAirPlay = false
    @Published var panelVisible = false
    @Published var requestedPane: IslandPane?
    var setExpanded: ((Bool) -> Void)?
    var pointerIsInside: () -> Bool = { false }
    var collapseWork: DispatchWorkItem?
    func hover(_ entered: Bool) {
        collapseWork?.cancel()
        if entered { setExpanded?(true) }
        else if !pinned && !showingAirPlay {
            let work = DispatchWorkItem { [weak self] in self?.setExpanded?(false) }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        }
    }
    func togglePin() {
        pinned.toggle()
        UserDefaults.standard.set(pinned, forKey: "keepExpanded")
        if pinned { setExpanded?(true) }
        else if !pointerIsInside() { hover(false) }
    }
}

struct AirPlayPicker: View {
    @ObservedObject var music: MusicModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sound").font(.system(size: 15, weight: .semibold))
                Spacer()
                if music.airPlayLoading { ProgressView().controlSize(.small) }
                else { Button { music.loadAirPlayOutputs() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh outputs").accessibilityLabel("Refresh outputs") }
            }
            Divider()
            Text("Output").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if music.airPlayOutputs.isEmpty && !music.airPlayLoading {
                Text("No outputs found. Check available speakers in Music.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(music.airPlayOutputs) { output in
                Button { music.selectAirPlayOutput(output.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: output.symbol).frame(width: 28, height: 28)
                            .foregroundStyle(output.selected ? Color.accentColor : .white)
                            .background(output.selected ? Color.white : Color.white.opacity(0.13), in: Circle())
                        Text(output.name).lineLimit(1)
                        Spacer()
                        if output.selected { Image(systemName: "checkmark").fontWeight(.semibold) }
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!output.available || music.airPlayLoading)
                    .accessibilityLabel(output.name).accessibilityValue(output.selected ? "Selected" : "Not selected")
            }
            if !music.airPlayError.isEmpty { Text(music.airPlayError).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Divider()
            Button("Sound Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
            }.buttonStyle(.plain).font(.system(size: 12))
        }.padding(18).frame(width: 280).preferredColorScheme(.dark)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { music.loadAirPlayOutputs(clearError: false) }
                }
            }
    }
}

struct ArtView: View {
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2).fill(LinearGradient(colors: [Color(red: 0.49, green: 0.08, blue: 0.19), Color(red: 0.14, green: 0.02, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.8)) }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .accessibilityLabel("Album artwork")
    }
}

struct Equalizer: View {
    var playing: Bool
    var color: Color
    @ObservedObject var meter: AudioVisualization
    var body: some View {
            HStack(spacing: 2.5) {
                ForEach(0..<4) { index in
                    Capsule().fill(color).frame(width: 3, height: playing ? max(3, 2 + meter.levels[index] * 20) : 3)
                        .animation(playing ? .linear(duration: 1.0 / 30.0) : nil, value: meter.levels[index])
                }
            }.frame(width: 23, height: 24)
                .accessibilityLabel(playing ? "Live music levels" : "Paused. Flat dots")
    }
}

struct CircleControl: View {
    let symbol: String
    let label: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: prominent ? 28 : 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: prominent ? 48 : 44, height: prominent ? 48 : 44)
                .contentShape(Circle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct MusicScrubber: View {
    @Binding var value: Double
    var upperBound: Double
    var tint: Color
    var label: String
    var onEditingChanged: (Bool) -> Void
    @State private var dragging = false
    @State private var hovered = false
    var body: some View {
        GeometryReader { geometry in
            let fraction = IslandLogic.boundedPosition(value, duration: max(1, upperBound)) / max(1, upperBound)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.17)).frame(height: 3)
                Capsule().fill(tint).frame(width: max(0, geometry.size.width * fraction), height: 3)
                Circle().fill(tint).frame(width: 7, height: 7)
                    .offset(x: max(0, geometry.size.width * fraction - 3.5))
                    .opacity(dragging || hovered ? 1 : 0)
            }.frame(height: 18).contentShape(Rectangle())
                .onHover { hovered = $0 }
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    if !dragging { dragging = true; onEditingChanged(true) }
                    value = min(1, max(0, gesture.location.x / max(1, geometry.size.width))) * upperBound
                }.onEnded { gesture in
                    value = min(1, max(0, gesture.location.x / max(1, geometry.size.width))) * upperBound
                    onEditingChanged(false)
                    dragging = false
                })
        }.frame(height: 18)
            .accessibilityRepresentation {
                Slider(value: Binding(get: { value }, set: { newValue in
                    onEditingChanged(true); value = newValue; onEditingChanged(false)
                }), in: 0...max(1, upperBound)).accessibilityLabel(label)
            }
    }
}

struct IslandView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var music: MusicModel
    @ObservedObject var island: IslandState
    @ObservedObject var stats: SystemStatsModel
    private var showingStats: Bool {
        return IslandPane.selected(playing: music.playing, playerRunning: music.isMusicRunning, hasTrack: music.hasCurrentTrack, requested: island.requestedPane) == .stats
    }
    private var musicPageMix: Double { showingStats ? 0 : 1 }
    private func selectPage(_ pane: IslandPane) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.20)) {
            island.requestedPane = pane
        }
    }
    // Keep a real rolling history across panes and between hovers. These
    // inexpensive kernel reads do not require the card or Activity Monitor open.
    private func updateSampling() { stats.setSamplingEnabled(island.panelVisible) }
    @State private var seekDraft = 0.0
    @State private var seeking = false
    @State private var volumeDraft = 50.0
    @State private var adjustingVolume = false
    private let accent = Color(red: 1, green: 0.22, blue: 0.36)
    private var artworkTint: Color {
        Color(red: music.artworkAccent.red, green: music.artworkAccent.green, blue: music.artworkAccent.blue)
    }
    private var lightArtworkTint: Color {
        Color(red: music.artworkAccent.red * 0.55 + 0.45,
              green: music.artworkAccent.green * 0.55 + 0.45,
              blue: music.artworkAccent.blue * 0.55 + 0.45)
    }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: island.safeTop > 0 ? 0 : 20,
                               bottomLeadingRadius: island.expanded ? 27 : 10,
                               bottomTrailingRadius: island.expanded ? 27 : 10,
                               topTrailingRadius: island.safeTop > 0 ? 0 : 20)
    }
    private var expandedHeight: CGFloat { island.safeTop > 0 ? island.safeTop + 232 : 246 }
    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(.black)
            VStack(spacing: 0) {
                Color.clear.frame(height: island.safeTop)
                ZStack {
                    Color(white: 0.14)
                    ZStack {
                        LinearGradient(colors: [artworkTint, artworkTint.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        if let backdrop = music.artworkBackdrop {
                            Image(nsImage: backdrop).resizable().interpolation(.high).scaledToFill()
                        }
                    }.opacity(musicPageMix)
                }
                .frame(width: 386, height: expandedHeight - island.safeTop).clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.32), .black.opacity(0.52)], startPoint: .top, endPoint: .bottom))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.13), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom))
            }.frame(width: 386, height: expandedHeight, alignment: .top)
                .opacity(island.expanded ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            // Keep content laid out at its final size; reveal it through the animated mask.
            expanded.padding(.horizontal, 22).padding(.top, island.safeTop > 0 ? island.safeTop + 13 : 17)
                .frame(width: 386, alignment: .top)
                .opacity(island.expanded ? 1 : 0)
                .offset(y: island.expanded ? 0 : -5)
                .animation(.easeOut(duration: island.expanded ? 0.18 : 0.08).delay(island.expanded ? 0.09 : 0), value: island.expanded)
                .allowsHitTesting(island.expanded)
                .accessibilityHidden(!island.expanded)
            Button { island.togglePin() } label: {
                HStack(spacing: 10) {
                    ArtView(image: music.artwork, size: 22)
                    if island.safeTop == 0 {
                        Text(music.status == "track" ? music.title : "FLYnamic YT Music").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Equalizer(playing: music.playing && !island.expanded, color: artworkTint, meter: music.visualizer)
                }.padding(.horizontal, 12)
                    .frame(width: island.collapsedWidth, height: island.safeTop > 0 ? island.safeTop : 40)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(music.hasCurrentTrack ? "Open music controls. \(music.title). \(music.playing ? "Playing" : "Paused")" : "Show system statistics")
                .accessibilityValue(music.visualizer.status)
                .opacity(!island.expanded && music.hasCurrentTrack ? 1 : 0)
                .animation(.easeOut(duration: 0.12).delay(island.expanded ? 0 : 0.16), value: island.expanded)
                .allowsHitTesting(!island.expanded)
                .accessibilityHidden(island.expanded)
        }
        .frame(width: island.expanded ? 386 : island.collapsedWidth,
               height: island.expanded ? expandedHeight : (island.safeTop > 0 ? island.safeTop : 40), alignment: .top)
        .foregroundStyle(.white)
        .clipShape(shape)
        .frame(width: 386, height: expandedHeight, alignment: .top)
        .animation(.easeInOut(duration: 0.45), value: music.artworkAccent)
        .onChange(of: island.showingAirPlay) { _, showing in
            if !showing && !island.pinned && !island.pointerIsInside() { island.hover(false) }
        }
        .onAppear { updateSampling() }
        .onChange(of: island.expanded) { _, expanded in
            if !expanded { island.requestedPane = nil }
            music.visualizer.setVisible(island.panelVisible && !expanded && music.playing)
            updateSampling()
        }
        .onChange(of: island.panelVisible) { _, _ in updateSampling() }
        .onChange(of: showingStats) { _, _ in updateSampling() }
        .onChange(of: music.playing) { _, _ in updateSampling() }
        .onChange(of: music.hasCurrentTrack) { _, _ in island.setExpanded?(island.expanded) }
        .onDisappear { stats.setSamplingEnabled(false) }
        .accessibilityAction(named: Text("Show system stats")) { selectPage(.stats) }
        .accessibilityAction(named: Text("Show music controls")) {
            selectPage(.music)
        }
        .preferredColorScheme(.dark)
    }
    @ViewBuilder var expanded: some View {
        VStack(spacing: 9) {
            HStack {
                if showingStats {
                    Text("System").font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                if music.isMusicRunning {
                    HStack(spacing: 5) {
                        Circle().fill(.white.opacity(0.8 - musicPageMix * 0.6))
                        Circle().fill(.white.opacity(0.2 + musicPageMix * 0.6))
                    }.frame(width: 13, height: 4).padding(.trailing, 8)
                        .help("Swipe left with two fingers for Music; swipe right for Stats.")
                        .accessibilityLabel(showingStats ? "Page 1 of 2, System statistics" : "Page 2 of 2, Music")
                }
                Button { island.togglePin() } label: {
                    Image(systemName: island.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 12)).foregroundStyle(island.pinned ? .white : .white.opacity(0.45))
                        .frame(width: 24, height: 24)
                }.buttonStyle(.plain).help(island.pinned ? "Unpin island" : "Keep expanded")
                    .accessibilityLabel(island.pinned ? "Unpin island" : "Keep expanded")
            }.frame(height: 25)
            ZStack(alignment: .topLeading) {
                SystemStatsView(stats: stats)
                    .frame(width: 342, height: 177, alignment: .top)
                    .offset(x: reduceMotion || showingStats ? 0 : -18)
                    .opacity(showingStats ? 1 : 0)
                    .allowsHitTesting(showingStats)
                    .accessibilityHidden(!showingStats)
                musicContents
                    .frame(width: 342, height: 177, alignment: .top)
                    .offset(x: reduceMotion || !showingStats ? 0 : 18)
                    .opacity(musicPageMix)
                    .allowsHitTesting(!showingStats)
                    .accessibilityHidden(showingStats)
            }.frame(width: 342, height: 177, alignment: .topLeading).clipped()
        }
    }
    @ViewBuilder var musicContents: some View {
        if music.status == "track" {
            VStack(spacing: 8) {
                HStack(spacing: 13) {
                    Button { music.openMusic() } label: {
                        HStack(spacing: 13) {
                            ArtView(image: music.artwork, size: 43)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(music.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Text(music.artist.isEmpty ? music.source.title : music.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .help("Open in \(music.source.title)")
                        .accessibilityLabel("Open \(music.title) in \(music.source.title)")
                    if music.source == .appleMusic {
                    Button { music.toggleFavorite() } label: {
                        ZStack {
                            if music.updatingFavorite { ProgressView().controlSize(.mini) }
                            else { Image(systemName: music.favorited ? "star.fill" : "star") }
                        }
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(music.favorited ? lightArtworkTint : .white.opacity(0.65))
                            .frame(width: 28, height: 30)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .disabled(music.busy || music.updatingFavorite || !music.favoriteAvailable)
                        .help(music.favoriteAvailable ? (music.favorited ? "Remove from Favorites" : "Add to Favorites") : "Favorites unavailable for this song")
                        .accessibilityLabel(music.favorited ? "Remove from Favorites" : "Add to Favorites")
                        .accessibilityValue(music.updatingFavorite ? "Saving in Apple Music" : (music.favorited ? "Favorited" : "Not favorited"))
                    }
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !music.playing || !island.expanded || showingStats)) { _ in
                    let livePosition = music.currentPosition()
                    VStack(spacing: 0) {
                    MusicScrubber(value: Binding(get: { seeking ? seekDraft : livePosition }, set: { seekDraft = $0 }), upperBound: music.duration, tint: lightArtworkTint, label: "Track position", onEditingChanged: { editing in
                        seeking = editing
                        if !editing { music.command("seek", value: seekDraft) }
                    }).disabled(music.duration <= 0)
                    HStack {
                        Text(IslandLogic.seconds(seeking ? seekDraft : livePosition))
                        Spacer()
                        Text("−" + IslandLogic.seconds(max(0, music.duration - (seeking ? seekDraft : livePosition))))
                    }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                    }
                }
                ZStack {
                    HStack(spacing: 20) {
                        CircleControl(symbol: "backward.fill", label: "Previous track") { music.command("previous") }
                            .disabled(music.busy)
                        CircleControl(symbol: music.playing ? "pause.fill" : "play.fill", label: music.playing ? "Pause" : "Play", prominent: true) { music.command("playpause") }
                        CircleControl(symbol: "forward.fill", label: "Next track") { music.command("next") }
                            .disabled(music.busy)
                    }
                    HStack {
                        Button { music.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(music.shuffleEnabled ? lightArtworkTint : .white.opacity(0.55))
                                .frame(width: 30, height: 40)
                                .background(music.shuffleEnabled ? lightArtworkTint.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .disabled(!music.shuffleAvailable || music.updatingShuffle)
                            .help(music.shuffleEnabled ? "Turn shuffle off" : "Turn shuffle on")
                            .accessibilityLabel("Shuffle")
                            .accessibilityValue(music.shuffleEnabled ? "On" : "Off")
                        Spacer()
                        Button {
                            island.collapseWork?.cancel(); island.showingAirPlay = true
                            music.loadAirPlayOutputs()
                        } label: {
                            Image(systemName: "airplay.audio").font(.system(size: 20)).foregroundStyle(.white.opacity(0.55)).frame(width: 28, height: 40)
                        }.buttonStyle(.plain).help("Sound output").accessibilityLabel("Sound output")
                            .popover(isPresented: $island.showingAirPlay, arrowEdge: .top) { AirPlayPicker(music: music) }
                    }
                }
                HStack(spacing: 9) {
                    Image(systemName: "speaker.fill").font(.system(size: 10))
                    MusicScrubber(value: Binding(get: { adjustingVolume ? volumeDraft : music.volume }, set: { volumeDraft = $0 }), upperBound: 100, tint: .white.opacity(0.55), label: "Music volume", onEditingChanged: { editing in
                        adjustingVolume = editing
                        if !editing { music.command("volume", value: volumeDraft) }
                    })
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
                }.foregroundStyle(.white.opacity(0.35))
                if !music.message.isEmpty { Text(music.message).font(.system(size: 9)).foregroundStyle(.orange) }
            }
        } else {
            VStack(spacing: 12) {
                HStack {
                    ArtView(image: nil, size: 43)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FLYnamic YT Music").font(.system(size: 16, weight: .semibold))
                        Text("Your music, a little closer.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                Text(emptyMessage).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(emptyAction) {
                        if music.status == "permission" { music.connect() }
                        else if music.status == "chrome-setting" { music.refresh() }
                        else if music.status == "denied" { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
                        else if music.status == "error" { music.refresh() }
                        else { music.openMusic() }
                    }.buttonStyle(.borderedProminent).tint(accent).disabled(music.busy)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.4))
                }
            }.padding(.top, 4)
        }
    }
    var emptyMessage: String {
        switch music.status {
        case "chrome-setting": return "In Chrome: View → Developer → Allow JavaScript from Apple Events. Then choose Retry here."
        case "permission": return "Allow FLYnamic YT Music to control \(music.source.title) to show your song and playback controls."
        case "denied": return "Allow FLYnamic YT Music to control \(music.source.title) in System Settings → Privacy & Security → Automation."
        case "closed": return "Open YouTube Music in Chrome and choose a song."
        case "idle": return "Choose a song in \(music.source.title) to get started."
        case "error": return "\(music.source.title) isn’t responding. You can retry or reopen it."
        default: return "Connecting to \(music.source.title)…"
        }
    }
    var emptyAction: String {
        switch music.status {
        case "chrome-setting": return "Retry"
        case "permission": return "Connect Chrome"
        case "denied": return "Open Settings"
        case "error": return "Retry"
        default: return "Open \(music.source.title)"
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let music = MusicModel()
    let island = IslandState()
    let stats = SystemStatsModel()
    var panel: IslandPanel!
    var item: NSStatusItem!
    var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }
    var visibility = IslandVisibility()
    var hidden: Bool { !visibility.isVisible }
    var pointerTimer: Timer?
    var hoverTracker = HoverTracker()
    var swipeTracker = IslandSwipeTracker()
    var scrollMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // The alternate edition replaces the companion panel in this session.
        // Keeping both panels at the same notch would cover the new controls.
        for companion in NSRunningApplication.runningApplications(withBundleIdentifier: "local.aryan.music-island") {
            companion.terminate()
        }
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.canBecomeVisibleWithoutLogin = false
        panel.title = "FLYnamic YT Music"
        panel.identifier = NSUserInterfaceItemIdentifier("YTMusicIsland")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: IslandView(music: music, island: island, stats: stats))
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleIslandScroll(event)
        }
        island.setExpanded = { [weak self] expanded in self?.resize(expanded) }
        island.pointerIsInside = { [weak self] in self?.hoverTracker.isInside ?? false }
        island.pinned = UserDefaults.standard.bool(forKey: "keepExpanded")
        if !UserDefaults.standard.bool(forKey: "ytOpenedBefore") {
            island.pinned = true
            UserDefaults.standard.set(true, forKey: "ytOpenedBefore")
        }
        resize(island.pinned, animate: false)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "FLYnamic YT Music")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / hide island", action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(withTitle: "Keep expanded", action: #selector(togglePin), keyEquivalent: "")
        menu.addItem(withTitle: "Open player", action: #selector(openMusic), keyEquivalent: "")
        menu.addItem(withTitle: "Audio-reactive bars", action: #selector(toggleAudioBars), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FLYnamic YT Music", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        menu.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.trackPointer() }
        timer.tolerance = 0.003
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(musicApplicationChanged(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(musicApplicationChanged(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        music.visibilityChanged = { [weak self] _ in
            self?.island.requestedPane = nil
            self?.island.showingAirPlay = false
            self?.applyVisibility()
        }
        music.playbackActivityChanged = { [weak self] _ in
            guard let self else { return }
            self.island.showingAirPlay = false
            self.resize(self.island.expanded, animate: false)
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            distributed.addObserver(self, selector: #selector(playerInfoChanged(_:)), name: Notification.Name(name), object: nil)
        }
        applyVisibility()
    }
    func resize(_ expanded: Bool, animate: Bool = true) {
        guard panel != nil else { return }
        if !expanded { swipeTracker.reset() }
        let s = screen
        island.safeTop = s.safeAreaInsets.top
        let notchWidth = (s.auxiliaryTopRightArea?.minX ?? s.frame.midX) - (s.auxiliaryTopLeftArea?.maxX ?? s.frame.midX)
        let compact = IslandLogic.panelFrame(screen: s.frame, topInset: island.safeTop, notchWidth: notchWidth, expanded: false)
        let host = IslandLogic.panelFrame(screen: s.frame, topInset: island.safeTop, notchWidth: notchWidth, expanded: true)
        island.collapsedWidth = music.hasCurrentTrack ? compact.width : (island.safeTop > 0 ? max(120, notchWidth) : 230)
        panel.ignoresMouseEvents = !expanded
        // Window geometry never animates. A single SwiftUI spring animates the visible mask.
        if panel.frame != host { panel.setFrame(host, display: true) }
        if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) { island.expanded = expanded }
        } else { island.expanded = expanded }
    }
    func trackPointer() {
        guard !hidden, panel != nil else { return }
        let s = screen
        let compact = CGRect(x: s.frame.midX - island.collapsedWidth / 2,
                             y: panel.frame.maxY - (island.safeTop > 0 ? island.safeTop : 40),
                             width: island.collapsedWidth, height: island.safeTop > 0 ? island.safeTop : 40)
        if let entered = hoverTracker.update(pointer: NSEvent.mouseLocation, collapsed: compact, expanded: panel.frame, isExpanded: island.expanded) {
            island.hover(entered)
        }
    }
    func handleIslandScroll(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, island.expanded, island.panelVisible,
              !island.showingAirPlay else {
            swipeTracker.reset()
            return event
        }
        // Only direct, phase-bearing trackpad scrolling changes pages. Mouse
        // wheels, vertical scrolling, and inertia never trigger extra switches.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return event }
        let phase: IslandSwipeTracker.Phase
        if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.changed) { phase = .changed }
        else { return event }
        let wasClaimed = swipeTracker.claimed
        let naturalSign = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
        let direction = swipeTracker.update(x: event.scrollingDeltaX * naturalSign,
                                            y: event.scrollingDeltaY, phase: phase)
        if let direction {
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.20
            withAnimation(.easeOut(duration: duration)) {
                island.requestedPane = direction == .left ? .music : .stats
            }
        }
        return wasClaimed || swipeTracker.claimed || direction != nil ? nil : event
    }
    @objc func toggleVisibility() {
        visibility.toggleManualVisibility()
        applyVisibility()
    }
    @objc func musicApplicationChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              MediaSource.allCases.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        music.refreshPlayers(excludingPID: notification.name == NSWorkspace.didTerminateApplicationNotification ? app.processIdentifier : nil)
    }
    @objc func playerInfoChanged(_ notification: Notification) {
        guard let state = notification.userInfo?["Player State"] as? String else { return }
        let source: MediaSource = notification.name.rawValue.hasPrefix("com.spotify") ? .spotify : .appleMusic
        music.playerNotification(source: source, playing: state.lowercased() == "playing")
    }
    func applyVisibility() {
        guard panel != nil else { return }
        if visibility.isVisible {
            island.panelVisible = true
            if !panel.isVisible { resize(island.pinned, animate: false) }
            music.visualizer.setVisible(!island.expanded && music.playing)
            pointerTimer?.fireDate = Date()
            panel.orderFrontRegardless()
        } else {
            island.panelVisible = false
            island.collapseWork?.cancel()
            island.showingAirPlay = false
            hoverTracker = HoverTracker()
            pointerTimer?.fireDate = .distantFuture
            stats.setSamplingEnabled(false)
            music.visualizer.setVisible(false)
            resize(false, animate: false)
            panel.orderOut(nil)
        }
    }
    @objc func togglePin() {
        island.togglePin()
        UserDefaults.standard.set(island.pinned, forKey: "keepExpanded")
        if !island.pinned { resize(false) }
    }
    @objc func openMusic() { music.openMusic() }
    @objc func toggleAudioBars() { music.visualizer.toggle() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        for entry in menu.items where entry.action == #selector(toggleVisibility) || entry.action == #selector(togglePin) {
            entry.isEnabled = true
        }
        for entry in menu.items where entry.action == #selector(toggleAudioBars) {
            entry.state = music.visualizer.enabled ? .on : .off
            entry.toolTip = music.visualizer.status
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        stats.setSamplingEnabled(false)
    }
    @objc func displayChanged() { resize(island.expanded, animate: false) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
enum MusicIslandMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
