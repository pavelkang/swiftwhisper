import AudioToolbox
import Combine
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let deviceID: AudioDeviceID
}

@MainActor
final class AudioInputDeviceManager: ObservableObject {
  static let shared = AudioInputDeviceManager()

  @Published private(set) var devices: [AudioInputDevice] = []
  @Published private(set) var defaultDeviceName = "Unavailable"

  private init() {
    refresh()
  }

  func refresh() {
    devices = AudioInputDeviceDiscovery.inputDevices()
    defaultDeviceName = AudioInputDeviceDiscovery.defaultInputDeviceName() ?? "Unavailable"
  }
}

enum AudioInputDeviceDiscovery {
  static func inputDevices() -> [AudioInputDevice] {
    allDeviceIDs()
      .filter(hasInputStreams)
      .compactMap { deviceID in
        guard let uid = stringProperty(
          deviceID,
          selector: kAudioDevicePropertyDeviceUID
        ), let name = stringProperty(
          deviceID,
          selector: kAudioObjectPropertyName
        ) else { return nil }
        return AudioInputDevice(id: uid, name: name, deviceID: deviceID)
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  static func defaultInputDeviceName() -> String? {
    guard let deviceID = defaultInputDeviceID() else { return nil }
    return stringProperty(deviceID, selector: kAudioObjectPropertyName)
  }

  static func applySelectedDevice(to audioUnit: AudioUnit) throws {
    let selectedID = AudioInputSelection.selectedID
    guard selectedID != AudioInputSelection.systemDefaultID else { return }
    guard var deviceID = inputDevices().first(where: { $0.id == selectedID })?.deviceID else {
      return
    }

    let status = AudioUnitSetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &deviceID,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard status == noErr else {
      throw AudioCaptureError.deviceConfigurationFailed(status)
    }
  }

  private static func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize
    ) == noErr else { return [] }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var devices = Array(repeating: AudioDeviceID(0), count: count)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize,
      &devices
    ) == noErr else { return [] }
    return devices
  }

  private static func defaultInputDeviceID() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize,
      &deviceID
    ) == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
  }

  private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    return AudioObjectGetPropertyDataSize(
      deviceID,
      &address,
      0,
      nil,
      &dataSize
    ) == noErr && dataSize >= UInt32(MemoryLayout<AudioStreamID>.size)
  }

  private static func stringProperty(
    _ deviceID: AudioDeviceID,
    selector: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &dataSize,
      &value
    ) == noErr, let value else { return nil }
    return value.takeUnretainedValue() as String
  }
}
