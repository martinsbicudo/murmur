import Foundation
import Testing
@testable import Murmur

private final class FakeMicrophone: MicrophoneControl {
    var uid: String? = "built-in"
    var muted: Bool?
    var level: Float?
    var failWrites = false

    init(muted: Bool? = nil, level: Float? = nil) {
        self.muted = muted
        self.level = level
    }

    func defaultInputUID() -> String? { uid }
    func isMuted(uid: String) -> Bool? { muted }
    func volume(uid: String) -> Float? { level }

    func setMuted(_ muted: Bool, uid: String) throws {
        if failWrites { throw CoreAudioError(status: -1) }
        self.muted = muted
    }

    func setVolume(_ volume: Float, uid: String) throws {
        if failWrites { throw CoreAudioError(status: -1) }
        level = volume
    }
}

struct MicrophoneMuterTests {
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "murmur-tests-\(UUID().uuidString)"))
    }

    @Test func mutesAndRestoresAMicThatSupportsMute() throws {
        let mic = FakeMicrophone(muted: false)
        let muter = MicrophoneMuter(control: mic, defaults: defaults)
        try muter.mute()
        #expect(mic.muted == true)
        muter.restore()
        #expect(mic.muted == false)
        #expect(muter.savedRecord == nil)
    }

    @Test func keepsAMicMutedIfItWasAlreadyMutedBefore() throws {
        let mic = FakeMicrophone(muted: true)
        let muter = MicrophoneMuter(control: mic, defaults: defaults)
        try muter.mute()
        muter.restore()
        #expect(mic.muted == true)
    }

    @Test func fallsBackToZeroVolumeAndRestoresTheExactLevel() throws {
        let mic = FakeMicrophone(level: 0.62)
        let muter = MicrophoneMuter(control: mic, defaults: defaults)
        try muter.mute()
        #expect(mic.level == 0)
        muter.restore()
        #expect(mic.level == 0.62)
    }

    @Test func mutingTwiceKeepsTheOriginalStateToRestore() throws {
        let mic = FakeMicrophone(level: 0.8)
        let muter = MicrophoneMuter(control: mic, defaults: defaults)
        try muter.mute()
        try muter.mute()
        muter.restore()
        #expect(mic.level == 0.8)
    }

    @Test func restoresAfterACrashOnTheNextLaunch() throws {
        let mic = FakeMicrophone(muted: false)
        try MicrophoneMuter(control: mic, defaults: defaults).mute()
        MicrophoneMuter(control: mic, defaults: defaults).restore()
        #expect(mic.muted == false)
        #expect(MicrophoneMuter(control: mic, defaults: defaults).savedRecord == nil)
    }

    @Test func restoreWithNothingMutedChangesNothing() {
        let mic = FakeMicrophone(muted: true, level: 0.5)
        MicrophoneMuter(control: mic, defaults: defaults).restore()
        #expect(mic.muted == true)
        #expect(mic.level == 0.5)
    }

    @Test func micThatCantBeMutedIsReported() {
        let muter = MicrophoneMuter(control: FakeMicrophone(), defaults: defaults)
        #expect(throws: MicrophoneMuteError.unsupported) { try muter.mute() }
        #expect(muter.savedRecord == nil)
    }

    @Test func noMicrophoneIsReported() {
        let mic = FakeMicrophone(muted: false)
        mic.uid = nil
        #expect(throws: MicrophoneMuteError.noInputDevice) { try MicrophoneMuter(control: mic, defaults: defaults).mute() }
    }

    @Test func failedMuteLeavesNothingToRestore() {
        let mic = FakeMicrophone(muted: false)
        mic.failWrites = true
        let muter = MicrophoneMuter(control: mic, defaults: defaults)
        #expect(throws: CoreAudioError.self) { try muter.mute() }
        #expect(muter.savedRecord == nil)
        #expect(mic.muted == false)
    }
}
