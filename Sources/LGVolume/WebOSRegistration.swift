import Foundation

enum WebOSRegistration {
    static func payload(forcePairing: Bool) -> [String: Any] {
        let permissions = [
            "CONTROL_AUDIO",
            "CONTROL_DISPLAY",
            "CONTROL_INPUT_TV",
            "LAUNCH",
            "READ_INPUT_DEVICE_LIST",
            "READ_RUNNING_APPS"
        ]

        return [
            "forcePairing": forcePairing,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "signed": [
                    "created": "20260523",
                    "appId": "local.codex.lgvolume",
                    "vendorId": "codex",
                    "localizedAppNames": ["": "LGVolume"],
                    "localizedVendorNames": ["": "Codex"],
                    "permissions": permissions,
                    "serial": "local-lgvolume"
                ],
                "permissions": permissions,
                "signatures": [["signatureVersion": 1, "signature": "LGVolume"]]
            ]
        ]
    }
}
