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

## Sit-up tracking integration plan (Sr iOS overview)

Below is a product + technical plan for adding sit-up tracking while preserving
the current pushup flows and notifications.

### 1. Product surface area & UX

**Core navigation**
- Add a top-level **Activity** switcher (segmented control or tab) with
  **Pushups** and **Sit-ups**. This keeps the experience familiar while
  letting users swap between activities quickly.
- Keep existing screens intact; for sit-ups the UI mirrors pushups but uses
  sit-up-specific data.

**Home / dashboard**
- Daily target + progress bar become activity-aware.
- Streaks and “daily completed” logic keyed off the selected activity.
- If both activities are enabled, show a small summary card for the
  non-selected activity (e.g., “Sit-ups today: 20 / 50”).

**Logging**
- The set logger supports sit-up set input with the same increment patterns
  (quick-add buttons + manual entry).
- Optionally add a “repeat last set” affordance for faster logging.

**Insights**
- Range insights and charts become multi-activity: user selects
  **Pushups** or **Sit-ups** within the insights view.
- If desired, add a combined “Total reps” chart for all activities.

**Notifications**
- Reminders remain shared; but allow per-activity reminder text (“Time for
  sit-ups”) or reuse the same schedule with different message templates.

**Settings**
- Add a toggle to enable sit-up tracking.
- Activity-specific targets stored per activity.

### 2. Data model changes

**Activity type**
- Introduce an `ActivityType` enum (`pushups`, `situps`) and use it to key
  all tracking data.

**Data entities**
- Add `activityType` to set logs and daily summaries.
- Targets and reminder preferences stored per activity.

**Migration**
- Backfill existing pushup data with `activityType = .pushups`.
- Keep existing data intact by default, so no user regression.

### 3. Architecture & state management

**State ownership**
- Add an `ActivityStore` (or extend current store) that exposes:
  - selected activity
  - activity-specific targets
  - derived daily progress

**View composition**
- Refactor existing Pushup views to be activity-agnostic where possible
  (`ActivityDashboardView`, `ActivityLogView`, etc.).
- Use dependency injection (environment objects) to keep the view logic clean.

### 4. Implementation notes

**Local notifications**
- Support per-activity content while sharing the schedule.
- Consider scheduling two notifications per time if both activities are
  enabled, or roll into a combined reminder if notification volume is a
  concern.

**Analytics / insights**
- Extend stats computation to filter by activity type.
- Avoid double-counting in combined summaries.

**Accessibility**
- Activity switcher should be accessible (voiceover labels reflect active
  activity).
- Numbers and units use localized formatting.

### 5. Delivery strategy

**Phase 1**
- Data model changes + sit-up logging + activity switcher.
- Ensure pushup feature parity is unaffected.

**Phase 2**
- Insights + combined analytics.
- Enhanced notifications and optional cross-activity dashboard.

**Phase 3**
- Optional “Activity templates” (custom reps, custom goals, other exercises).

### 6. Visual direction (high level)

- Keep the current pushup UI palette.
- Sit-up theme: add a subtle accent color (e.g., teal) to distinguish progress.
- Reuse iconography to minimize cognitive load.

## Sit-up tracking integration guide (implementation steps)

Follow these changes to wire sit-up tracking into the existing app:

1. **Add activity models**
   - Create `ActivityType` with `pushups` and `situps`, plus helper strings for UI copy and notifications.
   - Add `ActivitySettings` to store per-activity targets and rest days.
2. **Extend entries**
   - Add `activityType` to `PushupEntry` and default legacy entries to `.pushups` during decoding.
3. **Refactor the store**
   - Add `selectedActivity` and a dictionary of `activitySettings` in `PushupStore`.
   - Route `dailyTargetTotal`, `total`, `streak`, and rest-day logic through the selected activity.
   - Persist new settings in `StorePayload` and migrate legacy payloads into the pushup settings bucket.
4. **Update the main tracker UI**
   - Add an activity segmented picker at the top of `PushManagerView`.
   - Swap copy to use `selectedActivity` (labels, log text, nav title, goal alert).
   - Filter “Today” entries by `activityType`.
   - Keep camera logging available only for pushups.
5. **Update settings**
   - Add an activity picker to `AdminView` and bind steppers to per-activity settings.
   - Update reminders copy to reflect the selected activity.
6. **Update notifications**
   - Adjust notification content to use activity-specific titles/body copy.
   - Remove any previously scheduled pushup reminders when re-scheduling.

With these updates, the sit-up tracking screens are fully integrated, share the same navigation flow, and allow per-activity targets while preserving all existing pushup data.

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
