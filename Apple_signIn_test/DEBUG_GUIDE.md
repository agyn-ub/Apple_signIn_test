# Calendar Access Debugging Guide

## Quick Debug Steps

### 1. Check the Debug View
- Tap the "Debug" button in the main app
- Review all status information
- Check for any error messages

### 2. Monitor Console Logs
The app now has comprehensive logging. Look for these key log entries:

#### Calendar Connection Logs:
```
GoogleCalendarManager: Starting Google Sign-In for calendar
GoogleCalendarManager: Using client ID: 73003602008-0jgk8u5h4s4pdu3010utqovs0kb14fgb.apps.googleusercontent.com
GoogleCalendarManager: Calendar scopes requested: [scopes list]
GoogleCalendarManager: Granted scopes: [scopes list]
GoogleCalendarManager: Has calendar access: true/false
```

#### Firebase Function Logs:
```
FirebaseFunctions: Calling Firebase function: checkGoogleCalendarAuth
FirebaseFunctions: Firebase function checkGoogleCalendarAuth response: [response data]
```

#### Voice Command Logs:
```
VoiceCommandService: Processing voice command: [command]
VoiceCommandService: HTTP response status: 200
VoiceCommandService: Voice command response: success=true/false
```

## Common Issues and Solutions

### Issue 1: "Calendar access not available"

**Debug Steps:**
1. Check if user is signed in to Firebase
2. Verify Google Sign-In configuration
3. Check if calendar scopes were granted
4. Verify Firebase Functions are working

**Console Logs to Check:**
```
GoogleCalendarManager: Server auth check response: [response]
GoogleCalendarManager: Calendar authentication failed: [message]
```

**Solutions:**
- Ensure Google Calendar API is enabled in Google Cloud Console
- Check that calendar scopes are added to OAuth consent screen
- Verify Firebase Functions are deployed and working

### Issue 2: Google Sign-In Fails

**Debug Steps:**
1. Check GIDSignInError codes in console
2. Verify client ID configuration
3. Check URL schemes in Info.plist

**Console Logs to Check:**
```
GoogleCalendarManager: GIDSignInError code: [error code]
GoogleCalendarManager: Google Sign-In error: [error message]
```

**Solutions:**
- Verify Google OAuth client ID is correct
- Check URL schemes in Info.plist match client ID
- Ensure Google Sign-In is properly configured

### Issue 3: Firebase Functions Fail

**Debug Steps:**
1. Check Firebase Functions logs in Firebase Console
2. Verify function names and parameters
3. Check network connectivity

**Console Logs to Check:**
```
FirebaseFunctions: Firebase function [name] failed: [error]
FirebaseFunctions: Invalid response format from Firebase function: [name]
```

**Solutions:**
- Deploy Firebase Functions if not already done
- Check function implementation
- Verify Firebase project configuration

### Issue 4: Voice Commands Fail

**Debug Steps:**
1. Check HTTP response status
2. Verify voice command service URL
3. Check Firebase authentication

**Console Logs to Check:**
```
VoiceCommandService: HTTP response status: [status code]
VoiceCommandService: Voice command processing failed: [error]
```

**Solutions:**
- Verify voice command service is deployed
- Check Firebase authentication is working
- Ensure network connectivity

## Step-by-Step Debugging Process

### Step 1: Check Authentication
1. Open Debug View
2. Verify "Firebase User" shows "Signed In"
3. Check "User ID" is present
4. Verify "Providers" shows expected providers

### Step 2: Test Calendar Connection
1. In Debug View, tap "Test Calendar Connection"
2. Check console logs for response
3. Look for any error messages in Debug View

### Step 3: Test Google Sign-In
1. In Debug View, tap "Test Google Sign-In"
2. Complete the Google Sign-In flow
3. Check console logs for scope information
4. Verify calendar permissions are granted

### Step 4: Test Voice Commands
1. Try a simple voice command
2. Check console logs for processing
3. Verify response in Debug View

## Key Configuration Points

### Google Cloud Console:
- Project: `learning-auth-e6ea2`
- OAuth Client ID: `73003602008-0jgk8u5h4s4pdu3010utqovs0kb14fgb.apps.googleusercontent.com`
- Bundle ID: `angus.Apple-signIn-test`

### Required APIs:
- Google Calendar API
- Google Sign-In API

### Required Scopes:
- `https://www.googleapis.com/auth/calendar.events`
- `https://www.googleapis.com/auth/calendar.readonly`
- `https://www.googleapis.com/auth/calendar`

### Firebase Functions:
- `checkGoogleCalendarAuth`
- `storeGoogleCalendarAuth`
- `clearGoogleCalendarAuth`

## Debug Commands

### In Debug View:
- **Test Calendar Connection**: Tests server-side calendar auth
- **Test Google Sign-In**: Initiates Google Sign-In flow
- **Clear All Errors**: Clears error messages
- **Show Console Logs**: Opens log viewer

### Console Commands (in Xcode):
```swift
// Check current user
print("Firebase user: \(Auth.auth().currentUser?.uid ?? "none")")

// Check Google Sign-In state
print("Google Sign-In user: \(GIDSignIn.sharedInstance.currentUser?.profile?.email ?? "none")")

// Check calendar connection
await calendarManager.connectGoogleCalendar()
```

## Error Code Reference

### GIDSignInError Codes:
- `.canceled`: User canceled sign-in
- `.unknown`: Unknown error
- `.hasNoAuthInKeychain`: No stored authentication
- `.keychain`: Keychain access error

### HTTP Status Codes:
- `200-299`: Success
- `400-499`: Client error (check request)
- `500-599`: Server error (check Firebase Functions)

## Next Steps

1. **Run the app** and check Debug View
2. **Monitor console logs** for detailed information
3. **Test each component** using Debug View buttons
4. **Check Firebase Console** for function logs
5. **Verify Google Cloud Console** configuration

If you're still experiencing issues, provide the console logs and Debug View information for further assistance. 