//
//  AudioFilePlayer.swift
//
//  Created by Jon Gary on 8/17/20.
//  Copyright © 2020 Jon Gary. All rights reserved.
//

import AVFoundation
import Combine

struct EQSetting {
    static let numberOfBands = 3

    let filterType: AVAudioUnitEQFilterType
    let frequency: Float
    let gain: Float
    let bandwidth: Float
    let bypass: Bool


    init(filterType: AVAudioUnitEQFilterType, frequency: Float, gain: Float, bandwidth: Float, bypass: Bool) {
        self.filterType = filterType
        self.frequency = frequency
        self.gain = gain
        self.bandwidth = bandwidth
        self.bypass = bypass
    }

    func applySettings(_ parameters: AVAudioUnitEQFilterParameters) {
        parameters.filterType = filterType

        parameters.gain = gain
        parameters.frequency = frequency
        parameters.bypass = bypass
        parameters.bandwidth = bandwidth

    }
}

struct EQSettings {
    let low: EQSetting
    let mid: EQSetting
    let high: EQSetting

    static var defaults: EQSettings {
        return EQSettings(
            low: EQSetting(filterType: .lowShelf, frequency: 200, gain: 0, bandwidth: 2, bypass: true),
            mid: EQSetting(filterType: .parametric, frequency: 1200, gain: 0, bandwidth: 2, bypass: true),
            high: EQSetting(filterType: .highShelf, frequency: 6000, gain: 0, bandwidth: 2, bypass: true)
        )
    }

    func applySettings(_ eq: AVAudioUnitEQ) {
        low.applySettings(eq.bands[0])
        mid.applySettings(eq.bands[1])
        high.applySettings(eq.bands[2])
    }
}

/// Helper class to build the audio graph.
class AudioGraph {
    fileprivate var engine: AVAudioEngine
    fileprivate var playerNode: AVAudioPlayerNode
    fileprivate var eqNode: AVAudioUnitEQ

    func apply(settings: EQSettings) {
        settings.applySettings(eqNode)
    }

    convenience init() {
        let eq = AVAudioUnitEQ(numberOfBands: EQSetting.numberOfBands)
        self.init(engine: AVAudioEngine(), playerNode: AVAudioPlayerNode(), eq: eq)
    }

    fileprivate func configureAudioEngine() {
        self.engine.attach(self.playerNode)
        self.engine.attach(self.eqNode)
        self.engine.connect(self.playerNode, to: self.eqNode, format: nil)
        self.engine.connect(self.eqNode, to: self.engine.mainMixerNode, format: nil)

        self.engine.prepare()
    }

    required init(engine: AVAudioEngine, playerNode: AVAudioPlayerNode, eq: AVAudioUnitEQ) {
        self.engine = engine
        self.playerNode = playerNode
        self.eqNode = eq

        self.configureAudioEngine()
    }

    deinit {
        playerNode.stop()
        engine.stop()
    }
}

class AudioFilePlayer: NSObject, ObservableObject  {

    override init() {
        super.init()
        audioGraph.apply(settings: EQSettings.defaults)
    }

    var currentItemDuration: TimeInterval {
        guard let audioFile = audioFile else {
            return 0
        }
        return audioFile.durationInterval
    }

    var volume: Float = 1 {
        didSet {
            audioGraph.engine.mainMixerNode.volume = volume
        }
    }

    var globalGain: Float = 0 {
        didSet {
            audioGraph.eqNode.globalGain = globalGain
        }
    }

    var playerVolume: Float = 1 {
        didSet {
            audioGraph.playerNode.volume = playerVolume
        }
    }

    /// The audio file to play.
    var audioFile: AVAudioFile? = nil {
        didSet {
            playbackTime = 0
        }
    }

    var audioGraph = AudioGraph()
    var eqSettings = EQSettings.defaults {
        didSet {
            audioGraph.apply(settings: eqSettings)
        }
    }


    fileprivate var timer: Timer? = nil
    fileprivate var timeZero: TimeInterval = 0
    fileprivate var startTime: TimeInterval = 0

    enum Errors: Error {
        case noRenderTime
        case invalidRenderTime
    }

    @Published private (set) var isPlaying: Bool = false
    @Published private (set) var playbackTime: TimeInterval = 0
    @Published private (set) var playedToEnd: Bool = false

    func play(at t: TimeInterval = 0) throws {
        guard let audioFile = audioFile else { return }

        timer?.invalidate()

        // The player has to stop to seek.
        audioGraph.playerNode.stop()
        playedToEnd = false

        timeZero = t
        startTime = CACurrentMediaTime()

        let startingFrame = audioFile.framePosition(for: t)
        let frameCount = AVAudioFrameCount(audioFile.length - startingFrame)

        audioGraph.playerNode.scheduleSegment(audioFile,
                                              startingFrame: startingFrame,
                                              frameCount: frameCount,
                                              at: nil,
                                              completionCallbackType: .dataPlayedBack)
        { [weak self] (callbackType) in
            guard let self = self else { return }
            if (self.isPlaying && callbackType == .dataPlayedBack) {
                self.audioGraph.playerNode.pause()
                self.playedToEnd = true
            }
        }

        if !audioGraph.engine.isRunning {
            try audioGraph.engine.start()
        }
        isPlaying = true
        self.playedToEnd = false

        audioGraph.playerNode.play()
        timer = playbackTimer()

    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false

        timer?.invalidate()
        audioGraph.playerNode.pause()
    }

    fileprivate func playbackTimer() -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { [weak self] (_) in
            guard let self = self else { return }

            let t = (CACurrentMediaTime() - self.startTime) + self.timeZero
            self.playbackTime = t
        })

        timer.tolerance = 0.01
        return timer
    }

    fileprivate func renderTime() -> Result<TimeInterval, Error> {
        guard let renderTime = audioGraph.playerNode.lastRenderTime else {
            return .failure(Errors.noRenderTime)
        }
        guard let nodeTime = audioGraph.playerNode.playerTime(forNodeTime: renderTime) else {
            return .failure(Errors.noRenderTime)
        }

        guard nodeTime.isSampleTimeValid else {
            return .failure(Errors.noRenderTime)
        }
        return .success(Double(nodeTime.sampleTime) / nodeTime.sampleRate)
    }
}

extension AVAudioFile {

    var durationInterval: TimeInterval {
        return Double(self.length) / self.processingFormat.sampleRate
    }

    func framePosition(for timeInterval: TimeInterval) -> AVAudioFramePosition {
        guard timeInterval >= 0 else {
            return 0
        }
        guard timeInterval < durationInterval else {
            return self.length
        }
        return AVAudioFramePosition(timeInterval * self.processingFormat.sampleRate)
    }

}

