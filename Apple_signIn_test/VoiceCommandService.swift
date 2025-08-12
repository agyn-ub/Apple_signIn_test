//
//  VoiceCommandService.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions
import os.log

struct VoiceCommandRequest: Codable {
    let command: String
}

struct VoiceCommandResponse: Codable {
    let success: Bool
    let message: String
    let appointment: AppointmentData?
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
}

@MainActor
class VoiceCommandService: ObservableObject {
    @Published var isLoading = false
    @Published var lastResponse: VoiceCommandResponse?
    @Published var errorMessage: String?
    
    private lazy var functions = Functions.functions()
    private let logger = Logger(subsystem: "com.apple.signin.test", category: "VoiceCommandService")
    
    func processCommand(_ command: String) async {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            logger.warning("Empty command received")
            errorMessage = "Command cannot be empty"
            return
        }
        
        logger.info("Processing voice command: '\(trimmedCommand)'")
        isLoading = true
        errorMessage = nil
        
        do {
            // Ensure user is authenticated
            guard let currentUser = Auth.auth().currentUser else {
                logger.error("No authenticated user found")
                errorMessage = "You must be signed in to use voice commands"
                return
            }
            
            logger.info("Current user authenticated: \(currentUser.uid)")
            logger.info("Calling Firebase function with command: '\(trimmedCommand)'")
            
            let response = try await callFirebaseFunction(command: trimmedCommand)
            logger.info("Voice command response: success=\(response.success), message='\(response.message)'")
            
            lastResponse = response
            
            if !response.success {
                logger.warning("Voice command failed: \(response.message)")
                errorMessage = response.message
            } else {
                logger.info("Voice command processed successfully")
                if let appointment = response.appointment {
                    logger.info("Appointment data received: \(appointment.title)")
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
    
    private func callFirebaseFunction(command: String) async throws -> VoiceCommandResponse {
        logger.info("Calling Firebase callable function: processVoiceCommand")
        
        // Prepare data for Firebase callable function
        let data: [String: Any] = [
            "command": command,
            "timezone": TimeZone.current.identifier
        ]
        
        logger.info("Function data: \(data)")
        
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
            // Convert appointment dictionary to AppointmentData
            let id = appointmentDict["id"] as? String ?? ""
            let title = appointmentDict["title"] as? String ?? ""
            let date = appointmentDict["date"] as? String ?? ""
            let time = appointmentDict["time"] as? String ?? ""
            let duration = appointmentDict["duration"] as? Int
            let attendees = appointmentDict["attendees"] as? [String]
            let meetingLink = appointmentDict["meetingLink"] as? String
            let location = appointmentDict["location"] as? String
            let description = appointmentDict["description"] as? String
            
            appointmentData = AppointmentData(
                id: id,
                title: title,
                date: date,
                time: time,
                duration: duration,
                attendees: attendees,
                meetingLink: meetingLink,
                location: location,
                description: description
            )
        }
        
        return VoiceCommandResponse(
            success: success,
            message: message,
            appointment: appointmentData
        )
    }
    
    func clearLastResponse() {
        logger.info("Clearing last response")
        lastResponse = nil
        errorMessage = nil
    }
    
    // Debug function to test a simple command
    func testSimpleCommand() async {
        await processCommand("test")
    }
}