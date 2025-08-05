//
//  VoiceRecognitionManager.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import Speech
import AVFoundation
import AVFAudio
import SwiftUI
import os.log

@MainActor
class VoiceRecognitionManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var isListening = false
    @Published var hasPermission = false
    @Published var errorMessage: String?
    @Published var isProcessing = false
    
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Enhanced transcription tracking
    private var lastValidTranscription = ""
    private var hasProcessedCurrentCommand = false
    
    // Callback for when recording is finished and text is ready
    var onRecordingFinished: ((String) -> Void)?
    
    // Logger for debugging
    private let logger = Logger(subsystem: "com.apple.signin.test", category: "VoiceRecognitionManager")
    
    // Computed property for authorization status
    private var isAuthorized: Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    override init() {
        super.init()
        logger.info("VoiceRecognitionManager initializing")
        speechRecognizer = SFSpeechRecognizer()
        speechRecognizer?.delegate = self
    }
    
    func requestPermissions() async {
        logger.info("Requesting speech and microphone permissions")
        
        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                self?.logger.info("Speech recognition authorization status: \(status.rawValue)")
                continuation.resume(returning: status)
            }
        }
        
        // Request microphone permission
        let audioStatus = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    self?.logger.info("Microphone permission granted: \(granted)")
                    continuation.resume(returning: granted)
                }
            } else {
                // For older iOS versions
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                    self?.logger.info("Microphone permission granted (legacy): \(granted)")
                    continuation.resume(returning: granted)
                }
            }
        }
        
        await MainActor.run {
            self.hasPermission = speechStatus == .authorized && audioStatus
            self.logger.info("Final permission status - Speech: \(speechStatus.rawValue), Audio: \(audioStatus), Combined: \(self.hasPermission)")
            
            if !self.hasPermission {
                self.errorMessage = "Speech recognition and microphone permissions are required"
                self.logger.error("Permissions not granted - Speech: \(speechStatus.rawValue), Audio: \(audioStatus)")
            }
        }
    }
    
    func startRecording() {
        print("🎤 Starting transcription...")
        print("🌐 Speech recognizer available: \(speechRecognizer?.isAvailable ?? false)")
        print("🔐 Authorization status: \(isAuthorized)")
        logger.info("Starting recording process")
        
        // Reset processing flag for new transcription
        hasProcessedCurrentCommand = false
        
        // Check microphone permission
        if #available(iOS 17.0, *) {
            let micPermission = AVAudioApplication.shared.recordPermission
            print("🎤 Microphone permission: \(micPermission.rawValue)")
        } else {
            let micPermission = AVAudioSession.sharedInstance().recordPermission
            print("🎤 Microphone permission: \(micPermission.rawValue)")
        }
        
        guard hasPermission else {
            print("❌ Cannot start recording - permissions not granted")
            logger.error("Cannot start recording - permissions not granted")
            errorMessage = "Permissions not granted"
            return
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Speech recognizer is not available")
            logger.error("Speech recognizer not available")
            errorMessage = "Speech recognizer not available"
            return
        }
        
        print("✅ Speech recognizer is available and ready")
        logger.info("Speech recognizer is available and ready")
        
        // Reset any existing task
        if recognitionTask != nil {
            print("🔄 Canceling previous recognition task")
            logger.info("Canceling previous recognition task")
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("🎤 Audio session configured successfully")
            print("🎚️ Audio session category: \(audioSession.category)")
            print("🎛️ Audio session mode: \(audioSession.mode)")
            logger.info("Audio session configured successfully")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
            logger.error("Audio session setup failed: \(error.localizedDescription)")
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            return
        }
        
        // Create and configure recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ Unable to create recognition request")
            logger.error("Failed to create recognition request")
            errorMessage = "Unable to create recognition request"
            return
        }
        
        // Configure for better accuracy
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        recognitionRequest.taskHint = .dictation  // Use dictation mode for longer phrases
        
        // Set contextual strings to improve recognition of appointment-related terms
        recognitionRequest.contextualStrings = ["appointment", "schedule", "meeting", "calendar", 
                                               "Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                                               "morning", "afternoon", "evening", "o'clock", "AM", "PM"]
        
        // Add punctuation if available
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = true
        }
        
        print("🎙️ Recognition request configured with dictation mode and contextual hints")
        logger.info("Recognition request created successfully")
        
        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("🎧 Audio format: \(recordingFormat)")
        logger.info("Audio input node format: \(recordingFormat)")
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
            
            // Check if we're receiving audio (optional debug info)
            let channelData = buffer.floatChannelData?[0]
            let channelDataValue = channelData?[0] ?? 0
            if abs(channelDataValue) > 0.01 {
                // Uncomment for detailed audio debugging
                // print("🔊 Audio detected: \(channelDataValue)")
            }
        }
        print("🎧 Audio tap installed successfully")
        logger.info("Audio tap installed successfully")
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("🎵 Audio engine started successfully")
            print("🎤 Audio engine is running: \(audioEngine.isRunning)")
            logger.info("Audio engine started successfully")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
            logger.error("Audio engine failed to start: \(error.localizedDescription)")
            errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            return
        }
        
        // Start recognition task
        print("🎙️ Starting recognition task")
        logger.info("Starting recognition task")
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                // Handle specific speech recognition errors
                let errorCode = (error as NSError).code
                let errorDomain = (error as NSError).domain
                
                // Ignore common non-critical errors
                if errorDomain == "kLSRErrorDomain" && errorCode == 301 {
                    // Recognition request was canceled - this is normal when stopping
                    print("🔄 Recognition canceled (normal)")
                    return
                } else if errorDomain == "kAFAssistantErrorDomain" && errorCode == 1110 {
                    // No speech detected - this is normal during silence
                    print("🔇 No speech detected (normal)")
                    return
                } else if errorDomain == "kAFAssistantErrorDomain" && errorCode == 1101 {
                    // Local speech recognition service error - try to restart
                    print("🔄 Local speech recognition service error - attempting restart")
                    Task { @MainActor in
                        self.restartSpeechRecognition()
                    }
                    return
                } else {
                    // Log other errors but don't show to user unless they're significant
                    print("❌ Recognition error: \(error)")
                    Task { @MainActor in
                        self.logger.error("Recognition error: \(error.localizedDescription)")
                        if !error.localizedDescription.contains("canceled") {
                            self.errorMessage = "Recognition error: \(error.localizedDescription)"
                            self.isRecording = false
                            self.isListening = false
                        }
                    }
                    return
                }
            }
            
            if let result = result {
                Task { @MainActor in
                    let transcription = result.bestTranscription.formattedString
                    print("📝 Transcription update: '\(transcription)'")
                    print("🔄 Is final: \(result.isFinal)")
                    
                    self.transcribedText = transcription
                    
                    // Store the last valid (non-empty) transcription
                    if !transcription.isEmpty {
                        self.lastValidTranscription = transcription
                        print("💾 Stored valid transcription: '\(transcription)'")
                    }
                    
                    // Only update isListening if we're actually still recording
                    if self.isRecording {
                        self.isListening = !result.isFinal
                        self.logger.info("Recognition update - Text: '\(transcription)', Final: \(result.isFinal), Still recording: \(self.isRecording)")
                        
                        // Process command when speech recognition is final (but don't auto-stop recording)
                        if result.isFinal && !transcription.isEmpty && !self.hasProcessedCurrentCommand {
                            print("✅ Final transcription: '\(transcription)'")
                            // Keep recording active for user to manually stop
                        } else if !result.isFinal {
                            print("⏳ Partial result (not final yet): '\(transcription)'")
                        }
                    } else {
                        print("ℹ️ Recognition result received but recording already stopped - Text: '\(transcription)'")
                        self.logger.info("Recognition result received but recording already stopped - Text: '\(transcription)'")
                    }
                }
            }
        }
        
        isRecording = true
        isListening = true
        transcribedText = ""
        errorMessage = nil
        isProcessing = false
        print("✅ Recording started successfully")
        logger.info("Recording started successfully")
    }
    
    func stopRecording() {
        print("🛑 Stopping transcription...")
        logger.info("Stopping recording - current state: isRecording=\(self.isRecording), isListening=\(self.isListening)")
        
        // Ensure we're actually recording before trying to stop
        guard self.isRecording else {
            print("⚠️ stopRecording called but not currently recording")
            logger.warning("stopRecording called but not currently recording")
            return
        }
        
        // Give speech recognition more time to finalize before stopping
        self.isProcessing = true
        
        // Delay stopping to allow speech recognition to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // First, end the audio to finalize recognition
            self.recognitionRequest?.endAudio()
            
            // Wait a bit longer for final results to come in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // Update UI state
                self.isRecording = false
                self.isListening = false
                print("🔄 Updated UI state: isRecording=\(self.isRecording), isListening=\(self.isListening)")
                self.logger.info("Updated UI state: isRecording=\(self.isRecording), isListening=\(self.isListening)")
                
                // Stop audio engine if it's running
                if self.audioEngine.isRunning {
                    self.audioEngine.stop()
                    print("🎵 Audio engine stopped")
                    self.logger.info("Audio engine stopped")
                }
                
                if self.audioEngine.inputNode.numberOfInputs > 0 {
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    print("🎧 Audio tap removed")
                    self.logger.info("Audio tap removed")
                }
                
                self.recognitionTask?.cancel()
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                print("✅ Transcription stopped completely")
                self.logger.info("Recognition task canceled and request cleared")
                
                // Deactivate audio session
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    print("🎤 Audio session deactivated")
                    self.logger.info("Audio session deactivated")
                } catch {
                    print("❌ Failed to deactivate audio session: \(error)")
                    self.logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
                }
                
                // Process the current transcription when stopping
                let textToProcess = !self.transcribedText.isEmpty ? self.transcribedText : self.lastValidTranscription
                
                if !textToProcess.isEmpty {
                    print("🚀 Auto-processing text: '\(textToProcess)'")
                    self.logger.info("Processing transcribed text automatically: '\(textToProcess)'")
                    self.onRecordingFinished?(textToProcess)
                } else {
                    print("⚠️ No valid transcription to process")
                    self.logger.warning("No transcribed text to process")
                    self.isProcessing = false
                    // Clear any previous error when stopping without text
                    self.errorMessage = nil
                }
                
                print("✅ stopRecording completed - final state: isRecording=\(self.isRecording), isListening=\(self.isListening)")
                self.logger.info("stopRecording completed - final state: isRecording=\(self.isRecording), isListening=\(self.isListening)")
            }
        }
    }
    
    func clearTranscription() {
        print("🧹 Clearing transcription")
        logger.info("Clearing transcription")
        transcribedText = ""
        lastValidTranscription = ""
        hasProcessedCurrentCommand = false
        errorMessage = nil
        isProcessing = false
    }
    
    private func restartSpeechRecognition() {
        print("🔄 Restarting speech recognition...")
        logger.info("Restarting speech recognition")
        
        // Stop current recognition
        if isRecording {
            stopRecording()
        }
        
        // Wait a moment then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.hasPermission {
                self.startRecording()
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension VoiceRecognitionManager: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor [weak self] in
            self?.logger.info("Speech recognizer availability changed: \(available)")
            if !available {
                self?.stopRecording()
                self?.errorMessage = "Speech recognizer became unavailable"
                self?.logger.error("Speech recognizer became unavailable")
            }
        }
    }
}

