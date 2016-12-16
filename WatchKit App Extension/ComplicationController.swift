//
//  ComplicationController.swift
//  WatchKitApp Extension
//
//  Created by Jonny on 10/9/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import ClockKit


class ComplicationController: NSObject, CLKComplicationDataSource {
    
    private var earliestTimeTravelDate: Date {
        return CLKComplicationServer.sharedInstance().earliestTimeTravelDate
    }
    
    private var latestHeartRateDate: Date? {
        get {
            if let interval = UserDefaults.standard.value(forKey: "latestHeartRateDate") as? Double {
                return Date(timeIntervalSinceReferenceDate: interval)
            }
            return nil
        }
        set {
            let interval = newValue?.timeIntervalSinceReferenceDate
            UserDefaults.standard.set(interval, forKey: "latestHeartRateDate")
        }
    }
    
    // MARK: - Timeline Configuration
    
    func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([.backward])
    }
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.hideOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Call the handler with the current timeline entry
        
        HeartRateController.sharedInstance.fetchHeartRates(startDate: nil, endDate: Date(), limit: 1) { heartRates, _ in
            var entry: CLKComplicationTimelineEntry?
            if let heartRate = heartRates.first {
                entry = self.timelineEntryForComplication(complication, heartRate: heartRate)
            }
            handler(entry)
        }
    }
    
    func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Call the handler with the timeline entries prior to the given date
        
        let startDate = latestHeartRateDate ?? earliestTimeTravelDate
        let endDate = date
        
        guard startDate < endDate else {
            handler(nil)
            return
        }
        
        HeartRateController.sharedInstance.fetchHeartRates(startDate: startDate, endDate: endDate, limit: limit) { heartRates, _ in
            
            let entries = heartRates.reversed().map {
                self.timelineEntryForComplication(complication, heartRate: $0)
            }
            
            if let latestEntry = entries.last {
                self.latestHeartRateDate = latestEntry.date
            }
            
            print("handle entries.count \(entries.count)")
            
            handler(entries)
        }
    }
    
    
    // MARK: - Placeholder Templates
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        // This method will be called once per supported complication, and the results will be cached
        let entry = timelineEntryForComplication(complication)
        handler(entry.complicationTemplate)
    }
    
    
    // MARK: - Updates
    
    func requestedUpdateDidBegin() {
        print(#function)
        extendTimeline()
    }
    
    func requestedUpdateBudgetExhausted() {
        print(#function)
        extendTimeline()
    }
    
    private func extendTimeline() {
        let server = CLKComplicationServer.sharedInstance()
        for complication in server.activeComplications ?? [] {
            server.extendTimeline(for: complication)
        }
    }
    
    
    // MARK: - Entry
    
    /// Get timeline entry for specific complication and heart rate.
    /// - parameter heartRate: Default is nil. Set a non-nil value for timeline entry with real date and heart rate value.
    /// - returns: If heartRate is nil, will return the placeholder entry for Watch's complication selection screen.
    private func timelineEntryForComplication(_ complication: CLKComplication, heartRate: HeartRate? = nil) -> CLKComplicationTimelineEntry {
        
        let complicationTemplate: CLKComplicationTemplate
        
        let heartRateText = "\(heartRate?.bpm ?? 76)"
        let unitText = " BPM"
        let fullText = NSLocalizedString("Heart Rate", comment: "") + heartRateText + "BPM"
        
        let heartRateDate: Date
        
        if let heartRate = heartRate {
            heartRateDate = heartRate.date as Date
        }
        else { // set placeholder template's date to 9:41
            let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = 9
            components.minute = 41
            heartRateDate = calendar.date(from: components) ?? Date()
        }
        
        let timeTextProvider = CLKTimeTextProvider(date: heartRateDate)
        
        switch complication.family {
            
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: heartRateText + unitText, shortText: heartRateText, accessibilityLabel: fullText)
            template.line2TextProvider = timeTextProvider
            complicationTemplate = template
            
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = timeTextProvider
            template.body1TextProvider = CLKSimpleTextProvider(text: heartRateText + unitText, shortText: heartRateText, accessibilityLabel: fullText)
            
            let imageProvider = CLKImageProvider(onePieceImage: UIImage(named: "Modular")!)
            imageProvider.accessibilityLabel = fullText
            template.headerImageProvider = imageProvider
            
            complicationTemplate = template
            
        case .utilitarianSmall:
            let template = CLKComplicationTemplateUtilitarianSmallFlat()
            template.textProvider = CLKSimpleTextProvider(text: heartRateText + unitText, shortText: heartRateText, accessibilityLabel: fullText)
            
            let imageProvider = CLKImageProvider(onePieceImage: UIImage(named: "Utilitarian")!) // ComplicationControllerUtilitarianHeart
            imageProvider.accessibilityLabel = fullText
            template.imageProvider = imageProvider
            
            complicationTemplate = template
            
        case .utilitarianLarge:
            let template = CLKComplicationTemplateUtilitarianLargeFlat()
            template.textProvider = CLKSimpleTextProvider(text: heartRateText + unitText, shortText: heartRateText, accessibilityLabel: fullText)
            
            let imageProvider = CLKImageProvider(onePieceImage: UIImage(named: "Utilitarian")!)
            imageProvider.accessibilityLabel = fullText
            template.imageProvider = imageProvider
            
            complicationTemplate = template
            
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: heartRateText + unitText, shortText: heartRateText, accessibilityLabel: fullText)
            template.line2TextProvider = timeTextProvider
            
            complicationTemplate = template
            
        case .extraLarge:
            let template = CLKComplicationTemplateExtraLargeStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: heartRateText + unitText, shortText: heartRateText, accessibilityLabel: fullText)
            template.line2TextProvider = timeTextProvider
            
            complicationTemplate = template
            
        case .utilitarianSmallFlat:
            let template = CLKComplicationTemplateUtilitarianSmallFlat()
            template.textProvider = CLKSimpleTextProvider(text: heartRateText + unitText, shortText: heartRateText, accessibilityLabel: fullText)
            
            complicationTemplate = template
        }
        
        // use the Health app's tint color
        complicationTemplate.tintColor = UIColor(red: 1, green: 40/255, blue: 81/255, alpha: 1)
        
        return CLKComplicationTimelineEntry(date: heartRate?.date ?? Date(),
                                            complicationTemplate: complicationTemplate)
    }
    
}
