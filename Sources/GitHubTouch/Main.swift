import Foundation
import GitHubTouchCore

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--test-plumbing") {
            testPlumbing()
        }
        GitHubTouchApp.main()
    }

    // Round-trips a secret through the real Secure Enclave (no Touch ID gate)
    // to prove the production code path works on this machine.
    static func testPlumbing() -> Never {
        do {
            let key = try SecureEnclaveVaultKey.create(requireUserPresence: false)
            let sealed = try VaultCrypto.seal("test-secret-🔑", recipientPub: key.x963PublicKey)
            let out = try VaultCrypto.unseal(
                ciphertext: sealed.ciphertext, ephemeralPub: sealed.ephemeralPub, using: key)
            print(out == "test-secret-🔑"
                  ? "OK: Secure Enclave round-trip succeeded"
                  : "FAIL: decrypted value mismatch")
            exit(out == "test-secret-🔑" ? 0 : 1)
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
