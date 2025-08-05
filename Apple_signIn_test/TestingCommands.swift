//
//  TestingCommands.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import Foundation

/// Collection of test voice commands for manual testing
enum TestVoiceCommands {
    static let schedulingCommands = [
        "Schedule a meeting with John tomorrow at 2 PM for 30 minutes",
        "Book a call with Sarah next Tuesday at 10 AM",
        "Set up a team standup for Monday at 9 AM recurring weekly",
        "Schedule a doctor appointment on Friday at 3 PM",
        "Create a meeting with the marketing team tomorrow at 11 AM for one hour"
    ]
    
    static let cancellationCommands = [
        "Cancel my doctor appointment on Friday",
        "Remove the team meeting tomorrow",
        "Delete my call with Sarah next Tuesday",
        "Cancel all meetings for today"
    ]
    
    static let queryCommands = [
        "Show me my appointments for this week",
        "What meetings do I have today?",
        "List my appointments for tomorrow",
        "Show my calendar for next Monday",
        "What's my schedule for the rest of the week?"
    ]
    
    static let availabilityCommands = [
        "Set my availability to Monday to Friday 9 AM to 5 PM",
        "Block my calendar tomorrow from 2 PM to 4 PM",
        "Mark me as busy on Thursday afternoon",
        "Set working hours to 8 AM to 6 PM weekdays",
        "I'm unavailable next week"
    ]
    
    static let modificationCommands = [
        "Move my meeting with John to 3 PM",
        "Reschedule tomorrow's standup to 10 AM",
        "Change the duration of my doctor appointment to 45 minutes",
        "Add Sarah to my marketing meeting",
        "Update the location of tomorrow's meeting to Conference Room A"
    ]
    
    /// All test commands combined
    static let allCommands = schedulingCommands + cancellationCommands + queryCommands + availabilityCommands + modificationCommands
    
    /// Get a random test command
    static func randomCommand() -> String {
        return allCommands.randomElement() ?? "Show me my appointments for today"
    }
    
    /// Get commands by category
    static func commands(for category: CommandCategory) -> [String] {
        switch category {
        case .scheduling:
            return schedulingCommands
        case .cancellation:
            return cancellationCommands
        case .query:
            return queryCommands
        case .availability:
            return availabilityCommands
        case .modification:
            return modificationCommands
        }
    }
}

enum CommandCategory: String, CaseIterable {
    case scheduling = "Scheduling"
    case cancellation = "Cancellation"
    case query = "Query"
    case availability = "Availability"
    case modification = "Modification"
    
    var description: String {
        switch self {
        case .scheduling:
            return "Create new appointments and meetings"
        case .cancellation:
            return "Cancel or delete existing appointments"
        case .query:
            return "View and search appointments"
        case .availability:
            return "Set working hours and availability"
        case .modification:
            return "Update existing appointments"
        }
    }
}

/// Testing scenarios for comprehensive app testing
struct TestingScenario {
    let name: String
    let description: String
    let steps: [String]
    let expectedOutcome: String
}

extension TestingScenario {
    static let voiceRecognitionTest = TestingScenario(
        name: "Voice Recognition",
        description: "Test basic voice recording and transcription",
        steps: [
            "Tap the microphone button",
            "Speak clearly: 'Schedule a meeting with John tomorrow at 2 PM'",
            "Wait for transcription to appear",
            "Verify text accuracy"
        ],
        expectedOutcome: "Speech should be accurately transcribed and displayed"
    )
    
    static let firebaseFunctionTest = TestingScenario(
        name: "Firebase Functions Integration",
        description: "Test command processing through Firebase Functions",
        steps: [
            "Record a voice command",
            "Tap 'Send Command'",
            "Wait for Firebase response",
            "Check response message and appointment data"
        ],
        expectedOutcome: "Command should be processed and response displayed"
    )
    
    static let googleCalendarOAuthTest = TestingScenario(
        name: "Google Calendar OAuth",
        description: "Test Google Calendar connection flow",
        steps: [
            "Go to Settings",
            "Tap 'Connect to Google Calendar'",
            "Complete OAuth flow in browser",
            "Return to app and verify connection status"
        ],
        expectedOutcome: "Calendar should show as connected with sync status"
    )
    
    static let appointmentDisplayTest = TestingScenario(
        name: "Appointment Display",
        description: "Test fetching and displaying appointments",
        steps: [
            "Create an appointment via voice command",
            "Go to Appointments list",
            "Verify appointment appears",
            "Tap appointment for details"
        ],
        expectedOutcome: "Appointments should display with all details and meeting links"
    )
    
    static let errorHandlingTest = TestingScenario(
        name: "Error Handling",
        description: "Test network and permission errors",
        steps: [
            "Turn off internet connection",
            "Try to send a voice command",
            "Deny microphone permission",
            "Try to record voice"
        ],
        expectedOutcome: "Appropriate error messages should be shown"
    )
    
    static let offlineBehaviorTest = TestingScenario(
        name: "Offline Behavior",
        description: "Test app behavior without internet",
        steps: [
            "Disconnect from internet",
            "Try to record voice (should work)",
            "Try to send command (should show error)",
            "Try to sync calendar (should show error)"
        ],
        expectedOutcome: "Voice recording works offline, network operations show appropriate errors"
    )
    
    static let allScenarios = [
        voiceRecognitionTest,
        firebaseFunctionTest,
        googleCalendarOAuthTest,
        appointmentDisplayTest,
        errorHandlingTest,
        offlineBehaviorTest
    ]
}