//
//  HeartRateRecord.swift
//  HeartRate
//
//  Created by Jonny on 11/7/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

struct HeartRateRecord {
    
    let intergerValue: Int
    let recordDate: Date
    let uuid: UUID
    
    init(intergerValue: Int, recordDate: Date) {
        self.intergerValue = intergerValue
        self.recordDate = recordDate
        self.uuid = UUID()
    }
    
    init?(propertyList: [String : Any]) {
        
        guard let intergerValue = propertyList["intergerValue"] as? Int,
            let recordDate = propertyList["recordDate"] as? Date,
            let uuidString = propertyList["uuidString"] as? String,
            let uuid = UUID(uuidString: uuidString) else { return nil }
        
        self.intergerValue = intergerValue
        self.recordDate = recordDate
        self.uuid = uuid
    }
    
    var propertyList: [String : Any] {
        return [
            "intergerValue" : intergerValue,
            "recordDate" : recordDate,
            "uuidString" : uuid.uuidString,
        ]
    }
}
