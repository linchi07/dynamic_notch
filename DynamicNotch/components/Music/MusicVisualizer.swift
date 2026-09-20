//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan Goswami on 02/08/24.
//

import AppKit
import Cocoa
import SwiftUI

// MARK: - Spectrum Preset Configuration

struct SpectrumPreset {
    let speed: Double
    let minScale: CGFloat
    let maxScale: CGFloat
    let barWeights: [CGFloat]
    let frequencies: [Double]
    let harmonics: [Double]
    let phaseOffsets: [Double]

    static let defaultPreset = SpectrumPreset(
        speed: 1.0,
        minScale: 0.2,
        maxScale: 0.92,
        barWeights: [0.95, 1.0, 1.05, 1.0, 0.95, 0.9],
        frequencies: [2.5, 3.8, 5.2, 6.8, 8.6, 11.2],
        harmonics: [1.3, 2.1, 3.2, 4.1, 5.5, 7.3],
        phaseOffsets: [0.0, 1.1, 2.3, 3.6, 4.8, 5.9]
    )

    static let popPreset = SpectrumPreset(
        speed: 1.28,
        minScale: 0.22,
        maxScale: 0.94,
        barWeights: [0.9, 1.0, 1.15, 1.12, 1.05, 0.98],
        frequencies: [3.2, 4.6, 6.4, 8.2, 10.4, 13.0],
        harmonics: [1.6, 2.4, 3.8, 4.8, 6.2, 8.1],
        phaseOffsets: [0.0, 0.9, 2.1, 3.2, 4.4, 5.5]
    )

    static let jazzPreset = SpectrumPreset(
        speed: 0.72,
        minScale: 0.25,
        maxScale: 0.85,
        barWeights: [1.05, 1.1, 0.95, 0.85, 0.72, 0.62],
        frequencies: [1.8, 2.5, 3.4, 4.2, 5.0, 6.1],
        harmonics: [0.9, 1.4, 2.0, 2.7, 3.3, 4.0],
        phaseOffsets: [0.0, 1.5, 3.0, 4.2, 5.1, 0.8]
    )

    static let classicalPreset = SpectrumPreset(
        speed: 0.65,
        minScale: 0.18,
        maxScale: 0.88,
        barWeights: [0.88, 0.95, 1.05, 1.02, 0.98, 0.9],
        frequencies: [1.4, 2.2, 3.1, 4.0, 5.3, 6.8],
        harmonics: [0.7, 1.2, 1.8, 2.4, 3.2, 4.1],
        phaseOffsets: [0.0, 1.8, 3.5, 5.0, 0.6, 2.3]
    )

    static let electronicPreset = SpectrumPreset(
        speed: 1.45,
        minScale: 0.2,
        maxScale: 0.95,
        barWeights: [1.3, 1.22, 0.85, 0.9, 1.1, 1.25],
        frequencies: [4.0, 5.5, 7.0, 9.2, 12.0, 15.0],
        harmonics: [2.0, 3.0, 4.2, 5.6, 7.5, 9.5],
        phaseOffsets: [0.0, 0.7, 1.5, 2.8, 4.0, 5.2]
    )

    static let rockPreset = SpectrumPreset(
        speed: 1.35,
        minScale: 0.24,
        maxScale: 0.95,
        barWeights: [1.15, 1.18, 1.12, 1.1, 1.05, 1.0],
        frequencies: [3.6, 4.8, 6.2, 8.0, 10.2, 12.8],
        harmonics: [1.8, 2.6, 3.6, 4.9, 6.4, 8.2],
        phaseOffsets: [0.0, 1.0, 2.2, 3.4, 4.6, 5.8]
    )

    static let hipHopPreset = SpectrumPreset(
        speed: 1.1,
        minScale: 0.22,
        maxScale: 0.93,
        barWeights: [1.32, 1.25, 0.92, 0.95, 0.88, 0.82],
        frequencies: [2.8, 3.9, 5.4, 7.1, 8.9, 11.0],
        harmonics: [1.4, 2.1, 3.0, 4.2, 5.4, 6.9],
        phaseOffsets: [0.0, 1.2, 2.5, 3.8, 5.0, 0.4]
    )

    static let acousticPreset = SpectrumPreset(
        speed: 0.88,
        minScale: 0.2,
        maxScale: 0.86,
        barWeights: [0.85, 0.92, 1.08, 1.05, 0.95, 0.88],
        frequencies: [2.2, 3.2, 4.4, 5.8, 7.4, 9.5],
        harmonics: [1.1, 1.7, 2.5, 3.4, 4.5, 5.8],
        phaseOffsets: [0.0, 1.3, 2.7, 4.1, 5.3, 0.7]
    )

    static func preset(for genre: String) -> SpectrumPreset {
        let lower = genre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return defaultPreset }
        if lower.contains("jazz") || lower.contains("blues") || lower.contains("bossa") || lower.contains("soul") {
            return jazzPreset
        }
        if lower.contains("classical") || lower.contains("orchestr") || lower.contains("symphon") || lower.contains("soundtrack") || lower.contains("score") || lower.contains("opera") {
            return classicalPreset
        }
        if lower.contains("electronic") || lower.contains("edm") || lower.contains("dance") || lower.contains("house") || lower.contains("techno") || lower.contains("trance") || lower.contains("dubstep") {
            return electronicPreset
        }
        if lower.contains("rock") || lower.contains("metal") || lower.contains("punk") || lower.contains("alternative") || lower.contains("grunge") {
            return rockPreset
        }
        if lower.contains("hip-hop") || lower.contains("hip hop") || lower.contains("rap") || lower.contains("trap") || lower.contains("r&b") {
            return hipHopPreset
        }
        if lower.contains("folk") || lower.contains("acoustic") || lower.contains("country") || lower.contains("singer") {
            return acousticPreset
        }
        if lower.contains("pop") {
            return popPreset
        }
        return defaultPreset
    }
}

// MARK: - Audio Spectrum View Component

class AudioSpectrum: NSView {
    private static let BAR_COUNT = 6
    private static let UPDATE_INTERVAL: TimeInterval = 0.08

    private var barLayers: [CALayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var animationTimer: Timer?
    private var timeStep: Double = 0.0
    private var currentPreset: SpectrumPreset = .defaultPreset
    private var currentGenre: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    deinit {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func setupBars() {
        let barWidth: CGFloat = 1.6
        let barCount = Self.BAR_COUNT
        let spacing: CGFloat = 1.0
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let totalHeight: CGFloat = 12.0
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CALayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.cornerRadius = barWidth / 2
            barLayer.masksToBounds = true
            barLayer.allowsGroupOpacity = false

            barLayers.append(barLayer)
            barScales.append(0.2)
            barLayer.transform = CATransform3DMakeScale(1.0, 0.2, 1.0)
            layer?.addSublayer(barLayer)
        }
    }

    func setGenre(_ genre: String) {
        guard genre != currentGenre else { return }
        currentGenre = genre
        currentPreset = SpectrumPreset.preset(for: genre)
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: Self.UPDATE_INTERVAL, repeats: true) { [weak self] _ in
            self?.updateBars()
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func updateBars() {
        timeStep += Self.UPDATE_INTERVAL * currentPreset.speed
        let t = timeStep

        for i in 0 ..< Self.BAR_COUNT {
            let currentScale = barScales[i]
            let freq = currentPreset.frequencies[i]
            let harm = currentPreset.harmonics[i]
            let phase = currentPreset.phaseOffsets[i]
            let weight = currentPreset.barWeights[i]

            // Multi-frequency harmonic oscillator (Fourier simulation without random numbers)
            let wave1 = sin(freq * t + phase) * 0.28
            let wave2 = cos(harm * t + phase * 1.3) * 0.16
            let beat = sin(t * 1.8) * 0.08
            let rawScale = (0.54 + wave1 + wave2 + beat) * weight

            let targetScale = min(max(rawScale, currentPreset.minScale), currentPreset.maxScale)
            barScales[i] = targetScale

            let barLayer = barLayers[i]
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = Self.UPDATE_INTERVAL
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false

            barLayer.transform = CATransform3DMakeScale(1.0, targetScale, 1.0)
            barLayer.add(animation, forKey: "scaleY")
        }
    }

    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale: CGFloat = 0.2
            barScales[i] = targetScale

            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false

            barLayer.transform = CATransform3DMakeScale(1.0, targetScale, 1.0)
            barLayer.add(animation, forKey: "scaleY")
        }
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    var genre: String = ""

    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setGenre(genre)
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setGenre(genre)
        nsView.setPlaying(isPlaying)
    }

    static func dismantleNSView(_ nsView: AudioSpectrum, coordinator: ()) {
        nsView.setPlaying(false)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true), genre: "Pop")
        .frame(width: 16, height: 20)
        .padding()
}

