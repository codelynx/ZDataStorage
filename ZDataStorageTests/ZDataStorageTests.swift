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
		let fileManager = NSFileManager.defaultManager()
		let directory = NSTemporaryDirectory()
		do {
			for item in try fileManager.contentsOfDirectoryAtPath(directory) {
				let pathExtension = (item as NSString).pathExtension
				if self.extensions.contains(pathExtension) {
					let filePath = (directory as NSString).stringByAppendingPathComponent(item)
					try fileManager.removeItemAtPath(filePath)
				}
			}
		}
		catch let error {
			print("\(error)")
		}
		
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
    }


	func testBasic1() {
		let fileManager = NSFileManager.defaultManager()
		let filePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("basic1.store")
		print("filePath=\(filePath)")
		let backupFilePath = filePath.stringByAppendingString("~")
		do {
			let dataStorage = ZDataStorage(path: filePath)!
			let key1 = "name"
			let value1 = NSData(base64EncodedString: "R29vZCBtb3JuaW5nIE5ldyBZb3JrLg0K", options: [])!
			dataStorage.setData(value1, forKey: key1)
			XCTAssert(fileManager.fileExistsAtPath(backupFilePath)) // backup should have been created
			
			let data1 = dataStorage.dataForKey(key1)!
			XCTAssert(value1.isEqualToData(data1))
		}
		XCTAssert(!fileManager.fileExistsAtPath(backupFilePath)) // backup should have been removed
	}

	func testBasicMultipleWrite() {
		let filePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("basic2.store")
		do {
			let storage = ZDataStorage(path: filePath)!
			storage.setString("Tokyo", forKey: "city")
			storage.setString("Japan", forKey: "country")
			storage.setString("Sushi", forKey: "food")
			storage.setString("Apple", forKey: "fruit")
			
			XCTAssert(storage.stringForKey("city") == "Tokyo")
			XCTAssert(storage.stringForKey("country") == "Japan")
			XCTAssert(storage.stringForKey("food") == "Sushi")
			XCTAssert(storage.stringForKey("fruit") == "Apple")
		}
	}

	func testBasicOverwrite() {
		let filePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("basic3.store")
		do {
			let storage = ZDataStorage(path: filePath)!
			storage.setString("Tokyo", forKey: "city")
			storage.setString("Japan", forKey: "country")
			XCTAssert(storage.stringForKey("city") == "Tokyo")
			XCTAssert(storage.stringForKey("country") == "Japan")

			storage.setString(nil, forKey: "city")
			storage.setString("Orange", forKey: "fruit")
			
			XCTAssertNil(storage.stringForKey("city"))
			XCTAssert(storage.stringForKey("fruit") == "Orange")
		}
	}

	func testRollback() {
		let filePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("basic4.store")
		do {
			let storage = ZDataStorage(path: filePath)!
			storage.setString("Tokyo", forKey: "city")
			storage.setString("Japan", forKey: "country")
			storage.setString("Sushi", forKey: "food")
			storage.setString("Apple", forKey: "fruit")
			storage.commit()

			storage.setString(nil, forKey: "city")
			storage.setString("Orange", forKey: "fruit")
			storage.rollback()
			
			XCTAssert(storage.stringForKey("city") == "Tokyo")
			XCTAssert(storage.stringForKey("country") == "Japan")
			XCTAssert(storage.stringForKey("food") == "Sushi")
			XCTAssert(storage.stringForKey("fruit") == "Apple")
		}
	}

	func testMultithreading() {
		let filePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("basic5.store")
		print("filePath=\(filePath)")
		var dictionary = [String: String]()
		do {
			let storage = ZDataStorage(path: filePath)!
			let queue = dispatch_queue_create("com.threads", DISPATCH_QUEUE_CONCURRENT)
			let lock = NSLock()
			let remainder: UInt = 100
			dispatch_apply(100, queue) { _ in
				for _ in 0 ..< 100 {
					lock.lock()
					defer { lock.unlock() }
					let uuid = NSUUID().UUIDString
					let hash = unsafeBitCast(uuid.hashValue, UInt.self) % remainder
					let key = String(hash)
					dictionary[key] = uuid
					storage.setString(uuid, forKey: key)
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
				let destinationString = storage.stringForKey(key)
				XCTAssertNotNil(destinationString)
				XCTAssert(sourceString! == destinationString!)
			}

		}
	}
	
	func testCopy() {
		let sourceFilePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("basic6.store")
		let destinationFilePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("basic7.store")
		var dictionary = [String: String]()
		do {
			let storage = ZDataStorage(path: sourceFilePath)!
			for i in 0 ..< 1000 {
				let uuid = NSUUID().UUIDString
				let hash = unsafeBitCast(uuid.hashValue, UInt.self) % 10
				let key = String(hash)
				dictionary[key] = uuid
				storage.setString(uuid, forKey: key)
			}
			storage.commit()
			storage.copyToPath(destinationFilePath)
		}

		do {
			let destinationStorage = ZDataStorage(path: destinationFilePath)!
			for (key, _) in dictionary {
				let sourceString = dictionary[key]
				let destinationString = destinationStorage.stringForKey(key)
				if let sourceString = sourceString, let destinationString = destinationString {
					XCTAssert(sourceString == destinationString)
				}
				else { XCTAssert(false) }
			}
		}
	}
	

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
