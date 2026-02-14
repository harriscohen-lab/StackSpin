# StackSpin

StackSpin is a SwiftUI prototype that captures physical album media and sends the matching tracks to a Spotify playlist. The project targets iOS 17 and uses on-device Vision, Core Data, and BackgroundTasks.

## Features

- Spotify sign-in via PKCE (no backend) with playlist modification scopes
- Batch capture/import list with minimalist monochrome UI
- Matching pipeline: barcode → MusicBrainz/Discogs → Spotify, OCR fallback, feature print fallback
- Core Data persistence for jobs, album cache, dedupe, and settings
- Background processing queue ready for BGProcessingTask integration

## Project Structure

```
StackSpin/
  StackSpinApp.swift
  Models/
  Services/
  Views/
  Resources/
```


## Setup

1. Create a Spotify application at <https://developer.spotify.com/dashboard>.
   - Add a redirect URI matching `stackspin://auth` (update `PKCEAuth.swift` if you change it).
   - Copy the client ID into `Supporting/Info.plist` under the `SpotifyClientID` key.
2. Enable Background Modes in the Xcode project for `Background fetch` and `Background processing`.
3. Register the background processing identifier `com.stackspin.process` in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
4. Add the `Resources/CoreDataModel.xcdatamodeld` to the Xcode project.
5. Provide Camera, Photo Library, and Background modes usage descriptions in `Info.plist`:
   - `NSCameraUsageDescription`
   - `NSPhotoLibraryAddUsageDescription`
   - `NSPhotoLibraryUsageDescription`
6. Build and run on iOS 17+.

## Building & Running

### Requirements

- Xcode 15 or newer (iOS 17 SDK)
- A Spotify developer account for client configuration
- An iOS 17 simulator or device (camera/Photos access is only available on device)

### Steps

1. Clone the repository and open the project in Xcode:

   ```bash
   git clone <repo-url>
   cd DiscLib
   open StackSpin.xcodeproj
   ```

2. In Xcode, select the **StackSpin** target and set your Spotify client ID in `Supporting/Info.plist` by replacing the `YOUR_SPOTIFY_CLIENT_ID` value for `SpotifyClientID`.
3. Choose an iOS 17 simulator (or a provisioned device) from the scheme selector.
4. Press **Cmd + B** to build. Fix any signing warnings by selecting your Apple ID/team under *Signing & Capabilities* if you plan to run on device.
5. Press **Cmd + R** to launch the app. On first launch you will be prompted to sign into Spotify and pick the playlist that StackSpin should append to.

> Tip: you can also build from the command line with `xcodebuild -scheme StackSpin -destination 'platform=iOS Simulator,name=iPhone 15' build` once Xcode command line tools are installed.

## Testing Notes

- Use the sample UPCs in `TestData.swift` for quick verifications.
- Inject mock implementations of `MusicBrainzAPI`, `SpotifyAPI`, and `DiscogsAPI` to test the `Resolver` pipeline.

## License

Prototype code for demonstration purposes.
