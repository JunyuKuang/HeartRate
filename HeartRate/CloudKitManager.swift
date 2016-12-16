//
//  CloudKitManager.swift
//  CloudKitTest
//
//  Created by Jonny on 11/6/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import UIKit
import CloudKit

extension HeartRateRecord {
    
    init?(ckRecord: CKRecord) {
        guard let intergerValue = ckRecord["intergerValue"] as? Int,
            let recordDate = ckRecord["recordDate"] as? Date else { return nil }
        self.intergerValue = intergerValue
        self.recordDate = recordDate
        self.uuid = UUID(uuidString: ckRecord.recordID.recordName) ?? UUID()
    }
    
    var ckRecord: CKRecord {
        
        let recordID = CKRecordID(recordName: uuid.uuidString, zoneID: CloudKitManager.customZoneID)
        let record = CKRecord(recordType: "HeartRate", recordID: recordID)
        record["intergerValue"] = intergerValue as CKRecordValue
        record["recordDate"] = recordDate as CKRecordValue

        return record
    }
    
}


/// To enable database changes push, enabled follow capabilities: `iCloud - CloudKit`, `Push Notification`, `Background Modes - Remote Notifications`.   
class CloudKitManager {
    
    static let shared = CloudKitManager()
    
    /// The zond ID is useful when you configure a CKRecord.
    static let customZoneID = CKRecordZoneID(zoneName: "HeartRate", ownerName: CKCurrentUserDefaultName)
    
    private let privateDatabase = CKContainer.default().privateCloudDatabase
    
    private struct TimeoutInterval {
        static let request: TimeInterval = 30
        static let resource: TimeInterval = 7 * 24 * 60 * 60
    }
    
    private struct Key {
        static let cloudKitManager              = "CloudKitManager."
        
        static let pendingRecordsToSave         = cloudKitManager + "pendingRecordsToSave"
        static let pendingRecordIDsToDelete     = cloudKitManager + "pendingRecordIDsToDelete"
        static let savedZoneIDs                 = cloudKitManager + "savedZoneIDs"
        static let isSubscriptionLocallyCached  = cloudKitManager + "isSubscriptionLocallyCached"
        static let privateDatabaseChangeToken   = cloudKitManager + "privateDatabaseChangeToken"
        static let recordZoneChangeTokens       = cloudKitManager + "recordZoneChangeTokens"
        static let userRecordID                 = cloudKitManager + "userRecordID"
    }
    
    private let backgroundQueue = DispatchQueue(label: "CloudKitManager.backgroundQueue")
    
    private lazy var pendingRecordsToSave: [CKRecord] = {
        if let data = UserDefaults.standard.data(forKey: Key.pendingRecordsToSave) {
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [CKRecord] ?? []
        }
        return []
    }()
    
    private lazy var pendingRecordIDsToDelete: [CKRecordID] = {
        if let data = UserDefaults.standard.data(forKey: Key.pendingRecordIDsToDelete) {
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [CKRecordID] ?? []
        }
        return []
    }()
    
    private func saveContentsLocally() {
        backgroundQueue.async {
            let pendingRecordsToSaveData = NSKeyedArchiver.archivedData(withRootObject: self.pendingRecordsToSave)
            UserDefaults.standard.set(pendingRecordsToSaveData, forKey: Key.pendingRecordsToSave)
            
            let pendingRecordIDsToDeleteData = NSKeyedArchiver.archivedData(withRootObject: self.pendingRecordIDsToDelete)
            UserDefaults.standard.set(pendingRecordIDsToDeleteData, forKey: Key.pendingRecordIDsToDelete)
            
            print(#function)
        }
    }
    
    private var savedZoneIDs: [CKRecordZoneID] {
        get {
            if let data = UserDefaults.standard.data(forKey: Key.savedZoneIDs) {
                return NSKeyedUnarchiver.unarchiveObject(with: data) as? [CKRecordZoneID] ?? []
            } else {
                return []
            }
        }
        set {
            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            UserDefaults.standard.set(data, forKey: Key.savedZoneIDs)
        }
    }
    
    private var isSubscriptionLocallyCached: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Key.isSubscriptionLocallyCached)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.isSubscriptionLocallyCached)
            print("isSubscriptionLocallyCached didSet \(isSubscriptionLocallyCached)")
        }
    }
    
    private var privateDatabaseChangeToken: CKServerChangeToken? {
        get {
            if let data = UserDefaults.standard.data(forKey: Key.privateDatabaseChangeToken) {
                return NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
            } else {
                return nil
            }
        }
        set {
            if let token = newValue {
                let data = NSKeyedArchiver.archivedData(withRootObject: token)
                UserDefaults.standard.set(data, forKey: Key.privateDatabaseChangeToken)
            } else {
                UserDefaults.standard.set(nil, forKey: Key.privateDatabaseChangeToken)
            }
            print("privateDatabaseChangeToken didSet \(privateDatabaseChangeToken)")
        }
    }
    
    private var recordZoneChangeTokens: [CKRecordZoneID : CKServerChangeToken] {
        get {
            if let data = UserDefaults.standard.data(forKey: Key.recordZoneChangeTokens) {
                return NSKeyedUnarchiver.unarchiveObject(with: data) as? [CKRecordZoneID : CKServerChangeToken] ?? [:]
            } else {
                return [:]
            }
        }
        set {
            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            UserDefaults.standard.set(data, forKey: Key.recordZoneChangeTokens)
            print("recordZoneChangeTokens didSet \(recordZoneChangeTokens)")
        }
    }
    
    // Do not set nil to this property.
    private var userRecordID: CKRecordID? {
        get {
            if let idData = UserDefaults.standard.value(forKey: Key.userRecordID) as? Data {
                return NSKeyedUnarchiver.unarchiveObject(with: idData) as? CKRecordID ?? nil
            }
            return nil
        }
        set {
            guard let newRecordID = newValue else { return }
            
            print("userRecordID willSet:", newRecordID)
            
            func save() {
                let idData = NSKeyedArchiver.archivedData(withRootObject: newRecordID)
                UserDefaults.standard.set(idData, forKey: Key.userRecordID)
                handleUserAccountChanged()
            }
            
            if let userRecordID = userRecordID {
                if userRecordID == newRecordID {
                    print("userRecordID no change")
                } else {
                    print("userRecordID changed")
                    save()
                }
            } else {
                print("userRecordID initial set")
                save()
            }
        }
    }
    
    /// You should save (merge) all cached contents to CloudKit via `saveRecords(_:completion:)` when user account changed.
    var userAccountDidChangeHandler: (() -> Void)?
    
    /// This will revoke database and record zones tokens, upload all records to iCloud.
    func handleUserAccountChanged() {
        backgroundQueue.async {
            self.isSubscriptionLocallyCached = false
            self.privateDatabaseChangeToken = nil
            self.recordZoneChangeTokens = [:]
            self.savedZoneIDs = []
            
            self.pendingRecordsToSave = []
            self.pendingRecordIDsToDelete = []
            self.saveContentsLocally()
            
            self.createZoneIfNeeded(withZoneID: CloudKitManager.customZoneID)
            self.subscribeIfNeeded()
            self.userAccountDidChangeHandler?()
            self.fetchDatabaseChanges()
        }
    }
    
    private func subscribeIfNeeded(previousRetryAfterSeconds: TimeInterval = 0) {
        
        if isSubscriptionLocallyCached {
            return
        }
        
        print(#function, previousRetryAfterSeconds)
        
        let subscription = CKDatabaseSubscription(subscriptionID: "shared-changes")
        
        let notificationInfo = CKNotificationInfo()
        // When this property is true, the server includes the content-available flag in the push notification’s payload. That flag causes the system to wake or launch an app that is not currently running. The app is then given background execution time to download any data related to the push notification, such as the set of records that changed. If the app is already running in the foreground, the inclusion of this flag has no additional effect and the notification is delivered to the app delegate for processing as usual.
        notificationInfo.shouldSendContentAvailable = true
        
        subscription.notificationInfo = notificationInfo
        
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
        operation.timeoutIntervalForRequest = TimeoutInterval.request
        operation.timeoutIntervalForResource = TimeoutInterval.resource
        
        operation.modifySubscriptionsCompletionBlock = { _, _, error in
            if let error = error as? CKError {
                print("CKModifySubscriptionsOperation error: \(error)")
                
                if var retryAfterSeconds = error.retryAfterSeconds {
                    if previousRetryAfterSeconds > 1 {
                        retryAfterSeconds *= previousRetryAfterSeconds
                    }
                    self.backgroundQueue.asyncAfter(deadline: .now() + retryAfterSeconds) {
                        self.subscribeIfNeeded(previousRetryAfterSeconds: retryAfterSeconds)
                    }
                }
            } else {
                self.isSubscriptionLocallyCached = true
            }
        }
        privateDatabase.add(operation)
    }
    
//    private func retryIfNeeded(with error: CKError, retryHandler: @escaping (Bool) -> Void) {
//        if let retryAfter = error.userInfo[CKErrorRetryAfterKey] as? Double {
//            self.backgroundQueue.asyncAfter(deadline: .now() + retryAfter) {
//                retryHandler(true)
//            }
//        } else {
//            retryHandler(false)
//        }
//    }
    
    func fetchDatabaseChanges(previousRetryAfterSeconds: TimeInterval = 0, completionHandler: (() -> Void)? = nil) {
        print(#function, previousRetryAfterSeconds)
        
        let changesOperation = CKFetchDatabaseChangesOperation(previousServerChangeToken: privateDatabaseChangeToken)
        changesOperation.timeoutIntervalForRequest = TimeoutInterval.request
        changesOperation.timeoutIntervalForResource = TimeoutInterval.resource
        
        defer {
            privateDatabase.add(changesOperation)
        }
        
        changesOperation.fetchAllChanges = true
        changesOperation.recordZoneWithIDChangedBlock = { zoneID in
            self.fetchRecordZoneChanges(with: [zoneID])
        }
//        changesOperation.recordZoneWithIDWasDeletedBlock = { zoneID in } // delete local cache
        changesOperation.changeTokenUpdatedBlock = { newToken in
            self.privateDatabaseChangeToken = newToken
        }
        changesOperation.fetchDatabaseChangesCompletionBlock = { newToken, _, error in
            defer {
                completionHandler?()
            }
            if let error = error as? CKError {
                print("fetchDatabaseChangesCompletionBlock error: \(error)")
                
                // If the server returns a CKErrorChangeTokenExpired error, the previousServerChangeToken value was too old 
                // and the client should toss its local cache and re-fetch the changes in this record zone starting with a nil previousServerChangeToken.
                if error.code == .changeTokenExpired {
                    self.privateDatabaseChangeToken = nil
                    self.fetchDatabaseChanges(completionHandler: completionHandler)
                }
                else if var retryAfterSeconds = error.retryAfterSeconds {
                    if previousRetryAfterSeconds > 1 {
                        retryAfterSeconds *= previousRetryAfterSeconds
                    }
                    self.backgroundQueue.asyncAfter(deadline: .now() + retryAfterSeconds) {
                        self.fetchDatabaseChanges(previousRetryAfterSeconds: retryAfterSeconds,
                                                  completionHandler: completionHandler)
                    }
                }
            }
        }
    }
    
    var recordChangedHandler: ((CKRecord) -> Void)?
    var recordWithIDWasDeletedHandler: ((CKRecordID) -> Void)?
    var recordChangesCompletionHandler: (() -> Void)?
    
    private func fetchRecordZoneChanges(with zoneIDs: [CKRecordZoneID], previousRetryAfterSeconds: TimeInterval = 0) {
        print(#function, zoneIDs, previousRetryAfterSeconds)
        
        let recordZoneChangeTokens = self.recordZoneChangeTokens
        
        var optionsByRecordZoneID = [CKRecordZoneID : CKFetchRecordZoneChangesOptions]()
        
        for zoneID in zoneIDs {
            let options = CKFetchRecordZoneChangesOptions()
            options.previousServerChangeToken = recordZoneChangeTokens[zoneID]
            optionsByRecordZoneID[zoneID] = options
        }
        
        let changesOperation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, optionsByRecordZoneID: optionsByRecordZoneID)
        defer {
            privateDatabase.add(changesOperation)
        }
        
        changesOperation.timeoutIntervalForRequest = TimeoutInterval.request
        changesOperation.timeoutIntervalForResource = TimeoutInterval.resource
        
        changesOperation.fetchAllChanges = true
        
        changesOperation.recordChangedBlock = { record in
            self.recordChangedHandler?(record)
        }
        changesOperation.recordWithIDWasDeletedBlock = { recordID, _ in
            self.recordWithIDWasDeletedHandler?(recordID)
        }
        changesOperation.recordZoneChangeTokensUpdatedBlock = { zoneID, serverChangeToken, clientChangeTokenData in
            // significate change triggered, save token and ask controller to save state.
            self.recordZoneChangeTokens[zoneID] = serverChangeToken
            self.recordChangesCompletionHandler?()
        }
        
        func handleTokenExpiredErrorIfHave(error: CKError, zoneID: CKRecordZoneID?) -> Bool {
            
            var didHandle = false
            
            if error.code == .changeTokenExpired {
                // revoke tokens and fetch fully changes.
                if let zoneID = zoneID {
                    self.recordZoneChangeTokens[zoneID] = nil
                    self.fetchRecordZoneChanges(with: [zoneID])
                } else {
                    zoneIDs.forEach {
                        self.recordZoneChangeTokens[$0] = nil
                    }
                    self.fetchRecordZoneChanges(with: zoneIDs)
                }
                
                didHandle = true
            }
            // error.partialErrorsByItemID is not usable, confirmed (always returns nil)
            // must cast to [CKRecordID : NSError] first. cast [CKRecordID : CKError] or [CKRecordID : Error] returns nil
            else if let errorDictionary = error.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecordZoneID : NSError] {
                for (recordID, error) in errorDictionary {
                    if let error = error as? CKError, error.code == .changeTokenExpired {
                        // revoke tokens and fetch fully changes.
                        self.recordZoneChangeTokens[recordID] = nil
                        self.fetchRecordZoneChanges(with: [recordID])
                    }
                }
                didHandle = true
            }
                // If the server returns a CKErrorChangeTokenExpired error, the previousServerChangeToken value was too old and the client should toss its local cache and re-fetch the changes in this record zone starting with a nil previousServerChangeToken.
            return didHandle
        }
        
        changesOperation.recordZoneFetchCompletionBlock = { zoneID, serverChangeToken, clientChangeTokenData, _, error in
            if let error = error as? CKError {
                print("recordZoneFetchCompletionBlock error \(error)")
                if handleTokenExpiredErrorIfHave(error: error, zoneID: zoneID) {
                    print("Did revoke record zone change tokens")
                }
            } else {
                self.recordZoneChangeTokens[zoneID] = serverChangeToken
                self.recordChangesCompletionHandler?()
            }
        }
        changesOperation.fetchRecordZoneChangesCompletionBlock = { error in
            if let error = error as? CKError {
                print("fetchRecordZoneChangesCompletionBlock error \(error)")
                
                if handleTokenExpiredErrorIfHave(error: error, zoneID: nil) {
                    print("Did revoke record zone change tokens")
                }
                else if var retryAfterSeconds = error.retryAfterSeconds {
                    if previousRetryAfterSeconds > 1 {
                        retryAfterSeconds *= previousRetryAfterSeconds
                    }
                    self.backgroundQueue.asyncAfter(deadline: .now() + retryAfterSeconds) {
                        self.fetchRecordZoneChanges(with: zoneIDs, previousRetryAfterSeconds: retryAfterSeconds)
                    }
                }
            } else {
//                self.saveContentsLocally()
            }
        }
    }
    
    
    func startSync() {
        print(#function)
        
        backgroundQueue.async {
            self.subscribeIfNeeded()
            self.createZoneIfNeeded(withZoneID: CloudKitManager.customZoneID)
            self.fetchDatabaseChanges()
            self.modifyPendingRecords()
        }
    }
    
    /// Call this method when app enter background, to try again for previous sync failured records.
    ///
    /// - parameter completion: Called when finish modify, contains a bool to indicated whether modify success.
    private func modifyPendingRecords(completion: ((Bool) -> Void)? = nil) {
        backgroundQueue.async {
            print(#function)
            
            let pendingRecordsToSave = self.removingDuplicateRecords(from: self.pendingRecordsToSave)
            let pendingRecordIDsToDelete = self.removingDuplicateRecordIDs(from: self.pendingRecordIDsToDelete)
            self.modifyRecords(recordsToSave: pendingRecordsToSave, recordIDsToDelete: pendingRecordIDsToDelete, completion: completion)
        }
    }
    
    private func removingDuplicateRecords(from records: [CKRecord]) -> [CKRecord] {
        if records.isEmpty {
            return records
        }
        var recordsDictionary = [CKRecordID : CKRecord]()
        records.forEach {
            recordsDictionary[$0.recordID] = $0
        }
        return Array(recordsDictionary.values)
    }
    
    private func removingDuplicateRecordIDs(from recordIDs: [CKRecordID]) -> [CKRecordID] {
        return Array(Set(recordIDs))
        
//        if recordIDs.isEmpty {
//            return recordIDs
//        }
//        var recordIDsDictionary = [CKRecordID : Bool]()
//        recordIDs.forEach {
//            recordIDsDictionary[$0] = true
//        }
//        return Array(recordIDsDictionary.keys)
    }
    
    func saveRecords(_ recordsToSave: [CKRecord], completion: ((Bool) -> Void)? = nil) {
        backgroundQueue.async {
            let allPendingRecordsToSave = self.removingDuplicateRecords(from: self.pendingRecordsToSave + recordsToSave)
            self.pendingRecordsToSave = allPendingRecordsToSave
            self.modifyRecords(recordsToSave: allPendingRecordsToSave, recordIDsToDelete: [], completion: completion)
        }
    }
    
    func deleteRecords(withRecordIDs recordIDsToDelete: [CKRecordID], completion: ((Bool) -> Void)? = nil) {
        backgroundQueue.async {
            let allPendingRecordIDsToDelete = self.removingDuplicateRecordIDs(from: self.pendingRecordIDsToDelete + recordIDsToDelete)
            self.pendingRecordIDsToDelete = allPendingRecordIDsToDelete
            self.modifyRecords(recordsToSave: [], recordIDsToDelete: allPendingRecordIDsToDelete, completion: completion)
        }
    }
    
    /// The system allowed maximum record modifications count.
    ///
    /// If excute a CKModifyRecordsOperation with more than 400 record modifications, system will return a CKErrorLimitExceeded error.
    private let maximumRecordModificationsLimit = 400
    
    private func modifyRecords(recordsToSave: [CKRecord], recordIDsToDelete: [CKRecordID], previousRetryAfterSeconds: TimeInterval = 0, completion: ((Bool) -> Void)? = nil) {
        
        guard !recordsToSave.isEmpty || !recordIDsToDelete.isEmpty else {
            completion?(true)
            return
        }
        
        func handleLimitExceeded() {
            let recordsToSaveFirstSplit = recordsToSave[0 ..< recordsToSave.count / 2]
            let recordsToSaveSecondSplit = recordsToSave[recordsToSave.count / 2 ..< recordsToSave.count]
            let recordIDsToDeleteFirstSplit = recordIDsToDelete[0 ..< recordIDsToDelete.count / 2]
            let recordIDsToDeleteSecondSplit = recordIDsToDelete[recordIDsToDelete.count / 2 ..< recordIDsToDelete.count]
            
            self.modifyRecords(recordsToSave: Array(recordsToSaveFirstSplit), recordIDsToDelete: Array(recordIDsToDeleteFirstSplit))
            self.modifyRecords(recordsToSave: Array(recordsToSaveSecondSplit), recordIDsToDelete: Array(recordIDsToDeleteSecondSplit), completion: completion)
        }
        
        if recordsToSave.count + recordIDsToDelete.count > maximumRecordModificationsLimit {
            handleLimitExceeded()
            return
        }
        
        print(#function, "recordsToSave.count:", recordsToSave.count, "recordIDsToDelete.count", recordIDsToDelete.count)
        
        let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
        
        defer {
            privateDatabase.add(operation)
        }
        
        operation.savePolicy = .changedKeys
        
        operation.timeoutIntervalForRequest = TimeoutInterval.request
        operation.timeoutIntervalForResource = TimeoutInterval.resource
        
        operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            self.backgroundQueue.async {
                
                if let error = error as? CKError { // may partialError
                    print("CKModifyRecordsOperation error: \(error)")
                    
                    // error.partialErrorsByItemID is not usable, confirmed (always returns nil)
                    // must cast to [CKRecordID : NSError] first. cast [CKRecordID : CKError] or [CKRecordID : Error] returns nil
                    if let errorDictionary = error.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecordID : NSError] {
                        var unrecoverableRecordIDsDictionary = [CKRecordID : Bool]()
                        for (recordID, error) in errorDictionary {
                            if let error = error as? CKError {
                                if error.code == .zoneNotFound {
                                    // it the zone is not found, create one, then send the modification request again.
                                    self.createZone(withZoneID: CloudKitManager.customZoneID) { _, success in
                                        if success {
                                            self.modifyRecords(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete, completion: completion)
                                        } else {
                                            completion?(false)
                                        }
                                    }
                                    return
                                }
                                if error.code == .serverRecordChanged || error.code == .batchRequestFailed {
                                    unrecoverableRecordIDsDictionary[recordID] = true
                                }
                            }
                        }
                        if !unrecoverableRecordIDsDictionary.isEmpty {
                            self.pendingRecordsToSave = self.pendingRecordsToSave.filter { unrecoverableRecordIDsDictionary[$0.recordID] == nil }
                        }
                    }
                    else if error.code == .limitExceeded {
                        handleLimitExceeded()
                        return
                    }
                    // Document: The current user is not authenticated and no user record was available. This error can occur if the user is not logged into iCloud.
                    // Jonny:    Records will be fully upload to iCloud after user log in, so pending records are no more useful.
                    else if error.code == .notAuthenticated {
                        self.pendingRecordsToSave.removeAll()
                        self.pendingRecordIDsToDelete.removeAll()
                        self.saveContentsLocally()
                        completion?(false)
                        return
                    }
                    else if var retryAfterSeconds = error.retryAfterSeconds {
                        if previousRetryAfterSeconds > 1 {
                            retryAfterSeconds *= previousRetryAfterSeconds
                        }
                        self.backgroundQueue.asyncAfter(deadline: .now() + retryAfterSeconds) {
                            self.modifyRecords(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete,
                                               previousRetryAfterSeconds: retryAfterSeconds, completion: completion)
                        }
                        return
                    }
                    
                    // todo
//                    case userDeletedZone = 28
//                    The user deleted this zone from the settings UI. Remove your local copy of the zone’s data or ask the user if you should upload the data again.
                }
                
                if let savedRecords = savedRecords, !savedRecords.isEmpty {
                    var savedRecordIDsDictionary = [CKRecordID : Bool]()
                    savedRecords.forEach {
                        savedRecordIDsDictionary[$0.recordID] = true
                    }
                    self.pendingRecordsToSave = self.pendingRecordsToSave.filter { savedRecordIDsDictionary[$0.recordID] == nil }
                }
                if let deletedRecordIDs = deletedRecordIDs, !deletedRecordIDs.isEmpty {
                    var deletedRecordIDsDictionary = [CKRecordID: Bool]()
                    deletedRecordIDs.forEach {
                        deletedRecordIDsDictionary[$0] = true
                    }
                    self.pendingRecordIDsToDelete = self.pendingRecordIDsToDelete.filter { deletedRecordIDsDictionary[$0] == nil }
                }
                
                if error == nil {
                    self.saveContentsLocally()
                }
                
                completion?(error == nil)
            }
        }
    }
  
    /// Handler return nil if create failed.
    private func createZoneIfNeeded(withZoneID zoneID: CKRecordZoneID, completion: ((CKRecordZoneID, Bool) -> Void)? = nil) {
        print(#function)
        
        guard savedZoneIDs.first(where: { $0 == zoneID }) == nil else {
            completion?(zoneID, true)
            return
        }

        // fetch zone from CloudKit
        let fetchRecordZonesOperation = CKFetchRecordZonesOperation(recordZoneIDs: [zoneID])
        fetchRecordZonesOperation.timeoutIntervalForRequest = TimeoutInterval.request
        fetchRecordZonesOperation.timeoutIntervalForResource = TimeoutInterval.resource
        
        fetchRecordZonesOperation.fetchRecordZonesCompletionBlock = { recordZonesByZoneID, error in
            if let error = error as? CKError {
                print("fetchRecordZonesCompletionBlock error:", error, error.code.rawValue)
                
                if error.code == .partialFailure {
                    
                    if let errorDictionary = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Any], let error = errorDictionary.values.first as? CKError {
                        if error.code == CKError.zoneNotFound {
                            self.createZone(withZoneID: zoneID, completion: completion)
                            return
                        }
                    }
                }
                completion?(zoneID, false)
            }
            else if let recordZonesByZoneID = recordZonesByZoneID, recordZonesByZoneID[zoneID] != nil {
                self.savedZoneIDs = [zoneID]
                completion?(zoneID, true)
            }
        }
        privateDatabase.add(fetchRecordZonesOperation)
    }
    
    private func createZone(withZoneID zoneID: CKRecordZoneID, previousRetryAfterSeconds: TimeInterval = 0, completion: ((CKRecordZoneID, Bool) -> Void)? = nil) {
        
        print(#function, "savedZoneIDs:", savedZoneIDs)
        
        guard savedZoneIDs.first(where: { $0 == zoneID }) == nil else {
            completion?(zoneID, true)
            return
        }
        
        let recordZone = CKRecordZone(zoneID: zoneID)
        
        let modifyRecordZonesOperation = CKModifyRecordZonesOperation(recordZonesToSave: [recordZone], recordZoneIDsToDelete: nil)
        modifyRecordZonesOperation.timeoutIntervalForRequest = TimeoutInterval.request
        modifyRecordZonesOperation.timeoutIntervalForResource = TimeoutInterval.resource
        
        modifyRecordZonesOperation.modifyRecordZonesCompletionBlock = { zones, zoneIDs, error in
            if let error = error as? CKError {
                print("modifyRecordZonesCompletionBlock error:", error)
                
                if var retryAfterSeconds = error.retryAfterSeconds {
                    if previousRetryAfterSeconds > 1 {
                        retryAfterSeconds *= previousRetryAfterSeconds
                    }
                    self.backgroundQueue.asyncAfter(deadline: .now() + retryAfterSeconds) {
                        self.createZone(withZoneID: zoneID, previousRetryAfterSeconds: retryAfterSeconds, completion: completion)
                    }
                } else {
                    completion?(zoneID, false)
                }
            } else {
                // currently we only use one zone, so just rewrite the array
                self.savedZoneIDs = [zoneID]
                completion?(zoneID, true)
                print(#function, "success")
            }
        }
        
        privateDatabase.add(modifyRecordZonesOperation)
    }
    
    private init() {
        updateUserRecordID()
        
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(updateUserRecordID), name: .CKAccountChanged, object: nil)
        center.addObserver(self, selector: #selector(applicationDidBecomeActive), name: .UIApplicationDidBecomeActive, object: nil)
        center.addObserver(self, selector: #selector(applicationWillResignActive), name: .UIApplicationWillResignActive, object: nil)
        center.addObserver(self, selector: #selector(applicationDidEnterBackground), name: .UIApplicationDidEnterBackground, object: nil)
    }
    
    @objc private func updateUserRecordID() {
        print(#function)
        
        backgroundQueue.async {
            CKContainer.default().fetchUserRecordID { recordID, error in
                if let error = error {
                    print("fetchUserRecordID error:", error)
                    CKContainer.default().accountStatus { status, _ in
                        print("accountStatus", status.rawValue)
                    }
                } else if let recordID = recordID {
                    self.userRecordID = recordID
                }
            }
        }
    }
    
    @objc private func applicationDidBecomeActive() {
        if KJYReachability.shared.isInternetAvailable {
            startSync()
        }
    }
    
    @objc private func applicationWillResignActive() {
        saveContentsLocally()
    }
    
    @objc private func applicationDidEnterBackground() {
        
        guard KJYReachability.shared.isInternetAvailable && (!pendingRecordsToSave.isEmpty || !pendingRecordIDsToDelete.isEmpty) else { return }
        
        print("Start to finish update pending records in background.")
        
        var backgroundTaskIdentifier: UIBackgroundTaskIdentifier!
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        }
        modifyRecords(recordsToSave: pendingRecordsToSave, recordIDsToDelete: pendingRecordIDsToDelete) { _ in
            self.saveContentsLocally()
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        }
    }
}
