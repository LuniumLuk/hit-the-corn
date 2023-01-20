//
//  AudioViewModel.swift
//  HitTheCorn
//
//  Created by Ziyi Lu on 2022/12/31.
//

import Foundation
import AVFoundation
import SwiftUI

class AudioViewModel: NSObject, ObservableObject {
    
    // MARK: Public properties
    
    var isPlaying = false {
        willSet {
            objectWillChange.send()
        }
    }
    var isPlayerReady = false {
        willSet {
            objectWillChange.send()
        }
    }
    var playbackRate: Float = 1.0 {
        willSet {
            objectWillChange.send()
        }
        didSet {
            updateAudioPlaybackRate()
        }
    }
    // The pitch here are calculated as per semitones
    var playbackPitch: Float = 0.0 {
        willSet {
            objectWillChange.send()
        }
        didSet {
            updateAudioPlaybackPitch()
        }
    }
    var audioProgress: Double = 0.0 {
        willSet {
            objectWillChange.send()
        }
    }
    var audioMeterLevel: Float = 0.0 {
        willSet {
            objectWillChange.send()
        }
    }
    var audioPositionOffsetX: Float = 0.0 {
        willSet {
            objectWillChange.send()
        }
        didSet {
            updateAudioPosition()
        }
    }
    var audioPositionOffsetY: Float = 0.0 {
        willSet {
            objectWillChange.send()
        }
        didSet {
            updateAudioPosition()
        }
    }
    var audioPosition3D: AVAudio3DPoint = AVAudio3DPoint(x: 0, y: 0, z: 0) {
        willSet {
            objectWillChange.send()
        }
        didSet {
            updateAudioPosition3D()
        }
    }
    
    // MARK: Private properties
    
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let environment = AVAudioEnvironmentNode()
    private let reverb = AVAudioUnitReverb()
    private let timeEffect = AVAudioUnitTimePitch()
    
    private var displayLink: CADisplayLink?
    
    private var needsFileScheduled = true
    
    private var audioFile: AVAudioFile?
    private var audioSampleRate: Double = 0
    private var audioLengthSeconds: Double = 0
    
    private var seekFrame: AVAudioFramePosition = 0
    private var currentPosition: AVAudioFramePosition = 0
    private var audioSeekFrame: AVAudioFramePosition = 0
    private var audioLengthSamples: AVAudioFramePosition = 0
    
    private var currentFrame: AVAudioFramePosition {
        guard
            let lastRenderTime = player.lastRenderTime,
            let playerTime = player.playerTime(forNodeTime: lastRenderTime)
        else {
            return 0
        }
        
        return playerTime.sampleTime
    }
    
    // MARK: - Public
    
    init(_ fileName: String, withExtension ext: String) {
        super.init()
        
        setupAudio(fileName, ext)
        setupDisplayLink()
    }
    
    func playOrPause() {
        isPlaying.toggle()
        
        if player.isPlaying {
            displayLink?.isPaused = true
            disconnectVolumeTap()
            
            player.pause()
        } else {
            displayLink?.isPaused = false
            connectVolumeTap()
            
            if needsFileScheduled {
                scheduleAudioFile()
            }
            player.play()
        }
    }
    
    func skip(for sec: Double) {
        seek(to: sec)
    }
    
    // MARK: - Private
    
    private func setupAudio(_ fileName: String, _ ext: String) {
        do {
            let sourceFileURL = Bundle.main.url(forResource: fileName, withExtension: ext)!
            let sourceFile = try AVAudioFile(forReading: sourceFileURL)
            let format = sourceFile.processingFormat
            
            audioLengthSamples = sourceFile.length
            audioSampleRate = format.sampleRate
            audioLengthSeconds = Double(audioLengthSamples) / audioSampleRate
            
            audioFile = sourceFile
            
            configureEngine(with: format)
        } catch {
            fatalError("<AudioViewModel> Fail to open source audio file: \(error.localizedDescription)")
        }
    }
    
    // MARK: Configure Engine
    private func configureEngine(with format: AVAudioFormat) {
        engine.attach(player)
        // timeEffect used to configure audio pitch, rate
        engine.attach(timeEffect)
        // environment used to configure 3d audio effect
        engine.attach(environment)
        // reverb used to configure audio effect
        engine.attach(reverb)
        
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 70
        
        engine.connect(
            player,
            to: timeEffect,
            format: format)
        engine.connect(
            timeEffect,
            to: environment,
            format: format)
        engine.connect(
            environment,
            to: reverb,
            format: constructOutputConnectionFormatForEnvironment())
        engine.connect(
            reverb,
            to: engine.mainMixerNode,
            format: constructOutputConnectionFormatForEnvironment())
        
        engine.prepare()
        
        do {
            try engine.start()
            
            scheduleAudioFile()
            isPlayerReady = true
        } catch {
            print("<AudioViewModel> Fail to start the player: \(error.localizedDescription)")
        }
    }
    
    private func scheduleAudioFile() {
        guard
            let file = audioFile,
            needsFileScheduled
        else {
            return
        }
        
        needsFileScheduled = false
        seekFrame = 0
        
        player.scheduleFile(file, at: nil) {
            self.needsFileScheduled = true
        } // Completion Handler, called when the audio file is finished
    }
    
    private func constructOutputConnectionFormatForEnvironment() -> AVAudioFormat {
        let environmentOutputConnectionFormat: AVAudioFormat
        let numHardwareOutputChannels = engine.outputNode.outputFormat(forBus: 0).channelCount
        let hardwareSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        
        // if we're connected to multichannel hardware, create a compatible multichannel format for the environment node
        if numHardwareOutputChannels > 2 && numHardwareOutputChannels != 3 {
            
            // find an AudioChannelLayoutTag that the environment node knows how to render to
            // this is documented in AVAudioEnvironmentNode.h
            let environmentOutputLayoutTag: AudioChannelLayoutTag
            switch numHardwareOutputChannels {
            case 4:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_4
                
            case 5:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_5_0
                
            case 6:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_6_0
                
            case 7:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_7_0
                
            case 8:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_8
                
            default:
                // based on our logic, we shouldn't hit this case
                environmentOutputLayoutTag = kAudioChannelLayoutTag_Stereo
            }
            
            // using that layout tag, now construct a format
            let environmentOutputChannelLayout = AVAudioChannelLayout(layoutTag: environmentOutputLayoutTag)
            environmentOutputConnectionFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareSampleRate, channelLayout: environmentOutputChannelLayout!)
            // _multichannelOutputEnabled = true
        } else {
            // stereo rendering format, this is the common case
            environmentOutputConnectionFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareSampleRate, channels: 2)!
            // _multichannelOutputEnabled = false
        }
        return environmentOutputConnectionFormat
    }
    
    // MARK: Audio adjustments
    
    private func seek(to time: Double) {
        guard let audioFile = audioFile else {
            return
        }
        
        let offset = AVAudioFramePosition(time * audioSampleRate)
        seekFrame = currentPosition + offset
        seekFrame = max(seekFrame, 0)
        seekFrame = min(seekFrame, audioLengthSamples)
        currentPosition = seekFrame
        
        let wasPlaying = player.isPlaying
        player.stop() // call to clear previous settings
        
        if currentPosition < audioLengthSamples {
            updateDisplay()
            needsFileScheduled = false
            
            let frameCount = AVAudioFrameCount(audioLengthSamples - seekFrame)
            player.scheduleSegment(
                audioFile,
                startingFrame: seekFrame,
                frameCount: frameCount,
                at: nil
            ) {
                self.needsFileScheduled = true
            }
            
            if wasPlaying {
                player.play()
            }
        }
        
    }
    
    // MARK: Needed Functions
    
    private func updateAudioPlaybackRate() {
        timeEffect.rate = playbackRate
    }
    
    private func updateAudioPlaybackPitch() {
        timeEffect.pitch = 100 * playbackPitch
    }
    
    private func updateAudioPosition() {
        environment.listenerPosition = AVAudio3DPoint(x: audioPositionOffsetX, y: audioPositionOffsetY, z: 0.0)
    }
    
    private func updateAudioPosition3D() {
        environment.listenerPosition = audioPosition3D
    }
    
    // MARK: Audio metering
    
    private func scaledPower(power: Float) -> Float {
        // 1
        guard power.isFinite else {
            return 0.0
        }
        
        let minDb: Float = -80
        
        // 2
        if power < minDb {
            return 0.0
        } else if power >= 1.0 {
            return 1.0
        } else {
            // 3
            return (abs(minDb) - abs(power)) / abs(minDb)
        }
    }
    
    private func connectVolumeTap() {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format
        ) { buffer, _ in // request audio data and return AVAudioPCMBuffer and AVAudioTime
            // here buffer.frameLength is the actual bufferSize
            guard let channelData = buffer.floatChannelData else {
                return
            }
            // channelData is an array of pointers to each sample’s data
            
            let channelDataValue = channelData.pointee
            // an array of UnsafeMutablePointer<Float>
            let channelDataValueArray = stride(
                from: 0,
                to: Int(buffer.frameLength),
                by: buffer.stride)
                .map { channelDataValue[$0] } // map to create list object
            
            let rms = sqrt(channelDataValueArray.map {
                return $0 * $0
            }
            .reduce(0, +) / Float(buffer.frameLength))
            
            let avgPower = 20 * log10(rms)
            let meterLevel = self.scaledPower(power: avgPower)
            
            DispatchQueue.main.async {
                self.audioMeterLevel = self.isPlaying ? meterLevel : 0
            }
        }
        
    }
    
    private func disconnectVolumeTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
        audioMeterLevel = 0
    }
    
    // MARK: Display updates
    
    private func setupDisplayLink() {
        // A timer object sychronized with Display's refreshing rate
        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplay))
        // add to default run loop
        displayLink?.add(to: .current, forMode: .default)
        displayLink?.isPaused = true
    }
    
    @objc private func updateDisplay() {
        currentPosition = currentFrame + seekFrame
        currentPosition = max(currentPosition, 0)
        currentPosition = min(currentPosition, audioLengthSamples)
        
        if currentPosition >= audioLengthSamples {
            player.stop()
            
            seekFrame = 0
            currentPosition = 0
            
            isPlaying = false
            displayLink?.isPaused = true
            
            disconnectVolumeTap()
        }
        
        audioProgress = Double(currentPosition) / Double(audioLengthSamples)
    }
}
