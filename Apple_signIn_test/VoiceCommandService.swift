//
//  VoiceCommandService.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions
import GoogleSignIn
import os.log

struct VoiceCommandRequest: Codable {
    let command: String
}

struct VoiceCommandResponse: Codable {
    let success: Bool
    let message: String
    let appointment: AppointmentData?
    let conversational: Bool? // New: indicates this is a conversational response
    let threadId: String? // New: conversation thread ID for context
    let error: String? // New: detailed error information
}

struct AppointmentData: Codable, Identifiable {
    let id: String
    let title: String
    let date: String
    let time: String
    let duration: Int? // in minutes
    let attendees: [String]?
    let meetingLink: String?
    let location: String?
    let description: String?
    let type: String? // "personal_event" or nil (default to appointment)
    let status: String? // "scheduled", "cancelled", etc.
    let googleCalendarEventId: String? // Google Calendar event ID for synced events
    let calendarSynced: Bool? // Whether the event is synced to Google Calendar
    
    // Computed property to determine if this is a personal event
    var isPersonalEvent: Bool {
        return type == "personal_event"
    }
    
    // Computed property for display type
    var displayType: String {
        return isPersonalEvent ? "Personal Event" : "Appointment"
    }
    
    // Computed property to check if cancelled
    var isCancelled: Bool {
        return status == "cancelled"
    }
}

@MainActor
class VoiceCommandService: ObservableObject {
    @Published var isLoading = false
    @Published var lastResponse: VoiceCommandResponse?
    @Published var errorMessage: String?
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var currentThreadId: String?
    
    // New: Conversation message structure
    struct ConversationMessage: Identifiable, Codable {
        let id: UUID
        let content: String
        let isUser: Bool
        let timestamp: Date
        let appointment: AppointmentData?
        
        init(content: String, isUser: Bool, appointment: AppointmentData? = nil) {
            self.id = UUID()
            self.content = content
            self.isUser = isUser
            self.timestamp = Date()
            self.appointment = appointment
        }
    }
    
    private lazy var functions = Functions.functions()
    private let logger = Logger(subsystem: "com.apple.signin.test", category: "VoiceCommandService")
    
    func processCommand(_ command: String) async {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            logger.warning("Empty command received")
            errorMessage = "Command cannot be empty"
            return
        }
        
        logger.info("Processing conversational command: '\(trimmedCommand)'")
        isLoading = true
        errorMessage = nil
        
        // Add user message to conversation history immediately
        let userMessage = ConversationMessage(content: trimmedCommand, isUser: true)
        conversationHistory.append(userMessage)
        
        do {
            // Ensure user is authenticated
            guard let currentUser = Auth.auth().currentUser else {
                logger.error("No authenticated user found")
                errorMessage = "You must be signed in to use voice commands"
                return
            }
            
            // Validate Firebase Auth token before making function call
            do {
                let tokenResult = try await currentUser.getIDTokenResult(forcingRefresh: false)
                let now = Date()
                
                // Check if token expires within next 5 minutes (300 seconds)
                if tokenResult.expirationDate.timeIntervalSince(now) < 300 {
                    logger.info("Firebase token expires soon, refreshing...")
                    _ = try await currentUser.getIDTokenResult(forcingRefresh: true)
                    logger.info("Firebase token refreshed successfully")
                }
            } catch {
                logger.error("Firebase token validation failed: \(error.localizedDescription)")
                errorMessage = "Authentication session expired. Please sign in again."
                return
            }
            
            logger.info("Current user authenticated: \(currentUser.uid)")
            logger.info("Calling Firebase function with conversational command: '\(trimmedCommand)'")
            
            let response = try await callFirebaseFunctionWithRetry(command: trimmedCommand)
            logger.info("Conversational response: success=\(response.success), message='\(response.message)'")
            
            lastResponse = response
            
            // Store thread ID if provided
            if let threadId = response.threadId {
                currentThreadId = threadId
                logger.info("Updated conversation thread ID: \(threadId)")
            }
            
            // Add assistant response to conversation history
            let assistantMessage = ConversationMessage(
                content: response.message,
                isUser: false,
                appointment: response.appointment
            )
            conversationHistory.append(assistantMessage)
            
            if !response.success {
                logger.warning("Conversational command failed: \(response.message)")
                errorMessage = response.error ?? response.message
            } else {
                logger.info("Conversational command processed successfully")
                if let appointment = response.appointment {
                    logger.info("Appointment data received: \(appointment.title)")
                }
                if response.conversational == true {
                    logger.info("Conversational context maintained with thread: \(self.currentThreadId ?? "unknown")")
                }
            }
            
        } catch {
            logger.error("Voice command processing failed: \(error.localizedDescription)")
            
            // Provide more specific error messages
            if let urlError = error as? URLError {
                switch urlError.code {
                case .badServerResponse:
                    errorMessage = "Server returned invalid response"
                case .cannotConnectToHost:
                    errorMessage = "Cannot connect to voice command service"
                case .networkConnectionLost:
                    errorMessage = "Network connection lost"
                default:
                    if urlError.code.rawValue == 400 {
                        errorMessage = "Invalid command format. Please try again."
                    } else {
                        errorMessage = "Network error: \(error.localizedDescription)"
                    }
                }
            } else {
                errorMessage = "Failed to process command: \(error.localizedDescription)"
            }
            lastResponse = nil
        }
        
        isLoading = false
        logger.info("Command processing completed")
    }
    
    private func callFirebaseFunctionWithRetry(command: String, maxRetries: Int = 2) async throws -> VoiceCommandResponse {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await callFirebaseFunction(command: command)
            } catch {
                lastError = error
                logger.warning("Firebase function call attempt \(attempt) failed: \(error.localizedDescription)")
                
                // Check if it's an authentication error that we should retry
                if let functions_error = error as NSError?, 
                   functions_error.domain == "FIRFunctionsErrorDomain",
                   functions_error.code == 16 { // UNAUTHENTICATED
                    
                    if attempt < maxRetries {
                        logger.info("Authentication error detected, refreshing token and retrying...")
                        
                        // Try to refresh Firebase Auth token
                        if let currentUser = Auth.auth().currentUser {
                            do {
                                _ = try await currentUser.getIDTokenResult(forcingRefresh: true)
                                logger.info("Token refreshed for retry attempt \(attempt + 1)")
                                continue // Retry the call
                            } catch {
                                logger.error("Token refresh failed: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                // For other errors, don't retry
                if attempt >= maxRetries {
                    break
                }
            }
        }
        
        // If we get here, all retries failed
        throw lastError ?? NSError(domain: "VoiceCommandServiceError", code: -1, 
                                  userInfo: [NSLocalizedDescriptionKey: "All retry attempts failed"])
    }
    
    private func callFirebaseFunction(command: String) async throws -> VoiceCommandResponse {
        logger.info("Calling Firebase callable function: processVoiceCommand")
        
        // Prepare data for Firebase callable function
        var data: [String: Any] = [
            "command": command,
            "timezone": TimeZone.current.identifier
        ]
        
        // Add Google Calendar access token if available
        if let currentGoogleUser = GIDSignIn.sharedInstance.currentUser {
            let accessToken = currentGoogleUser.accessToken.tokenString
            if !accessToken.isEmpty {
                data["googleCalendarToken"] = accessToken
                logger.info("Including Google Calendar access token in request")
                
                // Check if token is about to expire and refresh if needed
                let expirationDate = currentGoogleUser.accessToken.expirationDate
                if let expirationDate = expirationDate {
                    let timeUntilExpiry = expirationDate.timeIntervalSinceNow
                    if timeUntilExpiry < 300 { // Less than 5 minutes until expiry
                        logger.info("Google access token expires soon, refreshing...")
                        do {
                            try await currentGoogleUser.refreshTokensIfNeeded()
                            // Get the refreshed token
                            let refreshedToken = currentGoogleUser.accessToken.tokenString
                            data["googleCalendarToken"] = refreshedToken
                            logger.info("Google access token refreshed successfully")
                        } catch {
                            logger.warning("Failed to refresh Google access token: \(error.localizedDescription)")
                            // Continue with existing token
                        }
                    }
                }
            } else {
                logger.warning("Google user exists but access token is empty")
            }
        } else {
            logger.info("No Google user signed in, proceeding without calendar token")
        }
        
        logger.info("Function data keys: \(data.keys)")
        
        // Call the Firebase function with proper concurrency handling
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            functions.httpsCallable("processVoiceCommand").call(data) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result, let responseData = result.data as? [String: Any] {
                    continuation.resume(returning: responseData)
                } else {
                    continuation.resume(throwing: NSError(domain: "VoiceCommandServiceError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format from server"]))
                }
            }
        }
        
        logger.info("Firebase function completed successfully")
        logger.info("Raw result data: \(result)")
        
        // Parse the response
        let responseData = result
        
        // Convert to our response structure
        let success: Bool = responseData["success"] as? Bool ?? false
        let message: String = responseData["message"] as? String ?? "Unknown response"
        
        // Parse appointment data if present
        var appointmentData: AppointmentData? = nil
        if let appointmentDict = responseData["appointment"] as? [String: Any] {
            // Convert appointment dictionary to AppointmentData with better fallback handling
            let id = appointmentDict["id"] as? String ?? ""
            let rawTitle = appointmentDict["title"] as? String ?? ""
            let date = appointmentDict["date"] as? String ?? ""
            let time = appointmentDict["time"] as? String ?? ""
            let duration = appointmentDict["duration"] as? Int
            let attendees = appointmentDict["attendees"] as? [String]
            let meetingLink = appointmentDict["meetingLink"] as? String
            let location = appointmentDict["location"] as? String
            let description = appointmentDict["description"] as? String
            let type = appointmentDict["type"] as? String
            let status = appointmentDict["status"] as? String
            let googleCalendarEventId = appointmentDict["googleCalendarEventId"] as? String
            let calendarSynced = appointmentDict["calendarSynced"] as? Bool
            
            // Generate fallback title if empty or missing
            let title: String
            if rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let validAttendees = attendees?.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), !validAttendees.isEmpty {
                    if validAttendees.count == 1 {
                        title = "Meeting with \(validAttendees[0])"
                    } else if validAttendees.count == 2 {
                        title = "Meeting with \(validAttendees.joined(separator: " and "))"
                    } else {
                        title = "Meeting with \(validAttendees[0]) and \(validAttendees.count - 1) others"
                    }
                } else {
                    title = time.isEmpty ? "Appointment" : "Appointment at \(time)"
                }
            } else {
                title = rawTitle
            }
            
            appointmentData = AppointmentData(
                id: id,
                title: title,
                date: date,
                time: time,
                duration: duration,
                attendees: attendees?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, // Filter out empty attendees
                meetingLink: meetingLink?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : meetingLink,
                location: location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : location,
                description: description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : description,
                type: type,
                status: status,
                googleCalendarEventId: googleCalendarEventId,
                calendarSynced: calendarSynced
            )
        }
        
        return VoiceCommandResponse(
            success: success,
            message: message,
            appointment: appointmentData,
            conversational: responseData["conversational"] as? Bool,
            threadId: responseData["threadId"] as? String,
            error: responseData["error"] as? String
        )
    }
    
    func clearLastResponse() {
        logger.info("Clearing last response")
        lastResponse = nil
        errorMessage = nil
    }
    
    // New: Clear conversation history and start fresh
    func clearConversation() {
        logger.info("Clearing conversation history")
        conversationHistory.removeAll()
        currentThreadId = nil
        lastResponse = nil
        errorMessage = nil
    }
    
    // New: Process text input (for chat interface)
    func processTextCommand(_ text: String) async {
        await processCommand(text)
    }
    
    // New: Get recent conversation for display
    func getRecentMessages(limit: Int = 10) -> [ConversationMessage] {
        return Array(conversationHistory.suffix(limit))
    }
    
    // Debug function to test a simple command
    func testSimpleCommand() async {
        await processCommand("test")
    }
}