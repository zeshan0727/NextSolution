enum NextDroidVMConfiguration {
    static let directoryName = "NextDroid Android 11.utm"
    static let isoName = "BlissOS-Android11.iso"
    static let dataDiskName = "android-data.img"
    static let displayName = "NextDroid Android 11"
    static let expectedISOSize: UInt64 = 2_087_714_816
    static let expectedISOSHA256 = "9feb9482e6e5c41c52172a0d42a436ea808de1cfdd6b1e0187dc883b2df9085c"
    static let downloadURL = URL(string: "https://downloads.sourceforge.net/project/blissos-x86/Official/BlissOS14/OpenGApps/Generic/Bliss-v14.10.3-x86_64-OFFICIAL-opengapps-20241012.iso")!
    static let guestMemoryMiB = 2_048
    static let jitCacheMiB = 256

    static var virtualMachineURL: URL {
        UTMData.defaultStorageUrl.appendingPathComponent(directoryName, isDirectory: true)
    }

    static var dataDirectoryURL: URL {
        virtualMachineURL.appendingPathComponent("Data", isDirectory: true)
    }

    static var isoURL: URL {
        dataDirectoryURL.appendingPathComponent(isoName)
    }

    static var dataDiskURL: URL {
        dataDirectoryURL.appendingPathComponent(dataDiskName)
    }

    static var configURL: URL {
        virtualMachineURL.appendingPathComponent("config.plist")
    }

    /// Repairs the oversized Test 4 cache without replacing the downloaded ISO
    /// or the user's installed Android disk. UTM's TrollStore profile uses
    /// split-W^X JIT mappings, so each MiB of cache costs roughly two MiB of
    /// process address space. Respect any smaller value selected by the user.
    static func applySafeMemoryProfileIfNeeded() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: configURL.path) else { return }

        let data = try Data(contentsOf: configURL)
        guard var configuration = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
        var system = configuration["System"] as? [String: Any] else {
            return
        }

        var changed = false
        let currentMemory = (system["MemorySize"] as? NSNumber)?.intValue ?? guestMemoryMiB
        if currentMemory > guestMemoryMiB {
            system["MemorySize"] = guestMemoryMiB
            changed = true
        }

        let currentCache = (system["JITCacheSize"] as? NSNumber)?.intValue ?? 0
        if currentCache == 0 || currentCache > jitCacheMiB {
            system["JITCacheSize"] = jitCacheMiB
            changed = true
        }

        guard changed else { return }
        configuration["System"] = system
        let updatedData = try PropertyListSerialization.data(
            fromPropertyList: configuration,
            format: .xml,
            options: 0
        )
        try updatedData.write(to: configURL, options: .atomic)
    }

    static var propertyList: [String: Any] {
        [
            "Backend": "QEMU",
            "ConfigurationVersion": 4,
            "Display": [[
                "DownscalingFilter": "Linear",
                "DynamicResolution": false,
                "Hardware": "virtio-vga",
                "NativeResolution": false,
                "UpscalingFilter": "Nearest"
            ]],
            "Drive": [
                [
                    "Identifier": "android-data",
                    "ImageName": dataDiskName,
                    "ImageType": "Disk",
                    "Interface": "VirtIO",
                    "InterfaceVersion": 1,
                    "ReadOnly": false
                ],
                [
                    "Identifier": "android-installer",
                    "ImageName": isoName,
                    "ImageType": "CD",
                    "Interface": "IDE",
                    "InterfaceVersion": 1,
                    "ReadOnly": true
                ]
            ],
            "Information": [
                "Icon": "android",
                "IconCustom": false,
                "Name": displayName,
                "Notes": "Bliss OS 14.10.3 (Android 11) with OpenGApps and persistent storage.",
                "UUID": "E76B434D-3C88-42E7-9E7A-1A82FC876D31"
            ],
            "Input": [
                "MaximumUsbShare": 2,
                "UsbBusSupport": "3.0",
                "UsbSharing": true
            ],
            "Network": [[
                "Hardware": "virtio-net-pci",
                "IsolateFromHost": false,
                "MacAddress": "52:54:00:11:14:01",
                "Mode": "Emulated",
                "PortForward": []
            ]],
            "QEMU": [
                "AdditionalArguments": [],
                "BalloonDevice": false,
                "DebugLog": true,
                "Hypervisor": false,
                "PS2Controller": true,
                "RNGDevice": true,
                "RTCLocalTime": false,
                "TPMDevice": false,
                "TSO": false,
                "UEFIBoot": true
            ],
            "Serial": [],
            "Sharing": [
                "ClipboardSharing": false,
                "DirectoryShareMode": "None",
                "DirectoryShareReadOnly": false
            ],
            "Sound": [["Hardware": "AC97"]],
            "System": [
                "Architecture": "x86_64",
                "CPU": "default",
                "CPUCount": 2,
                "CPUFlagsAdd": [],
                "CPUFlagsRemove": [],
                "ForceMulticore": false,
                "JITCacheSize": jitCacheMiB,
                "MemorySize": guestMemoryMiB,
                "Target": "q35"
            ]
        ]
    }
}
