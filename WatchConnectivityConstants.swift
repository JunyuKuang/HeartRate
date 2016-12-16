//
//  WatchConnectivityConstants.swift
//  HeartRate
//
//  Created by Jonny on 10/25/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

extension WatchConnectivityManager.MessageKey {
    
    static let workoutStart = WatchConnectivityManager.MessageKey("Workout.start")
    static let workoutStop = WatchConnectivityManager.MessageKey("Workout.stop")
    static let workoutError = WatchConnectivityManager.MessageKey("Workout.error")
    
    static let heartRateIntergerValue = WatchConnectivityManager.MessageKey("HeartRate.intergerValue")
    static let heartRateRecordDate = WatchConnectivityManager.MessageKey("HeartRate.recordDate")
    
}
