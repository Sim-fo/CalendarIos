import AVFoundation
import Foundation

@MainActor
final class AudioNoteManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published var currentAudioFileName: String?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingFileName: String?

    init(initialFileName: String? = nil) {
        self.currentAudioFileName = initialFileName
        super.init()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        stopPlayback()
        errorMessage = nil

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            errorMessage = String(localized: "audio.permission_denied")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let target = try MediaStorageService.makeAudioFileURL()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            let newRecorder = try AVAudioRecorder(url: target.url, settings: settings)
            newRecorder.record()
            recorder = newRecorder
            recordingFileName = target.fileName
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let recordingFileName {
            if let old = currentAudioFileName, old != recordingFileName {
                MediaStorageService.deleteFile(named: old)
            }
            currentAudioFileName = recordingFileName
            self.recordingFileName = nil
        }
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }

        guard let fileName = currentAudioFileName,
              let url = MediaStorageService.url(for: fileName) else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.play()
            player = newPlayer
            isPlaying = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func deleteAudio() {
        stopPlayback()
        if isRecording {
            recorder?.stop()
            recorder = nil
            isRecording = false
            MediaStorageService.deleteFile(named: recordingFileName)
            recordingFileName = nil
        }
        MediaStorageService.deleteFile(named: currentAudioFileName)
        currentAudioFileName = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        self.player = nil
    }
}
