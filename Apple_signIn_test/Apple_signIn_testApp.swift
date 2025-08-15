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
        
        // Note: Google Sign-In restoration is handled by AuthenticationManager
        // We don't restore here to prevent duplicate authentication attempts
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
