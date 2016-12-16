//
//  WatchConnectivityManager.swift
//  HeartRate
//
//  Created by Jonny on 10/25/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import WatchConnectivity

/// The communication manager between iPhone and Apple Watch.
class WatchConnectivityManager: NSObject, WCSessionDelegate {
    
    // MARK: - Initial
    
    #if os(iOS)
    /// A shared singleton. Returns nil if the Watch Connectivity framework is not supported on current device.
    static var shared: WatchConnectivityManager? {
        if WCSession.isSupported() {
            return WatchConnectivityManager.sharedInstance
        }
        return nil
    }
    #elseif os(watchOS)
    /// A shared singleton.
    static var shared: WatchConnectivityManager {
        // Watch Connectivity framework is always supported on watchOS.
        return WatchConnectivityManager.sharedInstance
    }
    #endif
    
    /// A shared singleton.
    private static let sharedInstance = WatchConnectivityManager()
    
    private override init() {
        super.init()
    }
    
    
    // MARK: - Properties

    private var defaultSession: WCSession {
        return WCSession.default()
    }
    
    /// Called from main queue.
    private var sessionActivationCompletionHandlers = [((WCSession) -> Void)]()
    
    /// The handles use to response message and transferred user info that send from the paired device.
    ///
    /// Every handler is promised to be called from main queue.
    private var messageHandlers = [MessageHandler]()
    
    
    // MARK: - Functions
    
    /// Add the handle use to response message and transferred user info that send from the paired device.
    ///
    /// The handler is promised to be called from main queue.
    func addMessageHandler(_ messageHandler: MessageHandler) {
        messageHandlers.append(messageHandler)
    }
    
    fileprivate func removeMessageHandler(_ messageHandler: MessageHandler) {
        if let index = messageHandlers.index(of: messageHandler) {
            messageHandlers.remove(at: index)
        }
    }
    
    /// Activates the wcSession asynchronously.
    func activate() {
        defaultSession.delegate = self
        defaultSession.activate()
    }
    
    /// Fetch the WCSession that is activated. If currently the session is not activated, will activate it first
    ///
    /// - parameter handler: Return nil if current device do not support the Watch Connectivity. Will be called from main queue.
    func fetchActivatedSession(handler: @escaping (WCSession) -> Void) {
        
        activate()
        
        if defaultSession.activationState == .activated {
            handler(defaultSession)
        } else {
            sessionActivationCompletionHandlers.append(handler)
        }
    }
    
    func fetchReachableState(handler: @escaping (Bool) -> Void) {
        fetchActivatedSession { session in
            handler(session.isReachable)
        }
    }
    
    /// Send a message to paired device. 
    ///
    /// If paired device is not reachable, the message won't be send.
    func send(_ message: [MessageKey : Any]) {
        fetchActivatedSession { session in
            session.sendMessage(self.sessionMessage(for: message), replyHandler: nil)
        }
    }
    
    /// Transfer a message to paired device.
    func transfer(_ message: [MessageKey : Any]) {
        fetchActivatedSession { session in
            session.transferUserInfo(self.sessionMessage(for: message))
        }
    }
    
    private func sessionMessage(for message: [MessageKey : Any]) -> [String : Any] {
        var sessionMessage = [String : Any]()
        message.forEach { sessionMessage[$0.key.rawValue] = $0.value }
        return sessionMessage
    }
    
    private func handle(_ receivedMessage: [String : Any]) {
        
        var convertedMessage = [MessageKey: Any]()
        receivedMessage.forEach { convertedMessage[MessageKey($0.key)] = $0.value }
        
        DispatchQueue.main.async {
            self.messageHandlers.forEach { $0.handler(convertedMessage) }
        }
    }
    
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print(#function)
        
        if activationState == .activated {
            DispatchQueue.main.async {
                self.sessionActivationCompletionHandlers.forEach { $0(session) }
                self.sessionActivationCompletionHandlers.removeAll()
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handle(message)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handle(userInfo)
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    
    func sessionDidDeactivate(_ session: WCSession) {
        // support quick switching between Apple Watch devices in the iOS app
        defaultSession.activate()
    }
    #endif
    
    
    // MARK: - Structs
    
    struct MessageKey: RawRepresentable, Hashable {
        
        private static var hashDictionary = [String : Int]()
        
        let rawValue: String
        
        let hashValue: Int
        
        init(_ rawValue: String) {
            self.rawValue = rawValue
            self.hashValue = rawValue.hashValue
        }
        
        init(rawValue: String) {
            self.rawValue = rawValue
            self.hashValue = rawValue.hashValue
        }
        
        static func ==(lhs: MessageKey, rhs: MessageKey) -> Bool {
            return lhs.rawValue == rhs.rawValue
        }
    }
    
    struct MessageHandler: Hashable {
        
        fileprivate let uuid: UUID
        
        fileprivate let handler: (([MessageKey : Any]) -> Void)
        
        let hashValue: Int
        
        init(handler: @escaping (([MessageKey : Any]) -> Void)) {
            self.handler = handler
            self.uuid = UUID()
            self.hashValue = self.uuid.hashValue
        }
        
        func invalidate() {
            let manager: WatchConnectivityManager? = WatchConnectivityManager.shared
            manager?.removeMessageHandler(self)
        }
        
        static func ==(lhs: MessageHandler, rhs: MessageHandler) -> Bool {
            return lhs.hashValue == rhs.hashValue
        }
    }
    
}
