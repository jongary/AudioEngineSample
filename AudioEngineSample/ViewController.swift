//
//  ViewController.swift
//  AudioEngineSample
//
//  Created by Jon Gary on 11/20/20.
//

import UIKit
import AVFoundation
import Combine

class ViewController: UIViewController {

    var player: AudioFilePlayer!

    @IBOutlet var mainMixerNodeVolumeSlider: UISlider!

    @IBOutlet var eqNodeGlobalGainSlider: UISlider!

    @IBOutlet var timeLabel: UILabel!

    var timeSubscription: AnyCancellable?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        player = AudioFilePlayer()

        guard let sampleFileURL = Bundle.main.url(forResource: "shine a little light", withExtension: "mp3") else {
            fatalError("No audio file")
        }

        try! player.audioFile = AVAudioFile(forReading: sampleFileURL)

        timeSubscription = player.$playbackTime
            .sink { [weak self] (t) in
                self?.timeLabel.text = DateComponentsFormatter.durationFormatter.string(from: t)
            }

        updateUI()
    }


    @IBAction func playButtonAction(_ sender: Any) {
        try! player.play()
    }

    @IBAction func mixerVolumeAction(_ sender: Any) {
        player.volume = mainMixerNodeVolumeSlider.value
    }

    @IBAction func eqGainSliderAction(_ sender: Any) {
        player.globalGain = eqNodeGlobalGainSlider.value
    }

    func updateUI() {
        mainMixerNodeVolumeSlider.value = player.volume
        eqNodeGlobalGainSlider.value = player.globalGain
    }


}


fileprivate var _durationFormatter: DateComponentsFormatter? = nil

extension DateComponentsFormatter {

    /// Return a formatter for durations. They can be slow to build, so cache an instance.
    static var durationFormatter: DateComponentsFormatter {
        if let durationFormatter = _durationFormatter {
            return durationFormatter
        }

        let durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.minute, .second]
        durationFormatter.unitsStyle = .positional
        durationFormatter.zeroFormattingBehavior = .pad

        _durationFormatter = durationFormatter

        return durationFormatter
    }
}
