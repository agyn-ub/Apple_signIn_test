//
//  ContentView.swift
//  Apple_signIn_test
//
//  Created by Agyn Bolatov on 30.07.2025.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import os.log

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var calendarManager = GoogleCalendarManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastSceneValidation: Date? // Track last validation time
    
    var body: some View {
        Group {
            if authManager.isLoading && !authManager.isSignedIn {
                // Show loading state only during initial authentication check
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                    
                    Text("Checking authentication...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Please wait")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
            } else if authManager.isSignedIn {
                // Show the conversation interface when signed in
                NavigationView {
                    MainConversationView()
                        .environmentObject(authManager)
                        .environmentObject(calendarManager)
                        .onAppear {
                            // Connect the managers
                            authManager.calendarManager = calendarManager
                        }
                }
            } else {
                // Show sign in view when not authenticated
                SignInView(authManager: authManager, calendarManager: calendarManager)
            }
        }
        .onAppear {
            // Connect the managers once at startup
            authManager.calendarManager = calendarManager
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && authManager.isSignedIn {
                // Update activity and check for timeout
                authManager.updateActivity()
                authManager.handleSessionTimeout()
                
                // Only validate session if significant time has passed since last validation
                let now = Date()
                let shouldValidate = lastSceneValidation == nil || 
                                   now.timeIntervalSince(lastSceneValidation!) > 60 // At least 60 seconds
                
                if shouldValidate {
                    lastSceneValidation = now
                    Task {
                        await authManager.validateSessionOnResume()
                    }
                }
            }
        }
    }
}

struct SignInView: View {
    @ObservedObject var authManager: AuthenticationManager
    @ObservedObject var calendarManager: GoogleCalendarManager
    @State private var showingCalendarPrompt = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // App Header
                VStack(spacing: 16) {
                    Image(systemName: "mic.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.blue)
                    
                    Text("Voice Calendar")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Manage your calendar with voice commands")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Sign In Options
                VStack(spacing: 20) {
                    Text("Choose your sign in method")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // Apple Sign In Button
                    VStack(spacing: 8) {
                        Button(action: {
                            authManager.signInWithApple()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "applelogo")
                                    .foregroundColor(.white)
                                    .font(.title3)
                                Text("Continue with Apple")
                                    .foregroundColor(.white)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black)
                            .cornerRadius(8)
                        }
                        .disabled(authManager.isLoading)
                    }
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.3))
                        Text("or")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.3))
                    }
                    
                    // Google Sign In Button
                    VStack(spacing: 8) {
                        Button(action: {
                            authManager.signInWithGoogle()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .foregroundColor(.white)
                                    .font(.title3)
                                Text("Continue with Google")
                                    .foregroundColor(.white)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(8)
                        }
                        .disabled(authManager.isLoading)
                        
                        Text("Includes immediate calendar access")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Loading State
                if authManager.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        Text("Signing in...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                
                // Error Display
                if let errorMessage = authManager.errorMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Sign In Error")
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                        
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Try Again") {
                            authManager.clearError()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Privacy Note
                VStack(spacing: 4) {
                    Text("By signing in, you agree to our Terms of Service")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Your data is secure and encrypted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .navigationBarHidden(true)
        }
        .onAppear {
            // Connect the managers
            authManager.calendarManager = calendarManager
        }
        .alert("Calendar Access", isPresented: $showingCalendarPrompt) {
            Button("Connect Calendar") {
                calendarManager.linkGoogleAccountAfterApple()
            }
            Button("Maybe Later", role: .cancel) { }
        } message: {
            Text("Would you like to connect your Google Calendar for full voice command functionality?")
        }
        .onChange(of: authManager.isSignedIn) { oldValue, isSignedIn in
            if isSignedIn && !authManager.linkedProviders.contains("google.com") {
                // Show calendar prompt for Apple-only users after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showingCalendarPrompt = true
                }
            }
        }
    }
}

// Main conversation view that replaces VoiceCalendarView
struct MainConversationView: View {
    @StateObject private var voiceManager = VoiceRecognitionManager()
    @StateObject private var commandService = VoiceCommandService()
    @StateObject private var appointmentService = AppointmentService()
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var calendarManager: GoogleCalendarManager
    
    @State private var showingAppointments = false
    
    private let logger = Logger(subsystem: "com.apple.signin.test", category: "MainConversationView")
    
    var body: some View {
        ZStack {
            ConversationView(
                commandService: commandService,
                voiceManager: voiceManager
            )
            .navigationBarTitleDisplayMode(.inline)
            
            // Floating calendar button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showingAppointments = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 56, height: 56)
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            
                            Image(systemName: "calendar")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 100) // Above the input area
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // Google Calendar connection status indicator
                Button(action: {
                    if !calendarManager.isConnected {
                        calendarManager.signInWithGoogleForCalendar()
                    }
                }) {
                    ZStack {
                        // Google-style icon with colors
                        if calendarManager.isConnected {
                            // Colorful Google-style indicator when connected
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 66/255, green: 133/255, blue: 244/255),  // Google Blue
                                            Color(red: 234/255, green: 67/255, blue: 53/255),   // Google Red
                                            Color(red: 251/255, green: 188/255, blue: 5/255),   // Google Yellow
                                            Color(red: 52/255, green: 168/255, blue: 83/255)    // Google Green
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "g.circle")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            // Gray indicator when not connected
                            Circle()
                                .fill(Color(.systemGray4))
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "g.circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    .scaleEffect(calendarManager.isLoading ? 0.9 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: calendarManager.isLoading)
                }
                .disabled(calendarManager.isLoading)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                // Sign Out button - now visible
                Button("Sign Out") {
                    authManager.signOut()
                }
                .foregroundColor(.red)
            }
        }
        .sheet(isPresented: $showingAppointments) {
            AppointmentsListView(appointmentService: appointmentService)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingAppointments = false
                        }
                    }
                }
        }
        .task {
            logger.info("MainConversationView setup started")
            
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
            
            // Only check calendar status, don't automatically connect
            logger.info("Checking calendar access status")
            await calendarManager.checkServerStoredAuth()
            
            logger.info("MainConversationView setup completed")
        }
    }
}

#Preview {
    ContentView()
}
