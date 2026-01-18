//
//  CameraView.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import SwiftUI

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PushupStore
    @State private var cameraCount: Int = 0
    @State private var cameraStatus: String = "Not calibrated"
    @State private var cameraDistance: Double?
    @State private var showingCameraAlert = false
    @State private var cameraAlertMessage = ""
    @State private var isCounting: Bool = false
    @State private var isCalibrated: Bool = false
    @State private var showCalibrationOverlay: Bool = true
    @State private var pendingSaveCount: Int?
    @State private var showingSaveConfirmation: Bool = false
    @State private var showFlash: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SectionCard(title: "Camera push-up counter") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Use the iPhone TrueDepth camera to estimate face distance for push-up counting.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ZStack {
                            CameraPushupCounterView(
                                count: $cameraCount,
                                statusText: $cameraStatus,
                                currentDistance: $cameraDistance,
                                isCounting: $isCounting,
                                isCalibrated: $isCalibrated,
                                showFlash: $showFlash,
                                onPermissionResult: { message in
                                    cameraAlertMessage = message
                                    showingCameraAlert = true
                                }
                            )
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            if showFlash {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.4))
                                    .transition(.opacity)
                                    .allowsHitTesting(false)
                            }

                            if showCalibrationOverlay {
                                CalibrationOverlayView(
                                    isCalibrated: isCalibrated,
                                    hasFaceLock: cameraDistance != nil,
                                    isCounting: isCounting,
                                    statusText: cameraStatus,
                                    onDismiss: { showCalibrationOverlay = false },
                                    onReset: resetCalibration
                                )
                                .transition(.opacity)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Push-ups counted")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(cameraCount)")
                                .font(.system(size: 56, weight: .bold))
                        }

                        if let distance = cameraDistance {
                            Text("Estimated distance: \(distance.formatted(.number.precision(.fractionLength(2)))) m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(cameraStatus)
                            .font(.headline)
                            .foregroundColor(.primary)

                        HStack {
                            Button("Start counting") {
                                isCounting = true
                                cameraStatus = "Counting started."
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Stop counting") {
                                stopCounting()
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Reset calibration") {
                            resetCalibration()
                        }
                        .buttonStyle(.bordered)

                        if !showCalibrationOverlay {
                            Button("Show calibration tips") {
                                showCalibrationOverlay = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Push-up Camera")
        .alert("Camera access", isPresented: $showingCameraAlert) {
            Button("OK") { }
        } message: {
            Text(cameraAlertMessage)
        }
        .alert("Save push-ups?", isPresented: $showingSaveConfirmation) {
            Button("Save") {
                finalizeStop(shouldSave: true)
            }
            Button("Discard", role: .destructive) {
                finalizeStop(shouldSave: false)
            }
        } message: {
            Text("Save \(pendingSaveCount ?? 0) push-ups to your log?")
        }

    }

    private func stopCounting() {
        isCounting = false
        cameraStatus = "Counting stopped. Review your session."
        guard cameraCount > 0 else {
            resetCameraSession(shouldDismiss: true)
            return
        }
        pendingSaveCount = cameraCount
        showingSaveConfirmation = true
    }

    private func finalizeStop(shouldSave: Bool) {
        if shouldSave, let count = pendingSaveCount, count > 0 {
            store.addEntry(count: count)
        }
        resetCameraSession(shouldDismiss: true)
        pendingSaveCount = nil
    }

    private func resetCalibration() {
        cameraCount = 0
        cameraStatus = "Not calibrated"
        cameraDistance = nil
        isCalibrated = false
        NotificationCenter.default.post(name: .resetPushupCalibration, object: nil)
    }

    private func resetCameraSession(shouldDismiss: Bool) {
        resetCalibration()
        if shouldDismiss {
            dismiss()
        }
    }
}

struct CalibrationOverlayView: View {
    let isCalibrated: Bool
    let hasFaceLock: Bool
    let isCounting: Bool
    let statusText: String
    let onDismiss: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Camera calibration")
                    .font(.headline)
                Spacer()
                Button("Dismiss") {
                    onDismiss()
                }
                .font(.caption)
            }

            Text("Follow these steps before starting your set.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                overlayStep(
                    title: "Keep your face centered in the frame.",
                    isComplete: hasFaceLock
                )
                overlayStep(
                    title: "Hold still to calibrate your starting distance.",
                    isComplete: isCalibrated
                )
                overlayStep(
                    title: "Tap Start counting when ready.",
                    isComplete: isCounting
                )
            }

            Text(statusText)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Reset calibration") {
                    onReset()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Got it") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(12)
    }

    private func overlayStep(title: String, isComplete: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isComplete ? .green : .secondary)
            Text(title)
                .font(.caption)
        }
    }
}
