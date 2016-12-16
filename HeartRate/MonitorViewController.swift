//
//  MonitorViewController.swift
//  HeartRate
//
//  Created by Jonny on 10/25/16.
//  Copyright © 2016 Jonny. All rights reserved.
//

import UIKit

class MonitorViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    enum MonitorState {
        case notStarted, launching, running, errorOccur(Error)
    }
    
    // MARK: - Properties
    
    var monitorState = MonitorState.notStarted {
        didSet {
            DispatchQueue.main.async {
                print("monitorState", self.monitorState)
                
                switch self.monitorState {
                case .notStarted:
                    self.title = "Ready to Start"
                    self.startStopBarButtonItem.title = "Start"
                case .launching:
                    self.title = "Launching Watch App"
                    self.startStopBarButtonItem.title = "Stop"
                case .running:
                    self.title = "Monitoring"
                    self.startStopBarButtonItem.title = "Stop"
                case .errorOccur:
                    self.title = "Error"
                    self.startStopBarButtonItem.title = "Start"
                }
            }
        }
    }
    
    @IBOutlet private var tableView: UITableView! {
        didSet {
            tableView.dataSource = self
            tableView.delegate = self
            tableView.scrollIndicatorInsets.top = tableViewHeaderHeight
        }
    }
    
    @IBOutlet weak var trashButtonItem: UIBarButtonItem!
    
    @IBOutlet private var startStopBarButtonItem: UIBarButtonItem!
    
    private let tableViewHeaderHeight: CGFloat = 44 * 3
    
    private let heartRateManager = HeartRateManager()
    
    private var messageHandler: WatchConnectivityManager.MessageHandler?
    
    private lazy var tableViewHeaderView: UIView = { [unowned self] in
        
        let headerView = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
        headerView.addSubview(self.chartImageView)
        
        self.chartImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.chartImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
//            self.chartImageView.topAnchor.constraint(equalTo: headerView.topAnchor),
            self.chartImageView.topAnchor.constraint(equalTo: headerView.centerYAnchor, constant: -24),
            self.chartImageView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            self.chartImageView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
        ])
        
        let seperatorLine = UIView()
        seperatorLine.backgroundColor = UIColor(red: 200/255, green: 199/255, blue: 204/255, alpha: 1)
        headerView.addSubview(seperatorLine)
        
        seperatorLine.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            seperatorLine.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            seperatorLine.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            seperatorLine.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            seperatorLine.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.nativeScale),
            ])
        
        return headerView
    }()
    
    private let chartImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let heartRateChartGenerator: YOLineChartImage = {
        
        let chartGenerator = YOLineChartImage()
        
        chartGenerator.strokeWidth = 2.0
        chartGenerator.strokeColor = .black
        chartGenerator.fillColor = .clear // UIColor.white.withAlphaComponent(0.4)
        chartGenerator.pointColor = .black
        chartGenerator.isSmooth = true
        
        return chartGenerator
    }()
    
    
    // MARK: - View Controller Lifecycle
    
    deinit {
        print("deinit \(type(of: self))")
        messageHandler?.invalidate()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        heartRateManager.recordsUpdateHandler = { records in
            self.tableView.reloadData()
            self.updateChartIfNeeded()
            self.trashButtonItem.isEnabled = !records.isEmpty
        }
        
        self.updateChartIfNeeded()
        
        // Handle session messages between iPhone and Apple Watch.
        guard let manager = WatchConnectivityManager.shared else {
            // if the current device don't support Watch Connectivity framework, disable the start/stop button.
            startStopBarButtonItem.isEnabled = false
            title = ""
            return
        }
        
        messageHandler = WatchConnectivityManager.MessageHandler { [weak self] message in
            guard let `self` = self else { return }
            
            print(message)
            print("\n")
            
            if let intergerValue = message[.heartRateIntergerValue] as? Int,
                let recordDate = message[.heartRateRecordDate] as? Date {
                
                let newRecord = HeartRateRecord(intergerValue: intergerValue, recordDate: recordDate)
                self.heartRateManager.save([newRecord])
                self.monitorState = .running
                
//                self.heartRateRecords.insert(newRecord, at: 0)
//                self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
//                self.updateChartIfNeeded()
                
//                CloudKitManager.shared.saveRecords([newRecord.ckRecord])
            }
            else if message[.workoutStop] != nil{
                self.monitorState = .notStarted
            }
            else if message[.workoutStart] != nil{
                self.monitorState = .running
            }
            else if let errorData = message[.workoutError] as? Data {
                if let error = NSKeyedUnarchiver.unarchiveObject(with: errorData) as? Error {
                    self.monitorState = .errorOccur(error)
                }
            }
        }
        manager.addMessageHandler(messageHandler!)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.updateChartIfNeeded() }, completion: nil)
    }
    
    
    // MARK: - UI Updates
    
    private func updateChartIfNeeded() {
        
        let heartRateRecords = heartRateManager.records
        
        // The framework require at least 2 point to draw a line chart.
        guard heartRateRecords.count >= 2 else {
            // chear chart
            chartImageView.image = nil
            return
        }
        
        // the records are sorted from new to old
        var integers = heartRateRecords.map { $0.intergerValue }
        
        // Only shows recent 10 heart rate records on chart.
        let maximumShowsCount = 10
        
        if integers.count > maximumShowsCount {
            integers = (integers as NSArray).subarray(with: NSMakeRange(0, maximumShowsCount)) as! [Int]
            integers = Array(integers.reversed())
        }
        
//        let minimunInteger = 40 // integers.min()!
        
        let numbers = integers.map { NSNumber(integerLiteral: $0) }
        
        self.heartRateChartGenerator.values = numbers

        let uiImage = self.heartRateChartGenerator.draw(in: chartImageView.bounds, scale: UIScreen.main.scale, edgeInsets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)) // draw an image
        
        chartImageView.image = uiImage
    }
    
    
    // MARK: - UITableViewDataSource, UITableViewDelegate
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return heartRateManager.records.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "\(UITableViewCell.self)", for: indexPath)
        let record = heartRateManager.records[indexPath.row]
        
        cell.textLabel?.text = "\(record.intergerValue)"
        cell.detailTextLabel?.text = DateFormatter.localizedString(from: record.recordDate, dateStyle: .none, timeStyle: .medium)
        
        let font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: UIFontWeightRegular)
        cell.textLabel?.font = font
        
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightRegular)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return tableViewHeaderHeight
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return tableViewHeaderView
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    
    // MARK: - Actions
    
    @IBAction func trashButtonItemDidTap(_ sender: Any) {
        
        let controller = UIAlertController(title: "Delete All Records", message: "This will delete all your heart rate record from all your device. This cannot be undone.", preferredStyle: .alert)
        
        controller.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.heartRateManager.deleteAllRecords()
        })
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(controller, animated: true)
    }
    
    @IBAction func startStopButtonItemDidTap(_ sender: UIBarButtonItem) {
        
        if sender.title == "Start" {
            monitorState = .launching
            heartRateManager.startWatchApp { error in
                if let error = error {
                    self.monitorState = .errorOccur(error)
                }
            }
        }
        else {
            monitorState = .notStarted
            
            guard let wcManager = WatchConnectivityManager.shared else { return }
            
            wcManager.fetchReachableState { isReachable in
                if isReachable {
                    wcManager.send([.workoutStop : true])
                } else {
                    wcManager.transfer([.workoutStop : true])
                }
            }
        }
    }
}
