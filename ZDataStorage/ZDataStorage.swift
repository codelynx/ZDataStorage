//
//	ZDataStorage.swift
//	ZKit
//
//	The MIT License (MIT)
//
//	Copyright (c) 2016 Electricwoods LLC, Kaz Yoshikawa.
//
//	Permission is hereby granted, free of charge, to any person obtaining a copy 
//	of this software and associated documentation files (the "Software"), to deal 
//	in the Software without restriction, including without limitation the rights 
//	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
//	copies of the Software, and to permit persons to whom the Software is 
//	furnished to do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in 
//	all copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
//	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
//	WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//	THE SOFTWARE.

import Foundation



class ZDataStorage {

	static let defaultFileSignature: UInt32 = 0x5a44415a  // 'ZDAT'
	static let defaultFileFormatVersion: UInt32 = 0x0002_0000  // 1.0
	static let defaultAppFormatVersion: UInt32 = 0x0000_0000
	
	private struct FileHeader {

		var fileSignature: UInt32
		var fileFormatVersion: UInt32
		var appFormatVersion: UInt32
		var versionHash: UInt32
		
		var directoryOffset: UInt64
		var deletedLength: UInt64
        
		init() {
			self.fileSignature = defaultFileSignature
			self.fileFormatVersion = defaultFileFormatVersion
			self.appFormatVersion = defaultAppFormatVersion
			self.versionHash = 0
			self.directoryOffset = 0
			self.deletedLength = 0
		}

		init?(fileHandle: FileHandle, appFormatVersion: UInt32 = defaultAppFormatVersion) {
			if let fileSignature = fileHandle.readUInt32(), fileSignature == defaultFileSignature,
			   let fileFormatVersion = fileHandle.readUInt32(), fileFormatVersion == defaultFileFormatVersion,
			   let appFormatVersion = fileHandle.readUInt32(),
			   let version = fileHandle.readUInt32(),
			   let directoryOffset = fileHandle.readUInt64(),
			   let deletedLength = fileHandle.readUInt64() {
				self.fileSignature = fileSignature
				self.fileFormatVersion = fileFormatVersion
				self.appFormatVersion = appFormatVersion
				self.versionHash = version
				self.directoryOffset = directoryOffset
				self.deletedLength = deletedLength
			}
			else { return nil }
		}

		func writeHeader(fileHandle: FileHandle) {
			fileHandle.writeUInt32(self.fileSignature)
			fileHandle.writeUInt32(self.fileFormatVersion)
			fileHandle.writeUInt32(self.appFormatVersion)
			fileHandle.writeUInt32(self.versionHash)
			fileHandle.writeUInt64(self.directoryOffset)
			fileHandle.writeUInt64(self.deletedLength)
		}

	}


	enum ChunkType: UInt16 {
		case data = 0x1111
		case directory = 0x2222
	}

	private struct ChunkHeader {
		var type: UInt16
		var crc16: UInt16
		var length: UInt32

		init?(fileHandle: FileHandle) {
			if let type = fileHandle.readUInt16(),
			   let crc16 = fileHandle.readUInt16(),
			   let length = fileHandle.readUInt32() {
				self.type = type
				self.crc16 = crc16
				self.length = length
			}
			else { return nil }
		}
		
		func writeChunkHeader(fileHandle: FileHandle) {
			fileHandle.writeUInt16(self.type)
			fileHandle.writeUInt16(self.crc16)
			fileHandle.writeUInt32(self.length)
		}
	}

	let path: String
	let backupFilePath: String
	let readonly: Bool
	var fileHandle: FileHandle
	var directory = [String: UInt64]()
	private var fileHeader: FileHeader!
	private var needsCommit: Bool = false
	private let lock = NSLock()

	// MARK: -

	init?(path: String, readonly: Bool = false) {
		self.path = path
		self.backupFilePath = self.path + "~"
		self.readonly = readonly
		
		// Setup FileHandle //

		let fileHandle: FileHandle
		let fileManager = FileManager.default
		let directory = (self.path as NSString).deletingLastPathComponent
		do {
			try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
		}
		catch let error {
			fatalError("\(error)")
		}
		if self.readonly {
			fileHandle = FileHandle(forReadingAtPath: path)!
		}
		else {
			if !fileManager.fileExists(atPath: path) {
				fileManager.createFile(atPath: path, contents: nil, attributes: nil)
			}
			fileHandle = FileHandle(forUpdatingAtPath: path)!
		}
		self.fileHandle = fileHandle

		// load directory
		fileHandle.seek(toFileOffset: 0)
		if let fileHeader = FileHeader(fileHandle: fileHandle) {
			let offset = fileHeader.directoryOffset == 0 ? fileHandle.offsetInFile : fileHeader.directoryOffset
			if let directoryData = self.readChunk(fileHandle: fileHandle, offset: offset, chunkType: .directory) {
				if let directory = self.decodeDirectory(data: directoryData) {
					self.directory = directory
				}
				else {
					
					// look like directry cannot be found, let's see if we can salvage it from backup
					if fileManager.fileExists(atPath: self.backupFilePath) {
						// directory may have already been overwritten, so salvage from backup file
						if let backupFileHandle = FileHandle(forReadingAtPath: self.backupFilePath) {
							backupFileHandle.seek(toFileOffset: 0)
							if let backupFileHeader = FileHeader(fileHandle: backupFileHandle) {
								// find offset where directory was saved, or just next to the header
								let backupDirectoryOffset = (backupFileHeader.directoryOffset > 0) ? backupFileHeader.directoryOffset : backupFileHandle.offsetInFile
								if let backupDirectoryData = self.readChunk(fileHandle: backupFileHandle, offset: backupDirectoryOffset, chunkType: .directory) {
									if let _ = try? JSONSerialization.jsonObject(with: backupDirectoryData, options: []) {
										if fileHeader.versionHash == backupFileHeader.versionHash {
											self.writeChunk(fileHandle: fileHandle, offset: fileHeader.directoryOffset, chunkType: .directory, data: backupDirectoryData)
											fileHandle.truncateFile(atOffset: fileHandle.offsetInFile)
										}
										else { print("Version hash not much") }
									}
									else { print("Directory is not not a json") }
								}
								else { fatalError("Backuped directory cannot be restore.") }
							}
						}
					}

				}
			}
			self.fileHeader = fileHeader
		}
		else {
			self.fileHeader = FileHeader()
			self.fileHeader.writeHeader(fileHandle: fileHandle)
		}
		assert(fileHeader != nil)

		if !readonly {
		
			// backup directory
			if !fileManager.fileExists(atPath: self.backupFilePath) {
				fileManager.createFile(atPath: self.backupFilePath, contents: nil, attributes: nil)
			}
			if let backupFileHandle = FileHandle(forUpdatingAtPath: self.backupFilePath) {
				let fileHeader = self.fileHeader
				fileHeader?.writeHeader(fileHandle: backupFileHandle)
				let data = self.encodeDirectory(directory: self.directory)
				self.writeChunk(fileHandle: backupFileHandle, offset: backupFileHandle.offsetInFile, chunkType: .directory, data: data)
			}
		}

	}
	
	deinit {
		if !readonly {
			if needsCommit {
				self.commit()
			}
			let fileManager = FileManager.default
			if fileManager.fileExists(atPath: self.backupFilePath) {
				do { try fileManager.removeItem(atPath: self.backupFilePath) }
				catch let error { print("Failed to remove backup file. \(error)") }
			}
		}
	}

	// MARK: -

	func data(forKey: String) -> Data? {
		self.lock.lock()
		defer { self.lock.unlock() }

		if let offset = self.directory[forKey] {
			return self.readChunk(fileHandle: fileHandle, offset: offset, chunkType: ChunkType.data)
		}
		return nil
	}

	func set(data: Data?, forKey key: String) {
		self.lock.lock()
		defer { self.lock.unlock() }

		// when overwriting, accumelate the total bytes deleted
		if let offset = self.directory[key] {
			if let header = self.readChunkHeader(fileHandle: self.fileHandle, offset: offset)  {
				fileHeader.deletedLength += UInt64(header.length) + UInt64(MemoryLayout<ChunkHeader>.size)
			}
			else { print("Chunk header cannot be read. File may be corrupted.") }
		}
	
		if let data = data { // append new chunk to the end of file
			self.fileHandle.seekToEndOfFile()
			let offset = self.fileHandle.offsetInFile
			self.writeChunk(fileHandle: self.fileHandle, offset: offset, chunkType: .data, data: data)
			self.directory[key] = offset
		}
		else { // make it unaccessible
			self.directory[key] = nil
		}

		needsCommit = true
	}


	subscript(key: String) -> Data? {
		get {
			return self.data(forKey: key)
		}
		set {
			self.set(data: newValue, forKey: key)
		}
	}

	func string(forKey: String) -> String? {
		let data: Data? = self.data(forKey: forKey)
		if let data = data {
			return String(data: data as Data, encoding: String.Encoding.utf8)
		}
		return nil
	}

	func set(string: String?, forKey key: String) {
		if let string = string {
			let data = string.data(using: String.Encoding.utf8)
			set(data: data, forKey: key)
		}
		else {
			set(data: nil, forKey: key)
		}
	}

	subscript(key: String) -> String? {
		get {
			let data: Data? = self.data(forKey: key)
			if let data = data {
				return String(data: data as Data, encoding: String.Encoding.utf8)
			}
			return nil
		}
		set {
			if let string = newValue {
				let data = string.data(using: String.Encoding.utf8)
				set(data: data, forKey: key)
			}
			else {
				set(data: nil, forKey: key)
			}
		}
	}

	// MARK: -

	subscript(key: String) -> NSArray? {
		get {
			if let data = self.data(forKey: key) {
				return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? NSArray
			}
			return nil
		}
		set {
			if let newValue = newValue {
				let data = try? PropertyListSerialization.data(fromPropertyList: newValue, format: .binary, options: 0)
				self.set(data: data, forKey: key)
			}
			else { self.set(data: nil, forKey: key) }
		}
	}

	subscript(key: String) -> NSDictionary? {
		get {
			if let data = self.data(forKey: key) {
				return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? NSDictionary
			}
			return nil
		}
		set {
			if let newValue = newValue {
				let data = try? PropertyListSerialization.data(fromPropertyList: newValue, format: .binary, options: 0)
				self.set(data: data, forKey: key)
			}
			else { self.set(data: nil, forKey: key) }
		}
	}

	// MARK: -

	var keys: [String] {
		return self.directory.keys.map { $0 }
	}

	// MARK: -

	private func encodeDirectory(directory: [String: UInt64]) -> Data {
		let dictionary = NSMutableDictionary()
		for (key, value) in directory {
			dictionary.setValue(NSNumber(value: value), forKey: key)
		}
		do {
			let data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
			return data
		}
		catch let error { fatalError("Failed converting directory into JSON. \(error)") }
	}
	
	private func decodeDirectory(data: Data) -> [String: UInt64]? {
		do {
			if let dictionary = (try JSONSerialization.jsonObject(with: data, options: [])) as? NSDictionary {
				var directory = [String: UInt64]()
				for (key, value) in dictionary {
					if let key = key as? String, let value = value as? UInt {
						directory[key] = UInt64(value)
					}
				}
				return directory
			}
			return nil
		}
		catch let error {
			print("Failed converting JSON into directory: \(error)")
		}
		return directory
	}
	
	private func readFileHeader(fileHandle: FileHandle) -> FileHeader? {
		fileHandle.seek(toFileOffset: 0)
		if let header = FileHeader(fileHandle: fileHandle) {
			return header
		}
		return nil
	}

	private func readChunk(fileHandle: FileHandle, offset: UInt64, chunkType: ChunkType) -> Data? {
		fileHandle.seek(toFileOffset: offset)
		assert(fileHandle.offsetInFile == offset)
		if let type = fileHandle.readUInt16(), type == chunkType.rawValue {
			if let crc16 = fileHandle.readUInt16(),
			   let bytes = fileHandle.readUInt32() {
				let data = fileHandle.readData(ofLength: Int(bytes))
				if data.crc16() == crc16 {
					return data
				}
				print("crc16 mismatch: offset=\(offset)")
			}
		}
		else { print("invalid chunktype") }
		return nil
	}
	
	private func writeChunk(fileHandle: FileHandle, offset: UInt64, chunkType: ChunkType, data: Data) {
		fileHandle.seek(toFileOffset: offset)
		assert(fileHandle.offsetInFile == offset)
		fileHandle.writeUInt16(chunkType.rawValue) // chunktype
		fileHandle.writeUInt16(data.crc16()) // crc16
		fileHandle.writeUInt32(UInt32(data.count))
		fileHandle.write(data)
	}

	private func readChunkHeader(fileHandle: FileHandle, offset: UInt64) -> ChunkHeader? {
		fileHandle.seek(toFileOffset: offset)
		assert(fileHandle.offsetInFile == offset)
		return ChunkHeader(fileHandle: fileHandle)
	}

	func checkIntegrity() -> Bool {
		self.lock.lock()
		defer { self.lock.unlock() }
	
		print("checking integrity.")
		self.fileHandle.seek(toFileOffset: 0)
		if let header = FileHeader(fileHandle: fileHandle) {
			let directoryOffset = header.directoryOffset
			let offset = (directoryOffset == 0) ? UInt64(MemoryLayout<FileHeader>.size) : directoryOffset
			fileHandle.seek(toFileOffset: offset)
			if let directoryData = self.readChunk(fileHandle: fileHandle, offset: offset, chunkType: .directory) {
				if let directory = self.decodeDirectory(data: directoryData) {
					for (key, offset) in directory {
						if let data = self.readChunk(fileHandle: fileHandle, offset: offset, chunkType: .data) {
							print("\t[\(key)] \(data)")
						}
					}
					print("number of entryies: \(directory.count)")
					return true
				}
				else { print("error: Invalid directory format.") ; return false }
			}
			else { print("error: No directory entry.") ; return false }
		}
		else { print("error: No file header.") ; return false }
		
	}

	func copyToPath(path: String) -> Bool {
		self.lock.lock()
		defer { self.lock.unlock() }

		let fileManager = FileManager.default
		let directoryPath = (path as NSString).deletingLastPathComponent
		do {
			if !fileManager.fileExists(atPath: directoryPath) {
				try fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)
			}
			if !fileManager.fileExists(atPath: path) {
				fileManager.createFile(atPath: path, contents: nil, attributes: nil)
			}
		}
		catch let error { print("Cannot prepare directory or file: \(error)") ; return false }
		guard let destinationFileHandle = FileHandle(forUpdatingAtPath: path)
		else { print("Cannot open file: \(path)") ; return false }
		var destinationDirectory = [String: UInt64]()
		var destinationFileHeader = self.fileHeader
		
		// header
		destinationFileHandle.seek(toFileOffset: 0)
		destinationFileHeader?.writeHeader(fileHandle: destinationFileHandle)

		// copy all entries
		for (key, offset) in directory {
			if let data = self.readChunk(fileHandle: self.fileHandle, offset: offset, chunkType: .data) {
				let destinationOffset = destinationFileHandle.offsetInFile
				self.writeChunk(fileHandle: destinationFileHandle, offset: destinationOffset, chunkType: .data, data: data)
				destinationDirectory[key] = destinationOffset
			}
		}

		// directory
		let destinationOffset = destinationFileHandle.offsetInFile
		let directoryData = self.encodeDirectory(directory: destinationDirectory)
		self.writeChunk(fileHandle: destinationFileHandle, offset: destinationOffset, chunkType: .directory, data: directoryData)
		
		// update file header
		destinationFileHeader?.directoryOffset = destinationOffset
		destinationFileHeader?.deletedLength = 0
		destinationFileHandle.seek(toFileOffset: 0)
		destinationFileHeader?.writeHeader(fileHandle: destinationFileHandle)
		return true
	}

	func rollback() {
		self.lock.lock()
		defer { self.lock.unlock() }

		let fileManager = FileManager.default

		if fileManager.fileExists(atPath: self.backupFilePath) {
			// directory may have already been overwritten, so salvage from backup file
			if let backupFileHandle = FileHandle(forReadingAtPath: self.backupFilePath) {
				backupFileHandle.seek(toFileOffset: 0)
				if let backupHeader = FileHeader(fileHandle: backupFileHandle) {
					// rollback file header
					fileHandle.seek(toFileOffset: 0)
					backupHeader.writeHeader(fileHandle: fileHandle)
				
					let offset = UInt64(MemoryLayout<FileHeader>.size)
					if let data = self.readChunk(fileHandle: backupFileHandle, offset: offset, chunkType: .directory) {
						if let directory = self.decodeDirectory(data: data) {
							self.directory = directory
							self.writeChunk(fileHandle: self.fileHandle, offset: self.fileHeader.directoryOffset, chunkType: .directory, data: data)
							self.fileHandle.truncateFile(atOffset: self.fileHandle.offsetInFile)
						}
						else { print("Failed to decode directory.") }
					}
					else { print("Failed to load backup directory.") }
				}
				else { print("Failed to load backup file header.") }
			}
			else { print("Failed to create FileHandle.") }
		}
		needsCommit = false
	}

	func commit() {
		self.lock.lock()
		defer { self.lock.unlock() }

		let directoryData = self.encodeDirectory(directory: self.directory)
		self.fileHandle.seekToEndOfFile()
		let offset = self.fileHandle.offsetInFile
		self.writeChunk(fileHandle: fileHandle, offset: offset, chunkType: .directory, data: directoryData)
		fileHeader.directoryOffset = offset
		fileHeader.versionHash += 1
		fileHandle.seek(toFileOffset: 0)
		fileHeader.writeHeader(fileHandle: fileHandle)

		let fileManager = FileManager.default
		if !readonly && fileManager.fileExists(atPath: self.backupFilePath) {
			if let backupFileHandle = FileHandle(forUpdatingAtPath: self.backupFilePath), var backupFileHeader = self.fileHeader {
				backupFileHandle.seek(toFileOffset: 0)
				backupFileHeader.writeHeader(fileHandle: backupFileHandle)
				let offset = backupFileHandle.offsetInFile
				let data = self.encodeDirectory(directory: self.directory)
				self.writeChunk(fileHandle: backupFileHandle, offset: offset, chunkType: .directory, data: data)
				backupFileHandle.truncateFile(atOffset: backupFileHandle.offsetInFile)
				backupFileHandle.seek(toFileOffset: 0)
				backupFileHeader.directoryOffset = offset
				backupFileHeader.versionHash = fileHeader.versionHash
				backupFileHeader.writeHeader(fileHandle: backupFileHandle)
			}
		}

		needsCommit = false
	}

}
