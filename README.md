# pushup-mgmt
# Push Manager (iOS)

Push Manager is a native iPhone app built with SwiftUI. It lets you set a daily
pushup target or incremental set goals, log each set, review progress across
multiple ranges, and receive reminders.

## Features

- Daily target or incremental sets per day
- Progress bar and streak tracking
- Daily log of pushup sets
- Range insights (daily, weekly, monthly, quarterly, yearly)
- Local notifications with multiple reminder times

## Open in Xcode

1. Open Xcode.
2. Create a new **iOS App** project named `PushManager`.
3. Replace the generated `PushManagerApp.swift` with the file in
   `ios/PushManager/PushManagerApp.swift`.
4. If Xcode generated a `ContentView.swift`, you can delete it (the app uses
   `PushManagerView` to avoid a duplicate `ContentView` symbol).
5. Ensure the project target is set to your iPhone and run.

## Version control with GitHub (SSH)

If you want to push this project to GitHub using SSH, use the commands below
with your username (`jpk300`).

### First push

```bash
git init
git add .
git commit -m "Initial native iOS app"
git branch -M main
git remote add origin git@github.com:jpk300/Push-Manager.git
git push -u origin main
```

### Future updates

```bash
git add .
git commit -m "Describe your change"
git push
```

## iPhone reminders

Reminders use local notifications. The first time you save a reminder, iOS will
prompt you to allow notifications. You can update this later in
**Settings > Notifications > Push Manager**.