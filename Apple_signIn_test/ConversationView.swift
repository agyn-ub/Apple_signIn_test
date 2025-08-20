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
                            
                            // Confirmation quick actions
                            if commandService.hasPendingConfirmation {
                                ConfirmationActionsView(
                                    operationType: commandService.pendingOperationType ?? "operation",
                                    onConfirm: {
                                        textInput = "Yes, confirm"
                                        sendTextMessage()
                                    },
                                    onCancel: {
                                        textInput = "No, cancel"
                                        sendTextMessage()
                                    }
                                )
                                .padding(.horizontal, 20)
                                .id("confirmation-actions")
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 140) // Increased space for input and typing indicator
                        .onTapGesture {
                            hideKeyboard()
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: commandService.conversationHistory.count) { _ in
                        scrollToBottom(proxy: proxy)
                        // Check if we should show quick responses
                        checkForQuickResponses()
                    }
                    .onChange(of: commandService.isLoading) { _ in
                        if commandService.isLoading {
                            // Add a small delay to ensure the typing indicator is rendered
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo("typing-indicator", anchor: .bottom)
                                }
                            }
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
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("quick-responses", anchor: UnitPoint.bottom)
            }
        } else if let lastMessage = commandService.conversationHistory.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: UnitPoint.bottom)
            }
        } else if commandService.isLoading {
            // Use simpler animation for typing indicator
            proxy.scrollTo("typing-indicator", anchor: UnitPoint.bottom)
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
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
    @State private var isAnimating = false
    
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
                            .opacity(isAnimating ? 0.3 : 1.0)
                            .scaleEffect(isAnimating ? 0.8 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                                value: isAnimating
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(18)
                .drawingGroup() // Optimize rendering performance
            }
            
            Spacer(minLength: 48)
        }
        .id("typing-indicator")
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

// MARK: - Recording Waveform Animation
struct RecordingWaveform: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 3, height: isAnimating ? 20 : 12)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
            }
        }
        .drawingGroup() // Optimize rendering
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

// MARK: - Recording Timer Display
struct RecordingTimerView: View {
    let duration: TimeInterval
    
    private var formattedTime: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        Text(formattedTime)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
    }
}

// MARK: - Enhanced Push to Talk Voice Button
struct PushToTalkButton: View {
    @ObservedObject var voiceManager: VoiceRecognitionManager
    @ObservedObject var commandService: VoiceCommandService
    let onVoiceCommand: (String) -> Void
    
    @State private var isPressed = false
    @State private var isLocked = false
    @State private var dragOffset: CGSize = .zero
    @State private var recordingStartTime: Date?
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var lastInteractionTime: Date?
    @State private var showPulse = false
    @State private var pulseAnimation = false
    
    private let cancelThreshold: CGFloat = -100
    private let lockThreshold: CGFloat = -80  // Slide up to lock
    private let interactionCooldown: TimeInterval = 0.3
    
    var body: some View {
        ZStack {
            // Simplified pulse animation when recording
            if isPressed || isLocked {
                Circle()
                    .stroke(Color.red.opacity(0.25), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseAnimation ? 1.4 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.4)
                    .animation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )
                    .drawingGroup() // Optimize rendering
            }
            
            // Main button
            ZStack {
                // Background with gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: (isPressed || isLocked) ? [Color.red, Color.red.opacity(0.8)] : [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: (isPressed || isLocked) ? 65 : 56, height: (isPressed || isLocked) ? 65 : 56)
                    .shadow(color: (isPressed || isLocked) ? Color.red.opacity(0.5) : Color.blue.opacity(0.3), 
                            radius: (isPressed || isLocked) ? 10 : 5, 
                            x: 0, y: 2)
                
                // Icon or waveform
                if isPressed || isLocked {
                    RecordingWaveform()
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect((isPressed || isLocked) ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isLocked)
            
            // Lock indicator when sliding up
            if dragOffset.height < lockThreshold && isPressed {
                VStack {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.orange))
                        .offset(y: -45)
                    Spacer()
                }
            }
            
            // Cancel indicator when sliding left
            if dragOffset.width < -50 && isPressed {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.red))
                        .offset(x: -45)
                    Spacer()
                }
            }
        }
        .offset(x: isLocked ? 0 : dragOffset.width, y: isLocked ? 0 : dragOffset.height)
        .opacity(dragOffset.width < cancelThreshold ? 0.3 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPressed && !isLocked {
                        // Start recording on press
                        startRecording()
                    }
                    
                    if !isLocked {
                        // Update drag offset for visual feedback
                        dragOffset = value.translation
                        
                        // Check if user is trying to lock (slide up)
                        if value.translation.height < lockThreshold && isPressed {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        
                        // Check if user is trying to cancel (slide left)
                        if value.translation.width < -50 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .onEnded { value in
                    if !isLocked {
                        // Check if should lock (slid up)
                        if value.translation.height < lockThreshold && isPressed {
                            lockRecording()
                        }
                        // Check if cancelled (slid left)
                        else if value.translation.width < cancelThreshold {
                            cancelRecording()
                        } else {
                            // Stop and send recording
                            stopAndSendRecording()
                        }
                        
                        // Reset visual state
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .disabled(commandService.isLoading || (!isLocked && voiceManager.isRecording && !isPressed))
        .onTapGesture {
            // Handle tap when locked to stop
            if isLocked {
                stopAndSendRecording()
            }
        }
        .onAppear {
            pulseAnimation = true
        }
    }
    
    private func startRecording() {
        guard !isPressed else { return }
        
        // Check cooldown to prevent rapid triggers
        if let lastTime = lastInteractionTime {
            let timeSinceLastInteraction = Date().timeIntervalSince(lastTime)
            if timeSinceLastInteraction < interactionCooldown {
                return
            }
        }
        
        // Prevent starting if already recording
        guard !voiceManager.isRecording else { return }
        
        isPressed = true
        recordingStartTime = Date()
        lastInteractionTime = Date()
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Start voice recording
        Task {
            if !voiceManager.hasPermission {
                await voiceManager.requestPermissions()
            }
            if voiceManager.hasPermission {
                voiceManager.startRecording()
                
                // Start duration timer
                await MainActor.run {
                    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        if let startTime = recordingStartTime {
                            recordingDuration = Date().timeIntervalSince(startTime)
                        }
                    }
                }
            }
        }
    }
    
    private func stopAndSendRecording() {
        guard isPressed || isLocked else { return }
        
        isPressed = false
        isLocked = false
        timer?.invalidate()
        timer = nil
        recordingDuration = 0
        recordingStartTime = nil
        lastInteractionTime = Date()
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Stop recording and automatically send
        voiceManager.stopRecording()
        
        // The transcribed text will be processed via onRecordingFinished callback
    }
    
    private func cancelRecording() {
        guard isPressed || isLocked else { return }
        
        isPressed = false
        isLocked = false
        timer?.invalidate()
        timer = nil
        recordingDuration = 0
        recordingStartTime = nil
        
        // Haptic feedback for cancel
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        
        // Stop recording without sending
        voiceManager.stopRecording()
        voiceManager.clearTranscription()
    }
    
    private func lockRecording() {
        guard isPressed else { return }
        
        isLocked = true
        isPressed = false
        
        // Strong haptic for lock
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        // Reset drag offset
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = .zero
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
    @State private var showCancelHint = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var recordingStartTime: Date?
    
    var body: some View {
        VStack(spacing: 0) {
            // Enhanced recording indicator
            if voiceManager.isRecording {
                HStack(spacing: 16) {
                    // Recording timer
                    RecordingTimerView(duration: recordingDuration)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.red))
                        .transition(.scale.combined(with: .opacity))
                    
                    Spacer()
                    
                    // Visual hints with icons
                    HStack(spacing: 12) {
                        // Lock hint
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.gray)
                        
                        Text("•")
                            .foregroundColor(.gray)
                        
                        // Cancel hint
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                            Image(systemName: "arrow.left")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.gray)
                    }
                    .font(.caption)
                    .opacity(0.7)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.3), value: voiceManager.isRecording)
            }
            
            // Input row
            HStack(spacing: 12) {
                // Text input with modern styling
                HStack(spacing: 8) {
                    TextField("Message...", text: $textInput, axis: .vertical)
                        .focused($isTextFieldFocused)
                        .lineLimit(1...6)
                        .font(.body)
                        .onSubmit {
                            onSendMessage()
                        }
                    
                    // Push-to-talk voice button
                    PushToTalkButton(
                        voiceManager: voiceManager,
                        commandService: commandService,
                        onVoiceCommand: onVoiceCommand
                    )
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
        .onReceive(voiceManager.$isRecording) { isRecording in
            if isRecording {
                // Start timer when recording starts
                recordingStartTime = Date()
                recordingDuration = 0
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    if let startTime = recordingStartTime {
                        recordingDuration = Date().timeIntervalSince(startTime)
                    }
                }
            } else {
                // Stop timer when recording stops
                recordingTimer?.invalidate()
                recordingTimer = nil
                recordingDuration = 0
                recordingStartTime = nil
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

// Confirmation Actions View for bulk operations
struct ConfirmationActionsView: View {
    let operationType: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text("⚠️ Confirmation Required")
                .font(.caption)
                .foregroundColor(.orange)
                .textCase(.uppercase)
                .tracking(0.5)
            
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                        Text("Cancel")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(20)
                }
                
                Button(action: onConfirm) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                        Text("Confirm")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(20)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .orange.opacity(0.2), radius: 8, y: 2)
        )
    }
}

#Preview {
    ConversationView(
        commandService: VoiceCommandService(),
        voiceManager: VoiceRecognitionManager()
    )
}