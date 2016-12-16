//
//  ExtensionDelegate.swift
//  WatchKitApp Extension
//
//  Created by Jonny on 10/24/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import WatchKit
import HealthKit

class ExtensionDelegate: NSObject, WKExtensionDelegate {

    override init() {
        super.init()
        
        // force activate WCSession at extension startup.
        WatchConnectivityManager.shared.activate()
    }
    
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let root = WKExtension.shared().rootInterfaceController as! InterfaceController
        root.startWorkout(with: workoutConfiguration)
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // Sent when the system needs to launch the application in the background to process tasks. Tasks arrive in a set, so loop through and process each one.
        for task in backgroundTasks {
            // Use a switch statement to check the task type
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                // Be sure to complete the background task once you’re done.
                backgroundTask.setTaskCompleted()
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                // Snapshot tasks have a unique completion call, make sure to set your expiration date
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Be sure to complete the connectivity task once you’re done.
                connectivityTask.setTaskCompleted()
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                // Be sure to complete the URL session task once you’re done.
                urlSessionTask.setTaskCompleted()
            default:
                // make sure to complete unhandled task types
                task.setTaskCompleted()
            }
        }
    }

}
