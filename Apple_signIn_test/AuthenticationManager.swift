//
//  AuthenticationManager.swift
//  Apple_signIn_test
//
//  Created by Assistant on 30.07.2025.
//

import SwiftUI
import AuthenticationServices
import FirebaseAuth
import CryptoKit
import GoogleSignIn
import FirebaseFunctions

@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var user: User?
    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var linkedProviders: [String] = []
    @Published var sessionExpired = false
    
    private var currentNonce: String? // For Apple Sign In security
    private var lastActivityTime = Date()
    private let sessionTimeoutInterval: TimeInterval = 3600 // 1 hour
    private var isCheckingSession = false // Prevent concurrent session checks
    private var lastSessionValidation: Date? // Track last validation time
    private let sessionValidationCooldownSeconds: TimeInterval = 30 // Minimum 30 seconds between validations
    weak var calendarManager: GoogleCalendarManager?
    
    override init() {
        super.init()
        // Check if user is already signed in
        self.user = Auth.auth().currentUser
        self.isSignedIn = user != nil
        // Listen for authentication state changes
        let _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in 
            self?.user = user
            self?.isSignedIn = user != nil
            self?.updateLinkedProviders()
            
            // Notify calendar manager of auth state change
            Task { @MainActor in
                if let calendarManager = self?.calendarManager {
                    await calendarManager.checkServerStoredAuth()
                }
            }
        }
        
        // Check and restore previous session on initialization
        Task { @MainActor in
            await checkAndRestorePreviousSession()
        }
    }
    
    // MARK: - Session Restoration
    @MainActor
    func checkAndRestorePreviousSession() async {
        // Mark as loading while checking for previous session
        isLoading = true
        defer { isLoading = false }
        
        // First check if Firebase has a valid session
        guard let currentUser = Auth.auth().currentUser else {
            print("No Firebase session to restore")
            return
        }
        
        // Check if the Firebase token is still valid
        do {
            let tokenResult = try await currentUser.getIDTokenResult(forcingRefresh: false)
            let now = Date()
            
            // If token is expired or expires soon, try to refresh it
            if tokenResult.expirationDate < now || tokenResult.expirationDate.timeIntervalSince(now) < 300 {
                print("Firebase token expired or expiring soon, attempting refresh...")
                _ = try await currentUser.getIDTokenResult(forcingRefresh: true)
                print("Firebase token refreshed successfully")
            }
            
            // Update our state to reflect the valid session
            self.user = currentUser
            self.isSignedIn = true
            self.updateLinkedProviders()
            
            // If we have Google provider, check if GIDSignIn already restored the session
            if linkedProviders.contains("google.com") {
                // The Google session restoration happens in Apple_signIn_testApp.swift
                // Just verify calendar connection status
                if let calendarManager = self.calendarManager {
                    await calendarManager.checkServerStoredAuth()
                }
            }
            
            print("Successfully restored authentication session")
        } catch {
            print("Failed to verify/refresh Firebase token: \(error.localizedDescription)")
            // Token is invalid, user needs to sign in again
            self.user = nil
            self.isSignedIn = false
            self.linkedProviders = []
        }
    }
    
    // MARK: - Apple Sign In
    func signInWithApple() {
        let nonce = randomNonceString() // Generate secure nonce
        currentNonce = nonce
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email] // Ask for name/email
        request.nonce = sha256(nonce) // Hash nonce for security
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests() // Show Apple Sign In UI
    }
    
    // MARK: - Google Sign In
    func signInWithGoogle() {
        // Find the current root view controller
        guard let presentingViewController = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene})
            .first?.windows
            .filter({$0.isKeyWindow}).first?.rootViewController else {
            self.errorMessage = "Unable to get presenting view controller"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Configure additional scopes for calendar access
        let calendarScopes = ["https://www.googleapis.com/auth/calendar.events"]
        
        // Start Google Sign In flow with calendar scopes
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, 
                                       hint: nil, 
                                       additionalScopes: calendarScopes) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Google Sign In error: \(error.localizedDescription)"
                    return
                }
                // Get Google ID token
                guard let googleUser = result?.user,
                      let idToken = googleUser.idToken?.tokenString else {
                    self?.errorMessage = "Failed to get Google ID token"
                    return
                }
                // Create Firebase credential
                let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                             accessToken: googleUser.accessToken.tokenString)
                // Store Google tokens for calendar access
                let googleAccessToken = googleUser.accessToken.tokenString
                let googleRefreshToken = googleUser.refreshToken.tokenString
                
                // If already signed in, link account; else, sign in
                if Auth.auth().currentUser != nil {
                    self?.linkAccount(with: credential, googleAccessToken: googleAccessToken, googleRefreshToken: googleRefreshToken)
                } else {
                    Auth.auth().signIn(with: credential) { authResult, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = "Firebase authentication error: \(error.localizedDescription)"
                                return
                            }
                            self?.user = authResult?.user
                            self?.isSignedIn = true
                            self?.errorMessage = nil
                            
                            // Store Google tokens for calendar access
                            Task { @MainActor in
                                await self?.storeGoogleTokensForCalendar(
                                    accessToken: googleAccessToken,
                                    refreshToken: googleRefreshToken,
                                    user: googleUser
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Google Calendar Token Management
    func storeGoogleTokensForCalendar(accessToken: String, refreshToken: String?, user: GIDGoogleUser) async {
        guard Auth.auth().currentUser != nil else {
            self.errorMessage = "No Firebase user found to store tokens"
            return
        }
        
        print("Storing Google tokens for calendar access...")
        
        // Store tokens using Firebase Functions for backend access
        let functions = Functions.functions()
        let data: [String: Any] = [
            "accessToken": accessToken,
            "refreshToken": refreshToken ?? "",
            "expiryDate": user.accessToken.expirationDate?.timeIntervalSince1970 ?? 0,
            "scopes": user.grantedScopes ?? [],
            "name": user.profile?.name ?? "",
            "email": user.profile?.email ?? ""
        ]
        
        do {
            try await functions.httpsCallable("storeGoogleCalendarAuth").call(data)
            print("✅ Google calendar tokens stored successfully")
            
            // Update calendar manager
            if let calendarManager = self.calendarManager {
                await calendarManager.checkServerStoredAuth()
            }
        } catch {
            print("❌ Failed to store Google calendar tokens: \(error.localizedDescription)")
            self.errorMessage = "Failed to set up calendar access: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Account Linking
    func linkAccount(with credential: AuthCredential, googleAccessToken: String? = nil, googleRefreshToken: String? = nil) {
        guard let currentUser = Auth.auth().currentUser else {
            self.errorMessage = "No user is currently signed in"
            return
        }
        isLoading = true
        currentUser.link(with: credential) { [weak self] authResult, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    // Handle already-linked error
                    if let authError = error as NSError?, authError.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                        self?.errorMessage = "This account is already linked with another user"
                    } else {
                        self?.errorMessage = "Account linking error: \(error.localizedDescription)"
                    }
                    return
                }
                self?.user = authResult?.user
                self?.errorMessage = nil
                self?.updateLinkedProviders()
                
                // If Google tokens were provided, store them for calendar access
                if googleAccessToken != nil {
                    Task { @MainActor in
                        // For linking case, we don't have the full GIDGoogleUser object
                        // So we'll use minimal data or check if calendar connection is needed
                        await self?.checkAndConnectGoogleCalendar()
                    }
                } else {
                    // Check and connect to Google Calendar if needed
                    Task { @MainActor in
                        await self?.checkAndConnectGoogleCalendar()
                    }
                }
            }
        }
    }
    
    // MARK: - Unlinking Providers
    func unlinkProvider(_ providerId: String) {
        guard let currentUser = Auth.auth().currentUser else {
            self.errorMessage = "No user is currently signed in"
            return
        }
        isLoading = true
        currentUser.unlink(fromProvider: providerId) { [weak self] user, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Account unlinking error: \(error.localizedDescription)"
                    return
                }
                self?.user = user
                self?.errorMessage = nil
                self?.updateLinkedProviders()
            }
        }
    }
    
    // MARK: - Sign Out
    func signOut() {
        do {
            // Sign out from Firebase Auth
            try Auth.auth().signOut()
            
            // IMPORTANT: We're NOT calling GIDSignIn.sharedInstance.signOut()
            // This preserves the Google Calendar authorization token
            // Google Calendar tokens are now managed by the Firebase function
            
            // Update local state
            self.user = nil
            self.isSignedIn = false
            self.linkedProviders = []
            self.errorMessage = nil
        } catch let signOutError as NSError {
            self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
        }
    }
    
    // Use this method if you need to completely sign out from all services
    func signOutCompletely() {
        do {
            // Prepare to clear server auth
            
            // If user is authenticated, clear calendar tokens on server
            if let userId = Auth.auth().currentUser?.uid {
                Task { @MainActor in
                    do {
                        _ = try await callFirebaseFunction(name: "clearGoogleCalendarAuth", parameters: ["userId": userId])
                    } catch {
                        print("Failed to clear server auth: \(error.localizedDescription)")
                    }
                }
            }
            
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut() // This will clear all Google tokens including Calendar
            
            // Clear local calendar tokens
            UserDefaults.standard.removeObject(forKey: "google_calendar_auth_code")
            UserDefaults.standard.removeObject(forKey: "google_calendar_auth_url")
            
            // Update local state
            self.user = nil
            self.isSignedIn = false
            self.linkedProviders = []
            self.errorMessage = nil
        } catch let signOutError as NSError {
            self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
        }
    }
    
    // MARK: - Helpers
    private func updateLinkedProviders() {
        guard let user = Auth.auth().currentUser else {
            self.linkedProviders = []
            return
        }
        self.linkedProviders = user.providerData.map { $0.providerID }
    }
    
    // Generate a secure random nonce for Apple Sign In
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    // Hash the nonce for Apple Sign In
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    // Check and connect to Google Calendar if needed - consolidated with guards
    @MainActor
    func checkAndConnectGoogleCalendar() async {
        guard let calendarManager = self.calendarManager else {
            print("No calendar manager available")
            return
        }
        
        // Prevent multiple simultaneous calendar checks
        guard !isCheckingSession else {
            print("Session validation in progress, deferring calendar check...")
            return
        }
        
        // Prevent if calendar manager is already connecting
        if calendarManager.isLoading {
            print("Calendar connection already in progress, skipping...")
            return
        }
        
        // Only check server auth, don't automatically trigger sign-in
        await calendarManager.checkServerStoredAuth()
        
        // Note: We no longer automatically call signInWithGoogleForCalendar here
        // This prevents recursive loops - let the UI handle manual calendar connection
        if !calendarManager.isConnected {
            print("Calendar not connected - user can manually connect if needed")
        } else {
            print("Calendar already connected")
        }
    }
    
    // Handle Apple Sign In result (for new ContentView)
    func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                guard let nonce = currentNonce else {
                    errorMessage = "Invalid state: A login callback was received, but no login request was sent."
                    return
                }
                guard let appleIDToken = appleIDCredential.identityToken else {
                    errorMessage = "Unable to fetch identity token"
                    return
                }
                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    errorMessage = "Unable to serialize token string from data"
                    return
                }
                
                let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                              rawNonce: nonce,
                                                              fullName: appleIDCredential.fullName)
                isLoading = true
                errorMessage = nil
                
                // If already signed in, link account; else, sign in
                if Auth.auth().currentUser != nil {
                    linkAccount(with: credential)
                } else {
                    Auth.auth().signIn(with: credential) { [weak self] (authResult, error) in
                        DispatchQueue.main.async {
                            self?.isLoading = false
                            if let error = error {
                                self?.errorMessage = error.localizedDescription
                                return
                            }
                            self?.user = authResult?.user
                            self?.isSignedIn = true
                            self?.errorMessage = nil
                            
                            Task { @MainActor in
                                await self?.checkAndConnectGoogleCalendar()
                            }
                        }
                    }
                }
            }
        case .failure(let error):
            errorMessage = "Sign in with Apple errored: \(error.localizedDescription)"
        }
    }
    
    // Link Google account for calendar access (after Apple Sign-In)
    func linkGoogleAccountForCalendar() {
        guard let calendarManager = self.calendarManager else {
            errorMessage = "Calendar manager not available"
            return
        }
        calendarManager.linkGoogleAccountAfterApple()
    }
    
    // Clear error message
    func clearError() {
        errorMessage = nil
    }
    
    // Validate session when app resumes from background
    @MainActor
    func validateSessionOnResume() async {
        // Prevent concurrent session checks
        guard !isCheckingSession else {
            print("Session validation already in progress, skipping...")
            return
        }
        
        // Check cooldown period - don't validate too frequently
        if let lastValidation = lastSessionValidation,
           Date().timeIntervalSince(lastValidation) < sessionValidationCooldownSeconds {
            print("Session validation cooldown active, skipping...")
            return
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            // User is no longer authenticated
            self.user = nil
            self.isSignedIn = false
            self.linkedProviders = []
            return
        }
        
        isCheckingSession = true
        lastSessionValidation = Date() // Update timestamp
        defer { isCheckingSession = false }
        
        do {
            // Check if Firebase Auth token is still valid
            let tokenResult = try await currentUser.getIDTokenResult(forcingRefresh: false)
            let now = Date()
            
            // If token expires within 10 minutes, refresh it
            if tokenResult.expirationDate.timeIntervalSince(now) < 600 {
                print("Firebase token expires soon on app resume, refreshing...")
                _ = try await currentUser.getIDTokenResult(forcingRefresh: true)
                print("Firebase token refreshed on app resume")
            }
            
            // Re-verify calendar connection if we have Google provider
            if linkedProviders.contains("google.com"), let calendarManager = self.calendarManager {
                await calendarManager.checkServerStoredAuth()
            }
            
        } catch {
            print("Session validation failed on app resume: \(error.localizedDescription)")
            // Don't immediately sign out - let user try to use the app
            // They'll get an error and can re-authenticate if needed
            self.errorMessage = "Session may have expired. If you encounter issues, please sign out and sign back in."
        }
    }
    
    // Update last activity time - call this when user interacts with the app
    func updateActivity() {
        lastActivityTime = Date()
        if sessionExpired {
            sessionExpired = false
            errorMessage = nil
        }
    }
    
    // Check if session has timed out due to inactivity
    func checkSessionTimeout() -> Bool {
        let now = Date()
        let timeSinceLastActivity = now.timeIntervalSince(lastActivityTime)
        
        if timeSinceLastActivity > sessionTimeoutInterval && isSignedIn {
            sessionExpired = true
            errorMessage = "Your session has expired due to inactivity. Please sign in again."
            return true
        }
        return false
    }
    
    // Handle session timeout with graceful re-authentication
    @MainActor
    func handleSessionTimeout() {
        if checkSessionTimeout() {
            // Don't immediately sign out - just mark as expired
            // User can continue using cached data but will need to re-auth for server calls
            sessionExpired = true
            print("Session expired due to inactivity")
        }
    }
    
    // Helper method to call Firebase functions in a nonisolated context
    private nonisolated func callFirebaseFunction(name: String, parameters: [String: Any]) async throws -> [String: Any] {
        let functions = Functions.functions()
        let result = try await functions.httpsCallable(name).call(parameters as [String: Any])
        // Extract data immediately to make it sendable
        let rawData = result.data
        guard let data = rawData as? [String: Any] else {
            return [:]
        }
        return data
    }
}

// MARK: - Apple Sign In Delegates
extension AuthenticationManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                fatalError("Invalid state: A login callback was received, but no login request was sent.")
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                self.errorMessage = "Unable to fetch identity token"
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                self.errorMessage = "Unable to serialize token string from data"
                return
            }
            // Create Firebase credential from Apple token
            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                          rawNonce: nonce,
                                                          fullName: appleIDCredential.fullName)
            isLoading = true
            Auth.auth().signIn(with: credential) { [weak self] (authResult, error) in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                        return
                    }
                    self?.user = authResult?.user
                    self?.isSignedIn = true
                    self?.errorMessage = nil
                    
                    // Check and connect to Google Calendar if needed
                    Task { @MainActor in
                        await self?.checkAndConnectGoogleCalendar()
                    }
                }
            }
        }
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.errorMessage = "Sign in with Apple errored: \(error.localizedDescription)"
    }
}

// MARK: - Apple Sign In Presentation Context
extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene})
            .first?.windows
            .filter({$0.isKeyWindow}).first ?? UIWindow()
    }
} 
