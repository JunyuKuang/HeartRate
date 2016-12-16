//
//  WorkoutManager.swift
//  HeartRate
//
//  Created by Jonny on 10/25/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import Foundation
import HealthKit

class WorkoutManager {
    
    // MARK: - Initial
    
    /// Shared singleton.
    static let shared = WorkoutManager()
    
    private init() {}
    
    
    // MARK: - Properties
    
    let healthStore = HKHealthStore()
    
    var isWorkoutSessionRunning: Bool {
        return currentWorkoutSession != nil
    }
    
    private(set) var currentWorkoutSession: HKWorkoutSession?
    
    
    // MARK: - Public Methods
    
    func startWorkout(with configuration: HKWorkoutConfiguration) throws {
    
        do {
            let workoutSession = try HKWorkoutSession(configuration: configuration)
            healthStore.start(workoutSession)
            currentWorkoutSession = workoutSession
        } catch {
            throw error
        }
    }
    
    func stopWorkout() {
        guard let currentWorkoutSession = currentWorkoutSession else { return }
        healthStore.end(currentWorkoutSession)
        self.currentWorkoutSession = nil
    }
    
    func streamingQuery(withQuantityType type: HKQuantityType, startDate: Date, samplesHandler: @escaping ([HKQuantitySample]) -> Void) -> HKAnchoredObjectQuery {
        
        // Set up a predicate to obtain only samples from the local device starting from `startDate`.
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: nil)
        let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates:[datePredicate, devicePredicate])
        
        let queryUpdateHandler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { _, samples, _, _, error in
            
            if let error = error {
                print("Unexpected \(type) query error: \(error)")
            }
            
            if let samples = samples as? [HKQuantitySample], samples.count > 0 {
                DispatchQueue.main.async {
                    samplesHandler(samples)
                }
            }
        }
        
        let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: Int(HKObjectQueryNoLimit), resultsHandler: queryUpdateHandler)
        query.updateHandler = queryUpdateHandler
        
        return query
    }
    
}


