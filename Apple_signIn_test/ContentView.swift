//
//  ContentView.swift
//  Apple_signIn_test
//
//  Created by Agyn Bolatov on 30.07.2025.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var calendarManager = GoogleCalendarManager()
    
    var body: some View {
        if authManager.isSignedIn {
            // Show the main Voice Calendar interface when signed in
            VoiceCalendarView()
                .environmentObject(authManager)
                .environmentObject(calendarManager)
                .onAppear {
                    // Connect the managers
                    authManager.calendarManager = calendarManager
                }
        } else {
            // Show sign in view when not authenticated
            SignInView(authManager: authManager, calendarManager: calendarManager)
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

#Preview {
    ContentView()
}
