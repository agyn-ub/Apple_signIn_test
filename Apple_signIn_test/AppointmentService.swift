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
            
            let fetchedAppointments = try snapshot.documents.map { document in
                let appointmentData = try document.data(as: AppointmentData.self)
                // Ensure the document ID is set
                if appointmentData.id.isEmpty {
                    return AppointmentData(
                        id: document.documentID,
                        title: appointmentData.title,
                        date: appointmentData.date,
                        time: appointmentData.time,
                        duration: appointmentData.duration,
                        attendees: appointmentData.attendees,
                        meetingLink: appointmentData.meetingLink,
                        location: appointmentData.location,
                        description: appointmentData.description
                    )
                }
                return appointmentData
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
            try await db.collection("users").document(userId).collection("appointments").addDocument(from: appointment)
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
            try await db.collection("users").document(userId).collection("appointments").document(appointment.id).setData(from: appointment)
            // Refresh the list
            await fetchAppointments()
        } catch {
            errorMessage = "Failed to update appointment: \(error.localizedDescription)"
        }
    }
}

