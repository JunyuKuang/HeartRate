//
//  InterfaceController.swift
//  WatchKitApp Extension
//
//  Created by Jonny on 10/9/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import WatchKit
import HealthKit

class InterfaceController: WKInterfaceController {
    
    @IBOutlet private var startStopButton: WKInterfaceButton!
    
    @IBOutlet private var realTimeHeartRateLabel: WKInterfaceLabel!
    
    @IBOutlet private var imageView: WKInterfaceImage!
    
    private lazy var heartRateChartGenerator: YOLineChartImage = {
        
        let chartGenerator = YOLineChartImage()
        
        chartGenerator.strokeWidth = 1.0
        chartGenerator.strokeColor = .white
        chartGenerator.fillColor = .clear //UIColor.white.withAlphaComponent(0.4)
        chartGenerator.pointColor = .white
        chartGenerator.isSmooth = true
        
        return chartGenerator
    }()
    
    private var defaultWorkoutConfiguration: HKWorkoutConfiguration {
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .outdoor
        
        return configuration
    }
    
    private let workoutManager = WorkoutManager.shared
    
    private var currentQuery: HKAnchoredObjectQuery?
    
    private var messageHandler: WatchConnectivityManager.MessageHandler?
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        messageHandler = WatchConnectivityManager.MessageHandler { [weak self] message in
            if message[.workoutStop] != nil {
                self?.stopWorkout()
            }
        }
        WatchConnectivityManager.shared.addMessageHandler(messageHandler!)
    }
    
    deinit {
        messageHandler?.invalidate()
    }
    
    
    // we can only get real time heart rate data when a workout session is running.
    func startWorkout(with configuration: HKWorkoutConfiguration? = nil) {
        
        // stop current workout if have
        if workoutManager.isWorkoutSessionRunning {
            workoutManager.stopWorkout()
        }
        if currentQuery != nil {
            stopHeartRateQuery()
        }
        
        setTitle("Running")
        startStopButton.setTitle("Stop")
        
        do {
            try workoutManager.startWorkout(with: configuration ?? defaultWorkoutConfiguration)
            
            WatchConnectivityManager.shared.send([.workoutStart : true])
            
            startHeartRateQuery()
            
            if WKExtension.shared().applicationState == .active {
                WKInterfaceDevice.current().play(.start)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    WKInterfaceDevice.current().play(.start)
                }
            }
        } catch {
            print("Workout initial error:", error)
            
            let errorData = NSKeyedArchiver.archivedData(withRootObject: error)
            WatchConnectivityManager.shared.send([.workoutError : errorData])
        }
    }
    
    func stopWorkout() {
        
        WKInterfaceDevice.current().play(.stop)
        
        setTitle("Ready")
        startStopButton.setTitle("Start")
        
        stopHeartRateQuery()
        WatchConnectivityManager.shared.send([.workoutStop : true])
        
        workoutManager.stopWorkout()
    }
    
    private func startHeartRateQuery() {
        
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        
        // Query samples that recorded in recent 15 min.
//        let predicate = HKQuery.predicateForSamples(withStart: Date() - 15 * 60, end: Date(), options: [])
//        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
//        
//        workoutManager.healthStore.execute(HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: 10, sortDescriptors: [sortDescriptor]) { _, samples, error in
//            
//            if let samples = samples as? [HKQuantitySample] {
//                // sort from old to new
//                self.handle(newHeartRateSamples: Array(samples.reversed()))
//            }
//        })
        
        let query = workoutManager.streamingQuery(withQuantityType: heartRateType, startDate: Date()) { samples in
            self.handle(newHeartRateSamples: samples)
        }
        currentQuery = query
        workoutManager.healthStore.execute(query)
    }
    
    private func stopHeartRateQuery() {
        guard let query = currentQuery else { return }
        workoutManager.healthStore.stop(query)
        currentQuery = nil
    }
    
    private func handle(newHeartRateSamples samples: [HKQuantitySample]) {
        
        let samplesCount = samples.count
        
        for (index, sample) in samples.enumerated() {
            let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
            
            let doubleValue = sample.quantity.doubleValue(for: heartRateUnit)
            let integerValue = Int(round(doubleValue))
            let date = sample.startDate
            let dateString = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
            
            print(doubleValue, dateString)
            
            // notify our iPhone app.
            WatchConnectivityManager.shared.send([
                .heartRateIntergerValue : integerValue,
                .heartRateRecordDate : date,
                ])
            
            DispatchQueue.main.async {
                
                self.heartRateChartGenerator.values.append(NSNumber(integerLiteral: integerValue))
                
                // only update UI when sample is the last one.
                guard index == samplesCount - 1 else { return }
                
                // guard WKExtension.shared().applicationState == .active else { return }
                
                self.realTimeHeartRateLabel.setText("\(integerValue)" + " bpm\n" + dateString)
                
                var values = self.heartRateChartGenerator.values
                
                // The framework require at least 2 point to draw a line chart.
                guard values.count >= 2 else { return }
                
                // Only shows recent 10 heart rate records on chart.
                let maximumShowsCount = 10
                
                if values.count > maximumShowsCount {
                    values = (values as NSArray).subarray(with: NSMakeRange(values.count - maximumShowsCount, maximumShowsCount)) as! [NSNumber]
                }
                
                self.heartRateChartGenerator.values = values
                
                let imageFrame = CGRect(x: 0, y: 0, width: self.contentFrame.width, height: 50)
                
                let uiImage = self.heartRateChartGenerator.draw(in: imageFrame, scale: WKInterfaceDevice.current().screenScale, edgeInsets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)) // draw an image
                
                self.imageView.setImage(uiImage)
            }
        }
    }
    
    
    // MARK: - Actions
    
    @IBAction func startStopButtonDidTap() {
        
        if workoutManager.isWorkoutSessionRunning {
            // heart rate recording, stop it.
            stopWorkout()
        }
        else {
            // heart rate recording not start yet, start.
            startWorkout()
        }
    }
    
}
