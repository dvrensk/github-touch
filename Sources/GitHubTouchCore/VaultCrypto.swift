import CryptoKit
import Foundation
import LocalAuthentication

public enum VaultError: Error {
    case corruptCiphertext
    case writeFailed
}

// Abstracts over the Secure Enclave key (production) and a software P256 key
// (tests, --test-plumbing) so the crypto is unit-testable without Touch ID.
public protocol AgreementPrivateKey {
    var x963PublicKey: Data { get }
    func sharedSecret(withEphemeralPub ephemeralPub: Data) throws -> SharedSecret
}

extension P256.KeyAgreement.PrivateKey: AgreementPrivateKey {
    public var x963PublicKey: Data { publicKey.x963Representation }
    public func sharedSecret(withEphemeralPub ephemeralPub: Data) throws -> SharedSecret {
        try sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: ephemeralPub))
    }
}

extension SecureEnclave.P256.KeyAgreement.PrivateKey: AgreementPrivateKey {
    public var x963PublicKey: Data { publicKey.x963Representation }
    public func sharedSecret(withEphemeralPub ephemeralPub: Data) throws -> SharedSecret {
        // Touch ID happens here, inside the SE key agreement.
        try sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: ephemeralPub))
    }
}

public enum VaultCrypto {
    static func symmetricKey(_ shared: SharedSecret, ephemeralPub: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPub,
            sharedInfo: Data("github-touch v1".utf8),
            outputByteCount: 32)
    }

    public static func seal(_ secret: String, recipientPub: Data) throws -> (ephemeralPub: Data, ciphertext: Data) {
        let recipient = try P256.KeyAgreement.PublicKey(x963Representation: recipientPub)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let ephemeralPub = ephemeral.publicKey.x963Representation
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let box = try AES.GCM.seal(Data(secret.utf8), using: symmetricKey(shared, ephemeralPub: ephemeralPub))
        return (ephemeralPub, box.combined!)
    }

    public static func unseal(ciphertext: Data, ephemeralPub: Data, using key: AgreementPrivateKey) throws -> String {
        let shared = try key.sharedSecret(withEphemeralPub: ephemeralPub)
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        let plain = try AES.GCM.open(box, using: symmetricKey(shared, ephemeralPub: ephemeralPub))
        guard let secret = String(data: plain, encoding: .utf8) else { throw VaultError.corruptCiphertext }
        return secret
    }
}

public enum SecureEnclaveVaultKey {
    public static func create(requireUserPresence: Bool = true) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        var acError: Unmanaged<CFError>?
        let flags: SecAccessControlCreateFlags = requireUserPresence
            ? [.privateKeyUsage, .userPresence] : [.privateKeyUsage]
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &acError) else {
            throw acError!.takeRetainedValue() as Error
        }
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
    }

    public static func load(blob: Data, reason: String,
                            context: LAContext = LAContext()) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        context.localizedReason = reason
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(
            dataRepresentation: blob, authenticationContext: context)
    }
}
