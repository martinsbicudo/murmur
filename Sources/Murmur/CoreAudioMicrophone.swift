import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? { "Core Audio error \(status)." }
}

struct CoreAudioMicrophone: MicrophoneControl {
    func defaultInputUID() -> String? {
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        var uidAddress = Self.address(kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal)
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    func isMuted(uid: String) -> Bool? {
        let value: UInt32? = settableValue(kAudioDevicePropertyMute, uid: uid)
        return value.map { $0 != 0 }
    }

    func setMuted(_ muted: Bool, uid: String) throws {
        try set(UInt32(muted ? 1 : 0), kAudioDevicePropertyMute, uid: uid)
    }

    func volume(uid: String) -> Float? {
        settableValue(kAudioDevicePropertyVolumeScalar, uid: uid)
    }

    func setVolume(_ volume: Float, uid: String) throws {
        try set(Float32(volume), kAudioDevicePropertyVolumeScalar, uid: uid)
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func device(uid: String) -> AudioDeviceID? {
        var address = Self.address(kAudioHardwarePropertyTranslateUIDToDevice, scope: kAudioObjectPropertyScopeGlobal)
        var cfUID = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), qualifier, &size, &device
            )
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private func settableValue<Value: Numeric & BitwiseCopyable>(_ selector: AudioObjectPropertySelector, uid: String) -> Value? {
        guard let device = device(uid: uid) else { return nil }
        var address = Self.address(selector, scope: kAudioObjectPropertyScopeInput)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return nil }
        var value: Value = 0
        var size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func set<Value: BitwiseCopyable>(_ value: Value, _ selector: AudioObjectPropertySelector, uid: String) throws {
        guard let device = device(uid: uid) else { throw MicrophoneMuteError.noInputDevice }
        var address = Self.address(selector, scope: kAudioObjectPropertyScopeInput)
        var value = value
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value)
        guard status == noErr else { throw CoreAudioError(status: status) }
    }
}
