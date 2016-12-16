//
//  KJYReachability.swift
//  LightDefine
//
//  Created by Jonny on 9/12/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import Foundation

class KJYReachability {
    
    static let shared = KJYReachability()
    
    var isInternetAvailable: Bool {
        return true
    }
}


//class KJYReachability: TMReachability {
//    
//    static let shared = KJYReachability.forInternetConnection()!
//    
//    var isInternetAvailable: Bool {
//        let status = currentReachabilityStatus()
//        return status == .ReachableViaWiFi || status == .ReachableViaWWAN
//    }
//}
