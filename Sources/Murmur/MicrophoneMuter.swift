import Foundation

protocol MicrophoneControl {
    func defaultInputUID() -> String?
    func isMuted(uid: String) -> Bool?
    func setMuted(_ muted: Bool, uid: String) throws
    func volume(uid: String) -> Float?
    func setVolume(_ volume: Float, uid: String) throws
}

enum MicrophoneMuteError: LocalizedError {
    case noInputDevice
    case unsupported

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone is selected in System Settings › Sound."
        case .unsupported: "This microphone can't be muted by other apps."
        }
    }
}

struct MuteRecord: Codable, Equatable {
    let deviceUID: String
    let wasMuted: Bool?
    let previousVolume: Float?
}

/// Mutes the Mac's default microphone for every app, and puts it back exactly as it was. What it
/// changed is saved first, so a crash while muted is undone at the next launch.
final class MicrophoneMuter {
    static let recordKey = "MicrophoneMuteRecord"

    private let control: MicrophoneControl
    private let defaults: UserDefaults

    init(control: MicrophoneControl, defaults: UserDefaults = .standard) {
        self.control = control
        self.defaults = defaults
    }

    var savedRecord: MuteRecord? {
        defaults.data(forKey: Self.recordKey).flatMap { try? JSONDecoder().decode(MuteRecord.self, from: $0) }
    }

    func mute() throws {
        guard savedRecord == nil else { return }
        guard let uid = control.defaultInputUID() else { throw MicrophoneMuteError.noInputDevice }
        if let wasMuted = control.isMuted(uid: uid) {
            try apply(MuteRecord(deviceUID: uid, wasMuted: wasMuted, previousVolume: nil)) {
                try control.setMuted(true, uid: uid)
            }
        } else if let volume = control.volume(uid: uid) {
            try apply(MuteRecord(deviceUID: uid, wasMuted: nil, previousVolume: volume)) {
                try control.setVolume(0, uid: uid)
            }
        } else {
            throw MicrophoneMuteError.unsupported
        }
    }

    func restore() {
        guard let record = savedRecord else { return }
        defaults.removeObject(forKey: Self.recordKey)
        do {
            if let wasMuted = record.wasMuted { try control.setMuted(wasMuted, uid: record.deviceUID) }
            if let volume = record.previousVolume { try control.setVolume(volume, uid: record.deviceUID) }
            Log.write("microphone restored")
        } catch {
            Log.write("couldn't restore the microphone: \(error)")
        }
    }

    private func apply(_ record: MuteRecord, change: () throws -> Void) throws {
        defaults.set(try JSONEncoder().encode(record), forKey: Self.recordKey)
        do {
            try change()
        } catch {
            defaults.removeObject(forKey: Self.recordKey)
            throw error
        }
    }
}
