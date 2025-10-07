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

See inline `// TODO(MVP)` comments for remaining work.

## Setup

1. Create a Spotify application at <https://developer.spotify.com/dashboard>.
   - Add a redirect URI matching `stackspin://auth` (update `PKCEAuth.swift` if you change it).
   - Copy the client ID into `PKCEAuth.swift`.
2. Enable Background Modes in the Xcode project for `Background fetch` and `Background processing`.
3. Register the background processing identifier `com.stackspin.process` in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
4. Add the `Resources/CoreDataModel.xcdatamodeld` to the Xcode project.
5. Provide Camera, Photo Library, and Background modes usage descriptions in `Info.plist`:
   - `NSCameraUsageDescription`
   - `NSPhotoLibraryAddUsageDescription`
   - `NSPhotoLibraryUsageDescription`
6. Build and run on iOS 17+.

## Testing Notes

- Use the sample UPCs in `TestData.swift` for quick verifications.
- Inject mock implementations of `MusicBrainzAPI`, `SpotifyAPI`, and `DiscogsAPI` to test the `Resolver` pipeline.

## License

Prototype code for demonstration purposes.
