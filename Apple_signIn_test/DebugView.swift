//
//  DebugView.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import SwiftUI
import os.log

struct DebugView: View {
    @ObservedObject var calendarManager: GoogleCalendarManager
    @ObservedObject var commandService: VoiceCommandService
    @ObservedObject var authManager: AuthenticationManager
    @State private var logEntries: [String] = []
    @State private var showingLogs = false
    
    var body: some View {
        NavigationView {
            List {
                // Calendar Status Section
                Section("Calendar Status") {
                    HStack {
                        Image(systemName: calendarManager.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(calendarManager.isConnected ? .green : .red)
                        Text("Calendar Connected")
                        Spacer()
                        Text(calendarManager.isConnected ? "Yes" : "No")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Sync Status")
                        Spacer()
                        Text(calendarManager.syncStatus)
                            .foregroundColor(.secondary)
                    }
                    
                    if let error = calendarManager.errorMessage {
                        HStack {
                            Text("Calendar Error")
                            Spacer()
                            Text(error)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                // Authentication Status Section
                Section("Authentication Status") {
                    HStack {
                        Text("Firebase User")
                        Spacer()
                        Text(authManager.isSignedIn ? "Signed In" : "Not Signed In")
                            .foregroundColor(.secondary)
                    }
                    
                    if let user = authManager.user {
                        HStack {
                            Text("User ID")
                            Spacer()
                            Text(user.uid)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(user.email ?? "No email")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Providers")
                            Spacer()
                            Text(authManager.linkedProviders.joined(separator: ", "))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Voice Command Status Section
                Section("Voice Command Status") {
                    HStack {
                        Text("Last Command")
                        Spacer()
                        Text(commandService.lastResponse?.message ?? "None")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if let error = commandService.errorMessage {
                        HStack {
                            Text("Command Error")
                            Spacer()
                            Text(error)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                // Debug Actions Section
                Section("Debug Actions") {
                    Button("Test Calendar Connection") {
                        Task {
                            await calendarManager.connectGoogleCalendar()
                        }
                    }
                    
                    Button("Test Google Sign-In") {
                        calendarManager.signInWithGoogleForCalendar()
                    }
                    
                    Button("Clear All Errors") {
                        calendarManager.errorMessage = nil
                        commandService.errorMessage = nil
                    }
                    
                    Button("Show Console Logs") {
                        showingLogs = true
                    }
                }
                
                // Network Configuration Section
                Section("Network Configuration") {
                    HStack {
                        Text("Voice Command URL")
                        Spacer()
                        Text("https://us-central1-learning-auth-e6ea2.cloudfunctions.net/processVoiceCommand")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Google Client ID")
                        Spacer()
                        Text("73003602008-0jgk8u5h4s4pdu3010utqovs0kb14fgb.apps.googleusercontent.com")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Debug Info")
            .sheet(isPresented: $showingLogs) {
                LogViewer()
            }
        }
    }
}

struct LogViewer: View {
    @State private var logs: [String] = []
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(logs, id: \.self) { log in
                    Text(log)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Console Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        refreshLogs()
                    }
                }
            }
            .onAppear {
                refreshLogs()
            }
        }
    }
    
    private func refreshLogs() {
        isRefreshing = true
        // In a real app, you would fetch logs from the system
        // For now, we'll show a placeholder
        logs = [
            "Debug logs will appear here when available",
            "Check Xcode console for detailed logs",
            "Use Console.app to view system logs"
        ]
        isRefreshing = false
    }
}

#Preview {
    DebugView(
        calendarManager: GoogleCalendarManager(),
        commandService: VoiceCommandService(),
        authManager: AuthenticationManager()
    )
} 