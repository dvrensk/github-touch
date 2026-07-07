import Foundation

public final class VaultStore {
    public let vaultURL: URL

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("github-touch")
    }

    public init(directory: URL = VaultStore.defaultDirectory) {
        vaultURL = directory.appendingPathComponent("vault.json")
    }

    /// nil means "no vault yet"; a thrown error means the file exists but is unreadable.
    public func load() throws -> VaultFile? {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else { return nil }
        let data = try Data(contentsOf: vaultURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VaultFile.self, from: data)
    }

    public func save(_ vault: VaultFile) throws {
        try FileManager.default.createDirectory(
            at: vaultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(vault)

        let tmpURL = vaultURL.appendingPathExtension("tmp")
        let created = FileManager.default.createFile(
            atPath: tmpURL.path, contents: data, attributes: [.posixPermissions: 0o600])
        guard created else { throw VaultError.writeFailed }

        _ = try FileManager.default.replaceItemAt(
            vaultURL, withItemAt: tmpURL, options: .usingNewMetadataOnly)
    }
}
