import Foundation
import CommonCrypto

enum PasswordStore {
    private static let recordKey = "passwordRecord"
    private static let iterations: UInt32 = 200_000
    private static let saltLength = 16
    private static let hashLength = 32
    static let minimumLength = 4

    static var hasPassword: Bool {
        UserDefaults.standard.data(forKey: recordKey) != nil
    }

    static func setPassword(_ password: String) {
        var salt = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, &salt)
        let hash = derive(password, salt: salt)
        UserDefaults.standard.set(Data(salt + hash), forKey: recordKey)
    }

    static func verify(_ password: String) -> Bool {
        guard let record = UserDefaults.standard.data(forKey: recordKey),
              record.count == saltLength + hashLength else { return false }
        let salt = Array(record.prefix(saltLength))
        let stored = Array(record.suffix(hashLength))
        return constantTimeEquals(stored, derive(password, salt: salt))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: recordKey)
    }

    private static func derive(_ password: String, salt: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: hashLength)
        let passwordBytes = Array(password.utf8)
        passwordBytes.withUnsafeBufferPointer { passwordPtr in
            salt.withUnsafeBufferPointer { saltPtr in
                output.withUnsafeMutableBufferPointer { outputPtr in
                    _ = CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) },
                        passwordBytes.count,
                        saltPtr.baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        outputPtr.baseAddress,
                        hashLength
                    )
                }
            }
        }
        return output
    }

    private static func constantTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
