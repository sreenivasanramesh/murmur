import Foundation
import IOKit

/// Queries macOS hardware and chassis properties via IOKit.
enum HardwareInfo {
    /// True if the machine is a portable Mac (MacBook, MacBook Pro, MacBook Air).
    static var isLaptop: Bool {
        // Portable Macs register an AppleSmartBattery / IOPMPowerSource service
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            IOObjectRelease(service)
            return true
        }
        let powerSource = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMPowerSource"))
        if powerSource != 0 {
            IOObjectRelease(powerSource)
            return true
        }
        return false
    }

    /// True if the MacBook lid is closed (clamshell mode with external display attached).
    static var isClamshellClosed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool else {
            return false
        }
        return prop
    }
}
