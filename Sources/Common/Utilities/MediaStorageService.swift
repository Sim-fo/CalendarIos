import Foundation
import UIKit

enum MediaStorageService {
    private static func mediaDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("CalendarIos/Media", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func saveImageData(_ data: Data, prefix: String = "photo") throws -> String {
        let fileName = "\(prefix)_\(UUID().uuidString).jpg"
        let url = try mediaDirectory().appendingPathComponent(fileName)
        if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82) {
            try jpeg.write(to: url, options: .atomic)
        } else {
            try data.write(to: url, options: .atomic)
        }
        return fileName
    }

    static func makeAudioFileURL() throws -> (fileName: String, url: URL) {
        let fileName = "audio_\(UUID().uuidString).m4a"
        let url = try mediaDirectory().appendingPathComponent(fileName)
        return (fileName, url)
    }

    static func url(for relativeName: String) -> URL? {
        guard !relativeName.isEmpty else { return nil }
        if relativeName.hasPrefix("/") {
            return URL(fileURLWithPath: relativeName)
        }
        return try? mediaDirectory().appendingPathComponent(relativeName)
    }

    static func loadImage(named relativeName: String?) -> UIImage? {
        guard let relativeName, let fileURL = url(for: relativeName) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }

    static func deleteFile(named relativeName: String?) {
        guard let relativeName, let fileURL = url(for: relativeName) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
