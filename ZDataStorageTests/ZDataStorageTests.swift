//
//  ZDataStorageTests.swift
//  ZDataStorageTests
//
//  Created by Kaz Yoshikawa on 6/25/16.
//  Copyright © 2016 Electricwoods LLC. All rights reserved.
//

import XCTest

class ZDataStorageTests: XCTestCase {

	lazy var extensions: [String] = {
		return ["store", "store~"]
	}()

	
    override func setUp() {
        super.setUp()
		let fileManager = FileManager.default
		let directory = NSTemporaryDirectory()
		do {
			for item in try fileManager.contentsOfDirectory(atPath: directory) {
				let pathExtension = (item as NSString).pathExtension
				if self.extensions.contains(pathExtension) {
					let filePath = (directory as NSString).appendingPathComponent(item)
					try fileManager.removeItem(atPath: filePath)
				}
			}
		}
		catch let error {
			print("\(error)")
		}
		
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        super.tearDown()

		let fileManager = FileManager.default
		let directory = NSTemporaryDirectory()
		do {
			for item in try fileManager.contentsOfDirectory(atPath: directory) {
				let pathExtension = (item as NSString).pathExtension
				if self.extensions.contains(pathExtension) {
					let filePath = (directory as NSString).appendingPathComponent(item)
					try fileManager.removeItem(atPath: filePath)
				}
			}
		}
		catch let error {
			print("\(error)")
		}
    }
    
    func testExample() {
    }


	func testBasic1() {
		let fileManager = FileManager.default
		let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic1.store")
		print("filePath=\(filePath)")
		let backupFilePath = filePath.appending("~")
		do {
			let dataStorage = ZDataStorage(path: filePath)!
			let key1 = "name"
			let value1 = Data(base64Encoded: "R29vZCBtb3JuaW5nIE5ldyBZb3JrLg0K", options: [])!
			dataStorage.set(data: value1, forKey: key1)
			XCTAssert(fileManager.fileExists(atPath: backupFilePath)) // backup should have been created
			let data1 = dataStorage.data(forKey: key1)!
			XCTAssert(value1 == data1)
		}
		XCTAssert(!fileManager.fileExists(atPath: backupFilePath)) // backup should have been removed
	}

	func testBasicMultipleWrite() {
		let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic2.store")
		do {
			let storage = ZDataStorage(path: filePath)!
			storage.set(string: "Tokyo", forKey: "city")
			storage.set(string: "Japan", forKey: "country")
			storage.set(string: "Sushi", forKey: "food")
			storage.set(string: "Apple", forKey: "fruit")
			
			XCTAssert(storage.string(forKey: "city") == "Tokyo")
			XCTAssert(storage.string(forKey: "country") == "Japan")
			XCTAssert(storage.string(forKey: "food") == "Sushi")
			XCTAssert(storage.string(forKey: "fruit") == "Apple")
		}
	}

	func testBasicOverwrite() {

		let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic3.store")
		do {
			let storage = ZDataStorage(path: filePath)!
			storage.set(string: "Tokyo", forKey: "city")
			storage.set(string: "Japan", forKey: "country")
			XCTAssert(storage.string(forKey: "city") == "Tokyo")
			XCTAssert(storage.string(forKey: "country") == "Japan")

			storage.set(string: nil, forKey: "city")
			storage.set(string: "Orange", forKey: "fruit")
			
			XCTAssertNil(storage.string(forKey: "city"))
			XCTAssert(storage.string(forKey: "fruit") == "Orange")
		}
	}

	func testRollback() {
		let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic4.store")
		do {
			let storage = ZDataStorage(path: filePath)!
			storage.set(string: "Tokyo", forKey: "city")
			storage.set(string: "Japan", forKey: "country")
			storage.set(string: "Sushi", forKey: "food")
			storage.set(string: "Apple", forKey: "fruit")
			storage.commit()

			storage.set(string: nil, forKey: "city")
			storage.set(string: "Orange", forKey: "fruit")
			storage.rollback()
			
			XCTAssert(storage.string(forKey: "city") == "Tokyo")
			XCTAssert(storage.string(forKey: "country") == "Japan")
			XCTAssert(storage.string(forKey: "food") == "Sushi")
			XCTAssert(storage.string(forKey: "fruit") == "Apple")
		}
	}

	func testMultithreading() {
		let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic5.store")
		print("filePath=\(filePath)")
		var dictionary = [String: String]()
		do {
			let storage = ZDataStorage(path: filePath)!
			let queue = DispatchQueue(label: "com.threads", attributes: .concurrent)
			let lock = NSLock()
			let remainder: Int = 100
			DispatchQueue.concurrentPerform(iterations: 100) { _ in
				for _ in 0 ..< 100 {
					lock.lock()
					defer { lock.unlock() }
					let uuid = NSUUID().uuidString
					let hash = uuid.hashValue % remainder
					let key = String(hash)
					dictionary[key] = uuid
					storage.set(string: uuid, forKey: key)
				}
			}
			storage.commit()
		}
		do {
			let storage = ZDataStorage(path: filePath)!
			let sourceKeys: [String] = dictionary.keys.map { $0 }
			let destinationKeys: [String] = storage.keys
			let sourceKeySet = NSSet(array: sourceKeys)
			let destinationKeySet = NSSet(array: destinationKeys)
			XCTAssert(sourceKeySet == destinationKeySet)

			for key in dictionary.keys {
				let sourceString = dictionary[key]
				let destinationString = storage.string(forKey: key)
				XCTAssertNotNil(destinationString)
				XCTAssert(sourceString! == destinationString!)
			}

		}
	}
	
	func testCopy() {
		let sourceFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic6.store")
		let destinationFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic7.store")
		var dictionary = [String: String]()
		do {
			let storage = ZDataStorage(path: sourceFilePath)!
			for _ in 0 ..< 1000 {
				let uuid = NSUUID().uuidString
				let hash = uuid.hashValue
				let key = String(hash)
				dictionary[key] = uuid
				storage.set(string: uuid, forKey: key)
			}
			storage.commit()
			_ = storage.copyToPath(path: destinationFilePath)
		}

		do {
			let destinationStorage = ZDataStorage(path: destinationFilePath)!
			for (key, _) in dictionary {
				let sourceString = dictionary[key]
				let destinationString = destinationStorage.string(forKey: key)
				if let sourceString = sourceString, let destinationString = destinationString {
					XCTAssert(sourceString == destinationString)
				}
				else { XCTAssert(false) }
			}
		}
	}
	

    func testPerformanceWriting() {
		let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic8.store")
		let storage = ZDataStorage(path: filePath)!
        self.measure {
			for _ in 0 ..< 1000 {
				let uuid = NSUUID().uuidString
				let hash = uuid.hashValue
				let key = String(hash)
				storage.set(string: uuid, forKey: key)
			}
			storage.commit()
        }

    }

    func testPerformanceReading() {
		let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("basic9.store")
		let storage = ZDataStorage(path: filePath)!
		for _ in 0 ..< 10000 {
			let uuid = NSUUID().uuidString
			let hash = uuid.hashValue
			let key = String(hash)
			storage.set(string: uuid, forKey: key)
		}
		storage.commit()

		let keys = storage.keys
        self.measure {
			for _ in 0 ..< 1000 {
				let key = keys[Int(arc4random_uniform(UInt32(keys.count)))]
				let _ = storage.string(forKey: key)
			}
		}
    }

	
}
