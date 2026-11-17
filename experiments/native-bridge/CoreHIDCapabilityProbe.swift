// Diagnostic only: creates no display association and sends no input reports.
// Use the production descriptor exported by `native-bridge hid-capability`.
import Foundation
import CoreHID

@main
struct CoreHIDCapabilityProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DeviceBridge.HIDProbe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Pass the hid-capability JSON file"])
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let input = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let encoded = input?["brightnessHIDDescriptorBase64"] as? String,
              let descriptor = Data(base64Encoded: encoded), !descriptor.isEmpty else {
            throw NSError(domain: "DeviceBridge.HIDProbe", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Missing production brightness descriptor"])
        }
        let properties = HIDVirtualDevice.Properties(
            descriptor: descriptor, vendorID: 0xffff, productID: 0xdb03,
            product: "DeviceBridge CoreHID Capability Probe",
            extraProperties: ["kUSBContainerID": UUID().uuidString as NSString])
        let device = HIDVirtualDevice(properties: properties)
        let result: [String: Any] = [
            "CoreHIDDeviceCreated": device != nil,
            "descriptorBytes": descriptor.count,
            "edidModified": false,
            "displayBindingVerified": false
        ]
        let output = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: output, as: UTF8.self))
        withExtendedLifetime(device) {} // Releasing the local device removes it.
    }
}
