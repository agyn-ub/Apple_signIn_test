# Calendar Access Troubleshooting Guide

## Common Issues and Solutions

### 1. "Calendar access not available" Error

**Possible Causes:**
- Google OAuth client not configured for calendar scopes
- User didn't grant calendar permissions during sign-in
- Server-side token storage failed
- Network connectivity issues

**Solutions:**

#### A. Check Google Cloud Console Configuration
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project: `learning-auth-e6ea2`
3. Navigate to "APIs & Services" > "OAuth consent screen"
4. Ensure calendar scopes are added:
   - `https://www.googleapis.com/auth/calendar.events`
   - `https://www.googleapis.com/auth/calendar.readonly`
   - `https://www.googleapis.com/auth/calendar`
5. Go to "APIs & Services" > "Credentials"
6. Verify your OAuth 2.0 client ID is configured correctly

#### B. Enable Google Calendar API
1. In Google Cloud Console, go to "APIs & Services" > "Library"
2. Search for "Google Calendar API"
3. Click on it and press "Enable"

#### C. Test the Sign-In Flow
1. Open the app
2. Go to Settings > Calendar Settings
3. Tap "Sign in with Google for Calendar"
4. Make sure to grant calendar permissions when prompted
5. Check the console logs for scope information

### 2. Debug Steps

#### Check Console Logs
The app now prints detailed information about granted scopes. Look for:
```
Granted scopes: [list of scopes]
Required scopes: [list of required scopes]
Has calendar access: true/false
```

#### Verify Firebase Functions
1. Check Firebase Functions logs in the Firebase Console
2. Look for errors in `checkGoogleCalendarAuth` and `storeGoogleCalendarAuth` functions
3. Ensure the functions are properly deployed

#### Test Network Connectivity
1. Ensure the device has internet connectivity
2. Check if Firebase Functions are accessible
3. Verify the base URL in VoiceCommandService.swift

### 3. Manual Testing Steps

1. **Clear App Data:**
   - Delete and reinstall the app
   - Or sign out completely and sign in again

2. **Test Google Sign-In:**
   - Go to Settings > Calendar Settings
   - Tap "Sign in with Google for Calendar"
   - Grant all requested permissions

3. **Check Connection Status:**
   - Look at the sync status in the main view
   - Should show "Connected (server)" when successful

4. **Test Voice Commands:**
   - Try a simple command like "Show my appointments"
   - Check if the response indicates calendar access

### 4. Error Messages and Meanings

- **"Calendar permissions not granted"**: User didn't allow calendar access during Google Sign-In
- **"Failed to store calendar tokens on server"**: Firebase function failed to save tokens
- **"Connection check failed"**: Network or server issue
- **"Configuration error"**: Google OAuth client not properly configured

### 5. Firebase Function Requirements

Ensure your Firebase Functions have these capabilities:
- `checkGoogleCalendarAuth`: Checks if user has valid calendar tokens
- `storeGoogleCalendarAuth`: Stores Google calendar tokens securely
- `clearGoogleCalendarAuth`: Removes stored calendar tokens

### 6. Google OAuth Configuration

Your app uses this OAuth client ID:
```
73003602008-0jgk8u5h4s4pdu3010utqovs0kb14fgb.apps.googleusercontent.com
```

Make sure this client ID is:
1. Configured in Google Cloud Console
2. Has calendar scopes enabled
3. Has the correct bundle ID: `angus.Apple-signIn-test`

### 7. If All Else Fails

1. **Reset Google Sign-In:**
   ```swift
   GIDSignIn.sharedInstance.signOut()
   ```

2. **Clear Keychain:**
   - Go to iOS Settings > Passwords & Accounts
   - Remove any stored Google credentials

3. **Contact Support:**
   - Check Firebase Functions logs
   - Verify Google Cloud Console configuration
   - Test with a different Google account

## Quick Fix Checklist

- [ ] Google Calendar API enabled in Google Cloud Console
- [ ] Calendar scopes added to OAuth consent screen
- [ ] OAuth client ID correctly configured
- [ ] Firebase Functions deployed and working
- [ ] User granted calendar permissions during sign-in
- [ ] Network connectivity available
- [ ] App has proper URL schemes configured

If you're still experiencing issues, check the console logs for specific error messages and refer to the debugging information above. 