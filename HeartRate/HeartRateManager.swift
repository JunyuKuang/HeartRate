//
//  HeartRateManager.swift
//  HeartRate
//
//  Created by Jonny on 11/7/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import Foundation
import HealthKit
import UIKit

func synchronized(_ lock: Any, closure: () -> ()) {
    objc_sync_enter(lock)
    closure()
    objc_sync_exit(lock)
}

class HeartRateManager {
    
    private let healthStore = HKHealthStore()
    
    var records = [HeartRateRecord]() {
        didSet {
            recordsUpdateHandler?(records)
        }
    }
    
    var recordsUpdateHandler: (([HeartRateRecord]) -> Void)?
    
    var recordDictionary = [UUID : HeartRateRecord]()
    
    private struct Key {
        static let recordDictionary = "HeartRateManager.recordDictionary"
    }
    
    init() {
     
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive), name: .UIApplicationWillResignActive, object: nil)
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            let termRecordsRaw = UserDefaults.standard.value(forKey: Key.recordDictionary) as? [[String : Any]] ?? []
            
            let records = termRecordsRaw.flatMap { HeartRateRecord(propertyList: $0) }
            
            DispatchQueue.main.async {
                self.records = records
            }
            
            var recordDictionary = [UUID : HeartRateRecord]()
            records.forEach {
                recordDictionary[$0.uuid] = $0
            }
            self.recordDictionary = recordDictionary
            
            let ckManager = CloudKitManager.shared
            
            ckManager.recordChangedHandler = { record in
                print("recordChangedHandler")
                guard let heartRateRecord = HeartRateRecord(ckRecord: record) else { return }
                self.recordDictionary[heartRateRecord.uuid] = heartRateRecord
            }
            
            ckManager.recordWithIDWasDeletedHandler = { recordID in
                print("recordWithIDWasDeletedHandler")
                guard let uuid = UUID(uuidString: recordID.recordName) else { return }
                self.recordDictionary[uuid] = nil
            }
            
            ckManager.recordChangesCompletionHandler = {
                print("recordChangesCompletionHandler")
                
                let newRecords = self.recordDictionary.values.sorted { $0.recordDate > $1.recordDate }
                DispatchQueue.main.async {
                    self.records = newRecords
                }
            }
        }
    }
    
    func save(_ heartRates: [HeartRateRecord]) {
        
        records.insert(contentsOf: heartRates, at: 0)
        heartRates.forEach { recordDictionary[$0.uuid] = $0 }
        CloudKitManager.shared.saveRecords(heartRates.map { $0.ckRecord })
        
        asyncSaveRecordsLocally()
    }
    
    func delete(_ heartRates: [HeartRateRecord]) {
        
        heartRates.forEach { recordDictionary[$0.uuid] = nil }
        records = recordDictionary.values.sorted { $0.recordDate > $1.recordDate }
        
        CloudKitManager.shared.deleteRecords(withRecordIDs: heartRates.map { $0.ckRecord.recordID })
        asyncSaveRecordsLocally()
    }
    
    func deleteAllRecords() {
        
        CloudKitManager.shared.deleteRecords(withRecordIDs: recordDictionary.values.map { $0.ckRecord.recordID })
        
        recordDictionary.removeAll()
        records.removeAll()
        
        asyncSaveRecordsLocally()
    }
    
    @objc func applicationWillResignActive() {
        asyncSaveRecordsLocally()
    }
    
    private func asyncSaveRecordsLocally() {
        print(#function)
        DispatchQueue.global(qos: .background).async {
            UserDefaults.standard.set(self.records.map { $0.propertyList }, forKey: Key.recordDictionary)
        }
    }
    
    func startWatchApp(handler: @escaping (Error?) -> Void) {
        
        WatchConnectivityManager.shared?.fetchActivatedSession { _ in
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .outdoor

        self.healthStore.startWatchApp(with: configuration) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("healthStore.startWatchApp error:", error)
                } else {
                    print("healthStore.startWatchApp success.")
                }
                handler(error)
            }
        }
        }
    }
    
    
    
}
