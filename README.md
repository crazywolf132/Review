# Review - GitHub PR Reviewer App

A macOS menu bar app for managing and reviewing GitHub pull requests.

## Features

- View all your pull requests that need review in the menu bar
- Quick access to PRs where you're requested as a reviewer
- View your own PRs and monitor their status
- Approve, request changes, or comment on PRs directly from the menu bar
- Customizable refresh intervals and display options
- Launch at login option

## Code Signing and Distribution

This app is configured for code signing with a Developer ID certificate for distribution to company devices outside the Mac App Store.

### Local Development

1. Clone the repository
2. Open `Review.xcodeproj` in Xcode
3. Build and run the app

### Building a Signed Version Locally

1. Make sure you have a Developer ID certificate in your keychain
2. Create a Developer ID provisioning profile named "Review Developer ID" in your Apple Developer account
3. Set the environment variable for notarization:
   ```
   export APP_SPECIFIC_PASSWORD='your-app-specific-password'
   ```
4. Run the build script:
   ```
   ./build_for_distribution.sh
   ```
5. The script will build, sign, notarize and create a DMG of the app

### GitHub Actions Automated Build

The repository includes a GitHub Actions workflow that automates the build and signing process. To set it up:

1. Convert your Developer ID certificate to base64:
   ```
   base64 -i DeveloperID.p12 -o certificate.base64
   ```

2. Convert your provisioning profile to base64:
   ```
   base64 -i "Review Developer ID.provisionprofile" -o profile.base64
   ```

3. Add the following secrets to your GitHub repository:
   - `CERTIFICATE_BASE64`: The base64-encoded Developer ID certificate
   - `CERTIFICATE_PASSWORD`: The password for your Developer ID certificate
   - `KEYCHAIN_PASSWORD`: A password for the temporary keychain (can be any secure string)
   - `PROVISIONING_PROFILE_BASE64`: The base64-encoded provisioning profile
   - `APP_SPECIFIC_PASSWORD`: Your Apple ID app-specific password for notarization

4. Push to the main branch or manually trigger the workflow to build the app

## Requirements

- macOS 15.2 or later
- GitHub account with a personal access token

## License

Copyright © 2025. All rights reserved. 