import SwiftUI

final class ChatterID {
    static let shared = ChatterID()
    private init() {}

    var creator = ""
    var expiration = Date(timeIntervalSince1970: 0.0)
    private var _id: String?
    var id: String? {
        get { Date() >= expiration ? nil : _id }
        set(newValue) { _id = newValue }
    }

    func open(errMsg: Binding<String>, showOk: Binding<Bool>) async {
        if expiration != Date(timeIntervalSince1970: 0.0) {
            // not first launch
            return
        }

        // search for chatterID
        let searchFor: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrDescription: "ChatterID",
            kSecReturnData: true,
            kSecReturnAttributes: true,
        ]

        var itemRef: AnyObject?
        let searchStatus = SecItemCopyMatching(searchFor as CFDictionary, &itemRef)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss '+'SSSS"

        // handle search results
        switch searchStatus {
        case errSecSuccess: // found keychain
            if let item = itemRef as? NSDictionary,
               let data = item[kSecValueData] as? Data,
               let dateStr = item[kSecAttrLabel] as? String,
               let idExp = df.date(from: dateStr),
               let idCreator = item[kSecAttrCreator] as? String
            {
                creator = idCreator
                if Date() >= idExp {
                    errMsg.wrappedValue = "ChatterID from last session expired. Will get a new one when you post."
                } else {
                    errMsg.wrappedValue = "ChatterID available from last session."
                    id = String(data: data, encoding: .utf8)
                    expiration = idExp
                }
                showOk.wrappedValue = true
            } else {
                errMsg.wrappedValue = "ChatterID found but invalid...deleting from KeyChain."
                await delete(errMsg)
            }

        case errSecItemNotFound: // add template
            // biometric check
            let accessControl = SecAccessControlCreateWithFlags(nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .userPresence,
                nil)!

            let item: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrDescription: "ChatterID",
                kSecAttrLabel: df.string(from: expiration),
                kSecAttrCreator: creator as CFString,
                kSecAttrAccessControl: accessControl // biometric check
            ]
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            if addStatus != 0 {
                errMsg.wrappedValue = "ChatterID.open add: \(String(describing: SecCopyErrorMessageString(addStatus, nil)!))"
            }

        // search error
        default:
            errMsg.wrappedValue = "ChatterID.open search: \(String(describing: SecCopyErrorMessageString(searchStatus, nil)!))"
        }
    }

    func save(errMsg: Binding<String>, showOk: Binding<Bool>) async {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss '+'SSSS"

        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrDescription: "ChatterID",
        ]

        let updates: [CFString: Any] = [
            kSecValueData: id?.data(using: .utf8) as Any,
            kSecAttrLabel: df.string(from: expiration),
            kSecAttrCreator: creator as CFString
        ]

        let updateStatus = SecItemUpdate(item as CFDictionary, updates as CFDictionary)
        if updateStatus != 0 {
            errMsg.wrappedValue = "\(String(describing: SecCopyErrorMessageString(updateStatus, nil)!))\nChatterID can be used to post, but won't persist across app launches."
        } else {
            showOk.wrappedValue = true
            errMsg.wrappedValue = "ChatterID saved"
        }
    }

    func delete(_ errMsg: Binding<String>) async {
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrDescription: "ChatterID",
        ]

        let delStatus = SecItemDelete(item as CFDictionary)
        if delStatus != 0 {
            errMsg.wrappedValue += "ChatterID.delete: \(String(describing: SecCopyErrorMessageString(delStatus, nil)!))"
        } else {
            errMsg.wrappedValue += "ChatterID: deleted!)"
        }
    }
}
