//
//  GoogleCalendarManager.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import Foundation
import GoogleSignIn
import SwiftUI
import FirebaseAuth
import FirebaseFunctions
import os.log

@MainActor
class GoogleCalendarManager: ObservableObject {
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var syncStatus = "Not connected"
    
    // Debug logging
    private let logger = Logger(subsystem: "com.apple.signin.test", category: "GoogleCalendarManager")
    
    // Authentication state guards
    private var isConnectingCalendar = false
    private var lastConnectionAttempt: Date?
    private var connectionAttempts = 0
    private let maxConnectionAttempts = 3
    private let baseCooldownSeconds: TimeInterval = 10
    
    // Calculate exponential backoff cooldown
    private var connectionCooldownSeconds: TimeInterval {
        return baseCooldownSeconds * pow(2.0, Double(connectionAttempts))
    }
    
    // Reset connection state on success
    private func resetConnectionState() {
        connectionAttempts = 0
        lastConnectionAttempt = nil
        isConnectingCalendar = false
    }
    
    // Public function to manually reset connection state (for UI recovery)
    func resetConnectionAttempts() {
        logger.info("Manually resetting connection attempts")
        resetConnectionState()
        errorMessage = nil
        syncStatus = "Ready to connect"
    }

    // Enhanced calendar scopes for complete access
    // Calendar scopes are now handled by AuthenticationManager during Google Sign-In
    private let calendarScopes = [
        "https://www.googleapis.com/auth/calendar.events"
    ]

    init() {
        logger.info("GoogleCalendarManager initialized")
        checkConnectionStatus()
    }

    private func checkConnectionStatus() {
        logger.info("Checking connection status")
        // Only check server-side tokens
        guard Auth.auth().currentUser != nil else {
            logger.warning("No Firebase user found")
            isConnected = false
            syncStatus = "Not connected"
            return
        }
        Task {
            await checkServerStoredAuth()
        }
    }

    @MainActor
    func checkServerStoredAuth() async {
        guard let userId = Auth.auth().currentUser?.uid else { 
            logger.error("No user ID available for server auth check")
            return 
        }
        
        logger.info("Checking server stored auth for user: \(userId)")
        isLoading = true
        syncStatus = "Checking server for saved connection..."
        
        do {
            let data = try await callFirebaseFunction(name: "checkGoogleCalendarAuth", parameters: ["userId": userId])
            logger.info("Server auth check response: \(String(describing: data))")
            
            if let isAuthenticated = data["authenticated"] as? Bool, isAuthenticated {
                logger.info("Calendar authentication successful")
                isConnected = true
                syncStatus = "Connected (server)"
                errorMessage = nil
            } else {
                let message = data["message"] as? String ?? "Calendar access not available"
                logger.warning("Calendar authentication failed: \(message)")
                
                // Check if tokens are expired and need re-authentication
                if message.contains("expired") || message.contains("could not be refreshed") {
                    logger.info("Google Calendar tokens expired, triggering re-authentication")
                    syncStatus = "Authentication expired - reconnecting..."
                    // Trigger re-authentication flow
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.linkGoogleAccountAfterApple()
                    }
                    return
                }
                
                // Check if server requires OAuth flow
                if checkAndHandleServerOAuth(data: data) {
                    // OAuth flow is being handled
                    return
                }
                
                isConnected = false
                syncStatus = "Not connected"
                errorMessage = message
            }
        } catch {
            logger.error("Server auth check failed: \(error.localizedDescription)")
            isConnected = false
            syncStatus = "Connection check failed"
            errorMessage = "Failed to check calendar connection: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // Re-authenticate with Google Calendar when tokens expire
    func signInWithGoogleForCalendar() {
        logger.info("Initiating Google Calendar re-authentication")
        
        // If already connected, just verify the connection
        if isConnected {
            Task {
                await checkServerStoredAuth()
            }
            return
        }
        
        // Otherwise trigger the full re-authentication flow
        linkGoogleAccountAfterApple()
    }
    
    // Public method to force re-authentication (useful for expired tokens)
    func forceReauthentication() {
        logger.info("Force re-authentication requested")
        isConnected = false
        errorMessage = nil
        syncStatus = "Re-authenticating..."
        linkGoogleAccountAfterApple()
    }

    // DEPRECATED: No longer needed - handled by AuthenticationManager
    // private func handleGoogleSignInResult(result: GIDSignInResult?, error: Error?) {
    private func handleGoogleSignInResult(result: GIDSignInResult?, error: Error?) {
        isLoading = false
        isConnectingCalendar = false // Clear connecting flag
        
        if let error = error {
            logger.error("Google Sign-In error: \(error.localizedDescription)")
            
            // Enhanced error handling with specific messages
            if let signInError = error as? GIDSignInError {
                let errorCode: GIDSignInError.Code = signInError.code
                logger.error("GIDSignInError code: \(errorCode.rawValue)")
                
                switch errorCode {
                case .canceled:
                    errorMessage = "Sign-in was canceled. Please try again and grant calendar access."
                    logger.info("User canceled Google Sign-In")
                case .unknown:
                    errorMessage = "Unknown sign-in error. Please try again."
                    logger.error("Unknown Google Sign-In error")
                case .hasNoAuthInKeychain:
                    errorMessage = "No authentication found. Please sign in again."
                    logger.warning("No auth found in keychain")
                case .keychain:
                    errorMessage = "Keychain error. Please try again."
                    logger.error("Keychain error during Google Sign-In")
                case .EMM:
                    errorMessage = "Enterprise Mobility Management error."
                    logger.error("EMM error during Google Sign-In")
                case .scopesAlreadyGranted:
                    errorMessage = "Scopes already granted."
                    logger.info("Scopes already granted during Google Sign-In")
                default:
                    errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                    logger.error("Unknown Google Sign-In error code: \(errorCode.rawValue)")
                }
            } else {
                let errorDescription: String = error.localizedDescription
                errorMessage = "Google Calendar connection failed: \(errorDescription)"
                logger.error("Non-GIDSignInError: \(errorDescription)")
            }
            syncStatus = "Sign-in failed"
            return
        }
        
        guard let user = result?.user else {
            logger.error("No user information received from Google Sign-In")
            errorMessage = "Failed to get user information from Google"
            syncStatus = "Sign-in failed"
            return
        }
        
        logger.info("Google Sign-In successful for user: \(user.profile?.email ?? "unknown")")
        
        // Check if calendar scopes were granted
        let grantedScopes: [String] = user.grantedScopes ?? []
        let hasCalendarAccess = self.calendarScopes.allSatisfy { scope in
            grantedScopes.contains(scope)
        }
        
        logger.info("Granted scopes: \(grantedScopes)")
        logger.info("Required scopes: \(self.calendarScopes)")
        logger.info("Has calendar access: \(hasCalendarAccess)")
        
        if hasCalendarAccess {
            logger.info("Calendar scopes granted successfully")
            // Reset connection attempts on successful scope grant
            resetConnectionState()
            // Successfully got calendar access - Call Firebase Function
            callGoogleSignInFirebaseFunction(user: user, result: result)
        } else {
            logger.warning("Calendar scopes not granted. Requesting calendar access...")
            // Request calendar access specifically
            requestCalendarAccess(user: user)
        }
    }
    
    // Request calendar access if not already granted
    private func requestCalendarAccess(user: GIDGoogleUser) {
        logger.info("Requesting specific calendar access")
        
        guard let presentingViewController = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene})
            .first?.windows
            .filter({$0.isKeyWindow}).first?.rootViewController else {
            logger.error("Unable to get presenting view controller for calendar access")
            errorMessage = "Unable to get presenting view controller"
            return
        }
        
        syncStatus = "Requesting calendar access..."
        
        // Try to sign in again with the calendar scopes explicitly requested
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, hint: user.profile?.email, additionalScopes: calendarScopes) { [weak self] signInResult, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Failed to add calendar scopes: \(error.localizedDescription)")
                self.errorMessage = "Failed to add calendar access: \(error.localizedDescription)"
                self.syncStatus = "Calendar access denied"
                return
            }
            
            guard let result = signInResult else {
                self.logger.error("No result after adding scopes")
                self.errorMessage = "Failed to get sign-in result"
                self.syncStatus = "Calendar access failed"
                return
            }
            
            let user = result.user
            
            // Verify calendar scopes were granted
            let grantedScopes: [String] = user.grantedScopes ?? []
            let hasCalendarAccess = self.calendarScopes.allSatisfy { scope in
                grantedScopes.contains(scope)
            }
            
            self.logger.info("After request - Granted scopes: \(grantedScopes)")
            self.logger.info("After request - Has calendar access: \(hasCalendarAccess)")
            
            if hasCalendarAccess {
                self.logger.info("Calendar scopes granted successfully after request")
                // Successfully got calendar access - Call Firebase Function
                self.callGoogleSignInFirebaseFunction(user: user, result: signInResult)
            } else {
                self.logger.warning("Calendar scopes still not granted after request")
                self.errorMessage = "Calendar permissions not granted. Please try again and make sure to grant calendar access in the consent screen."
                self.syncStatus = "Calendar access denied"
            }
        }
    }

    // 4. Call Firebase Function with Complete Token Data
    private func callGoogleSignInFirebaseFunction(user: GIDGoogleUser, result: GIDSignInResult?) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            logger.error("No Firebase user ID available for token storage")
            errorMessage = "Authentication error: No user ID available"
            syncStatus = "Authentication failed"
            return 
        }
        
        logger.info("Storing Google tokens on server for user: \(userId)")
        isLoading = true
        syncStatus = "Storing tokens on server..."
        errorMessage = nil
        
        // Validate user profile data
        guard let email = user.profile?.email, !email.isEmpty else {
            logger.error("No email available from Google profile")
            errorMessage = "Google profile missing email address"
            syncStatus = "Profile validation failed"
            isLoading = false
            return
        }
        
        // Prepare complete token data for Firebase function
        var tokenData: [String: Any] = [
            "userId": userId,
            "email": email,
            "name": user.profile?.name ?? "Unknown User"
        ]
        
        // Validate and add tokens
        let accessToken = user.accessToken.tokenString
        let refreshToken = user.refreshToken.tokenString
        
        if accessToken.isEmpty {
            logger.error("Access token is empty")
            errorMessage = "Invalid access token from Google"
            syncStatus = "Token validation failed"
            isLoading = false
            return
        }
        
        if refreshToken.isEmpty {
            logger.error("Refresh token is empty")
            errorMessage = "Invalid refresh token from Google"
            syncStatus = "Token validation failed"
            isLoading = false
            return
        }
        
        tokenData["accessToken"] = accessToken
        tokenData["refreshToken"] = refreshToken
        
        // Add token expiry information
        let expiryDate = user.accessToken.expirationDate
        logger.info("Access token expires at: \(expiryDate?.description ?? "unknown")")
        
        // Add available optional tokens
        if let idToken = user.idToken?.tokenString {
            tokenData["googleIdToken"] = idToken
            logger.info("ID token available")
        } else {
            logger.warning("No ID token available")
        }
        
        // Add server auth code if available
        if let authCode = result?.serverAuthCode {
            tokenData["authCode"] = authCode
            logger.info("Server auth code available")
        } else {
            logger.warning("No server auth code available, using direct tokens")
        }
        
        // Log granted scopes for debugging
        let grantedScopes = user.grantedScopes ?? []
        logger.info("Granted scopes: \(grantedScopes)")
        
        // Store tokens on server
        storeTokensOnServer(tokenData: tokenData)
    }

    // 5. Store Tokens on Server with Enhanced Data
    private func storeTokensOnServer(tokenData: [String: Any]) {
        logger.info("Calling storeGoogleCalendarAuth Firebase function")
        
        Task {
            do {
                // Prepare parameters that match the backend function expectations
                var backendParameters: [String: Any] = [:]
                
                // Extract required parameters for backend
                if let accessToken = tokenData["accessToken"] as? String {
                    backendParameters["accessToken"] = accessToken
                }
                
                if let refreshToken = tokenData["refreshToken"] as? String {
                    backendParameters["refreshToken"] = refreshToken
                }
                
                if let name = tokenData["name"] as? String {
                    backendParameters["name"] = name
                }
                
                if let email = tokenData["email"] as? String {
                    backendParameters["email"] = email
                }
                
                // Add expiry date - get from Google access token if available
                if let currentUser = GIDSignIn.sharedInstance.currentUser {
                    let expiryDate = currentUser.accessToken.expirationDate
                    if let expiryDate = expiryDate {
                        backendParameters["expiryDate"] = expiryDate.timeIntervalSince1970 * 1000 // Convert to milliseconds
                        logger.info("Access token expires at: \(expiryDate.description)")
                    } else {
                        logger.info("Access token expiry date not available")
                    }
                }
                
                // Add scopes
                backendParameters["scopes"] = calendarScopes
                
                logger.info("Sending backend parameters: \(backendParameters.keys)")
                
                let result = try await callFirebaseFunction(name: "storeGoogleCalendarAuth", parameters: backendParameters)
                logger.info("Store tokens response: \(String(describing: result))")
                
                // Handle the structured response from the backend
                if let success = result["success"] as? Bool {
                    if success {
                        logger.info("Calendar tokens stored successfully")
                        
                        // Log additional success details
                        if let tokenPath = result["tokenPath"] as? String {
                            logger.info("Tokens stored at path: \(tokenPath)")
                        }
                        
                        if let expiryDate = result["expiryDate"] as? Double {
                            let expiry = Date(timeIntervalSince1970: expiryDate / 1000)
                            logger.info("Token expires at: \(expiry)")
                        }
                        
                        // Reset connection state on successful token storage
                        resetConnectionState()
                        isConnected = true
                        syncStatus = "Calendar connected successfully"
                        errorMessage = nil
                        
                        // Verify the connection immediately after storing
                        await checkServerStoredAuth()
                    } else {
                        // Backend returned structured error response
                        let message = result["message"] as? String ?? "Failed to store calendar tokens on server"
                        let error = result["error"] as? String
                        
                        logger.error("Backend returned error - Message: \(message)")
                        if let error = error {
                            logger.error("Backend error details: \(error)")
                        }
                        
                        // Check if server requires OAuth flow
                        if checkAndHandleServerOAuth(data: result) {
                            // OAuth flow is being handled
                            return
                        }
                        
                        errorMessage = message
                        isConnected = false
                        syncStatus = "Token storage failed"
                    }
                } else {
                    // Unexpected response format
                    logger.error("Unexpected response format from backend")
                    let message = result["message"] as? String ?? "Unexpected response from server"
                    errorMessage = message
                    isConnected = false
                    syncStatus = "Token storage failed"
                }
            } catch {
                logger.error("Store tokens error: \(error.localizedDescription)")
                errorMessage = "Failed to store calendar tokens on server: \(error.localizedDescription)"
                isConnected = false
                syncStatus = "Token storage failed"
            }
            isLoading = false
        }
    }

    // 6. Calendar Access Flow - Check Connection Status
    func connectGoogleCalendar() async {
        guard let userId = Auth.auth().currentUser?.uid else { 
            logger.error("No user ID available for calendar connection check")
            return 
        }
        
        logger.info("Checking calendar access for user: \(userId)")
        isLoading = true
        syncStatus = "Checking calendar access..."
        
        do {
            let data = try await callFirebaseFunction(name: "checkGoogleCalendarAuth", parameters: ["userId": userId])
            logger.info("Calendar access check response: \(String(describing: data))")
            
            if let isAuthenticated = data["authenticated"] as? Bool, isAuthenticated {
                logger.info("Calendar access confirmed")
                isConnected = true
                syncStatus = "Google Calendar is connected and accessible"
                errorMessage = nil
            } else {
                let message = data["message"] as? String ?? "Calendar access not available"
                logger.warning("Calendar access denied: \(message)")
                
                // Check if tokens are expired and need re-authentication
                if message.contains("expired") || message.contains("could not be refreshed") {
                    logger.info("Google Calendar tokens expired during connection check, triggering re-authentication")
                    syncStatus = "Authentication expired - reconnecting..."
                    // Trigger re-authentication flow
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.linkGoogleAccountAfterApple()
                    }
                    return
                }
                
                isConnected = false
                syncStatus = "Calendar not connected"
                errorMessage = message
            }
        } catch {
            logger.error("Calendar access check failed: \(error.localizedDescription)")
            isConnected = false
            syncStatus = "Connection check failed"
            errorMessage = "Failed to check calendar access: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func disconnectFromGoogleCalendar() {
        logger.info("Disconnecting from Google Calendar")
        isLoading = true
        syncStatus = "Disconnecting from calendar..."
        errorMessage = nil
        
        guard let userId = Auth.auth().currentUser?.uid else { 
            logger.error("No user ID available for disconnect")
            return 
        }
        
        Task {
            do {
                let result = try await callFirebaseFunction(name: "clearGoogleCalendarAuth", parameters: ["userId": userId])
                logger.info("Disconnect response: \(String(describing: result))")
                isConnected = false
                syncStatus = "Disconnected from calendar"
                errorMessage = nil
            } catch {
                logger.error("Disconnect failed: \(error.localizedDescription)")
                errorMessage = "Failed to disconnect from calendar"
            }
            isLoading = false
        }
    }

    // REMOVED: This function was causing iOS security issues
    // We now use native Google Sign-In SDK instead of web OAuth flow
    // private func handleServerOAuthFlow(authUrl: String) {
    //     // This was trying to open web URLs in Safari - causes security errors
    // }
    
    // Check if we need to handle server-side OAuth with loop prevention
    private func checkAndHandleServerOAuth(data: [String: Any]) -> Bool {
        guard data["authUrl"] as? String != nil else {
            return false
        }
        
        // Prevent recursive OAuth loops
        if isConnectingCalendar {
            logger.warning("Already connecting calendar, ignoring OAuth URL to prevent loop")
            return true // Return true to indicate we handled it (by ignoring it)
        }
        
        // Check if we've exceeded connection attempts
        if connectionAttempts >= maxConnectionAttempts {
            logger.error("Maximum connection attempts reached, not starting OAuth flow")
            errorMessage = "Too many connection attempts. Please try again later."
            syncStatus = "Connection failed"
            return true
        }
        
        // Check cooldown period
        if let lastAttempt = lastConnectionAttempt,
           Date().timeIntervalSince(lastAttempt) < connectionCooldownSeconds {
            logger.warning("Connection cooldown active, not starting OAuth flow")
            return true
        }
        
        logger.info("Server requires OAuth flow, using native Google Sign-In (attempt \(self.connectionAttempts + 1)/\(self.maxConnectionAttempts))")
        
        // Increment attempts and update timestamp
        connectionAttempts += 1
        lastConnectionAttempt = Date()
        
        // Use a delay to prevent immediate recursive calls
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Double-check we're not already connecting
            guard !self.isConnectingCalendar else {
                self.logger.warning("Connection already in progress, skipping OAuth retry")
                return
            }
            self.signInWithGoogleForCalendar()
        }
        return true
    }

    // Link Google account after Apple Sign-In for calendar access
    func linkGoogleAccountAfterApple() {
        logger.info("Initiating Google account linking for calendar access after Apple Sign-In")
        
        // Prevent multiple simultaneous linking attempts
        guard !isConnectingCalendar else {
            logger.warning("Calendar linking already in progress, ignoring request")
            return
        }
        
        // Clear any previous errors
        errorMessage = nil
        isLoading = true
        isConnectingCalendar = true
        syncStatus = "Linking Google account for calendar..."
        
        // Find the current root view controller
        guard let presentingViewController = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene})
            .first?.windows
            .filter({$0.isKeyWindow}).first?.rootViewController else {
            logger.error("Unable to get presenting view controller for Google linking")
            errorMessage = "Unable to present Google Sign-In"
            isLoading = false
            syncStatus = "Connection failed"
            return
        }
        
        // Start Google Sign-In specifically for calendar scopes
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, hint: nil, additionalScopes: self.calendarScopes) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleGoogleLinkingResult(result: result, error: error)
            }
        }
    }
    
    // Handle Google linking result
    private func handleGoogleLinkingResult(result: GIDSignInResult?, error: Error?) {
        isLoading = false
        isConnectingCalendar = false // Clear connecting flag
        
        if let error = error {
            handleGoogleLinkingError(error)
            return
        }
        
        guard let result = result else {
            logger.error("Google linking failed: No result returned")
            errorMessage = "Google Sign-In failed: No result"
            syncStatus = "Connection failed"
            return
        }
        
        let user = result.user
        logger.info("Google linking successful for user: \(user.profile?.email ?? "unknown")")
        
        // Check if calendar scopes were granted
        let grantedScopes: [String] = user.grantedScopes ?? []
        let hasCalendarAccess = calendarScopes.allSatisfy { scope in
            grantedScopes.contains(scope)
        }
        
        if !hasCalendarAccess {
            logger.warning("Calendar scopes not granted during linking. Granted scopes: \(grantedScopes)")
            requestCalendarAccess(user: user)
            return
        }
        
        // Link the Google account to Firebase
        linkGoogleAccountToFirebase(user: user)
    }
    
    // Link Google account to Firebase
    private func linkGoogleAccountToFirebase(user: GIDGoogleUser) {
        guard let idToken = user.idToken?.tokenString else {
            logger.error("Failed to get Google ID token for linking")
            errorMessage = "Failed to get Google authentication token"
            syncStatus = "Connection failed"
            return
        }
        
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
        
        guard let currentUser = Auth.auth().currentUser else {
            logger.error("No current Firebase user for account linking")
            errorMessage = "No authenticated user found"
            syncStatus = "Connection failed"
            return
        }
        
        isLoading = true
        syncStatus = "Linking accounts..."
        
        currentUser.link(with: credential) { [weak self] authResult, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.handleFirebaseLinkingError(error)
                    return
                }
                
                self?.logger.info("Google account successfully linked to Firebase")
                
                // Now store the calendar tokens
                self?.callGoogleSignInFirebaseFunction(user: user, result: nil)
            }
        }
    }
    
    // Handle Firebase linking errors
    private func handleFirebaseLinkingError(_ error: Error) {
        logger.error("Firebase account linking failed: \(error.localizedDescription)")
        
        if let authError = error as NSError? {
            switch authError.code {
            case AuthErrorCode.credentialAlreadyInUse.rawValue:
                errorMessage = "This Google account is already linked to another user"
            case AuthErrorCode.emailAlreadyInUse.rawValue:
                errorMessage = "This email is already associated with another account"
            case AuthErrorCode.providerAlreadyLinked.rawValue:
                // Account already linked, but we still want calendar access
                logger.info("Google account already linked, proceeding with calendar connection")
                if let currentUser = GIDSignIn.sharedInstance.currentUser {
                    callGoogleSignInFirebaseFunction(user: currentUser, result: nil)
                    return
                }
                errorMessage = "Google account already linked, but calendar connection failed"
            default:
                errorMessage = "Account linking failed: \(error.localizedDescription)"
            }
        } else {
            errorMessage = "Account linking failed: \(error.localizedDescription)"
        }
        
        syncStatus = "Connection failed"
    }
    
    // Handle Google linking specific errors
    private func handleGoogleLinkingError(_ error: Error) {
        if let signInError = error as? GIDSignInError {
            let errorCode: GIDSignInError.Code = signInError.code
            let errorDescription: String = error.localizedDescription
            
            logger.error("Google linking error - Code: \(errorCode.rawValue), Description: \(errorDescription)")
            
            var errorMessage: String
            switch errorCode {
            case .canceled:
                errorMessage = "Google account linking was canceled. Calendar access requires Google Sign-In."
            case .unknown:
                errorMessage = "Unknown Google Sign-In error. Please try again."
            case .hasNoAuthInKeychain:
                errorMessage = "No Google authentication found. Please try linking again."
            case .keychain:
                errorMessage = "Keychain error during Google linking. Please try again."
            case .EMM:
                errorMessage = "Enterprise Mobility Management error during linking."
            case .scopesAlreadyGranted:
                errorMessage = "Calendar access already granted."
            default:
                errorMessage = "Google account linking failed: \(error.localizedDescription)"
            }
            
            self.errorMessage = errorMessage
        } else {
            logger.error("Google linking error: \(error.localizedDescription)")
            errorMessage = "Google account linking failed: \(error.localizedDescription)"
        }
        
        syncStatus = "Connection failed"
    }

    // Helper method to call Firebase functions with enhanced error handling
    private nonisolated func callFirebaseFunction(name: String, parameters: [String: Any]) async throws -> [String: Any] {
        let logger = Logger(subsystem: "com.apple.signin.test", category: "FirebaseFunctions")
        logger.info("Calling Firebase function: \(name) with parameters: \(parameters)")
        
        do {
            let functions = Functions.functions()
            let result = try await functions.httpsCallable(name).call(parameters as [String: Any])
            let rawData = result.data
            guard let data = rawData as? [String: Any] else {
                logger.error("Invalid response format from Firebase function: \(name)")
                return [:]
            }
            logger.info("Firebase function \(name) response: \(String(describing: data))")
            return data
        } catch {
            logger.error("Firebase function \(name) failed: \(error.localizedDescription)")
            throw error
        }
    }
}
