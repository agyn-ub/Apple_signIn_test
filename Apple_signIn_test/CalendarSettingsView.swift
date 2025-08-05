//
//  CalendarSettingsView.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import SwiftUI

struct CalendarSettingsView: View {
    @ObservedObject var calendarManager: GoogleCalendarManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // Google Calendar Section
                Section(header: Text("Google Calendar")) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Google Calendar")
                                .font(.headline)
                            
                            Text(calendarManager.syncStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if calendarManager.isConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if calendarManager.isConnected {
                        Button("Refresh Status") {
                            Task {
                                await calendarManager.connectGoogleCalendar()
                            }
                        }
                        .disabled(calendarManager.isLoading)
                        
                        Button("Disconnect") {
                            calendarManager.disconnectFromGoogleCalendar()
                        }
                        .foregroundColor(.red)
                    } else {
                        // Check if user needs Google Sign-In
                        if calendarManager.syncStatus == "Google Sign-In required" {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Google Sign-In Required")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                
                                Text("Calendar access requires a Google account. You signed in with Apple, but Google Calendar needs Google Sign-In.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button("Sign in with Google") {
                                    calendarManager.signInWithGoogleForCalendar()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(calendarManager.isLoading)
                            }
                            .padding(.vertical, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Button("Sign in with Google for Calendar") {
                                    calendarManager.signInWithGoogleForCalendar()
                                }
                                .disabled(calendarManager.isLoading)
                                
                                Text("This will sign you in with Google and grant calendar access in one step.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // Show retry button if there was an error
                                if calendarManager.errorMessage != nil {
                                    Button("Try Again") {
                                        calendarManager.signInWithGoogleForCalendar()
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.orange)
                                    .disabled(calendarManager.isLoading)
                                }
                            }
                        }
                    }
                }
                
                // Voice Commands Section
                Section(header: Text("Voice Commands"), 
                       footer: Text("Supported voice commands for managing your calendar")) {
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VoiceCommandExample(
                            command: "Schedule a meeting with John tomorrow at 2 PM for 30 minutes",
                            description: "Create a new appointment"
                        )
                        
                        VoiceCommandExample(
                            command: "Cancel my doctor appointment on Friday",
                            description: "Cancel an existing appointment"
                        )
                        
                        VoiceCommandExample(
                            command: "Show me my appointments for this week",
                            description: "View upcoming appointments"
                        )
                        
                        VoiceCommandExample(
                            command: "Set my availability to Monday to Friday 9 AM to 5 PM",
                            description: "Configure availability"
                        )
                    }
                    .padding(.vertical, 8)
                }
                
                // App Information Section
                Section(header: Text("App Information")) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Voice Calendar")
                                .font(.headline)
                            Text("Version 1.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    
                    Button("Privacy Policy") {
                        // Open privacy policy
                        if let url = URL(string: "https://example.com/privacy") {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    Button("Terms of Service") {
                        // Open terms of service
                        if let url = URL(string: "https://example.com/terms") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if calendarManager.isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            
                            Text("Connecting to Google Calendar...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
            .onAppear {
                // Check calendar access status
                Task {
                    await calendarManager.connectGoogleCalendar()
                }
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { calendarManager.errorMessage != nil },
                set: { _ in calendarManager.errorMessage = nil }
            )) {
                Button("OK") {
                    calendarManager.errorMessage = nil
                }
            } message: {
                if let errorMessage = calendarManager.errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
}

struct VoiceCommandExample: View {
    let command: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\"\(command)\"")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    CalendarSettingsView(calendarManager: GoogleCalendarManager())
} 