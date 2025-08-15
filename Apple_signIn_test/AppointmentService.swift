//
//  AppointmentService.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class AppointmentService: ObservableObject {
    @Published var appointments: [AppointmentData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    
    func fetchAppointments() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let snapshot = try await db.collection("users").document(userId).collection("appointments").getDocuments()
            
            let fetchedAppointments = snapshot.documents.compactMap { document -> AppointmentData? in
                do {
                    let appointmentData = try document.data(as: AppointmentData.self)
                    
                    // Filter out cancelled appointments
                    if appointmentData.status == "cancelled" {
                        return nil
                    }
                    
                    // Generate fallback title if empty or missing
                    let finalTitle: String
                    if appointmentData.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let validAttendees = appointmentData.attendees?.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), !validAttendees.isEmpty {
                            if validAttendees.count == 1 {
                                finalTitle = "Meeting with \(validAttendees[0])"
                            } else if validAttendees.count == 2 {
                                finalTitle = "Meeting with \(validAttendees.joined(separator: " and "))"
                            } else {
                                finalTitle = "Meeting with \(validAttendees[0]) and \(validAttendees.count - 1) others"
                            }
                        } else {
                            finalTitle = appointmentData.time.isEmpty ? "Appointment" : "Appointment at \(appointmentData.time)"
                        }
                    } else {
                        finalTitle = appointmentData.title
                    }
                    
                    // Clean up attendees list
                    let cleanAttendees = appointmentData.attendees?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    
                    return AppointmentData(
                        id: appointmentData.id.isEmpty ? document.documentID : appointmentData.id,
                        title: finalTitle,
                        date: appointmentData.date,
                        time: appointmentData.time,
                        duration: appointmentData.duration,
                        attendees: cleanAttendees?.isEmpty == true ? nil : cleanAttendees,
                        meetingLink: appointmentData.meetingLink?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : appointmentData.meetingLink,
                        location: appointmentData.location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : appointmentData.location,
                        description: appointmentData.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : appointmentData.description,
                        type: appointmentData.type,
                        status: appointmentData.status,
                        googleCalendarEventId: appointmentData.googleCalendarEventId,
                        calendarSynced: appointmentData.calendarSynced
                    )
                } catch {
                    errorMessage = "Failed to parse appointment data: \(error.localizedDescription)"
                    return nil
                }
            }
            
            appointments = fetchedAppointments.sorted { appointment1, appointment2 in
                // Sort by date and time
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                
                let date1 = formatter.date(from: "\(appointment1.date) \(appointment1.time)") ?? Date.distantPast
                let date2 = formatter.date(from: "\(appointment2.date) \(appointment2.time)") ?? Date.distantPast
                
                return date1 < date2
            }
            
        } catch {
            errorMessage = "Failed to fetch appointments: \(error.localizedDescription)"
            appointments = []
        }
        
        isLoading = false
    }
    
    func addAppointment(_ appointment: AppointmentData) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            _ = try db.collection("users").document(userId).collection("appointments").addDocument(from: appointment)
            // Refresh the list
            await fetchAppointments()
        } catch {
            errorMessage = "Failed to add appointment: \(error.localizedDescription)"
        }
    }
    
    func deleteAppointment(_ appointmentId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            try await db.collection("users").document(userId).collection("appointments").document(appointmentId).delete()
            // Refresh the list
            await fetchAppointments()
        } catch {
            errorMessage = "Failed to delete appointment: \(error.localizedDescription)"
        }
    }
    
    func updateAppointment(_ appointment: AppointmentData) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            try db.collection("users").document(userId).collection("appointments").document(appointment.id).setData(from: appointment)
            // Refresh the list
            await fetchAppointments()
        } catch {
            errorMessage = "Failed to update appointment: \(error.localizedDescription)"
        }
    }
}

