//
//  AppDelegate.swift
//  HeartRate
//
//  Created by Jonny on 10/9/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import UIKit
import HealthKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        application.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalMinimum)
        application.registerForRemoteNotifications()
        
        // activate WCSession at app startup.
        WatchConnectivityManager.shared?.activate()
        
        if HKHealthStore.isHealthDataAvailable() {
            let heartRateType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!
            let typesToRead = Set([heartRateType])
            
            HKHealthStore().requestAuthorization(toShare: nil, read: typesToRead) { success, error in }
        }
        
        // force init the manager at app startup.
        _ = CloudKitManager.shared
        
        window?.makeKeyAndVisible()
        
        return true
    }
    
    // receive CloudKit push notification
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print(#function)
        self.application(application, performFetchWithCompletionHandler: completionHandler)
    }
    
    // background fetch, the app will be waked periodcally by the system
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print(#function)
        
        var didCompleted = false
        
        // maximum fetch duration is 30 seconds, we set the deadline to 25 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            if !didCompleted {
                didCompleted = true
                completionHandler(.noData)
            }
        }
        
        CloudKitManager.shared.fetchDatabaseChanges {
            print("handleRemoteNotification completed")
            
            // give async process 2 more seconds to complete tasks
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if !didCompleted {
                    didCompleted = true
                    completionHandler(.newData)
                }
            }
        }
    }
    
    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        
        HKHealthStore().handleAuthorizationForExtension { _, error in
            if let error = error {
                print(error)
            }
        }
    }
    
}

