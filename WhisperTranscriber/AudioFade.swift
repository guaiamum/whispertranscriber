import Foundation
import AppKit
import AudioToolbox
import CoreAudio
import AudioToolbox

class AudioFade {
    static let shared = AudioFade()
    private var originalVolume: Int?
    private var fadeTimer: Timer?

    private func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    func getCurrentVolume() -> Int? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = volumeAddress
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Int((volume * 100).rounded())
    }

    func setVolume(_ volume: Int) {
        guard let device = defaultOutputDevice() else { return }
        var address = volumeAddress
        var scalar = Float32(max(0, min(100, volume))) / 100
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
    }

    func fadeOut(duration: TimeInterval) {
        guard let currentVolume = getCurrentVolume() else { return }
        originalVolume = currentVolume

        let steps = 20
        let stepInterval = duration / Double(steps)
        let volumeDecrement = Double(currentVolume) / Double(steps)
        var currentStep = 0

        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            currentStep += 1
            if currentStep >= steps {
                self.setVolume(0)
                timer.invalidate()
            } else {
                let newVolume = Int(Double(currentVolume) - (Double(currentStep) * volumeDecrement))
                self.setVolume(newVolume)
            }
        }
    }

    func fadeIn(duration: TimeInterval) {
        guard let targetVolume = originalVolume else { return }

        let steps = 20
        let stepInterval = duration / Double(steps)
        let volumeIncrement = Double(targetVolume) / Double(steps)
        var currentStep = 0

        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            currentStep += 1
            if currentStep >= steps {
                self.setVolume(targetVolume)
                timer.invalidate()
            } else {
                let newVolume = Int(Double(currentStep) * volumeIncrement)
                self.setVolume(newVolume)
            }
        }
    }
}
