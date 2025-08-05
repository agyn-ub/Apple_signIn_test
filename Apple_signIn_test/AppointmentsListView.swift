//
//  AppointmentsListView.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import SwiftUI

struct AppointmentsListView: View {
    @ObservedObject var appointmentService: AppointmentService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAppointment: AppointmentData?
    
    var body: some View {
        NavigationView {
            VStack {
                if appointmentService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading appointments...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appointmentService.appointments.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Appointments")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Use voice commands to schedule your first appointment")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedAppointments.keys.sorted(), id: \.self) { date in
                            Section(header: Text(formatSectionDate(date))) {
                                ForEach(groupedAppointments[date] ?? []) { appointment in
                                    AppointmentRowView(appointment: appointment)
                                        .onTapGesture {
                                            selectedAppointment = appointment
                                        }
                                }
                                .onDelete { indexSet in
                                    Task {
                                        for index in indexSet {
                                            let appointment = groupedAppointments[date]?[index]
                                            if let appointmentId = appointment?.id {
                                                await appointmentService.deleteAppointment(appointmentId)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await appointmentService.fetchAppointments()
                    }
                }
                
                if let errorMessage = appointmentService.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Appointments")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Refresh") {
                        Task {
                            await appointmentService.fetchAppointments()
                        }
                    }
                    .disabled(appointmentService.isLoading)
                }
            }
            .sheet(item: $selectedAppointment) { appointment in
                AppointmentDetailView(appointment: appointment, appointmentService: appointmentService)
            }
        }
        .task {
            await appointmentService.fetchAppointments()
        }
    }
    
    private var groupedAppointments: [String: [AppointmentData]] {
        Dictionary(grouping: appointmentService.appointments) { appointment in
            appointment.date
        }
    }
    
    private func formatSectionDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .full
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
}

struct AppointmentRowView: View {
    let appointment: AppointmentData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appointment.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text(appointment.time)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                if appointment.meetingLink != nil {
                    Image(systemName: "video.fill")
                        .foregroundColor(.green)
                }
            }
            
            if let duration = appointment.duration {
                Text("\(duration) minutes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let attendees = appointment.attendees, !attendees.isEmpty {
                Text("With: \(attendees.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            if let location = appointment.location {
                HStack {
                    Image(systemName: "location")
                        .font(.caption)
                    Text(location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AppointmentDetailView: View {
    let appointment: AppointmentData
    @ObservedObject var appointmentService: AppointmentService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title and basic info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appointment.title)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack {
                            Image(systemName: "calendar")
                            Text(formatFullDate(appointment.date))
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                        
                        HStack {
                            Image(systemName: "clock")
                            Text(appointment.time)
                            if let duration = appointment.duration {
                                Text("(\(duration) minutes)")
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Attendees
                    if let attendees = appointment.attendees, !attendees.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Attendees")
                                .font(.headline)
                            
                            ForEach(attendees, id: \.self) { attendee in
                                HStack {
                                    Image(systemName: "person")
                                    Text(attendee)
                                }
                                .font(.subheadline)
                            }
                        }
                        
                        Divider()
                    }
                    
                    // Location
                    if let location = appointment.location {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.headline)
                            
                            HStack {
                                Image(systemName: "location")
                                Text(location)
                            }
                            .font(.subheadline)
                        }
                        
                        Divider()
                    }
                    
                    // Description
                    if let description = appointment.description {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            
                            Text(description)
                                .font(.subheadline)
                        }
                        
                        Divider()
                    }
                    
                    // Meeting link
                    if let meetingLink = appointment.meetingLink {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Meeting Link")
                                .font(.headline)
                            
                            Button(action: {
                                if let url = URL(string: meetingLink) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "video")
                                    Text("Join Meeting")
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Appointment Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatFullDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .full
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
}

#Preview {
    AppointmentsListView(appointmentService: AppointmentService())
}