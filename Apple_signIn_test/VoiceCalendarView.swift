//
//  VoiceCalendarView.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import SwiftUI
import os.log

// DEPRECATED: This view has been replaced by MainConversationView in ContentView.swift
// Keeping for reference/backup purposes only
struct VoiceCalendarView_Deprecated: View {
    @StateObject private var voiceManager = VoiceRecognitionManager()
    @StateObject private var commandService = VoiceCommandService()
    @StateObject private var appointmentService = AppointmentService()
    @EnvironmentObject private var authManager: AuthenticationManager
    
    // Calendar manager will be passed from ContentView via environment
    @EnvironmentObject private var calendarManager: GoogleCalendarManager
    
    @State private var showingAppointments = false
    @State private var showingDebug = false
    @State private var showingConversation = false
    
    // Logger for debugging
    private let logger = Logger(subsystem: "com.apple.signin.test", category: "VoiceCalendarView")
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.blue)
                    
                    Text("Voice Calendar")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Tap the microphone to give voice commands")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Calendar sync status and conversation info
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: calendarManager.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(calendarManager.isConnected ? .green : .red)
                        
                        Text(calendarManager.syncStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Conversation indicator
                        if commandService.currentThreadId != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .foregroundColor(.blue)
                                Text("Chat Active")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    // Show conversation count if there are messages
                    if !commandService.conversationHistory.isEmpty {
                        HStack {
                            Text("\(commandService.conversationHistory.count) messages in conversation")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("View Chat") {
                                showingConversation = true
                            }
                            .font(.caption2)
                            .controlSize(.mini)
                        }
                    }
                    
                    // Calendar connection status
                    if !calendarManager.isConnected {
                        VStack(spacing: 8) {
                            if let errorMessage = calendarManager.errorMessage,
                               (errorMessage.contains("expired") || errorMessage.contains("could not be refreshed")) {
                                Button("Reconnect Calendar") {
                                    calendarManager.forceReauthentication()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Text("Calendar authentication expired")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else {
                                Button("Connect Calendar") {
                                    calendarManager.signInWithGoogleForCalendar()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Main microphone button
                VStack(spacing: 16) {
                    Button(action: {
                        logger.info("Microphone button tapped - isRecording: \(voiceManager.isRecording)")
                        
                        if voiceManager.isRecording {
                            logger.info("Stopping recording manually")
                            voiceManager.stopRecording()
                        } else {
                            logger.info("Starting recording process")
                            // Clear any previous errors
                            voiceManager.errorMessage = nil
                            Task {
                                if !voiceManager.hasPermission {
                                    logger.info("Requesting permissions")
                                    await voiceManager.requestPermissions()
                                }
                                if voiceManager.hasPermission {
                                    logger.info("Permissions granted, starting recording")
                                    voiceManager.startRecording()
                                } else {
                                    logger.error("Permissions not granted, cannot start recording")
                                    voiceManager.errorMessage = "Microphone permission required for voice commands"
                                }
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(voiceManager.isRecording ? Color.red : Color.blue)
                                .frame(width: 120, height: 120)
                                .scaleEffect(voiceManager.isListening ? 1.1 : 1.0)
                                .animation(voiceManager.isListening ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: voiceManager.isListening)
                            
                            Image(systemName: voiceManager.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(!voiceManager.hasPermission || commandService.isLoading)
                    
                    // Status text
                    if voiceManager.isRecording {
                        Text("Listening... Tap to stop")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if voiceManager.isProcessing || commandService.isLoading {
                        Text("Processing your command...")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("Tap to start recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Transcribed text (show briefly)
                if !voiceManager.transcribedText.isEmpty && !voiceManager.isProcessing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You said:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(voiceManager.transcribedText)
                            .font(.body)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        
                        Button("Clear") {
                            logger.info("Clearing transcription manually")
                            voiceManager.clearTranscription()
                            commandService.clearLastResponse()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Command response
                if let response = commandService.lastResponse {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Response:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(response.message)
                            .font(.body)
                            .padding()
                            .background(response.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .cornerRadius(8)
                        
                        if let appointment = response.appointment {
                            AppointmentCard(appointment: appointment)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Error messages
                if let errorMessage = voiceManager.errorMessage ?? commandService.errorMessage ?? calendarManager.errorMessage {
                    VStack(spacing: 8) {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // Show retry button for calendar errors
                        if calendarManager.errorMessage != nil {
                            Button("Try Again") {
                                calendarManager.signInWithGoogleForCalendar()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                
                Spacer()
                
                // Bottom buttons
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Button("Chat") {
                            showingConversation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        
                        Button("Appointments") {
                            showingAppointments = true
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    
                    HStack(spacing: 16) {
                        Button("Debug") {
                            showingDebug = true
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        
                        Button("Sign Out") {
                            authManager.signOut()
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
            .navigationTitle("Voice Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAppointments) {
                AppointmentsListView(appointmentService: appointmentService)
            }
            .sheet(isPresented: $showingConversation) {
                NavigationView {
                    ConversationView(
                        commandService: commandService,
                        voiceManager: voiceManager
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingConversation = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDebug) {
                DebugView(
                    calendarManager: calendarManager,
                    commandService: commandService,
                    authManager: authManager
                )
            }
            .task {
                logger.info("VoiceCalendarView task started")
                
                // Set up the calendar manager reference in auth manager
                authManager.calendarManager = calendarManager
                
                // Set up automatic command processing
                voiceManager.onRecordingFinished = { transcribedText in
                    logger.info("Recording finished callback triggered with text: '\(transcribedText)'")
                    Task {
                        let trimmedText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedText.isEmpty {
                            logger.info("Processing command in background task")
                            await commandService.processCommand(trimmedText)
                        } else {
                            logger.warning("No text to process from voice recording")
                            await MainActor.run {
                                voiceManager.errorMessage = "No speech detected. Please try speaking again."
                            }
                        }
                        // Clear the processing state after a short delay
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        await MainActor.run {
                            logger.info("Clearing processing state")
                            voiceManager.isProcessing = false
                        }
                    }
                }
                
                if !voiceManager.hasPermission {
                    logger.info("Requesting voice permissions on startup")
                    await voiceManager.requestPermissions()
                } else {
                    logger.info("Voice permissions already granted")
                }
                
                logger.info("Fetching appointments")
                await appointmentService.fetchAppointments()
                
                // Check calendar access status
                logger.info("Checking calendar access")
                await calendarManager.connectGoogleCalendar()
                
                logger.info("VoiceCalendarView setup completed")
            }
        }
    }
}

struct AppointmentCard: View {
    let appointment: AppointmentData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appointment.title)
                .font(.headline)
            
            HStack {
                Image(systemName: "calendar")
                Text("\(appointment.date) at \(appointment.time)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let duration = appointment.duration {
                HStack {
                    Image(systemName: "clock")
                    Text("\(duration) minutes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if let attendees = appointment.attendees, !attendees.isEmpty {
                HStack {
                    Image(systemName: "person.2")
                    Text(attendees.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            if let meetingLink = appointment.meetingLink {
                Button(action: {
                    if let url = URL(string: meetingLink) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "video")
                        Text("Join Meeting")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    VoiceCalendarView_Deprecated()
}