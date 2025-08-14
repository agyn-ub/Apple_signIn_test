//
//  ConversationView.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//  Enhanced with ChatGPT-style interface
//

import SwiftUI
import os.log

struct ConversationView: View {
    @ObservedObject var commandService: VoiceCommandService
    @ObservedObject var voiceManager: VoiceRecognitionManager
    @State private var textInput: String = ""
    @State private var showingExamples = false
    @State private var showQuickResponses = false
    @State private var quickResponseType: QuickResponseType = .none
    
    private let logger = Logger(subsystem: "com.apple.signin.test", category: "ConversationView")
    
    enum QuickResponseType {
        case none
        case time
        case date
        case duration
    }
    
    var body: some View {
        GeometryReader { geometry in
            mainContentView
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header with assistant info
            ChatHeaderView()
            
            // Conversation Messages
            ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Welcome message if no conversation
                            if commandService.conversationHistory.isEmpty {
                                WelcomeMessageView(showExamples: $showingExamples)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 32)
                            }
                            
                            // Example prompts
                            if showingExamples && commandService.conversationHistory.isEmpty {
                                ExamplePromptsView { example in
                                    textInput = example
                                    showingExamples = false
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            // Messages
                            ForEach(commandService.conversationHistory) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                                    .padding(.horizontal, 20)
                            }
                            
                            // Typing indicator
                            if commandService.isLoading {
                                TypingIndicatorView()
                                    .padding(.horizontal, 20)
                            }
                            
                            // Quick responses for missing information
                            if showQuickResponses && quickResponseType != .none {
                                QuickResponseView(
                                    responseType: quickResponseType,
                                    onSelectResponse: { response in
                                        textInput = response
                                        showQuickResponses = false
                                        sendTextMessage()
                                    }
                                )
                                .padding(.horizontal, 20)
                                .id("quick-responses")
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 100) // Space for input
                    }
                    .onChange(of: commandService.conversationHistory.count) { _ in
                        scrollToBottom(proxy: proxy)
                        // Check if we should show quick responses
                        checkForQuickResponses()
                    }
                    .onChange(of: commandService.isLoading) { _ in
                        if commandService.isLoading {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
                
                Spacer()
            }
            .overlay(alignment: .bottom) {
                // Floating input area
                ChatInputView(
                    textInput: $textInput,
                    voiceManager: voiceManager,
                    commandService: commandService,
                    onSendMessage: sendTextMessage,
                    onVoiceCommand: { command in
                        Task {
                            await commandService.processCommand(command)
                        }
                    }
                )
                .background(
                    Color(.systemBackground)
                        .ignoresSafeArea(edges: .bottom)
                        .shadow(color: .black.opacity(0.1), radius: 1, y: -1)
                )
            }
        }
    
    private func sendTextMessage() {
        let message = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        
        logger.info("Sending text message: '\(message)'")
        textInput = ""
        showingExamples = false
        
        Task {
            await commandService.processTextCommand(message)
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if showQuickResponses {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("quick-responses", anchor: UnitPoint.bottom)
            }
        } else if let lastMessage = commandService.conversationHistory.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastMessage.id, anchor: UnitPoint.bottom)
            }
        } else if commandService.isLoading {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("typing-indicator", anchor: UnitPoint.bottom)
            }
        }
    }
    
    private func checkForQuickResponses() {
        // Check if the last assistant message is asking for missing information
        guard let lastMessage = commandService.conversationHistory.last,
              !lastMessage.isUser else {
            showQuickResponses = false
            return
        }
        
        let messageText = lastMessage.content.lowercased()
        
        // Detect what type of information is being requested
        if messageText.contains("what time") || messageText.contains("time works") || messageText.contains("specific time") {
            quickResponseType = .time
            showQuickResponses = true
        } else if messageText.contains("when") || messageText.contains("what date") || messageText.contains("which day") {
            quickResponseType = .date
            showQuickResponses = true
        } else if messageText.contains("how long") || messageText.contains("duration") {
            quickResponseType = .duration
            showQuickResponses = true
        } else {
            showQuickResponses = false
            quickResponseType = .none
        }
    }
}

// MARK: - Chat Header
struct ChatHeaderView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Calendar Assistant")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                Text("I can help you manage your calendar and schedule")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .border(Color(.systemGray5), width: 0.5)
    }
}

// MARK: - Welcome Message
struct WelcomeMessageView: View {
    @Binding var showExamples: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Welcome to your Calendar Assistant")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text("I can help you schedule appointments, create events, check your calendar, and manage your availability. Just tell me what you need!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            Button(action: {
                withAnimation(.easeInOut) {
                    showExamples.toggle()
                }
            }) {
                HStack {
                    Text(showExamples ? "Hide Examples" : "Show Examples")
                        .fontWeight(.medium)
                    Image(systemName: showExamples ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
        }
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Example Prompts
struct ExamplePromptsView: View {
    let onSelectExample: (String) -> Void
    
    private let examples = [
        "Schedule a meeting with Sarah tomorrow at 2 PM",
        "What do I have planned for this week?",
        "Block my calendar for gym time every Monday at 6 AM",
        "Cancel my dentist appointment on Friday",
        "Set up a daily standup at 9 AM with the team",
        "I'm free from 9 to 5 on weekdays"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try asking me:")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(examples, id: \.self) { example in
                    Button(action: {
                        onSelectExample(example)
                    }) {
                        Text(example)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Modern Message Bubble
struct ChatMessageView: View {
    let message: VoiceCommandService.ConversationMessage
    
    private var backgroundForMessage: some View {
        Group {
            if message.isUser {
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).opacity(0.9)
            } else {
                Color(.systemGray6)
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !message.isUser {
                // Assistant avatar
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                if !message.isUser {
                    Text("Assistant")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 12) {
                    // Message content
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(message.isUser ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(backgroundForMessage)
                        .cornerRadius(18)
                        .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
                    
                    // Appointment card if present
                    if let appointment = message.appointment {
                        ModernAppointmentCard(appointment: appointment)
                            .frame(maxWidth: 280, alignment: .leading)
                    }
                }
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.isUser {
                Spacer(minLength: 32)
            } else {
                Spacer(minLength: 48)
            }
        }
    }
}

// MARK: - Modern Appointment Card
struct ModernAppointmentCard: View {
    let appointment: AppointmentData
    var isPartial: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isPartial ? "calendar.badge.clock" : "calendar.badge.checkmark")
                    .foregroundColor(isPartial ? .orange : .green)
                    .font(.system(size: 16, weight: .semibold))
                Text(isPartial ? "Gathering Details..." : "Event Created")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isPartial ? .orange : .green)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(appointment.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("\(appointment.date) at \(appointment.time)")
                        .font(.subheadline)
                }
                
                if let duration = appointment.duration {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("\(duration) minutes")
                            .font(.subheadline)
                    }
                }
                
                if let attendees = appointment.attendees, !attendees.isEmpty {
                    HStack {
                        Image(systemName: "person.2")
                            .foregroundColor(.purple)
                            .font(.caption)
                        Text(attendees.joined(separator: ", "))
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((isPartial ? Color.orange : Color.green).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

// MARK: - Typing Indicator
struct TypingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Assistant avatar
            Circle()
                .fill(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Assistant")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                                value: animationPhase
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(18)
            }
            
            Spacer(minLength: 48)
        }
        .id("typing-indicator")
        .onAppear {
            animationPhase = 0
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Modern Chat Input
struct ChatInputView: View {
    @Binding var textInput: String
    @ObservedObject var voiceManager: VoiceRecognitionManager
    @ObservedObject var commandService: VoiceCommandService
    let onSendMessage: () -> Void
    let onVoiceCommand: (String) -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Show recording indicator if recording
            if voiceManager.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(voiceManager.isListening ? 1.2 : 0.8)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: voiceManager.isListening)
                    
                    Text("Recording... Tap mic to stop")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            
            // Input row
            HStack(spacing: 12) {
                // Text input with modern styling
                HStack(spacing: 8) {
                    TextField("Message Calendar Assistant...", text: $textInput, axis: .vertical)
                        .focused($isTextFieldFocused)
                        .lineLimit(1...6)
                        .font(.body)
                        .onSubmit {
                            onSendMessage()
                        }
                    
                    // Voice button - now starts recording immediately
                    Button(action: {
                        if isTextFieldFocused {
                            isTextFieldFocused = false
                        }
                        
                        if voiceManager.isRecording {
                            // Stop recording
                            voiceManager.stopRecording()
                        } else {
                            // Start recording immediately
                            Task {
                                if !voiceManager.hasPermission {
                                    await voiceManager.requestPermissions()
                                }
                                if voiceManager.hasPermission {
                                    voiceManager.startRecording()
                                }
                            }
                        }
                    }) {
                        Image(systemName: voiceManager.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(voiceManager.isRecording ? .red : .blue)
                    }
                    .disabled(commandService.isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(24)
                
                // Send button
                Button(action: onSendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSendMessage ? .blue : .gray)
                }
                .disabled(!canSendMessage || commandService.isLoading)
                .scaleEffect(canSendMessage ? 1.0 : 0.8)
                .animation(.spring(response: 0.2), value: canSendMessage)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Clear chat button
            if !commandService.conversationHistory.isEmpty {
                HStack {
                    Button(action: {
                        commandService.clearConversation()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.caption)
                            Text("Clear Chat")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    if let threadId = commandService.currentThreadId {
                        Text("ID: \(String(threadId.prefix(8)))")
                            .font(.caption2)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .onReceive(voiceManager.$transcribedText) { text in
            // Auto-process voice commands when transcription is complete
            if !text.isEmpty && !voiceManager.isRecording && !voiceManager.isProcessing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let command = voiceManager.transcribedText
                    if !command.isEmpty {
                        voiceManager.clearTranscription()
                        onVoiceCommand(command)
                    }
                }
            }
        }
    }
    
    private var canSendMessage: Bool {
        !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Quick Response View
struct QuickResponseView: View {
    let responseType: ConversationView.QuickResponseType
    let onSelectResponse: (String) -> Void
    
    private var responses: [String] {
        switch responseType {
        case .time:
            return ["9:00 AM", "10:00 AM", "2:00 PM", "3:00 PM", "4:00 PM", "All-day event"]
        case .date:
            return ["Today", "Tomorrow", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Next week"]
        case .duration:
            return ["30 minutes", "1 hour", "90 minutes", "2 hours", "All day"]
        case .none:
            return []
        }
    }
    
    private var promptText: String {
        switch responseType {
        case .time:
            return "Quick time selection:"
        case .date:
            return "Quick date selection:"
        case .duration:
            return "How long should this be?"
        case .none:
            return ""
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(promptText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(responses, id: \.self) { response in
                        Button(action: {
                            onSelectResponse(response)
                        }) {
                            Text(response)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

#Preview {
    ConversationView(
        commandService: VoiceCommandService(),
        voiceManager: VoiceRecognitionManager()
    )
}