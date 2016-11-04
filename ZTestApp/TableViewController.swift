//
//	TableViewController.swift
//	ZDataStorage
//
//	Created by Kaz Yoshikawa on 11/4/16.
//
//

import UIKit

class TableViewController: UITableViewController {

	@IBOutlet weak var generarteItem: UIBarButtonItem!
	@IBOutlet weak var crashItem: UIBarButtonItem!

	var dataStorage: ZDataStorage!
	var keys = [String]()

	var documentDirectory: String {
		return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
	}

	var storageFile: String {
		return (self.documentDirectory as NSString).appendingPathComponent("test.storage")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Uncomment the following line to preserve selection between presentations
		// self.clearsSelectionOnViewWillAppear = false

		// Uncomment the following line to display an Edit button in the navigation bar for this view controller.
		// self.navigationItem.rightBarButtonItem = self.editButtonItem()

		self.dataStorage = ZDataStorage(path: self.storageFile)

		self.navigationController?.isToolbarHidden = false
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		// #warning Incomplete implementation, return the number of sections
		self.keys = self.dataStorage.keys
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return self.keys.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
		let key = self.keys[indexPath.row]
		cell.textLabel?.text = key
		cell.detailTextLabel?.text = self.dataStorage.string(forKey: key)
		return cell
	}

	// MARK: -

	weak var timer: Timer?
	
	@IBAction func generateAction(_ sender: UIBarButtonItem) {
		if let timer = self.timer {
			timer.invalidate()
			sender.title = "Start Generating"
		}
		else {
			self.addEntry()
			let selector = #selector(TableViewController.timerDidFire(timer:))
			self.timer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: selector, userInfo: nil, repeats: true)
			sender.title = "Stop Generating"
		}
	}

	func addEntry() {
		let number = arc4random_uniform(UInt32.max)
		let key = String(format: "%08x", number)
		let value = UUID().uuidString
		self.dataStorage.set(string: value, forKey: key)
		self.tableView.reloadData()
	}

	func timerDidFire(timer: Timer) {
		self.addEntry()
	}

	@IBAction func crashAction(_ sender: Any) {
		abort()
	}

	@IBAction func clearAction(_ sender: Any) {
		self.dataStorage = nil
		try! FileManager.default.removeItem(atPath: self.storageFile)
		let dataStorage = ZDataStorage(path: self.storageFile, readonly: false)
		self.dataStorage = dataStorage
		self.tableView.reloadData()
	}

	@IBAction func commitAction(_ sender: Any) {
		self.dataStorage.commit()
	}
	
	
}
