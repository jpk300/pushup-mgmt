//
//  CameraPushupCounterView.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import ARKit
import AVFoundation
import SwiftUI
import UIKit

extension Notification.Name {
    static let resetPushupCalibration = Notification.Name("resetPushupCalibration")
}

struct CameraPushupCounterView: UIViewRepresentable {
    @Binding var count: Int
    @Binding var statusText: String
    @Binding var currentDistance: Double?
    @Binding var isCounting: Bool
    @Binding var isCalibrated: Bool
    @Binding var showFlash: Bool
    let onPermissionResult: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            count: $count,
            statusText: $statusText,
            currentDistance: $currentDistance,
            isCounting: $isCounting,
            isCalibrated: $isCalibrated,
            showFlash: $showFlash,
            onPermissionResult: onPermissionResult
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.scene = SCNScene()
        context.coordinator.attachBlurOverlay(to: view)
        context.coordinator.startSession(on: view.session)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    final class Coordinator: NSObject, ARSessionDelegate {
        @Binding private var count: Int
        @Binding private var statusText: String
        @Binding private var currentDistance: Double?
        @Binding private var isCounting: Bool
        @Binding private var isCalibrated: Bool
        @Binding private var showFlash: Bool
        private let onPermissionResult: (String) -> Void
        private var baselineDistance: Double?
        private var isNear: Bool = false
        private var calibrationSamples: [(time: Date, distance: Double)] = []
        private var downCandidateStart: Date?
        private var lastDownTime: Date?
        private var lastRepTime: Date?
        private var smoothedDistance: Double?
        private weak var session: ARSession?
        private weak var sceneView: ARSCNView?
        private weak var blurView: UIVisualEffectView?
        private let maskLayer = CAShapeLayer()

        init(
            count: Binding<Int>,
            statusText: Binding<String>,
            currentDistance: Binding<Double?>,
            isCounting: Binding<Bool>,
            isCalibrated: Binding<Bool>,
            showFlash: Binding<Bool>,
            onPermissionResult: @escaping (String) -> Void
        ) {
            _count = count
            _statusText = statusText
            _currentDistance = currentDistance
            _isCounting = isCounting
            _isCalibrated = isCalibrated
            _showFlash = showFlash
            self.onPermissionResult = onPermissionResult
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(resetCalibration), name: .resetPushupCalibration, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self, name: .resetPushupCalibration, object: nil)
            session?.pause()
        }

        func attachBlurOverlay(to view: ARSCNView) {
            sceneView = view
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            blur.frame = view.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            maskLayer.fillRule = .evenOdd
            blur.layer.mask = maskLayer
            view.addSubview(blur)
            blurView = blur
            updateBlurMask(center: CGPoint(x: view.bounds.midX, y: view.bounds.midY), in: view.bounds)
        }

        func startSession(on session: ARSession) {
            self.session = session
            guard ARFaceTrackingConfiguration.isSupported else {
                statusText = "Face tracking requires a TrueDepth camera."
                return
            }
            requestCameraAccessIfNeeded()
        }

        private func requestCameraAccessIfNeeded() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                runSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.onPermissionResult("Camera access granted.")
                            self.runSession()
                        } else {
                            self.statusText = "Camera access denied."
                            self.onPermissionResult("Camera access denied. Enable it in Settings.")
                        }
                    }
                }
            case .denied, .restricted:
                statusText = "Camera access denied."
                onPermissionResult("Camera access denied. Enable it in Settings.")
            @unknown default:
                statusText = "Camera access unavailable."
                onPermissionResult("Camera access unavailable.")
            }
        }

        private func runSession() {
            guard let session else { return }
            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            statusText = "Look at the camera to calibrate."
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            let faceTransform = faceAnchor.transform
            let zDistance = abs(Double(faceTransform.columns.3.z))
            DispatchQueue.main.async {
                self.currentDistance = zDistance
                self.handleDistance(zDistance)
                if let point = self.projectFaceCenter(faceTransform) {
                    self.updateBlurMask(center: point, in: self.sceneView?.bounds ?? .zero)
                }
            }
        }

        private func projectFaceCenter(_ transform: simd_float4x4) -> CGPoint? {
            guard let sceneView else { return nil }
            let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let projected = sceneView.projectPoint(SCNVector3(position))
            return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        }

        private func updateBlurMask(center: CGPoint, in bounds: CGRect) {
            guard bounds.width > 0, bounds.height > 0 else { return }
            let radius: CGFloat = 120
            let path = UIBezierPath(rect: bounds)
            let holeRect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            path.append(UIBezierPath(ovalIn: holeRect))
            maskLayer.frame = bounds
            maskLayer.path = path.cgPath
        }

        private func handleDistance(_ distance: Double) {
            let calibrationWindowSeconds: TimeInterval = 1.2
            let calibrationMaxVariance = 0.025
            let minCalibrationSamples = 20
            let minDownHoldSeconds: TimeInterval = 0.15
            let minRepDurationSeconds: TimeInterval = 0.45
            let smoothingWeight = 0.2

            if let smoothedDistance {
                self.smoothedDistance = (smoothingWeight * distance) + ((1 - smoothingWeight) * smoothedDistance)
            } else {
                smoothedDistance = distance
            }

            let effectiveDistance = smoothedDistance ?? distance

            if baselineDistance == nil {
                let now = Date()
                calibrationSamples.append((time: now, distance: effectiveDistance))
                calibrationSamples.removeAll { now.timeIntervalSince($0.time) > calibrationWindowSeconds }

                if calibrationSamples.count >= minCalibrationSamples {
                    let distances = calibrationSamples.map(\.distance).sorted()
                    if let minDistance = distances.first, let maxDistance = distances.last,
                       (maxDistance - minDistance) <= calibrationMaxVariance {
                        let median = distances[distances.count / 2]
                        baselineDistance = median
                        isCalibrated = true
                        calibrationSamples.removeAll()
                        statusText = "Calibrated at \(median.formatted(.number.precision(.fractionLength(2)))) m. Begin push-ups."
                        return
                    }
                }

                statusText = "Hold still to calibrate."
                return
            }

            guard isCounting else {
                statusText = "Counting paused."
                return
            }

            guard let baselineDistance = baselineDistance else { return }
            let downDelta = max(0.05, min(0.15, baselineDistance * 0.08))
            let upTolerance = max(0.015, baselineDistance * 0.03)
            let nearDistance = max(baselineDistance - downDelta, 0.05)
            let now = Date()
            if effectiveDistance <= nearDistance && !isNear {
                if let downCandidateStart = downCandidateStart {
                    if now.timeIntervalSince(downCandidateStart) >= minDownHoldSeconds {
                        isNear = true
                        lastDownTime = now
                        self.downCandidateStart = nil
                        statusText = "Down position detected."
                    }
                } else {
                    downCandidateStart = now
                }
            } else if effectiveDistance > nearDistance {
                downCandidateStart = nil
            }

            if effectiveDistance >= baselineDistance - upTolerance && isNear {
                if let lastDownTime, now.timeIntervalSince(lastDownTime) >= minRepDurationSeconds {
                    if lastRepTime == nil || now.timeIntervalSince(lastRepTime ?? now) >= minRepDurationSeconds {
                        isNear = false
                        lastRepTime = now
                        count += 1
                        statusText = "Up position detected. Push-up counted."
                        showFlash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.showFlash = false
                        }
                    }
                }
            }
        }

        @objc private func resetCalibration() {
            baselineDistance = nil
            isNear = false
            isCalibrated = false
            calibrationSamples.removeAll()
            smoothedDistance = nil
            downCandidateStart = nil
            lastDownTime = nil
            lastRepTime = nil
            statusText = "Not calibrated"
        }
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
        uiView.session.delegate = nil
    }
}
