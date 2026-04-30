# Calisthenics Form Correction App

This app was built for my final year project at the University of Bath. The aim of the project is to explore how pose estimation can be used to give users immediate feedback on their exercise form during calisthenics movements.

The app analyses exercise form, counts repetitions, highlights higher-risk errors, and gives live and post-session feedback. The main exercises currently supported are:

- push-up
- squat
- pull-up

Demo video: https://www.youtube.com/watch?v=hnLgO6gGZsw

## Description

The app is written in SwiftUI and uses MediaPipe pose estimation for movement tracking. It includes:

- live camera-based exercise analysis
- offline video analysis from the photo library
- repetition counting
- rule-based feedback using `CRITICAL`, `IMPORTANT`, and `MINOR` severity levels
- session summaries and workout history
- settings for theme, sensitivity, reps, and audio feedback

## Running the app

The app was developed using:

- Xcode
- iOS 18.0+
- CocoaPods

This project uses:

- `MediaPipeTasksVision`

To run the app:

1. Make sure CocoaPods is installed.
2. In the project root, run:

```bash
pod install
```

3. Open the workspace file:

```bash
open calisthenicsApp.xcworkspace
```

4. Build and run the app in Xcode.

For live camera analysis, running on a real iPhone is recommended.

## Project structure

Some of the main files are:

- `calisthenicsApp/ExerciseEngine.swift` for repetition counting, scoring, and feedback
- `calisthenicsApp/PoseDetectionManager.swift` for camera handling and pose detection
- `calisthenicsApp/BiometricEvaluator.swift` for biomechanical measurements
- `calisthenicsApp/ExerciseDefinitions.swift` and `calisthenicsApp/ExerciseDefinitions/*.json` for exercise rules

## Notes

- Some feedback rules depend on the detected camera view, for example front view vs side view.
- The app supports both live sessions and offline analysis.
- Debug overlays and logs can be enabled in the app settings if needed during development.
