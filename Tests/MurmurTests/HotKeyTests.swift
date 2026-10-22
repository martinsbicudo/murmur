import AppKit
import Carbon.HIToolbox
import Testing
@testable import Murmur

struct HotKeyTests {
    @Test func defaultShortcutIsControlOptionCommandR() throws {
        let spec = try #require(HotKeySpec.parse(HotKeySpec.defaultValue))
        #expect(spec.keyCode == UInt32(kVK_ANSI_R))
        #expect(spec.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
        #expect(spec.modifierFlags == [.control, .option, .command])
        #expect(spec.display == "⌃⌥⌘R")
    }

    @Test func acceptsAliasesSpacesAndAnyCase() throws {
        let spec = try #require(HotKeySpec.parse(" Command + Shift + Alt + 5 "))
        #expect(spec.keyCode == UInt32(kVK_ANSI_5))
        #expect(spec.carbonModifiers == UInt32(cmdKey | shiftKey | optionKey))
        #expect(spec.display == "⌥⇧⌘5")
    }

    @Test func defaultMuteShortcutIsControlOptionCommandM() throws {
        let spec = try #require(HotKeySpec.parse(HotKeySpec.defaultMuteValue))
        #expect(spec.keyCode == UInt32(kVK_ANSI_M))
        #expect(spec.display == "⌃⌥⌘M")
        #expect(spec != HotKeySpec.parse(HotKeySpec.defaultValue))
    }

    @Test func eachShortcutOnlyAnswersItsOwnPress() {
        let recordPress = EventHotKeyID(signature: GlobalHotKey.signature, id: 1)
        let mutePress = EventHotKeyID(signature: GlobalHotKey.signature, id: 2)
        #expect(GlobalHotKey.matches(recordPress, id: 1))
        #expect(!GlobalHotKey.matches(recordPress, id: 2))
        #expect(GlobalHotKey.matches(mutePress, id: 2))
        #expect(!GlobalHotKey.matches(mutePress, id: 1))
    }

    @Test func ignoresAnotherAppsShortcutWithTheSameID() {
        #expect(!GlobalHotKey.matches(EventHotKeyID(signature: OSType(0x41424344), id: 1), id: 1))
    }

    @Test func unavailableShortcutNamesTheSettingToChange() throws {
        let spec = try #require(HotKeySpec.parse(HotKeySpec.defaultMuteValue))
        let error = HotKeyError(spec: spec, setting: "MUTE_HOTKEY", status: OSStatus(eventHotKeyExistsErr))
        #expect(error.errorDescription == "⌃⌥⌘M is already used by another app. Set a different MUTE_HOTKEY in Settings (.env).")
    }

    @Test(arguments: ["r", "shift+r", "ctrl+option+cmd+f13", "hyper+r", "ctrl+option+cmd+", ""])
    func rejectsShortcutsThatAreUnsafeOrUnknown(_ value: String) {
        #expect(HotKeySpec.parse(value) == nil)
    }
}
