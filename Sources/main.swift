import AppKit
import Combine
import CryptoKit
import Foundation
import SwiftUI

struct SyncedFileItem: Codable, Identifiable, Equatable {
    var relativePath: String
    var localRelativePath: String
    var sha256: String
    var modifiedAt: Date?
    var sizeBytes: Int64?
    var mimeType: String?

    var id: String { localRelativePath }
}

struct SourceTreeNode: Identifiable {
    let id: String
    let name: String
    let localRelativePath: String
    let file: SyncedFileItem?
    let ownerNoteID: UUID?
    let children: [SourceTreeNode]?

    var isFolder: Bool { children != nil }
}

struct FolderOption: Identifiable, Hashable {
    let value: UUID?
    let label: String

    var id: String { value?.uuidString ?? "root" }
}

struct NoteDisplayRow: Identifiable {
    let note: NoteItem
    let depth: Int

    var id: UUID { note.id }
}

struct NoteItem: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var fileName: String
    var isGroup: Bool = false
    var parentID: UUID?
    var sha256: String?
    var lastCheckedAt: Date?
    var lastUpdatedAt: Date?
    var status: String
    var lastError: String?
    var sourceType: String?
    var folderFiles: [SyncedFileItem]?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case fileName
        case isGroup
        case parentID
        case sha256
        case lastCheckedAt
        case lastUpdatedAt
        case status
        case lastError
        case sourceType
        case folderFiles
    }

    init(
        id: UUID,
        title: String,
        url: String,
        fileName: String,
        isGroup: Bool = false,
        parentID: UUID? = nil,
        sha256: String? = nil,
        lastCheckedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        status: String = "Never synced",
        lastError: String? = nil,
        sourceType: String? = nil,
        folderFiles: [SyncedFileItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.fileName = fileName
        self.isGroup = isGroup
        self.parentID = parentID
        self.sha256 = sha256
        self.lastCheckedAt = lastCheckedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.status = status
        self.lastError = lastError
        self.sourceType = sourceType
        self.folderFiles = folderFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        isGroup = try container.decodeIfPresent(Bool.self, forKey: .isGroup) ?? false
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "Never synced"
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        folderFiles = try container.decodeIfPresent([SyncedFileItem].self, forKey: .folderFiles)
    }
}

struct AppConfig: Codable {
    enum SourceFileSortMode: String, Codable, CaseIterable, Identifiable {
        case name
        case date

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Name"
            case .date: return "Date"
            }
        }
    }

    var checkIntervalMinutes: Int
    var notes: [NoteItem]
    var skipVideoFiles: Bool
    var skipLargeFiles: Bool
    var maxFileSizeMB: Int
    var sourceFileSortMode: SourceFileSortMode

    init(
        checkIntervalMinutes: Int,
        notes: [NoteItem],
        skipVideoFiles: Bool = false,
        skipLargeFiles: Bool = false,
        maxFileSizeMB: Int = 100,
        sourceFileSortMode: SourceFileSortMode = .name
    ) {
        self.checkIntervalMinutes = checkIntervalMinutes
        self.notes = notes
        self.skipVideoFiles = skipVideoFiles
        self.skipLargeFiles = skipLargeFiles
        self.maxFileSizeMB = max(1, maxFileSizeMB)
        self.sourceFileSortMode = sourceFileSortMode
    }

    private enum CodingKeys: String, CodingKey {
        case checkIntervalMinutes
        case notes
        case skipVideoFiles
        case skipLargeFiles
        case maxFileSizeMB
        case sourceFileSortMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkIntervalMinutes = try container.decode(Int.self, forKey: .checkIntervalMinutes)
        notes = try container.decode([NoteItem].self, forKey: .notes)
        skipVideoFiles = try container.decodeIfPresent(Bool.self, forKey: .skipVideoFiles) ?? false
        skipLargeFiles = try container.decodeIfPresent(Bool.self, forKey: .skipLargeFiles) ?? false
        let decodedMax = try container.decodeIfPresent(Int.self, forKey: .maxFileSizeMB) ?? 100
        maxFileSizeMB = max(1, decodedMax)
        sourceFileSortMode = try container.decodeIfPresent(SourceFileSortMode.self, forKey: .sourceFileSortMode) ?? .name
    }

    static var `default`: AppConfig {
        AppConfig(
            checkIntervalMinutes: 180,
            notes: [],
            skipVideoFiles: false,
            skipLargeFiles: false,
            maxFileSizeMB: 100,
            sourceFileSortMode: .name
        )
    }
}

struct StorageManager {
    let baseDirectory: URL
    let configFileURL: URL
    let pdfDirectory: URL
    let sourcesDirectory: URL
    let tempDirectory: URL

    init(fileManager: FileManager = .default) throws {
        let home = fileManager.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".notes-sync-app", isDirectory: true)
        let pdfs = base.appendingPathComponent("pdfs", isDirectory: true)
        let sources = base.appendingPathComponent("sources", isDirectory: true)
        let temp = base.appendingPathComponent("tmp", isDirectory: true)
        let config = base.appendingPathComponent("config.json")

        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pdfs, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)

        self.baseDirectory = base
        self.pdfDirectory = pdfs
        self.sourcesDirectory = sources
        self.tempDirectory = temp
        self.configFileURL = config
    }

    func loadConfig() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return .default
        }

        let data = try Data(contentsOf: configFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppConfig.self, from: data)
    }

    func saveConfig(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(config)
        let tempURL = configFileURL.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)

        if FileManager.default.fileExists(atPath: configFileURL.path) {
            try FileManager.default.removeItem(at: configFileURL)
        }

        try FileManager.default.moveItem(at: tempURL, to: configFileURL)
    }

    func fileURL(for note: NoteItem) -> URL {
        pdfDirectory.appendingPathComponent(note.fileName)
    }

    func sourceDirectory(for note: NoteItem) -> URL {
        sourcesDirectory.appendingPathComponent(note.id.uuidString, isDirectory: true)
    }

    func fileURL(for note: NoteItem, localRelativePath: String) -> URL {
        sourceDirectory(for: note).appendingPathComponent(localRelativePath, isDirectory: false)
    }

    func makeFileName(title: String, id: UUID) -> String {
        let folded = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let rawSlug = folded.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        let trimmedSlug = rawSlug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let slug = trimmedSlug.isEmpty ? "note" : String(trimmedSlug.prefix(36))

        return "\(slug)-\(id.uuidString.prefix(8)).pdf"
    }
}

enum DownloadFailure: LocalizedError {
    case invalidURL
    case yandexMalformedResponse
    case yandexMissingDownloadLink
    case yandexUnsupportedLink
    case singleFileDownloadUnsupported
    case unsupportedGoogleDriveLink
    case googleDriveTokenNotFound
    case googleDriveReturnedHTML
    case notPDF
    case badHTTPStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .yandexMalformedResponse:
            return "Yandex Disk returned invalid response"
        case .yandexMissingDownloadLink:
            return "Yandex Disk did not provide direct download URL"
        case .yandexUnsupportedLink:
            return "Unsupported Yandex link format"
        case .singleFileDownloadUnsupported:
            return "Single-file on-demand download is currently supported only for Yandex folder sources"
        case .unsupportedGoogleDriveLink:
            return "Unsupported Google Drive URL format"
        case .googleDriveTokenNotFound:
            return "Google Drive confirmation token not found"
        case .googleDriveReturnedHTML:
            return "Google Drive returned an HTML page instead of PDF"
        case .notPDF:
            return "Downloaded file is not a valid PDF"
        case .badHTTPStatus(let code):
            return "HTTP error \(code)"
        }
    }
}

actor NotesDownloader {
    private let session: URLSession

    struct DownloadOptions {
        let skipVideoFiles: Bool
        let skipLargeFiles: Bool
        let maxFileSizeBytes: Int64

        static let `default` = DownloadOptions(
            skipVideoFiles: false,
            skipLargeFiles: false,
            maxFileSizeBytes: 100 * 1_048_576
        )
    }

    struct DownloadedFolderFile {
        let remotePath: String
        let localRelativePath: String
        let tempURL: URL?
        let modifiedAt: Date?
        let sizeBytes: Int64?
        let mimeType: String?
        let wasSkipped: Bool
        let downloadError: String?
    }

    struct FolderDownloadPreview {
        let remotePath: String
        let localRelativePath: String
        let modifiedAt: Date?
        let sizeBytes: Int64?
        let mimeType: String?
    }

    struct FolderDownloadProgress {
        let downloadedCount: Int
        let totalCount: Int
        let latestFile: FolderDownloadPreview?
    }

    typealias FolderProgressHandler = (FolderDownloadProgress) async -> Void

    enum SourceDownloadResult {
        case singleFile(tempURL: URL)
        case folderFiles(files: [DownloadedFolderFile])
    }

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: configuration)
    }

    func downloadSourceToTemp(
        from source: String,
        tempDirectory: URL,
        options: DownloadOptions = .default,
        onFolderProgress: FolderProgressHandler? = nil
    ) async throws -> SourceDownloadResult {
        guard let sourceURL = URL(string: source) else {
            throw DownloadFailure.invalidURL
        }

        let loweredHost = sourceURL.host?.lowercased() ?? ""
        let loweredAbsolute = sourceURL.absoluteString.lowercased()
        let data: Data

        if loweredAbsolute.hasPrefix("ya-disk-public://")
            || loweredHost.contains("yadi.sk")
            || loweredHost.contains("disk.yandex")
            || loweredHost.contains("disk.360.yandex")
            || loweredHost.contains("docs.yandex")
        {
            return try await downloadFromYandexDisk(
                publicURL: sourceURL,
                tempDirectory: tempDirectory,
                options: options,
                onFolderProgress: onFolderProgress
            )
        } else if loweredHost.contains("drive.google.com") || loweredHost.contains("docs.google.com") {
            data = try await downloadFromGoogleDrive(sharedURL: sourceURL)
        } else {
            data = try await fetchData(from: normalizeDirectDownloadURL(sourceURL))
        }

        try validatePDF(data)

        let tempURL = try writeTempFile(
            data: data,
            tempDirectory: tempDirectory,
            preferredExtension: "pdf"
        )
        return .singleFile(tempURL: tempURL)
    }

    func downloadSingleFileToTemp(
        from source: String,
        remotePath: String,
        tempDirectory: URL
    ) async throws -> URL {
        guard let sourceURL = URL(string: source) else {
            throw DownloadFailure.invalidURL
        }

        let loweredHost = sourceURL.host?.lowercased() ?? ""
        let loweredAbsolute = sourceURL.absoluteString.lowercased()

        if loweredAbsolute.hasPrefix("ya-disk-public://")
            || loweredHost.contains("yadi.sk")
            || loweredHost.contains("disk.yandex")
            || loweredHost.contains("disk.360.yandex")
            || loweredHost.contains("docs.yandex")
        {
            guard let resource = resolveYandexPublicResource(from: sourceURL) else {
                throw DownloadFailure.yandexUnsupportedLink
            }

            let data = try await downloadFromYandexResource(publicKey: resource.publicKey, path: remotePath)
            return try writeTempFile(
                data: data,
                tempDirectory: tempDirectory,
                preferredExtension: extensionFromName(extractPreferredFileName(from: remotePath))
            )
        }

        throw DownloadFailure.singleFileDownloadUnsupported
    }

    private func downloadFromYandexDisk(
        publicURL: URL,
        tempDirectory: URL,
        options: DownloadOptions,
        onFolderProgress: FolderProgressHandler?
    ) async throws -> SourceDownloadResult {
        guard let resource = resolveYandexPublicResource(from: publicURL) else {
            throw DownloadFailure.yandexUnsupportedLink
        }

        if let rootResource = try await fetchYandexPublicResource(publicKey: resource.publicKey, path: resource.path),
           rootResource.type == "dir" {
            let files = try await downloadYandexFolderFiles(
                publicKey: resource.publicKey,
                folderPath: rootResource.path ?? resource.path,
                tempDirectory: tempDirectory,
                options: options,
                onFolderProgress: onFolderProgress
            )
            return .folderFiles(files: files)
        }

        do {
            let data = try await downloadFromYandexResource(publicKey: resource.publicKey, path: resource.path)
            let tempURL = try writeTempFile(
                data: data,
                tempDirectory: tempDirectory,
                preferredExtension: extensionFromName(extractPreferredFileName(from: resource.path))
            )
            return .singleFile(tempURL: tempURL)
        } catch DownloadFailure.yandexMissingDownloadLink {
            if let rootResource = try await fetchYandexPublicResource(publicKey: resource.publicKey, path: nil),
               rootResource.type == "dir" {
                let files = try await downloadYandexFolderFiles(
                    publicKey: resource.publicKey,
                    folderPath: rootResource.path,
                    tempDirectory: tempDirectory,
                    options: options,
                    onFolderProgress: onFolderProgress
                )
                return .folderFiles(files: files)
            }
            guard let fallbackPath = try await findYandexFilePathInFolder(
                publicKey: resource.publicKey,
                startPath: resource.path,
                preferredFileName: resource.preferredFileName
            ) else {
                throw DownloadFailure.yandexMissingDownloadLink
            }
            let data = try await downloadFromYandexResource(publicKey: resource.publicKey, path: fallbackPath)
            let tempURL = try writeTempFile(
                data: data,
                tempDirectory: tempDirectory,
                preferredExtension: extensionFromName(extractPreferredFileName(from: fallbackPath))
            )
            return .singleFile(tempURL: tempURL)
        }
    }

    private func downloadFromGoogleDrive(sharedURL: URL) async throws -> Data {
        if let exportURL = buildGoogleWorkspaceExportURL(from: sharedURL) {
            return try await fetchData(from: exportURL)
        }

        let fileID = try extractGoogleDriveFileID(from: sharedURL)

        var components = URLComponents(string: "https://drive.google.com/uc")
        components?.queryItems = [
            URLQueryItem(name: "export", value: "download"),
            URLQueryItem(name: "id", value: fileID)
        ]

        guard let firstURL = components?.url else {
            throw DownloadFailure.invalidURL
        }

        let (firstData, firstResponse) = try await fetchDataAndResponse(from: firstURL)
        if !looksLikeHTML(data: firstData, response: firstResponse) {
            return firstData
        }

        guard let token = extractGoogleDriveToken(data: firstData, response: firstResponse) else {
            throw DownloadFailure.googleDriveTokenNotFound
        }

        components?.queryItems = [
            URLQueryItem(name: "export", value: "download"),
            URLQueryItem(name: "id", value: fileID),
            URLQueryItem(name: "confirm", value: token)
        ]

        guard let confirmedURL = components?.url else {
            throw DownloadFailure.invalidURL
        }

        let (confirmedData, confirmedResponse) = try await fetchDataAndResponse(from: confirmedURL)
        guard !looksLikeHTML(data: confirmedData, response: confirmedResponse) else {
            throw DownloadFailure.googleDriveReturnedHTML
        }

        return confirmedData
    }

    private func downloadFromYandexResource(publicKey: String, path: String?) async throws -> Data {
        let payload = try await requestYandexDownloadPayload(publicKey: publicKey, path: path)
        guard let directURLString = payload.href, let directURL = URL(string: directURLString) else {
            throw DownloadFailure.yandexMissingDownloadLink
        }
        return try await fetchData(from: directURL)
    }

    private func downloadYandexFolderFiles(
        publicKey: String,
        folderPath: String?,
        tempDirectory: URL,
        options: DownloadOptions,
        onFolderProgress: FolderProgressHandler?
    ) async throws -> [DownloadedFolderFile] {
        let entries = try await collectYandexFiles(publicKey: publicKey, path: folderPath)
        let fileEntries = entries.filter { entry in
            entry.type == "file" && entry.path != nil
        }

        var files: [DownloadedFolderFile] = []
        files.reserveCapacity(fileEntries.count)

        if let onFolderProgress {
            await onFolderProgress(
                FolderDownloadProgress(
                    downloadedCount: 0,
                    totalCount: fileEntries.count,
                    latestFile: nil
                )
            )
        }

        var processedCount = 0
        for entry in fileEntries {
            guard let remotePath = entry.path else {
                continue
            }

            let localRelativePath = makeSafeRelativePath(remotePath: remotePath, rootPath: folderPath)
            let modifiedAt = parseYandexTimestamp(entry.modified)
            var tempURL: URL?
            var wasSkipped = false
            var downloadError: String?

            if options.skipVideoFiles && isVideoYandexEntry(entry) {
                wasSkipped = true
            } else if options.skipLargeFiles,
                      options.maxFileSizeBytes > 0,
                      let size = entry.size,
                      size > options.maxFileSizeBytes {
                wasSkipped = true
            } else {
                do {
                    let data = try await downloadFromYandexResource(publicKey: publicKey, path: remotePath)
                    tempURL = try writeTempFile(
                        data: data,
                        tempDirectory: tempDirectory,
                        preferredExtension: extensionFromName(entry.name)
                    )
                } catch {
                    downloadError = error.localizedDescription
                }
            }

            files.append(
                DownloadedFolderFile(
                    remotePath: remotePath,
                    localRelativePath: localRelativePath,
                    tempURL: tempURL,
                    modifiedAt: modifiedAt,
                    sizeBytes: entry.size,
                    mimeType: entry.mimeType,
                    wasSkipped: wasSkipped,
                    downloadError: downloadError
                )
            )

            processedCount += 1

            if let onFolderProgress {
                let preview = FolderDownloadPreview(
                    remotePath: remotePath,
                    localRelativePath: localRelativePath,
                    modifiedAt: modifiedAt,
                    sizeBytes: entry.size,
                    mimeType: entry.mimeType
                )
                await onFolderProgress(
                    FolderDownloadProgress(
                        downloadedCount: processedCount,
                        totalCount: fileEntries.count,
                        latestFile: preview
                    )
                )
            }
        }

        return files.sorted { $0.localRelativePath.localizedCaseInsensitiveCompare($1.localRelativePath) == .orderedAscending }
    }

    private func collectYandexFiles(publicKey: String, path: String?, depth: Int = 0) async throws -> [YandexResource] {
        if depth > 8 {
            return []
        }

        guard let resource = try await fetchYandexPublicResource(publicKey: publicKey, path: path) else {
            return []
        }

        if resource.type == "file" {
            return [resource]
        }

        guard resource.type == "dir" else {
            return []
        }

        var files: [YandexResource] = []
        for item in resource.embedded?.items ?? [] {
            if item.type == "file" {
                files.append(item)
            } else if item.type == "dir", let childPath = item.path {
                let nested = try await collectYandexFiles(publicKey: publicKey, path: childPath, depth: depth + 1)
                files.append(contentsOf: nested)
            }
        }

        return files
    }

    private func writeTempFile(data: Data, tempDirectory: URL, preferredExtension: String?) throws -> URL {
        var tempURL = tempDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        if let preferredExtension, !preferredExtension.isEmpty {
            tempURL.appendPathExtension(preferredExtension)
        } else {
            tempURL.appendPathExtension("bin")
        }
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func extensionFromName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else {
            return nil
        }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : ext
    }

    private func makeSafeRelativePath(remotePath: String, rootPath: String?) -> String {
        let remoteComponents = sanitizedPathComponents(remotePath)
        let rootComponents = sanitizedPathComponents(rootPath)

        var relative = remoteComponents
        if remoteComponents.count >= rootComponents.count && remoteComponents.starts(with: rootComponents) {
            relative = Array(remoteComponents.dropFirst(rootComponents.count))
        }

        if relative.isEmpty, let lastComponent = remoteComponents.last {
            relative = [lastComponent]
        }

        if relative.isEmpty {
            relative = [UUID().uuidString]
        }

        return relative.joined(separator: "/")
    }

    private func sanitizedPathComponents(_ path: String?) -> [String] {
        guard let path else {
            return []
        }

        return path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private func requestYandexDownloadPayload(publicKey: String, path: String?) async throws -> YandexPayload {
        if let payload = try await requestYandexDownloadPayloadAttempt(publicKey: publicKey, path: path) {
            return payload
        }

        // Some wrapper links include an incorrect subpath; retrying without path often succeeds.
        if path != nil,
           let payload = try await requestYandexDownloadPayloadAttempt(publicKey: publicKey, path: nil) {
            return payload
        }

        throw DownloadFailure.yandexMissingDownloadLink
    }

    private func requestYandexDownloadPayloadAttempt(publicKey: String, path: String?) async throws -> YandexPayload? {
        var components = URLComponents(string: "https://cloud-api.yandex.net/v1/disk/public/resources/download")
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "public_key", value: publicKey)]
        if let path, !path.isEmpty {
            queryItems.append(URLQueryItem(name: "path", value: path))
        }
        components?.queryItems = queryItems

        guard let apiURL = components?.url else {
            throw DownloadFailure.invalidURL
        }

        let (responseData, httpResponse) = try await fetchDataAndResponse(from: apiURL)
        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadFailure.badHTTPStatus(httpResponse.statusCode)
        }

        do {
            let payload = try JSONDecoder().decode(YandexPayload.self, from: responseData)
            return payload.href == nil ? nil : payload
        } catch {
            throw DownloadFailure.yandexMalformedResponse
        }
    }

    private func resolveYandexPublicResource(from sourceURL: URL, depth: Int = 0) -> YandexPublicResource? {
        guard depth < 5 else {
            return nil
        }

        if let parsed = parseYandexPublicPseudoURL(sourceURL.absoluteString) {
            return parsed
        }

        let host = sourceURL.host?.lowercased() ?? ""
        if host.contains("docs.yandex") {
            guard let queryItems = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)?.queryItems
            else {
                return nil
            }

            let preferredName = queryItems.first(where: { $0.name == "name" })?.value

            guard let wrappedValue = queryItems.first(where: { $0.name == "url" })?.value else {
                return YandexPublicResource(
                    publicKey: sourceURL.absoluteString,
                    path: nil,
                    preferredFileName: preferredName
                )
            }

            let decodedWrapped = wrappedValue.removingPercentEncoding ?? wrappedValue
            if let parsed = parseYandexPublicPseudoURL(decodedWrapped) {
                return parsed.withPreferredFileName(preferredName)
            }
            if let wrappedURL = URL(string: decodedWrapped) {
                if let recursive = resolveYandexPublicResource(from: wrappedURL, depth: depth + 1) {
                    return recursive.withPreferredFileName(preferredName)
                }
                return YandexPublicResource(
                    publicKey: wrappedURL.absoluteString,
                    path: nil,
                    preferredFileName: preferredName
                )
            }
            return nil
        }

        if host.contains("yadi.sk") || host.contains("disk.yandex") || host.contains("disk.360.yandex") {
            return YandexPublicResource(
                publicKey: sourceURL.absoluteString,
                path: nil,
                preferredFileName: nil
            )
        }

        return nil
    }

    private func parseYandexPublicPseudoURL(_ rawValue: String) -> YandexPublicResource? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ya-disk-public://"
        guard trimmed.lowercased().hasPrefix(prefix) else {
            return nil
        }

        var remainder = String(trimmed.dropFirst(prefix.count))
        guard !remainder.isEmpty else {
            return nil
        }

        var path: String?
        if let range = remainder.range(of: ":/") {
            let pathTail = String(remainder[range.upperBound...])
            remainder = String(remainder[..<range.lowerBound])
            let normalizedPathTail = pathTail.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !normalizedPathTail.isEmpty {
                path = "/" + normalizedPathTail
            }
        }

        let normalizedKey = remainder
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "+")
        guard !normalizedKey.isEmpty else {
            return nil
        }

        return YandexPublicResource(
            publicKey: prefix + normalizedKey,
            path: path,
            preferredFileName: extractPreferredFileName(from: path)
        )
    }

    private func findYandexFilePathInFolder(
        publicKey: String,
        startPath: String?,
        preferredFileName: String?
    ) async throws -> String? {
        guard let rootEntry = try await fetchYandexPublicResource(publicKey: publicKey, path: startPath) else {
            return nil
        }

        if rootEntry.type == "file", isPDFYandexEntry(rootEntry) {
            return rootEntry.path
        }

        guard rootEntry.type == "dir" else {
            return nil
        }

        let items = rootEntry.embedded?.items ?? []
        let pdfItems = items.filter(isPDFYandexEntry)
        guard !pdfItems.isEmpty else {
            return nil
        }

        let normalizedPreferredName = preferredFileName?.lowercased()
        if let normalizedPreferredName,
           let byName = pdfItems.first(where: { ($0.name ?? "").lowercased() == normalizedPreferredName }) {
            return byName.path
        }

        if let startPath,
           let hintName = startPath.split(separator: "/").last.map(String.init)?.lowercased(),
           let byPathName = pdfItems.first(where: { ($0.name ?? "").lowercased() == hintName }) {
            return byPathName.path
        }

        let newest = pdfItems.max {
            parseYandexTimestamp($0.modified) < parseYandexTimestamp($1.modified)
        }
        return newest?.path
    }

    private func fetchYandexPublicResource(publicKey: String, path: String?) async throws -> YandexResource? {
        var components = URLComponents(string: "https://cloud-api.yandex.net/v1/disk/public/resources")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "public_key", value: publicKey),
            URLQueryItem(name: "limit", value: "200")
        ]
        if let path, !path.isEmpty {
            queryItems.append(URLQueryItem(name: "path", value: path))
        }
        components?.queryItems = queryItems

        guard let apiURL = components?.url else {
            throw DownloadFailure.invalidURL
        }

        let (responseData, httpResponse) = try await fetchDataAndResponse(from: apiURL)
        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadFailure.badHTTPStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(YandexResource.self, from: responseData)
        } catch {
            throw DownloadFailure.yandexMalformedResponse
        }
    }

    private func isPDFYandexEntry(_ entry: YandexResource) -> Bool {
        if entry.type != "file" {
            return false
        }

        if let mime = entry.mimeType?.lowercased(), mime.contains("pdf") {
            return true
        }

        return (entry.name ?? "").lowercased().hasSuffix(".pdf")
    }

    private func isVideoYandexEntry(_ entry: YandexResource) -> Bool {
        if entry.type != "file" {
            return false
        }

        if let mime = entry.mimeType?.lowercased(), mime.hasPrefix("video/") {
            return true
        }

        guard let name = entry.name?.lowercased() else {
            return false
        }
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty else {
            return false
        }
        return Self.videoExtensions.contains(ext)
    }

    private static let videoExtensions: Set<String> = [
        "3gp", "avi", "flv", "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg",
        "mts", "ogv", "ts", "webm", "wmv"
    ]

    private func parseYandexTimestamp(_ timestamp: String?) -> Date {
        guard let timestamp else {
            return .distantPast
        }
        if let withFractional = yandexDateFormatter.date(from: timestamp) {
            return withFractional
        }
        return yandexDateFormatterNoFraction.date(from: timestamp) ?? .distantPast
    }

    private func extractPreferredFileName(from path: String?) -> String? {
        guard let path else {
            return nil
        }
        let fileName = path.split(separator: "/").last.map(String.init)
        return fileName?.isEmpty == false ? fileName : nil
    }

    private func buildGoogleWorkspaceExportURL(from sourceURL: URL) -> URL? {
        let host = sourceURL.host?.lowercased() ?? ""
        guard host.contains("docs.google.com") else {
            return nil
        }

        let path = sourceURL.path

        if let docID = path.firstMatch(pattern: "/document/d/([A-Za-z0-9_-]+)") {
            return URL(string: "https://docs.google.com/document/d/\(docID)/export?format=pdf")
        }

        if let sheetID = path.firstMatch(pattern: "/spreadsheets/d/([A-Za-z0-9_-]+)") {
            return URL(string: "https://docs.google.com/spreadsheets/d/\(sheetID)/export?format=pdf")
        }

        if let presentationID = path.firstMatch(pattern: "/presentation/d/([A-Za-z0-9_-]+)") {
            return URL(string: "https://docs.google.com/presentation/d/\(presentationID)/export/pdf")
        }

        return nil
    }

    private func normalizeDirectDownloadURL(_ sourceURL: URL) -> URL {
        let host = sourceURL.host?.lowercased() ?? ""

        if host.contains("dropbox.com"),
           var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) {
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name.lowercased() == "dl" || $0.name.lowercased() == "raw" }
            queryItems.append(URLQueryItem(name: "dl", value: "1"))
            components.queryItems = queryItems
            return components.url ?? sourceURL
        }

        if host == "github.com" {
            let chunks = sourceURL.path.split(separator: "/")
            if chunks.count >= 5, chunks[2] == "blob" {
                let owner = chunks[0]
                let repo = chunks[1]
                let branch = chunks[3]
                let remainingPath = chunks.dropFirst(4).joined(separator: "/")
                let rawURLString = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(remainingPath)"
                if let rawURL = URL(string: rawURLString) {
                    return rawURL
                }
            }
        }

        return sourceURL
    }

    private struct YandexPayload: Decodable {
        let href: String?
    }

    private struct YandexPublicResource {
        let publicKey: String
        let path: String?
        let preferredFileName: String?

        func withPreferredFileName(_ value: String?) -> YandexPublicResource {
            let cleanedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cleanedValue, !cleanedValue.isEmpty else {
                return self
            }
            if preferredFileName != nil {
                return self
            }
            return YandexPublicResource(publicKey: publicKey, path: path, preferredFileName: cleanedValue)
        }
    }

    private struct YandexResource: Decodable {
        let type: String?
        let name: String?
        let path: String?
        let modified: String?
        let size: Int64?
        let mimeType: String?
        let embedded: Embedded?

        struct Embedded: Decodable {
            let items: [YandexResource]?
        }

        enum CodingKeys: String, CodingKey {
            case type
            case name
            case path
            case modified
            case size
            case mimeType = "mime_type"
            case embedded = "_embedded"
        }
    }

    private let yandexDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let yandexDateFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await fetchDataAndResponse(from: url)
        guard (200..<300).contains(response.statusCode) else {
            throw DownloadFailure.badHTTPStatus(response.statusCode)
        }
        return data
    }

    private func fetchDataAndResponse(from url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadFailure.badHTTPStatus(-1)
        }

        return (data, httpResponse)
    }

    private func validatePDF(_ data: Data) throws {
        guard data.count > 8 else {
            throw DownloadFailure.notPDF
        }

        let header = data.prefix(1024)
        guard header.range(of: Data("%PDF-".utf8)) != nil else {
            throw DownloadFailure.notPDF
        }
    }

    private func extractGoogleDriveFileID(from url: URL) throws -> String {
        let absolute = url.absoluteString

        if let idFromPath = absolute.firstMatch(pattern: "/file/d/([a-zA-Z0-9_-]+)") {
            return idFromPath
        }

        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let idFromQuery = queryItems.first(where: { $0.name == "id" })?.value,
           !idFromQuery.isEmpty {
            return idFromQuery
        }

        throw DownloadFailure.unsupportedGoogleDriveLink
    }

    private func extractGoogleDriveToken(data: Data, response: HTTPURLResponse) -> String? {
        if let cookieHeader = response.value(forHTTPHeaderField: "Set-Cookie"),
           let token = cookieHeader.firstMatch(pattern: "download_warning[^=]*=([^;]+)") {
            return token
        }

        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        if let token = html.firstMatch(pattern: "confirm=([0-9A-Za-z_]+)&") {
            return token
        }

        if let token = html.firstMatch(pattern: "name=\"confirm\" value=\"([0-9A-Za-z_]+)\"") {
            return token
        }

        return nil
    }

    private func looksLikeHTML(data: Data, response: HTTPURLResponse) -> Bool {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            return true
        }

        let prefix = data.prefix(128)
        if let textPrefix = String(data: prefix, encoding: .utf8)?.lowercased() {
            return textPrefix.contains("<html") || textPrefix.contains("<!doctype html")
        }

        return false
    }
}

@MainActor
final class NotesViewModel: ObservableObject {
    @Published var notes: [NoteItem] = []
    @Published var selectedNoteID: UUID?
    @Published var selectedFolderFileID: String?
    @Published var checkIntervalMinutes: Int = 180
    @Published var skipVideoFiles: Bool = false
    @Published var skipLargeFiles: Bool = false
    @Published var maxFileSizeMB: Int = 100
    @Published var sourceFileSortMode: AppConfig.SourceFileSortMode = .name
    @Published var isSyncing = false
    @Published var isStoppingSync = false
    @Published var statusLine = "Ready"
    @Published var alertMessage: String?

    private let storage: StorageManager
    private let downloader = NotesDownloader()
    private var timerCancellable: AnyCancellable?
    private var syncTask: Task<Void, Never>?
    private var inFlightFileDownloads: Set<String> = []
    private var lastAutoSyncAt: Date = .distantPast

    private static let folderSelectionPrefix = "folder:"

    private final class SourceTreeBuildNode {
        let name: String
        let localRelativePath: String
        var file: SyncedFileItem?
        var children: [String: SourceTreeBuildNode] = [:]

        init(name: String, localRelativePath: String) {
            self.name = name
            self.localRelativePath = localRelativePath
        }
    }

    init() {
        do {
            self.storage = try StorageManager()
        } catch {
            fatalError("Failed to initialize storage: \(error)")
        }

        loadConfig()
        sanitizeParentLinks()
        configureAutoSyncTimer()
    }

    var selectedNote: NoteItem? {
        guard let selectedNoteID else { return nil }
        return notes.first(where: { $0.id == selectedNoteID })
    }

    var noteDisplayRows: [NoteDisplayRow] {
        flattenNotesForDisplay()
    }

    var hasAnySyncableSource: Bool {
        notes.contains(where: { !$0.isGroup })
    }

    var selectedHasSyncableSources: Bool {
        !syncIDsForSelectedNote().isEmpty
    }

    var selectedSourceTree: [SourceTreeNode] {
        guard let selectedNote else {
            return []
        }

        if selectedNote.isGroup {
            var roots: [SourceTreeNode] = []
            for sourceNote in groupFolderSources(for: selectedNote) {
                let files = sourceNote.folderFiles ?? []
                guard !files.isEmpty else {
                    continue
                }

                let sourceNodes = Self.buildSourceTree(
                    from: files,
                    sortMode: sourceFileSortMode,
                    ownerNoteID: sourceNote.id,
                    idNamespace: sourceNote.id.uuidString
                )
                guard !sourceNodes.isEmpty else {
                    continue
                }

                let sourceIDPath = "group:\(selectedNote.id.uuidString)::source:\(sourceNote.id.uuidString)"
                roots.append(
                    SourceTreeNode(
                        id: Self.folderSelectionID(for: sourceIDPath),
                        name: groupSourceLabel(for: sourceNote, inside: selectedNote),
                        localRelativePath: sourceIDPath,
                        file: nil,
                        ownerNoteID: sourceNote.id,
                        children: sourceNodes
                    )
                )
            }
            return roots.sorted { Self.sourceTreeSort($0, $1, mode: sourceFileSortMode) }
        }

        guard selectedNote.sourceType == "folder",
              let files = selectedNote.folderFiles,
              !files.isEmpty
        else {
            return []
        }

        return Self.buildSourceTree(
            from: files,
            sortMode: sourceFileSortMode,
            ownerNoteID: selectedNote.id,
            idNamespace: selectedNote.id.uuidString
        )
    }

    var canOpenSelectedSourceFile: Bool {
        selectedSourceFileTarget() != nil
    }

    var canOpenCurrentSelection: Bool {
        guard let selectedNote else {
            return false
        }
        if selectedNote.isGroup || selectedNote.sourceType == "folder" {
            return canOpenSelectedSourceFile
        }
        return true
    }

    func selectDefaultFolderFileSelection() {
        let tree = selectedSourceTree
        guard !tree.isEmpty else {
            selectedFolderFileID = nil
            return
        }

        if let current = selectedFolderFileID,
           Self.findSourceNode(selectionID: current, in: tree) != nil {
            return
        }

        // Keep selection empty until user explicitly picks a file.
        selectedFolderFileID = nil
    }

    private func groupFolderSources(for groupNote: NoteItem) -> [NoteItem] {
        let descendants = descendantIDs(of: groupNote.id)
        return notes
            .filter { note in
                descendants.contains(note.id)
                    && !note.isGroup
                    && note.sourceType == "folder"
                    && !((note.folderFiles ?? []).isEmpty)
            }
            .sorted {
                groupSourceLabel(for: $0, inside: groupNote)
                    .localizedCaseInsensitiveCompare(groupSourceLabel(for: $1, inside: groupNote)) == .orderedAscending
            }
    }

    private func groupSourceLabel(for sourceNote: NoteItem, inside groupNote: NoteItem) -> String {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var chain: [String] = []
        var seen: Set<UUID> = []
        var currentID: UUID? = sourceNote.id
        var reachedGroup = false

        while let current = currentID {
            if seen.contains(current) {
                break
            }
            seen.insert(current)
            if current == groupNote.id {
                reachedGroup = true
                break
            }
            guard let currentNote = byID[current] else {
                break
            }
            chain.append(currentNote.title)
            currentID = currentNote.parentID
        }

        if reachedGroup, !chain.isEmpty {
            return chain.reversed().joined(separator: " / ")
        }
        return sourceNote.title
    }

    private func selectedSourceFileTarget() -> (note: NoteItem, file: SyncedFileItem)? {
        guard let selectedFolderFileID else {
            return nil
        }
        guard let node = Self.findSourceNode(selectionID: selectedFolderFileID, in: selectedSourceTree),
              !node.isFolder,
              let file = node.file
        else {
            return nil
        }
        let ownerID = node.ownerNoteID ?? selectedNote?.id
        guard let ownerID,
              let ownerNote = notes.first(where: { $0.id == ownerID })
        else {
            return nil
        }
        return (ownerNote, file)
    }

    private func children(of parentID: UUID?) -> [NoteItem] {
        notes.filter { $0.parentID == parentID }
    }

    private func descendantIDs(of rootID: UUID) -> Set<UUID> {
        var descendants: Set<UUID> = []
        var stack: [UUID] = [rootID]

        while let current = stack.popLast() {
            for child in children(of: current) {
                if descendants.contains(child.id) {
                    continue
                }
                descendants.insert(child.id)
                stack.append(child.id)
            }
        }

        descendants.remove(rootID)
        return descendants
    }

    private func flattenNotesForDisplay() -> [NoteDisplayRow] {
        let validIDs = Set(notes.map(\.id))
        var byParent: [UUID?: [NoteItem]] = [:]

        for note in notes {
            let parent = (note.parentID != nil && validIDs.contains(note.parentID!)) ? note.parentID : nil
            byParent[parent, default: []].append(note)
        }

        for key in byParent.keys {
            byParent[key]?.sort(by: Self.noteSort)
        }

        var result: [NoteDisplayRow] = []
        var visited: Set<UUID> = []

        func walk(parentID: UUID?, depth: Int) {
            let branch = byParent[parentID] ?? []
            for note in branch {
                if visited.contains(note.id) {
                    continue
                }
                visited.insert(note.id)
                result.append(NoteDisplayRow(note: note, depth: depth))
                walk(parentID: note.id, depth: depth + 1)
            }
        }

        walk(parentID: nil, depth: 0)

        for note in notes.sorted(by: Self.noteSort) where !visited.contains(note.id) {
            result.append(NoteDisplayRow(note: note, depth: 0))
        }

        return result
    }

    private static func noteSort(_ lhs: NoteItem, _ rhs: NoteItem) -> Bool {
        if lhs.isGroup != rhs.isGroup {
            return lhs.isGroup && !rhs.isGroup
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    func noteDisplayTitle(_ note: NoteItem, depth: Int) -> String {
        let indent = String(repeating: "    ", count: depth)
        if note.isGroup {
            return "\(indent)[Folder] \(note.title)"
        }
        return "\(indent)\(note.title)"
    }

    func folderOptions(excluding rootID: UUID? = nil) -> [FolderOption] {
        var excluded: Set<UUID> = []
        if let rootID {
            excluded.insert(rootID)
            excluded.formUnion(descendantIDs(of: rootID))
        }

        var options: [FolderOption] = [FolderOption(value: nil, label: "Top level")]
        for row in flattenNotesForDisplay() where row.note.isGroup && !excluded.contains(row.note.id) {
            let indent = String(repeating: "  ", count: row.depth)
            options.append(FolderOption(value: row.note.id, label: indent + row.note.title))
        }
        return options
    }

    private func syncIDsForSelectedNote() -> [UUID] {
        guard let selected = selectedNote else {
            return []
        }
        if !selected.isGroup {
            return [selected.id]
        }
        let descendants = descendantIDs(of: selected.id)
        return notes.filter { descendants.contains($0.id) && !$0.isGroup }.map(\.id)
    }

    private func allSyncableIDs() -> [UUID] {
        notes.filter { !$0.isGroup }.map(\.id)
    }

    private func sanitizeParentLinks() {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        for idx in notes.indices {
            if notes[idx].parentID == notes[idx].id {
                notes[idx].parentID = nil
                continue
            }
            guard let parentID = notes[idx].parentID else {
                continue
            }
            guard let parent = byID[parentID], parent.isGroup else {
                notes[idx].parentID = nil
                continue
            }
        }
    }

    @discardableResult
    func addNote(title: String, url: String, parentID: UUID?) -> String? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedTitle.isEmpty else {
            return "Title cannot be empty"
        }

        guard let normalizedURL = Self.normalizeSourceURL(url) else {
            return "URL is invalid. Use public http/https or ya-disk-public link."
        }

        let newID = UUID()
        let note = NoteItem(
            id: newID,
            title: cleanedTitle,
            url: normalizedURL,
            fileName: storage.makeFileName(title: cleanedTitle, id: newID),
            isGroup: false,
            parentID: parentID,
            sha256: nil,
            lastCheckedAt: nil,
            lastUpdatedAt: nil,
            status: "Never synced",
            lastError: nil,
            sourceType: nil,
            folderFiles: nil
        )

        notes.append(note)
        selectedNoteID = note.id
        persistConfig()
        statusLine = "Added 1 note"
        return nil
    }

    @discardableResult
    func addFolder(title: String, parentID: UUID?) -> String? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            return "Folder name cannot be empty"
        }

        let newID = UUID()
        let folder = NoteItem(
            id: newID,
            title: cleanedTitle,
            url: "",
            fileName: storage.makeFileName(title: cleanedTitle, id: newID),
            isGroup: true,
            parentID: parentID,
            sha256: nil,
            lastCheckedAt: nil,
            lastUpdatedAt: nil,
            status: "Folder",
            lastError: nil,
            sourceType: nil,
            folderFiles: nil
        )

        notes.append(folder)
        selectedNoteID = folder.id
        persistConfig()
        statusLine = "Added 1 folder"
        return nil
    }

    @discardableResult
    func updateNote(id: UUID, title: String, url: String, parentID: UUID?) -> String? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return "Note not found"
        }

        if notes[index].isGroup {
            return "Use folder editor for folder rows"
        }

        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedTitle.isEmpty else {
            return "Title cannot be empty"
        }

        guard let normalizedURL = Self.normalizeSourceURL(url) else {
            return "URL is invalid. Use public http/https or ya-disk-public link."
        }

        let urlChanged = notes[index].url != normalizedURL
        let previous = notes[index]

        notes[index].title = cleanedTitle
        notes[index].url = normalizedURL
        notes[index].parentID = parentID
        notes[index].status = "Edited. Sync recommended"
        notes[index].lastError = nil
        if urlChanged {
            notes[index].sha256 = nil
            notes[index].sourceType = nil
            notes[index].folderFiles = nil
            try? FileManager.default.removeItem(at: storage.fileURL(for: previous))
            try? FileManager.default.removeItem(at: storage.sourceDirectory(for: previous))
            selectedFolderFileID = nil
        }
        persistConfig()
        statusLine = "Note updated"
        return nil
    }

    @discardableResult
    func updateFolder(id: UUID, title: String, parentID: UUID?) -> String? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return "Folder not found"
        }
        guard notes[index].isGroup else {
            return "Selected row is not a folder"
        }

        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            return "Folder name cannot be empty"
        }

        if let parentID {
            if parentID == id {
                return "Folder cannot be inside itself"
            }
            if descendantIDs(of: id).contains(parentID) {
                return "Folder cannot be moved inside its child"
            }
        }

        notes[index].title = cleanedTitle
        notes[index].parentID = parentID
        notes[index].status = "Folder"
        notes[index].lastError = nil
        persistConfig()
        statusLine = "Folder updated"
        return nil
    }

    func deleteSelectedNote() {
        guard let selectedNoteID, let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else {
            return
        }

        let note = notes[index]
        if note.isGroup {
            let hasChildren = notes.contains(where: { $0.parentID == note.id })
            if hasChildren {
                alertMessage = "Folder is not empty. Move or delete nested items first."
                return
            }
            notes.remove(at: index)
            self.selectedNoteID = nil
            self.selectedFolderFileID = nil
            persistConfig()
            statusLine = "Deleted 1 folder"
            return
        }
        let fileURL = storage.fileURL(for: note)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let folderURL = storage.sourceDirectory(for: note)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.removeItem(at: folderURL)
        }

        notes.remove(at: index)
        self.selectedNoteID = nil
        self.selectedFolderFileID = nil
        persistConfig()
    }

    func openSelectedLocalFile() {
        guard let note = selectedNote else {
            alertMessage = "Select a note first"
            return
        }

        if note.isGroup || note.sourceType == "folder" {
            guard let target = selectedSourceFileTarget() else {
                alertMessage = "Select a file in the folder list"
                return
            }

            let sourceNote = target.note
            let folderFile = target.file
            let fileURL = storage.fileURL(for: sourceNote, localRelativePath: folderFile.localRelativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                downloadMissingSourceFile(note: sourceNote, folderFile: folderFile)
                return
            }
            NSWorkspace.shared.open(fileURL)
            statusLine = "Opened file: \(folderFile.localRelativePath)"
        } else {
            let fileURL = storage.fileURL(for: note)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                alertMessage = "Local PDF is missing. Run sync first."
                return
            }

            if let previewURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
                NSWorkspace.shared.open(
                    [fileURL],
                    withApplicationAt: previewURL,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            } else {
                NSWorkspace.shared.open(fileURL)
            }
            statusLine = "Opened in Preview: \(note.title)"
        }
    }

    func openSourceFile(fileID: String) {
        guard selectedNote != nil else {
            return
        }
        selectedFolderFileID = fileID
        openSelectedLocalFile()
    }

    private func downloadMissingSourceFile(note: NoteItem, folderFile: SyncedFileItem) {
        let downloadKey = "\(note.id.uuidString)::\(folderFile.id)"
        if inFlightFileDownloads.contains(downloadKey) {
            statusLine = "Already downloading: \(folderFile.localRelativePath)"
            return
        }

        inFlightFileDownloads.insert(downloadKey)
        statusLine = "Local file missing. Starting download: \(folderFile.localRelativePath)"

        Task {
            defer {
                inFlightFileDownloads.remove(downloadKey)
            }

            do {
                let tempURL = try await downloader.downloadSingleFileToTemp(
                    from: note.url,
                    remotePath: folderFile.relativePath,
                    tempDirectory: storage.tempDirectory
                )
                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }

                let destinationURL = storage.fileURL(for: note, localRelativePath: folderFile.localRelativePath)
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                try await Self.replaceFile(from: tempURL, to: destinationURL)
                let newHash = try await Self.sha256Hex(fileURL: destinationURL)

                if let noteIndex = notes.firstIndex(where: { $0.id == note.id }),
                   let fileIndex = notes[noteIndex].folderFiles?.firstIndex(where: { $0.id == folderFile.id }) {
                    notes[noteIndex].folderFiles?[fileIndex].sha256 = newHash
                    notes[noteIndex].lastUpdatedAt = Date()
                    persistConfig()
                }

                statusLine = "Downloaded: \(folderFile.localRelativePath)"
                NSWorkspace.shared.open(destinationURL)
                statusLine = "Opened file: \(folderFile.localRelativePath)"
            } catch {
                alertMessage = "Failed to download file: \(error.localizedDescription)"
                statusLine = "Download failed: \(folderFile.localRelativePath)"
            }
        }
    }

    func updateCheckInterval(minutes: Int) {
        let normalized = max(5, minutes)
        checkIntervalMinutes = normalized
        persistConfig()
    }

    func updateSkipVideoFiles(_ skip: Bool) {
        guard skipVideoFiles != skip else {
            return
        }
        skipVideoFiles = skip
        persistConfig()
    }

    func updateSkipLargeFiles(_ skip: Bool) {
        guard skipLargeFiles != skip else {
            return
        }
        skipLargeFiles = skip
        persistConfig()
    }

    func updateMaxFileSizeMB(_ sizeMB: Int) {
        let normalized = max(1, sizeMB)
        guard maxFileSizeMB != normalized else {
            return
        }
        maxFileSizeMB = normalized
        persistConfig()
    }

    func updateSourceFileSortMode(_ mode: AppConfig.SourceFileSortMode) {
        guard sourceFileSortMode != mode else {
            return
        }
        sourceFileSortMode = mode
        persistConfig()
    }

    func syncSelected() {
        guard selectedNote != nil else {
            alertMessage = "Select a note first"
            return
        }

        let targets = syncIDsForSelectedNote()
        if targets.isEmpty {
            statusLine = "No source links in selected folder"
            return
        }
        startSync(noteIDs: targets, reason: "manual")
    }

    func syncAll() {
        startSync(noteIDs: allSyncableIDs(), reason: "manual")
    }

    func stopSync() {
        guard isSyncing else {
            return
        }

        guard !isStoppingSync else {
            return
        }

        isStoppingSync = true
        statusLine = "Stopping sync..."
        syncTask?.cancel()
    }

    private func startSync(noteIDs: [UUID], reason: String) {
        guard !isSyncing else {
            statusLine = "Sync already in progress"
            return
        }

        guard !noteIDs.isEmpty else {
            statusLine = "No notes to sync"
            return
        }

        isSyncing = true
        isStoppingSync = false
        statusLine = "Sync started"

        syncTask = Task {
            await runSync(noteIDs: noteIDs, reason: reason)
        }
    }

    private func runSync(noteIDs: [UUID], reason: String) async {
        let total = noteIDs.count
        var updatedCount = 0
        var errorCount = 0
        var wasStopped = false

        defer {
            isSyncing = false
            isStoppingSync = false
            syncTask = nil
            lastAutoSyncAt = Date()
        }

        for (offset, noteID) in noteIDs.enumerated() {
            if Task.isCancelled {
                wasStopped = true
                break
            }

            guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
                continue
            }

            notes[index].status = "Checking (\(offset + 1)/\(total))"
            notes[index].lastError = nil
            persistConfig()

            let current = notes[index]
            if current.isGroup {
                continue
            }
            let synced = await syncSingle(note: current)
            notes[index] = synced
            if synced.id == selectedNoteID {
                selectDefaultFolderFileSelection()
            }

            if synced.status == "Stopped" {
                wasStopped = true
            }

            if synced.lastError == nil {
                if synced.status == "Updated" || synced.status.hasPrefix("Folder synced:") {
                    updatedCount += 1
                }
            } else {
                errorCount += 1
            }

            persistConfig()

            if Task.isCancelled {
                wasStopped = true
                break
            }
        }

        if wasStopped || Task.isCancelled {
            statusLine = "Sync stopped. Updated: \(updatedCount), errors: \(errorCount)"
            return
        }

        if errorCount == 0 {
            statusLine = "Sync complete. Updated: \(updatedCount)"
        } else {
            statusLine = "Sync complete. Updated: \(updatedCount), errors: \(errorCount)"
            if reason == "manual" {
                alertMessage = "Some notes failed to sync. Select a row to view error details in status column."
            }
        }
    }

    private func syncSingle(note: NoteItem) async -> NoteItem {
        var updated = note
        updated.lastCheckedAt = Date()

        do {
            let options = NotesDownloader.DownloadOptions(
                skipVideoFiles: skipVideoFiles,
                skipLargeFiles: skipLargeFiles,
                maxFileSizeBytes: Int64(max(1, maxFileSizeMB)) * 1_048_576
            )
            let result = try await downloader.downloadSourceToTemp(
                from: note.url,
                tempDirectory: storage.tempDirectory,
                options: options
            ) { progress in
                await MainActor.run {
                    self.applyFolderDownloadProgress(
                        noteID: note.id,
                        noteTitle: note.title,
                        progress: progress
                    )
                }
            }

            switch result {
            case .singleFile(let tempURL):
                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }

                let newHash = try await Self.sha256Hex(fileURL: tempURL)
                let destinationURL = storage.fileURL(for: note)

                var hasChanges = true
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    let currentHash = try await Self.sha256Hex(fileURL: destinationURL)
                    hasChanges = currentHash != newHash
                }

                if hasChanges {
                    try await Self.replaceFile(from: tempURL, to: destinationURL)
                    updated.lastUpdatedAt = Date()
                    updated.status = "Updated"
                } else {
                    updated.status = "No changes"
                }

                updated.sha256 = newHash
                updated.sourceType = "file"
                updated.folderFiles = nil

                let folderURL = storage.sourceDirectory(for: note)
                if FileManager.default.fileExists(atPath: folderURL.path) {
                    try? FileManager.default.removeItem(at: folderURL)
                }
            case .folderFiles(let files):
                defer {
                    for file in files {
                        if let tempURL = file.tempURL {
                            try? FileManager.default.removeItem(at: tempURL)
                        }
                    }
                }

                updated = try await applyFolderSync(note: updated, downloadedFiles: files)
            }
            updated.lastError = nil
        } catch is CancellationError {
            updated.status = "Stopped"
            updated.lastError = nil
        } catch {
            if Task.isCancelled || Self.isCancellationError(error) {
                updated.status = "Stopped"
                updated.lastError = nil
            } else {
                updated.status = "Error: \(error.localizedDescription)"
                updated.lastError = error.localizedDescription
            }
        }

        return updated
    }

    private func applyFolderDownloadProgress(
        noteID: UUID,
        noteTitle: String,
        progress: NotesDownloader.FolderDownloadProgress
    ) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            return
        }

        var partialFiles = notes[index].folderFiles ?? []
        if let latest = progress.latestFile {
            let modifiedAt = latest.modifiedAt == .distantPast ? nil : latest.modifiedAt
            let item = SyncedFileItem(
                relativePath: latest.remotePath,
                localRelativePath: latest.localRelativePath,
                sha256: "",
                modifiedAt: modifiedAt,
                sizeBytes: latest.sizeBytes,
                mimeType: latest.mimeType
            )

            if let existingIndex = partialFiles.firstIndex(where: { $0.localRelativePath == item.localRelativePath }) {
                partialFiles[existingIndex] = item
            } else {
                partialFiles.append(item)
            }

            partialFiles.sort {
                $0.localRelativePath.localizedCaseInsensitiveCompare($1.localRelativePath) == .orderedAscending
            }
        }

        notes[index].sourceType = "folder"
        notes[index].folderFiles = partialFiles
        notes[index].status = "Checking folder (\(progress.downloadedCount)/\(progress.totalCount))"
        statusLine = "Syncing \(noteTitle): \(progress.downloadedCount)/\(progress.totalCount)"

        if noteID == selectedNoteID {
            selectDefaultFolderFileSelection()
        }
    }

    private func applyFolderSync(
        note: NoteItem,
        downloadedFiles: [NotesDownloader.DownloadedFolderFile]
    ) async throws -> NoteItem {
        var updated = note
        let fileManager = FileManager.default
        let folderRoot = storage.sourceDirectory(for: note)
        try fileManager.createDirectory(at: folderRoot, withIntermediateDirectories: true)

        let previousItems = note.folderFiles ?? []
        let previousByPath = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.localRelativePath, $0) })
        var changedCount = 0
        var failedCount = 0
        var skippedCount = 0

        // If source switched from single-file mode, remove legacy standalone file.
        let legacyFileURL = storage.fileURL(for: note)
        if fileManager.fileExists(atPath: legacyFileURL.path) {
            try? fileManager.removeItem(at: legacyFileURL)
        }

        var nextItems: [SyncedFileItem] = []
        nextItems.reserveCapacity(downloadedFiles.count)

        for file in downloadedFiles {
            try Task.checkCancellation()
            let destinationURL = storage.fileURL(for: note, localRelativePath: file.localRelativePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let newHash: String
            if let tempURL = file.tempURL {
                let downloadedHash = try await Self.sha256Hex(fileURL: tempURL)
                var hasChanges = true

                if fileManager.fileExists(atPath: destinationURL.path) {
                    let currentHash = try await Self.sha256Hex(fileURL: destinationURL)
                    hasChanges = currentHash != downloadedHash
                }

                if hasChanges {
                    try await Self.replaceFile(from: tempURL, to: destinationURL)
                    changedCount += 1
                }

                newHash = downloadedHash
            } else {
                if file.wasSkipped {
                    skippedCount += 1
                } else if file.downloadError != nil {
                    failedCount += 1
                }

                if let existing = previousByPath[file.localRelativePath]?.sha256, !existing.isEmpty {
                    newHash = existing
                } else if fileManager.fileExists(atPath: destinationURL.path) {
                    newHash = (try? await Self.sha256Hex(fileURL: destinationURL)) ?? ""
                } else {
                    newHash = ""
                }
            }

            let normalizedModifiedAt: Date?
            if let modified = file.modifiedAt, modified != .distantPast {
                normalizedModifiedAt = modified
            } else {
                normalizedModifiedAt = nil
            }

            nextItems.append(
                SyncedFileItem(
                    relativePath: file.remotePath,
                    localRelativePath: file.localRelativePath,
                    sha256: newHash,
                    modifiedAt: normalizedModifiedAt,
                    sizeBytes: file.sizeBytes,
                    mimeType: file.mimeType
                )
            )
        }

        let nextPaths = Set(nextItems.map(\.localRelativePath))
        var removedCount = 0
        for oldItem in previousItems where !nextPaths.contains(oldItem.localRelativePath) {
            let oldURL = storage.fileURL(for: note, localRelativePath: oldItem.localRelativePath)
            if fileManager.fileExists(atPath: oldURL.path) {
                try? fileManager.removeItem(at: oldURL)
                removedCount += 1
            }
        }

        cleanupEmptyDirectories(in: folderRoot)

        updated.sourceType = "folder"
        updated.folderFiles = nextItems.sorted {
            $0.localRelativePath.localizedCaseInsensitiveCompare($1.localRelativePath) == .orderedAscending
        }
        updated.sha256 = nil

        if changedCount > 0 || removedCount > 0 || note.sourceType != "folder" {
            updated.lastUpdatedAt = Date()
        }

        if nextItems.isEmpty {
            updated.status = "Folder synced: 0 files"
        } else if changedCount > 0 || removedCount > 0 || failedCount > 0 || skippedCount > 0 {
            updated.status = "Folder synced: \(nextItems.count) files (\(changedCount) updated, \(removedCount) removed, \(failedCount) failed, \(skippedCount) skipped)"
        } else {
            updated.status = "Folder no changes: \(nextItems.count) files"
        }

        return updated
    }

    private func cleanupEmptyDirectories(in root: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var directories: [URL] = []
        for case let item as URL in enumerator {
            if let isDirectory = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory == true {
                directories.append(item)
            }
        }

        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path), entries.isEmpty {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    private func loadConfig() {
        do {
            let config = try storage.loadConfig()
            notes = config.notes
            sanitizeParentLinks()
            checkIntervalMinutes = max(5, config.checkIntervalMinutes)
            skipVideoFiles = config.skipVideoFiles
            skipLargeFiles = config.skipLargeFiles
            maxFileSizeMB = max(1, config.maxFileSizeMB)
            sourceFileSortMode = config.sourceFileSortMode
            statusLine = "Loaded \(notes.count) notes"
        } catch {
            notes = []
            checkIntervalMinutes = 180
            skipVideoFiles = false
            skipLargeFiles = false
            maxFileSizeMB = 100
            sourceFileSortMode = .name
            statusLine = "Failed to load config. Starting with empty list."
        }
    }

    private func persistConfig() {
        sanitizeParentLinks()
        let config = AppConfig(
            checkIntervalMinutes: max(5, checkIntervalMinutes),
            notes: notes,
            skipVideoFiles: skipVideoFiles,
            skipLargeFiles: skipLargeFiles,
            maxFileSizeMB: max(1, maxFileSizeMB),
            sourceFileSortMode: sourceFileSortMode
        )
        do {
            try storage.saveConfig(config)
        } catch {
            alertMessage = "Failed to save config: \(error.localizedDescription)"
        }
    }

    private func configureAutoSyncTimer() {
        timerCancellable = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.runAutoSyncIfNeeded()
            }
    }

    private func runAutoSyncIfNeeded() {
        guard !isSyncing else {
            return
        }

        guard hasAnySyncableSource else {
            return
        }

        let interval = TimeInterval(max(5, checkIntervalMinutes) * 60)
        guard Date().timeIntervalSince(lastAutoSyncAt) >= interval else {
            return
        }

        startSync(noteIDs: allSyncableIDs(), reason: "auto")
    }

    private static func folderSelectionID(for localRelativePath: String) -> String {
        folderSelectionPrefix + localRelativePath
    }

    private static func buildSourceTree(
        from files: [SyncedFileItem],
        sortMode: AppConfig.SourceFileSortMode,
        ownerNoteID: UUID?,
        idNamespace: String
    ) -> [SourceTreeNode] {
        guard !files.isEmpty else {
            return []
        }

        let root = SourceTreeBuildNode(name: "", localRelativePath: "")

        for file in files {
            let components = file.localRelativePath
                .split(separator: "/")
                .map(String.init)
            guard let fileName = components.last else {
                continue
            }

            var current = root
            var pathComponents: [String] = []

            for folderName in components.dropLast() {
                pathComponents.append(folderName)
                let folderPath = pathComponents.joined(separator: "/")
                if current.children[folderName] == nil {
                    current.children[folderName] = SourceTreeBuildNode(
                        name: folderName,
                        localRelativePath: folderPath
                    )
                }
                if let next = current.children[folderName] {
                    current = next
                }
            }

            let filePath = components.joined(separator: "/")
            let fileNode = SourceTreeBuildNode(name: fileName, localRelativePath: filePath)
            fileNode.file = file
            current.children[fileName] = fileNode
        }

        return root.children.values
            .map {
                freezeSourceTree(
                    $0,
                    sortMode: sortMode,
                    ownerNoteID: ownerNoteID,
                    idNamespace: idNamespace
                )
            }
            .sorted { sourceTreeSort($0, $1, mode: sortMode) }
    }

    private static func freezeSourceTree(
        _ node: SourceTreeBuildNode,
        sortMode: AppConfig.SourceFileSortMode,
        ownerNoteID: UUID?,
        idNamespace: String
    ) -> SourceTreeNode {
        let pathForID = idNamespace.isEmpty ? node.localRelativePath : "\(idNamespace)::\(node.localRelativePath)"
        if let file = node.file {
            return SourceTreeNode(
                id: idNamespace.isEmpty ? file.id : "\(idNamespace)::\(file.id)",
                name: node.name,
                localRelativePath: node.localRelativePath,
                file: file,
                ownerNoteID: ownerNoteID,
                children: nil
            )
        }

        let children = node.children.values
            .map {
                freezeSourceTree(
                    $0,
                    sortMode: sortMode,
                    ownerNoteID: ownerNoteID,
                    idNamespace: idNamespace
                )
            }
            .sorted { sourceTreeSort($0, $1, mode: sortMode) }

        return SourceTreeNode(
            id: folderSelectionID(for: pathForID),
            name: node.name,
            localRelativePath: node.localRelativePath,
            file: nil,
            ownerNoteID: nil,
            children: children.isEmpty ? nil : children
        )
    }

    private static func findSourceNode(selectionID: String, in nodes: [SourceTreeNode]) -> SourceTreeNode? {
        for node in nodes {
            if node.id == selectionID {
                return node
            }
            if let children = node.children,
               let found = findSourceNode(selectionID: selectionID, in: children) {
                return found
            }
        }
        return nil
    }

    private static func sourceTreeSort(
        _ lhs: SourceTreeNode,
        _ rhs: SourceTreeNode,
        mode: AppConfig.SourceFileSortMode
    ) -> Bool {
        if lhs.isFolder != rhs.isFolder {
            return lhs.isFolder && !rhs.isFolder
        }
        if !lhs.isFolder, !rhs.isFolder, mode == .date {
            let lhsDate = lhs.file?.modifiedAt ?? .distantPast
            let rhsDate = rhs.file?.modifiedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static func sha256Hex(fileURL: URL) async throws -> String {
        try Task.checkCancellation()
        return try await Task(priority: .utility) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private static func replaceFile(from tempURL: URL, to destinationURL: URL) async throws {
        try Task.checkCancellation()
        try await Task(priority: .utility) {
            try Task.checkCancellation()
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempURL, to: destinationURL)
        }.value
    }

    private static func normalizeSourceURL(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.lowercased().hasPrefix("ya-disk-public://") {
            return trimmed.replacingOccurrences(of: " ", with: "+")
        }

        var candidate = trimmed
        if !trimmed.contains("://") {
            candidate = "https://" + trimmed
        }

        guard var components = URLComponents(string: candidate) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        if components.host == nil, let currentPath = components.path.split(separator: "/").first {
            components.host = String(currentPath)
            components.path = "/" + components.path.dropFirst(currentPath.count)
        }

        guard let host = components.host, !host.isEmpty else {
            return nil
        }

        return components.url?.absoluteString
    }
}

struct NoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let titleText: String
    let initialTitle: String
    let initialURL: String
    let initialParentID: UUID?
    let parentOptions: [FolderOption]
    let showURLField: Bool
    let onSave: (String, String, UUID?) -> String?

    @State private var titleValue: String = ""
    @State private var urlValue: String = ""
    @State private var parentSelectionKey: String = "root"
    @State private var inlineError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titleText)
                .font(.headline)

            NativeTextField(placeholder: "Title", text: $titleValue, autoFocus: true)
                .frame(height: 28)

            if showURLField {
                NativeTextField(placeholder: "Public link", text: $urlValue)
                    .frame(height: 28)
            }

            HStack(spacing: 8) {
                Text("Parent folder")
                    .foregroundStyle(.secondary)
                Picker("Parent folder", selection: $parentSelectionKey) {
                    ForEach(parentOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }

            if let inlineError {
                Text(inlineError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    let parentID = parentOptions.first(where: { $0.id == parentSelectionKey })?.value
                    let error = onSave(titleValue, urlValue, parentID)
                    if let error {
                        inlineError = error
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            titleValue = initialTitle
            urlValue = initialURL
            let candidate = initialParentID?.uuidString ?? "root"
            if parentOptions.contains(where: { $0.id == candidate }) {
                parentSelectionKey = candidate
            } else {
                parentSelectionKey = "root"
            }
            inlineError = nil
        }
    }
}

struct NativeTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var autoFocus: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = true
        field.isBordered = true
        field.drawsBackground = true
        field.isEnabled = true
        field.isEditable = true
        field.isSelectable = true
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .default
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if autoFocus && !context.coordinator.didAutoFocus {
            DispatchQueue.main.async {
                guard let window = nsView.window else {
                    return
                }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(nsView)
                context.coordinator.didAutoFocus = true
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        var didAutoFocus = false

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            text = field.stringValue
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = NotesViewModel()

    @State private var showAddSheet = false
    @State private var showAddFolderSheet = false
    @State private var noteForEditing: NoteItem?
    @State private var intervalText = "180"
    @State private var maxFileSizeText = "100"
    @State private var expandedFolderIDs: Set<String> = []

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 12) {
            controls

            Table(viewModel.noteDisplayRows, selection: $viewModel.selectedNoteID) {
                TableColumn("Title") { row in
                    Text(viewModel.noteDisplayTitle(row.note, depth: row.depth))
                        .lineLimit(1)
                }
                .width(min: 180, ideal: 220)

                TableColumn("Status") { row in
                    Text(row.note.status)
                        .lineLimit(1)
                }
                .width(min: 160, ideal: 240)

                TableColumn("Last checked") { row in
                    Text(Self.string(for: row.note.lastCheckedAt))
                }
                .width(min: 140, ideal: 150)

                TableColumn("Last updated") { row in
                    Text(Self.string(for: row.note.lastUpdatedAt))
                }
                .width(min: 140, ideal: 150)

                TableColumn("Source URL") { row in
                    Text(row.note.isGroup ? "-" : row.note.url)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 280, ideal: 460)
            }
            .onChange(of: viewModel.selectedNoteID) { _ in
                expandedFolderIDs = []
                viewModel.selectedFolderFileID = nil
                viewModel.selectDefaultFolderFileSelection()
            }
            .onChange(of: viewModel.selectedFolderFileID) { newValue in
                expandAncestors(for: newValue)
            }

            if !viewModel.selectedSourceTree.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Files in source")
                            .font(.headline)
                        Spacer()
                        Picker(
                            "Sort",
                            selection: Binding(
                                get: { viewModel.sourceFileSortMode },
                                set: { viewModel.updateSourceFileSortMode($0) }
                            )
                        ) {
                            ForEach(AppConfig.SourceFileSortMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    HStack(spacing: 12) {
                        Text("File")
                            .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
                        Text("Size")
                            .frame(width: 90, alignment: .trailing)
                        Text("Modified")
                            .frame(width: 130, alignment: .leading)
                        Text("Type")
                            .frame(minWidth: 140, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            sourceTreeRows(nodes: viewModel.selectedSourceTree, depth: 0)
                        }
                    }
                    .frame(minHeight: 140, maxHeight: 280)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack {
                Text(viewModel.statusLine)
                    .font(.footnote)
                Spacer()
                if viewModel.isSyncing {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Syncing...")
                        .font(.footnote)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
            intervalText = String(viewModel.checkIntervalMinutes)
            maxFileSizeText = String(viewModel.maxFileSizeMB)
        }
        .onChange(of: viewModel.checkIntervalMinutes) { newValue in
            intervalText = String(newValue)
        }
        .onChange(of: viewModel.maxFileSizeMB) { newValue in
            maxFileSizeText = String(newValue)
        }
        .sheet(isPresented: $showAddSheet) {
            NoteEditorSheet(
                titleText: "Add source",
                initialTitle: "",
                initialURL: "",
                initialParentID: nil,
                parentOptions: viewModel.folderOptions(),
                showURLField: true
            ) { title, url, parentID in
                viewModel.addNote(title: title, url: url, parentID: parentID)
            }
        }
        .sheet(isPresented: $showAddFolderSheet) {
            NoteEditorSheet(
                titleText: "Add folder",
                initialTitle: "",
                initialURL: "",
                initialParentID: nil,
                parentOptions: viewModel.folderOptions(),
                showURLField: false
            ) { title, _url, parentID in
                viewModel.addFolder(title: title, parentID: parentID)
            }
        }
        .sheet(item: $noteForEditing) { note in
            if note.isGroup {
                NoteEditorSheet(
                    titleText: "Edit folder",
                    initialTitle: note.title,
                    initialURL: "",
                    initialParentID: note.parentID,
                    parentOptions: viewModel.folderOptions(excluding: note.id),
                    showURLField: false
                ) { title, _url, parentID in
                    viewModel.updateFolder(id: note.id, title: title, parentID: parentID)
                }
            } else {
                NoteEditorSheet(
                    titleText: "Edit source",
                    initialTitle: note.title,
                    initialURL: note.url,
                    initialParentID: note.parentID,
                    parentOptions: viewModel.folderOptions(),
                    showURLField: true
                ) { title, url, parentID in
                    viewModel.updateNote(id: note.id, title: title, url: url, parentID: parentID)
                }
            }
        }
        .alert("Error", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("Add") {
                showAddSheet = true
            }

            Button("Add folder") {
                showAddFolderSheet = true
            }

            Button("Edit") {
                if let selected = viewModel.selectedNote {
                    noteForEditing = selected
                }
            }
            .disabled(viewModel.selectedNote == nil)

            Button("Delete") {
                viewModel.deleteSelectedNote()
            }
            .disabled(viewModel.selectedNote == nil)

            Divider()
                .frame(height: 20)

            Button("Update selected") {
                viewModel.syncSelected()
            }
            .disabled(viewModel.isSyncing || !viewModel.selectedHasSyncableSources)

            Button("Update all") {
                viewModel.syncAll()
            }
            .disabled(viewModel.isSyncing || !viewModel.hasAnySyncableSource)

            Button(viewModel.isStoppingSync ? "Stopping..." : "Stop") {
                viewModel.stopSync()
            }
            .disabled(!viewModel.isSyncing || viewModel.isStoppingSync)

            Button("Open selected file") {
                viewModel.openSelectedLocalFile()
            }
            .disabled(!viewModel.canOpenCurrentSelection)

            Spacer()

            Toggle(
                "Skip videos",
                isOn: Binding(
                    get: { viewModel.skipVideoFiles },
                    set: { viewModel.updateSkipVideoFiles($0) }
                )
            )
            .toggleStyle(.switch)
            .help("Do not download files with video MIME type or common video extensions.")
            .disabled(viewModel.isSyncing)

            Toggle(
                "Skip >",
                isOn: Binding(
                    get: { viewModel.skipLargeFiles },
                    set: { viewModel.updateSkipLargeFiles($0) }
                )
            )
            .toggleStyle(.switch)
            .help("Do not download files larger than the configured MB limit.")
            .disabled(viewModel.isSyncing)

            TextField("MB", text: $maxFileSizeText)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .disabled(viewModel.isSyncing)
            Text("MB")
            Button("Set") {
                if let value = Int(maxFileSizeText) {
                    viewModel.updateMaxFileSizeMB(value)
                } else {
                    viewModel.alertMessage = "Max file size must be an integer (MB)"
                }
            }
            .disabled(viewModel.isSyncing)

            Text("Auto every")
            TextField("minutes", text: $intervalText)
                .frame(width: 60)
            Text("min")
            Button("Apply") {
                if let value = Int(intervalText) {
                    viewModel.updateCheckInterval(minutes: value)
                } else {
                    viewModel.alertMessage = "Interval must be an integer"
                }
            }
        }
    }

    private func sourceTreeRows(nodes: [SourceTreeNode], depth: Int) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                VStack(spacing: 0) {
                    sourceTreeRow(node: node, depth: depth)

                    if node.isFolder,
                       expandedFolderIDs.contains(node.id),
                       let children = node.children,
                       !children.isEmpty
                    {
                        sourceTreeRows(nodes: children, depth: depth + 1)
                    }
                }
            }
        )
    }

    private func sourceTreeRow(node: SourceTreeNode, depth: Int) -> some View {
        let isSelected = viewModel.selectedFolderFileID == node.id
        let isExpanded = expandedFolderIDs.contains(node.id)

        return HStack(spacing: 12) {
            HStack(spacing: 4) {
                Color.clear
                    .frame(width: CGFloat(depth) * 16)

                if node.isFolder {
                    Button {
                        viewModel.selectedFolderFileID = node.id
                        toggleFolderExpansion(node.id)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .center)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }

                if node.isFolder {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "doc")
                        .foregroundStyle(.primary)
                }

                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)

            Text(Self.sizeString(node.file?.sizeBytes))
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(.secondary)

            Text(Self.string(for: node.file?.modifiedAt))
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(node.isFolder ? "folder" : (node.file?.mimeType ?? "-"))
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.20) : Color.clear)
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                handleSourceNodeDoubleClick(node)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                viewModel.selectedFolderFileID = node.id
            }
        )
    }

    private func handleSourceNodeDoubleClick(_ node: SourceTreeNode) {
        viewModel.selectedFolderFileID = node.id

        if node.isFolder {
            toggleFolderExpansion(node.id)
            return
        }

        guard node.file != nil else {
            return
        }
        viewModel.openSourceFile(fileID: node.id)
    }

    private func toggleFolderExpansion(_ folderID: String) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    private func expandAncestors(for selectionID: String?) {
        guard let selectionID else {
            return
        }

        guard let ancestorFolderIDs = ancestorFolders(for: selectionID, in: viewModel.selectedSourceTree) else {
            return
        }
        for folderID in ancestorFolderIDs {
            expandedFolderIDs.insert(folderID)
        }
    }

    private func ancestorFolders(
        for selectionID: String,
        in nodes: [SourceTreeNode],
        trail: [String] = []
    ) -> [String]? {
        for node in nodes {
            if node.id == selectionID {
                return trail
            }
            guard node.isFolder, let children = node.children else {
                continue
            }
            var childTrail = trail
            childTrail.append(node.id)
            if let found = ancestorFolders(for: selectionID, in: children, trail: childTrail) {
                return found
            }
        }
        return nil
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.alertMessage = nil
                }
            }
        )
    }

    private static func string(for date: Date?) -> String {
        guard let date else {
            return "-"
        }
        return dateFormatter.string(from: date)
    }

    private static func sizeString(_ bytes: Int64?) -> String {
        guard let bytes else {
            return "-"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct NotesSyncDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private extension String {
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: utf16.count)
        guard let match = regex.firstMatch(in: self, range: range), match.numberOfRanges > 1 else {
            return nil
        }

        let captureRange = match.range(at: 1)
        guard let swiftRange = Range(captureRange, in: self) else {
            return nil
        }

        return String(self[swiftRange])
    }
}
