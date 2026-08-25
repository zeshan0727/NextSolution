enum NextDroidVMConfiguration {
    static let directoryName = "NextDroid Android 11.utm"
    static let isoName = "BlissOS-Android11.iso"
    static let dataDiskName = "android-data.img"
    static let displayName = "NextDroid Android 11"
    static let expectedISOSize: UInt64 = 2_087_714_816
    static let expectedISOSHA256 = "9feb9482e6e5c41c52172a0d42a436ea808de1cfdd6b1e0187dc883b2df9085c"
    static let downloadURL = URL(string: "https://downloads.sourceforge.net/project/blissos-x86/Official/BlissOS14/OpenGApps/Generic/Bliss-v14.10.3-x86_64-OFFICIAL-opengapps-20241012.iso")!

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
                "JITCacheSize": 1024,
                "MemorySize": 2048,
                "Target": "q35"
            ]
        ]
    }
}
