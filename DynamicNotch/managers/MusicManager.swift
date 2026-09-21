//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables: [MediaControllerType: Set<AnyCancellable>] = [:]
    private var debounceIdleTask: Task<Void, Never>?

    // The system media adapter is attempted directly. A failed capability
    // probe must not silently disable Universal for Safari and other players.
    public private(set) var isNowPlayingDeprecated: Bool = false

    // Multi-controller management
    private var controllers: [MediaControllerType: any MediaControllerProtocol] = [:]
    private var sessionStates: [MediaControllerType: PlaybackState] = [:]

    // Available and selected sessions
    @Published var availableSessions: [MediaSession] = []
    @Published var selectedSessionType: MediaControllerType = .nowPlaying

    // Active controller computed property
    var activeController: (any MediaControllerProtocol)? {
        if selectedSessionType == .qqMusic || selectedSessionType == .neteaseMusic {
            return controllers[.nowPlaying]
        }
        return controllers[selectedSessionType] ?? controllers.values.first
    }

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false
    @Published var currentGenre: String = ""

    private var artworkData: Data? = nil

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setupControllersFromPreferences()
            }
            .store(in: &cancellables)

        // Listen for app termination to refresh sessions
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshAllSessions()
                }
            }
            .store(in: &cancellables)

        Task { @MainActor in
            self.setupControllersFromPreferences()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.values.forEach { subs in subs.forEach { $0.cancel() } }
        controllerCancellables.removeAll()
        controllers.removeAll()
        sessionStates.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()
    }

    // MARK: - Setup & Controller Management
    @MainActor
    func setupControllersFromPreferences() {
        if !UserDefaults.standard.bool(forKey: "didEnableUniversalPlaybackV2") {
            var migrated = Defaults[.enabledMediaControllers]
            if !migrated.contains(.nowPlaying) {
                migrated.insert(.nowPlaying, at: 0)
                Defaults[.enabledMediaControllers] = migrated
            }
            UserDefaults.standard.set(true, forKey: "didEnableUniversalPlaybackV2")
        }
        let selectedTypes = Defaults[.enabledMediaControllers]
        let needsUniversalBackend = selectedTypes.contains(.qqMusic) || selectedTypes.contains(.neteaseMusic)
        let enabledTypes = needsUniversalBackend
            ? Array(Set(selectedTypes).union([.nowPlaying]))
            : selectedTypes

        // 1. Remove controllers that are no longer enabled
        for (type, _) in controllers where !enabledTypes.contains(type) {
            controllerCancellables[type]?.forEach { $0.cancel() }
            controllerCancellables.removeValue(forKey: type)
            controllers.removeValue(forKey: type)
            sessionStates.removeValue(forKey: type)
        }

        // 2. Instantiate and observe new controllers
        for type in enabledTypes where type != .qqMusic && type != .neteaseMusic {
            if controllers[type] == nil {
                if let controller = instantiateController(for: type) {
                    controllers[type] = controller
                    var subs = Set<AnyCancellable>()
                    controller.playbackStatePublisher
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] state in
                            self?.handleStateUpdate(from: type, state: state)
                        }
                        .store(in: &subs)
                    controllerCancellables[type] = subs
                }
            }
        }

        refreshAllSessions()
        forceUpdate()
    }

    private func instantiateController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        switch type {
        case .nowPlaying:
            return NowPlayingController()
        case .appleMusic:
            return AppleMusicController()
        case .spotify:
            return SpotifyController()
        case .youtubeMusic:
            return YouTubeMusicController()
        case .qqMusic:
            return QQMusicController()
        case .neteaseMusic:
            return NetEaseMusicController()
        }
    }

    @MainActor
    private func handleStateUpdate(from type: MediaControllerType, state: PlaybackState) {
        sessionStates[type] = state
        refreshAllSessions(lastUpdatedType: type)
    }

    @MainActor
    func refreshAllSessions(lastUpdatedType: MediaControllerType? = nil) {
        var sessions: [MediaSession] = []

        // 1. Collect dedicated music app sessions
        let dedicatedTypes: [MediaControllerType] = [.appleMusic, .spotify, .youtubeMusic]
        var dedicatedBundleIDs: Set<String> = []

        for type in dedicatedTypes {
            guard let controller = controllers[type], controller.isActive() else { continue }
            if let state = sessionStates[type] {
                let hasTrack = !state.title.isEmpty && state.title != "I'm Handsome"
                if state.isPlaying || hasTrack {
                    let session = MediaSession(
                        type: type,
                        bundleIdentifier: state.bundleIdentifier,
                        title: state.title,
                        artist: state.artist,
                        album: state.album,
                        artwork: state.artwork,
                        isPlaying: state.isPlaying,
                        currentTime: state.currentTime,
                        duration: state.duration,
                        playbackRate: state.playbackRate,
                        isShuffled: state.isShuffled,
                        repeatMode: state.repeatMode,
                        volume: state.volume,
                        isFavorite: state.isFavorite,
                        genre: state.genre,
                        lastUpdated: state.lastUpdated
                    )
                    sessions.append(session)
                    if !state.bundleIdentifier.isEmpty {
                        dedicatedBundleIDs.insert(state.bundleIdentifier)
                    }
                }
            }
        }

        // 2. Now Playing session with dynamic app filtering and deduplication
        if let npController = controllers[.nowPlaying], npController.isActive(),
           let npState = sessionStates[.nowPlaying] {
            let hasTrack = !npState.title.isEmpty && npState.title != "I'm Handsome"
            if npState.isPlaying || hasTrack {
                let isDuplicateBundle = dedicatedBundleIDs.contains(npState.bundleIdentifier)

                // Universal owns every app without an active dedicated source.
                let sourceType: MediaControllerType
                switch npState.bundleIdentifier {
                case "com.netease.163music" where Defaults[.enabledMediaControllers].contains(.neteaseMusic):
                    sourceType = .neteaseMusic
                case "com.tencent.QQMusicMac" where Defaults[.enabledMediaControllers].contains(.qqMusic):
                    sourceType = .qqMusic
                default:
                    sourceType = .nowPlaying
                }

                if !isDuplicateBundle &&
                    (sourceType != .nowPlaying || Defaults[.enabledMediaControllers].contains(.nowPlaying)) {
                    let session = MediaSession(
                        type: sourceType,
                        bundleIdentifier: npState.bundleIdentifier,
                        title: npState.title,
                        artist: npState.artist,
                        album: npState.album,
                        artwork: npState.artwork,
                        isPlaying: npState.isPlaying,
                        currentTime: npState.currentTime,
                        duration: npState.duration,
                        playbackRate: npState.playbackRate,
                        isShuffled: npState.isShuffled,
                        repeatMode: npState.repeatMode,
                        volume: npState.volume,
                        isFavorite: npState.isFavorite,
                        genre: npState.genre,
                        lastUpdated: npState.lastUpdated
                    )
                    sessions.append(session)
                }
            }
        }

        // 3. Sort: playing first
        sessions.sort { s1, s2 in
            if s1.isPlaying != s2.isPlaying {
                return s1.isPlaying && !s2.isPlaying
            }
            return s1.type.rawValue < s2.type.rawValue
        }

        self.availableSessions = sessions

        if sessions.isEmpty {
            if self.isPlaying {
                withAnimation(.smooth) {
                    self.isPlaying = false
                    self.updateIdleState(state: false)
                }
            }
            LiveActivityManager.shared.end("music.playback")
            return
        }

        // 4. Update selected session
        let sessionExists = sessions.contains { $0.type == selectedSessionType }

        // If another session started playing while current is paused, switch to it
        if let lastUpdatedType = lastUpdatedType,
           let updatedState = sessionStates[lastUpdatedType],
           updatedState.isPlaying,
           lastUpdatedType != selectedSessionType {
            let currentIsPlaying = sessionStates[selectedSessionType]?.isPlaying ?? false
            if !currentIsPlaying {
                selectedSessionType = lastUpdatedType
            }
        } else if !sessionExists {
            if let firstPlaying = sessions.first(where: { $0.isPlaying }) {
                selectedSessionType = firstPlaying.type
            } else if let firstSession = sessions.first {
                selectedSessionType = firstSession.type
            } else {
                selectedSessionType = Defaults[.enabledMediaControllers].first ?? .nowPlaying
            }
        }

        // 5. Sync active session properties
        syncActiveSessionProperties()
    }

    func selectSession(type: MediaControllerType) {
        guard selectedSessionType != type else { return }
        selectedSessionType = type
        syncActiveSessionProperties()
    }

    @MainActor
    private func syncActiveSessionProperties() {
        let stateType: MediaControllerType = (selectedSessionType == .qqMusic || selectedSessionType == .neteaseMusic)
            ? .nowPlaying : selectedSessionType
        if let state = sessionStates[stateType] {
            updateFromPlaybackState(state)
        } else if let controller = controllers[selectedSessionType] {
            Task {
                await controller.updatePlaybackInfo()
            }
        }
        self.canFavoriteTrack = activeController?.supportsFavorite ?? false
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek(title: state.title, artist: state.artist)
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            var latestArtworkImage: NSImage? = nil

            if artworkChanged, let artwork = state.artwork {
                if let decoded = NSImage(data: artwork) {
                    self.usingAppIconForArtwork = false
                    latestArtworkImage = decoded
                    self.updateAlbumArt(newAlbumArt: decoded)
                } else {
                    self.updateArtwork(artwork)
                }
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    latestArtworkImage = appIconImage
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork

            if artworkChanged || state.artwork == nil {
                // Update last artwork change values
                self.lastArtworkTitle = state.title
                self.lastArtworkArtist = state.artist
                self.lastArtworkAlbum = state.album
                self.lastArtworkBundleIdentifier = state.bundleIdentifier
            }

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek(title: state.title, artist: state.artist, customImage: latestArtworkImage)
            }

            // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        if state.genre != self.currentGenre {
            self.currentGenre = state.genre
        }
        
        self.timestampDate = state.lastUpdated
        updateLiveActivity()
    }

    @MainActor
    func refreshLiveActivity() {
        updateLiveActivity()
    }

    @MainActor
    private func updateLiveActivity() {
        guard BoringViewCoordinator.shared.musicLiveActivityEnabled,
              isPlaying || !isPlayerIdle,
              !songTitle.isEmpty,
              songTitle != "I'm Handsome" else {
            LiveActivityManager.shared.end("music.playback")
            return
        }
        let tint = Defaults[.coloredSpectrogram]
            ? Color(nsColor: avgColor).ensureMinimumBrightness(factor: 0.6)
            : Color.gray
        let albumItem = NotchActivityItem(
            visual: .customImage(image: albumArt),
            accessibilityLabel: songTitle,
            heroId: NotchHeroIdentifier.MUSIC_ARTWORK.rawValue
        )
        LiveActivityManager.shared.register(NotchLiveActivity(
            id: "music.playback",
            leading: albumItem,
            trailing: NotchActivityItem(
                visual: Defaults[.useMusicVisualizer] ? .audioVisualizer : .system(name: "waveform"),
                tintColor: tint,
                accessibilityLabel: isPlaying ? "Playing" : "Paused"
            ),
            minimalPresentation: albumItem
        ))
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            self.isFavoriteTrack = loved
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        guard Defaults[.enableLyrics], !title.isEmpty else {
            DispatchQueue.main.async {
                self.isFetchingLyrics = false
                self.currentLyrics = ""
            }
            return
        }

        // Prefer native Apple Music lyrics when available
        if let bundleIdentifier = bundleIdentifier, bundleIdentifier.contains("com.apple.Music") {
            Task { @MainActor in
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                guard !runningApps.isEmpty else {
                    await self.fetchLyricsFromWeb(title: title, artist: artist)
                    return
                }

                self.isFetchingLyrics = true
                self.currentLyrics = ""
                do {
                    let script = """
                    tell application \"Music\"
                        if it is running then
                            if player state is playing or player state is paused then
                                try
                                    set l to lyrics of current track
                                    if l is missing value then
                                        return \"\"
                                    else
                                        return l
                                    end if
                                on error
                                    return \"\"
                                end try
                            else
                                return \"\"
                            end if
                        else
                            return \"\"
                        end if
                    end tell
                    """
                    if let result = try await AppleScriptHelper.execute(script), let lyricsString = result.stringValue, !lyricsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.currentLyrics = lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.isFetchingLyrics = false
                        self.syncedLyrics = []
                        return
                    }
                } catch {
                    // fall through to web lookup
                }
                await self.fetchLyricsFromWeb(title: title, artist: artist)
            }
        } else {
            Task { @MainActor in
                self.isFetchingLyrics = true
                self.currentLyrics = ""
                await self.fetchLyricsFromWeb(title: title, artist: artist)
            }
        }
    }

    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }

    @MainActor
    private func fetchLyricsFromWeb(title: String, artist: String) async {
        let cleanTitle = normalizedQuery(title)
        let cleanArtist = normalizedQuery(artist)
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            return
        }

        // LRCLIB simple search (no auth): https://lrclib.net/api/search?track_name=...&artist_name=...
        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        guard let url = URL(string: urlString) else {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                self.currentLyrics = ""
                self.isFetchingLyrics = false
                return
            }
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first {
                // Prefer plain lyrics (syncedLyrics may also be present)
                let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let synced = (first["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolved = plain.isEmpty ? synced : plain
                self.currentLyrics = resolved
                self.isFetchingLyrics = false
                if !synced.isEmpty {
                    self.syncedLyrics = self.parseLRC(synced)
                } else {
                    self.syncedLyrics = []
                }
            } else {
                self.currentLyrics = ""
                self.isFetchingLyrics = false
                self.syncedLyrics = []
            }
        } catch {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            self.syncedLyrics = []
        }
    }

    // MARK: - Synced lyrics helpers
    private func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        lrc.split(separator: "\n").forEach { lineSub in
            let line = String(lineSub)
            // Match [mm:ss.xx] or [m:ss]
            let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,2}))?\]"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsLine = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let csRange = match.range(at: 3)
                let centiStr = csRange.location != NSNotFound ? nsLine.substring(with: csRange) : "0"
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                let centis = Double(centiStr) ?? 0
                let time = minutes * 60 + seconds + centis / 100.0
                let textStart = match.range.location + match.range.length
                let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    result.append((time, text))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    func lyricLine(at elapsed: Double) -> String {
        guard !syncedLyrics.isEmpty else { return currentLyrics }
        // Binary search for last line with time <= elapsed
        var low = 0
        var high = syncedLyrics.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if syncedLyrics[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return syncedLyrics[idx].text
    }

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    @MainActor
    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { @MainActor [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
                self.updateLiveActivity()
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        }
        coordinator.updateActiveNotificationImage(newAlbumArt)
    }

    private static let MUSIC_ACTIVITY_ID = "music.playback"

    private func updateSneakPeek(title: String, artist: String, customImage: NSImage? = nil) {
        guard isPlaying && Defaults[.enableSneakPeek] else { return }
        let image = customImage ?? (usingAppIconForArtwork ? nil : self.albumArt)
        coordinator.postNotification(
            title: title,
            message: artist,
            customImage: image,
            iconName: "music.note",
            iconColor: .pink,
            iconBackground: Color.pink.opacity(0.18),
            category: .activityUpdate,
            activityId: Self.MUSIC_ACTIVITY_ID,
            duration: 3.0
        )
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        Task { [weak self] in
            guard let self = self else { return }
            for (_, controller) in self.controllers {
                if controller.isActive() {
                    if let youtubeController = controller as? YouTubeMusicController {
                        await youtubeController.pollPlaybackState()
                    } else {
                        await controller.updatePlaybackInfo()
                    }
                }
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
