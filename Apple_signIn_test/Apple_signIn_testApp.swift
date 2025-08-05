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
        
        // Configure Google Sign In with the correct client ID for calendar access
        let clientID = "73003602008-0jgk8u5h4s4pdu3010utqovs0kb14fgb.apps.googleusercontent.com"
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
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
