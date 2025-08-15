//
//  Apple_signIn_testApp.swift
//  Apple_signIn_test
// Angus.apple-sign-in.test
// 
//  Created by Agyn Bolatov on 30.07.2025.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct Apple_signIn_testApp: App {
    
    init() {
        FirebaseApp.configure()
        
        // Configure Google Sign In using client ID from GoogleService-Info.plist
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            fatalError("No client ID found in GoogleService-Info.plist")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        
        // Restore previous Google Sign-In session if available
        // This will automatically restore the user's authentication from keychain
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let user = user {
                print("Successfully restored Google Sign-In session for: \(user.profile?.email ?? "unknown")")
            } else if let error = error {
                print("Failed to restore Google Sign-In session: \(error.localizedDescription)")
            } else {
                print("No previous Google Sign-In session to restore")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
