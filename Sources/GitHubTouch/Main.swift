import Foundation
import GitHubTouchCore
import LocalAuthentication

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--test-plumbing") {
            testPlumbing()
        }
        if CommandLine.arguments.contains("--test-one-touch") {
            testOneTouch()
        }
        if CommandLine.arguments.contains("--test-notify") {
            Notifier.testNotify()
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

    // Unseals two secrets through one loaded Touch ID-gated key. The second
    // unseal runs with interaction forbidden, so it fails instead of
    // prompting if one touch does not cover both.
    static func testOneTouch() -> Never {
        do {
            let key = try SecureEnclaveVaultKey.create(requireUserPresence: true)
            let one = try VaultCrypto.seal("secret-one", recipientPub: key.x963PublicKey)
            let two = try VaultCrypto.seal("secret-two", recipientPub: key.x963PublicKey)
            let context = LAContext()
            let loaded = try SecureEnclaveVaultKey.load(
                blob: key.dataRepresentation, reason: "run the one-touch self-test", context: context)
            let outOne = try VaultCrypto.unseal(
                ciphertext: one.ciphertext, ephemeralPub: one.ephemeralPub, using: loaded)
            context.interactionNotAllowed = true
            let outTwo = try VaultCrypto.unseal(
                ciphertext: two.ciphertext, ephemeralPub: two.ephemeralPub, using: loaded)
            let ok = outOne == "secret-one" && outTwo == "secret-two"
            print(ok ? "OK: unsealed 2 secrets" : "FAIL: decrypted value mismatch")
            exit(ok ? 0 : 1)
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
