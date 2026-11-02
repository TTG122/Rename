//
//  VoiceRecorder.swift
//  轻点记账
//
//  语音记账：系统语音识别 + 实时波形。默认优先使用设备端识别（on-device），
//  只有设备不支持时才回落到在线识别，并在 UI 上明确提示。
//

import Foundation
import AVFoundation
import Speech
import Observation

@MainActor
@Observable
final class VoiceRecorder {

    enum Phase: Equatable {
        case idle
        case requesting
        case recording
        case finished
        case denied
        case unavailable(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript: String = ""
    private(set) var audioLevel: Double = 0
    private(set) var isOnDevice: Bool = false
    var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    // MARK: - 权限

    func requestAuthorization() async -> Bool {
        phase = .requesting

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            phase = .denied
            errorMessage = "语音识别权限未开启，请在「设置 → 轻点记账 → 语音识别」中打开"
            return false
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            phase = .denied
            errorMessage = "麦克风权限未开启，请在「设置 → 轻点记账 → 麦克风」中打开"
            return false
        }

        phase = .idle
        return true
    }

    // MARK: - 开始 / 结束

    func start() {
        guard phase != .recording else { return }
        guard let recognizer, recognizer.isAvailable else {
            phase = .unavailable("当前设备暂时无法使用语音识别")
            return
        }

        transcript = ""
        errorMessage = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // 支持设备端识别时优先本地，隐私优先
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                isOnDevice = true
            } else {
                isOnDevice = false
            }

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.level(from: buffer)
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }

            engine.prepare()
            try engine.start()

            audioEngine = engine
            recognitionRequest = request

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil {
                        self.finish()
                    }
                }
            }

            phase = .recording
            Haptics.impact(.light)
        } catch {
            phase = .unavailable(error.localizedDescription)
            errorMessage = "录音启动失败：\(error.localizedDescription)"
            stopEngine()
        }
    }

    func stop() {
        guard phase == .recording else { return }
        recognitionRequest?.endAudio()
        stopEngine()
        phase = .finished
    }

    func reset() {
        transcript = ""
        errorMessage = nil
        phase = .idle
    }

    private func finish() {
        stopEngine()
        if phase == .recording {
            phase = .finished
        }
    }

    private func stopEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 波形

    private static func level(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frames {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))
        let normalized = max(0, min(1, (20 * log10(rms + 0.000_000_1) + 50) / 50))
        return Double(normalized)
    }
}
