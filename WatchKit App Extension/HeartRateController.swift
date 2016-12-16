//
//  HeartRateController.swift
//  InstantHeart
//
//  Created by Jonny on 3/27/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import Foundation
import HealthKit

struct HeartRate : Equatable {
    
    // Beat per minute.
    let bpm: Int
    
    // The heart rate's collect date.
    let date: Date
    
    static func ==(lhs: HeartRate, rhs: HeartRate) -> Bool {
        return lhs.bpm == rhs.bpm && lhs.date == rhs.date
    }
}

class HeartRateController {
    
    static let sharedInstance = HeartRateController()
    
    private init() {}
    
    private let healthStore = HKHealthStore()
    
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!
    
    private let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
    
    
    /// Fetch recent heart rates.
    /// - parameter handler: The closure will return you a heart rate list that sort from latest to earliest.
    func fetchHeartRates(startDate: Date? = nil, endDate: Date? = nil, limit: Int = HKObjectQueryNoLimit, handler: @escaping ([HeartRate], Error?) -> Void) {
        
        fetchHeartRateSamplesWithStartDate(startDate, endDate: endDate, limit: limit) { samples, error in
            let heartRates = self.heartRatesWithSamples(samples)
            handler(heartRates, error)
            
            if let error = error {
                print("fetchHeartRates error: \(error)")
            }
        }
    }
    
    /// Latest first, earliest last.
    private func fetchHeartRateSamplesWithStartDate(_ startDate: Date?, endDate: Date?, limit: Int, handler: @escaping ([HKQuantitySample], Error?) -> Void) {
        
        requestAuthorization {
            
            let adjustedEndDate = endDate?.addingTimeInterval(-1) // complication requires the samples must before the end date.
            
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: adjustedEndDate, options: [.strictEndDate])
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            
            let query = HKSampleQuery(sampleType: self.heartRateType, predicate: predicate, limit: limit, sortDescriptors: [sortDescriptor]) { query, samples, error in
                
                if let samples = samples as? [HKQuantitySample] {
                    handler(samples, error)
                } else {
                    handler([], error)
                }
            }
            
            self.healthStore.execute(query)
        }
    }
    
    
//    /// Fetch recent heart rates. 
//    /// - parameter handler: The closure will return you a heart rate list that generated in 24 hours and sort from latest to earliest.
//    func fetchHeartRates(handler: (heartRates: [HeartRate], error: NSError?) -> Void) {
//        
////        let fakes = randomHeartRatesWithEndDate(NSDate())
////        handler(heartRates: fakes, error: nil)
////        
////        return()
//        
//        fetchHeartRateSamples { samples, error in
//            let heartRates = self.heartRatesWithSamples(samples)
//            handler(heartRates: heartRates, error: error)
//            
//            if let error = error {
//                print("fetchHeartRates error: \(error)")
//            }
//        }
//    }
//    
//    /// Latest first, earliest last.
//    private func fetchHeartRateSamples(handler: (samples: [HKQuantitySample], error: NSError?) -> Void) {
//        
//        requestAuthorization {
//            
//            let endDate = NSDate()
//            let startDate = endDate.dateByAddingTimeInterval(-24 * 60 * 60)
//            
//            let predicate = HKQuery.predicateForSamplesWithStartDate(startDate, endDate: endDate, options: [])
//            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
//            
//            let query = HKSampleQuery(sampleType: self.heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { query, samples, error in
//                
//                if let samples = samples as? [HKQuantitySample] {
//                    handler(samples: samples, error: error)
//                } else {
//                    handler(samples: [], error: error)
//                }
//            }
//            
//            self.healthStore.executeQuery(query)
//        }
//    }
    
    private func heartRatesWithSamples(_ samples: [HKQuantitySample]) -> [HeartRate] {
        
        var heartRates = [HeartRate]()
        
        for sample in samples {
            let bpm = Int(round(sample.quantity.doubleValue(for: heartRateUnit)))
            let date = sample.endDate
            heartRates.append(HeartRate(bpm: bpm, date: date))
        }
        
        return heartRates
    }
    
    private func requestAuthorization(_ handler: @escaping () -> Void) {
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let readTypes = Set([heartRateType])
        
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            handler()
            if let error = error {
                print(error)
            }
        }
    }
    
    private func randomHeartRatesWithEndDate(_ endDate: Date) -> [HeartRate] {
        
        var heartRates = [HeartRate]()
        
        for i in (0 ..< 500).reversed() {
            let date = endDate.addingTimeInterval(-10 * 60 * TimeInterval(i) - 60)
            
            let heartRate = HeartRate(bpm: 60 + Int(arc4random_uniform(100)), date: date)
            heartRates.append(heartRate)
        }
        
        return heartRates
    }
    
    
    func saveRandomHeartRatesWithEndDate(_ endDate: Date, amount: Int = 6 * 24 * 5) {
        
        requestAuthorization {
            
            var heartRateSamples = [HKQuantitySample]()
            
            for i in 0 ..< amount {
                let date = endDate.addingTimeInterval(-10 * 60 * TimeInterval(i) - 60)
                let randomBPM = 60 + Double(arc4random_uniform(101))
                let sample = HKQuantitySample(type: self.heartRateType, quantity: HKQuantity(unit: self.heartRateUnit, doubleValue: randomBPM), start: date, end: date, device: HKDevice.local(), metadata: nil)
                
                heartRateSamples.append(sample)
            }
            
            self.healthStore.save(heartRateSamples) { success, error in
                print("save objects success? \(success), error \(error)")
            }
        }
    }
}
