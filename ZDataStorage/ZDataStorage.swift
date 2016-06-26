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
	static let defaultFileFormatVersion: UInt32 = 0x0001_0000  // 1.0
	static let defaultAppFormatVersion: UInt32 = 0x0000_0000
	
	private struct FileHeader {

		var fileSignature: UInt32
		var fileFormatVersion: UInt32
		var appFormatVersion: UInt32
		var reserved: UInt32
		
		var directoryOffset: UInt64
		var deletedLength: UInt64
		
		init() {
			self.fileSignature = defaultFileSignature
			self.fileFormatVersion = defaultFileFormatVersion
			self.appFormatVersion = defaultAppFormatVersion
			self.reserved = 0
			self.directoryOffset = 0
			self.deletedLength = 0
		}

		init?(fileHandle: NSFileHandle, appFormatVersion: UInt32 = defaultAppFormatVersion) {
			if let fileSignature = fileHandle.readUInt32() where fileSignature == defaultFileSignature,
			   let fileFormatVersion = fileHandle.readUInt32() where fileFormatVersion == defaultFileFormatVersion,
			   let appFormatVersion = fileHandle.readUInt32(),
			   let reserved = fileHandle.readUInt32(),
			   let directoryOffset = fileHandle.readUInt64(),
			   let deletedLength = fileHandle.readUInt64() {
				self.fileSignature = fileSignature
				self.fileFormatVersion = fileFormatVersion
				self.appFormatVersion = appFormatVersion
				self.reserved = reserved
				self.directoryOffset = directoryOffset
				self.deletedLength = deletedLength
			}
			else { return nil }
		}

		func writeHeader(fileHandle: NSFileHandle) {
			fileHandle.writeUInt32(self.fileSignature)
			fileHandle.writeUInt32(self.fileFormatVersion)
			fileHandle.writeUInt32(self.appFormatVersion)
			fileHandle.writeUInt32(self.reserved)
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

		init?(fileHandle: NSFileHandle) {
			if let type = fileHandle.readUInt16(),
			   let crc16 = fileHandle.readUInt16(),
			   let length = fileHandle.readUInt32() {
				self.type = type
				self.crc16 = crc16
				self.length = length
			}
			else { return nil }
		}
		
		func writeChunkHeader(fileHandle: NSFileHandle) {
			fileHandle.writeUInt16(self.type)
			fileHandle.writeUInt16(self.crc16)
			fileHandle.writeUInt32(self.length)
		}
	}

	let path: String
	let backupFilePath: String
	let readonly: Bool
	var fileHandle: NSFileHandle
	var directory = [String: UInt64]()
	private var fileHeader: FileHeader!
	private var needsCommit: Bool = false
	private let lock = NSLock()

	// MARK: -

	init?(path: String, readonly: Bool = false) {
		self.path = path
		self.backupFilePath = self.path.stringByAppendingString("~")
		self.readonly = readonly
		
		// Setup FileHandle //

		let fileHandle: NSFileHandle
		let fileManager = NSFileManager.defaultManager()
		let directory = (self.path as NSString).stringByDeletingLastPathComponent
		do {
			try fileManager.createDirectoryAtPath(directory, withIntermediateDirectories: true, attributes: nil)
		}
		catch let error {
			fatalError("\(error)")
		}
		if self.readonly {
			fileHandle = NSFileHandle(forReadingAtPath: path)!
		}
		else {
			if !fileManager.fileExistsAtPath(path) {
				fileManager.createFileAtPath(path, contents: nil, attributes: nil)
			}
			fileHandle = NSFileHandle(forUpdatingAtPath: path)!
		}
		self.fileHandle = fileHandle

		// look like it crashed last time -- salvage it from backup
		if fileManager.fileExistsAtPath(self.backupFilePath) {
			// directory may have already been overwritten, so salvage from backup file
			if let backupFileHandle = NSFileHandle(forReadingAtPath: self.backupFilePath) {
				backupFileHandle.seekToFileOffset(0)
				if let header = FileHeader(fileHandle: backupFileHandle) {
					// find offset where directory was saved, or just next to the header
					let offset = (header.directoryOffset > 0) ? header.directoryOffset : backupFileHandle.offsetInFile
					if let directoryData = self.readChunk(fileHandle: backupFileHandle, offset: offset, chunkType: .directory) {
						self.writeChunk(fileHandle: fileHandle, offset: header.directoryOffset, chunkType: .directory, data: directoryData)
						fileHandle.truncateFileAtOffset(fileHandle.offsetInFile)
					}
					else { fatalError("Backuped directory cannot be restore.") }
				}
			}
		}

		// load directory
		fileHandle.seekToFileOffset(0)
		if let fileHeader = FileHeader(fileHandle: fileHandle) {
			let offset = fileHeader.directoryOffset == 0 ? fileHandle.offsetInFile : fileHeader.directoryOffset
			if let directoryData = self.readChunk(fileHandle: fileHandle, offset: offset, chunkType: .directory) {
				if let directory = self.decodeDirectory(directoryData) {
					self.directory = directory
				}
				else { print("directory not found.") }
			}
			self.fileHeader = fileHeader
		}
		else {
			self.fileHeader = FileHeader()
			self.fileHeader.writeHeader(fileHandle)
		}
		assert(fileHeader != nil)

		if !readonly {
		
			// backup directory
			if !fileManager.fileExistsAtPath(self.backupFilePath) {
				fileManager.createFileAtPath(self.backupFilePath, contents: nil, attributes: nil)
			}
			if let backupFileHandle = NSFileHandle(forUpdatingAtPath: self.backupFilePath) {
				let fileHeader = self.fileHeader
				fileHeader.writeHeader(backupFileHandle)
				let data = self.encodeDirectory(self.directory)
				self.writeChunk(fileHandle: backupFileHandle, offset: backupFileHandle.offsetInFile, chunkType: .directory, data: data)
			}
		}

	}
	
	deinit {
		if !readonly {
			if needsCommit {
				self.commit()
			}
			let fileManager = NSFileManager.defaultManager()
			if fileManager.fileExistsAtPath(self.backupFilePath) {
				do { try fileManager.removeItemAtPath(self.backupFilePath) }
				catch let error { print("Failed to remove backup file. \(error)") }
			}
		}
	}

	// MARK: -

	func dataForKey(key: String) -> NSData? {
		self.lock.lock()
		defer { self.lock.unlock() }

		if let offset = self.directory[key] {
			return self.readChunk(fileHandle: fileHandle, offset: offset, chunkType: ChunkType.data)
		}
		return nil
	}

	func setData(data: NSData?, forKey key: String) {
		self.lock.lock()
		defer { self.lock.unlock() }

		// when overwriting, accumelate the total bytes deleted
		if let offset = self.directory[key] {
			if let header = self.readChunkHeader(fileHandle: self.fileHandle, offset: offset)  {
				fileHeader.deletedLength += UInt64(header.length) + UInt64(sizeof(ChunkHeader))
			}
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

	
	// MARK: -

	subscript(key: String) -> NSData? {
		get {
			return self.dataForKey(key)
		}
		set {
			self.setData(newValue, forKey: key)
		}
	}

	func stringForKey(key: String) -> String? {
		let data: NSData? = self.dataForKey(key)
		if let data = data {
			return String(data: data, encoding: NSUTF8StringEncoding)
		}
		return nil
	}

	func setString(string: String?, forKey key: String) {
		if let string = string {
			let data = string.dataUsingEncoding(NSUTF8StringEncoding)
			setData(data, forKey: key)
		}
		else {
			setData(nil, forKey: key)
		}
	}

	// MARK: -

	var keys: [String] {
		return self.directory.keys.map { $0 }
	}

	// MARK: -

	private func encodeDirectory(directory: [String: UInt64]) -> NSData {
		let dictionary = NSMutableDictionary()
		for (key, value) in directory {
			dictionary.setValue(NSNumber(unsignedLongLong: value), forKey: key)
		}
		do {
			let data = try NSJSONSerialization.dataWithJSONObject(dictionary, options: [])
			return data
		}
		catch let error { fatalError("Failed converting directory into JSON. \(error)") }
	}
	
	private func decodeDirectory(data: NSData) -> [String: UInt64]? {
		do {
			if let dictionary = (try NSJSONSerialization.JSONObjectWithData(data, options: [])) as? NSDictionary {
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
	
	private func readFileHeader(fileHandle fileHandle: NSFileHandle) -> FileHeader? {
		fileHandle.seekToFileOffset(0)
		if let header = FileHeader(fileHandle: fileHandle) {
			return header
		}
		return nil
	}

	private func readChunk(fileHandle fileHandle: NSFileHandle, offset: UInt64, chunkType: ChunkType) -> NSData? {
		fileHandle.seekToFileOffset(offset)
		assert(fileHandle.offsetInFile == offset)
		if let type = fileHandle.readUInt16() where type == chunkType.rawValue {
			if let crc16 = fileHandle.readUInt16(),
			   let bytes = fileHandle.readUInt32() {
				let data = fileHandle.readDataOfLength(Int(bytes))
				if data.crc16() == crc16 {
					return data
				}
				print("crc16 mismatch: offset=\(offset)")
			}
		}
		else { print("invalid chunktype") }
		return nil
	}
	
	private func writeChunk(fileHandle fileHandle: NSFileHandle, offset: UInt64, chunkType: ChunkType, data: NSData) {
		fileHandle.seekToFileOffset(offset)
		assert(fileHandle.offsetInFile == offset)
		fileHandle.writeUInt16(chunkType.rawValue) // chunktype
		fileHandle.writeUInt16(data.crc16()) // crc16
		fileHandle.writeUInt32(UInt32(data.length))
		fileHandle.writeData(data)
	}

	private func readChunkHeader(fileHandle fileHandle: NSFileHandle, offset: UInt64) -> ChunkHeader? {
		fileHandle.seekToFileOffset(offset)
		assert(fileHandle.offsetInFile == offset)
		return ChunkHeader(fileHandle: fileHandle)
	}

	func checkIntegrity() {
		self.lock.lock()
		defer { self.lock.unlock() }
	
		print("checking integrity.")
		self.fileHandle.seekToFileOffset(0)
		if let header = FileHeader(fileHandle: fileHandle) {
			let directoryOffset = header.directoryOffset
			let offset = (directoryOffset == 0) ? UInt64(sizeof(FileHeader)) : directoryOffset
			fileHandle.seekToFileOffset(offset)
			if let directoryData = self.readChunk(fileHandle: fileHandle, offset: offset, chunkType: .directory) {
				if let directory = self.decodeDirectory(directoryData) {
					for (key, offset) in directory {
						if let data = self.readChunk(fileHandle: fileHandle, offset: offset, chunkType: .data) {
							print("\t[\(key)] \(data)")
						}
					}
					print("number of entryies: \(directory.count)")
				}
				else { print("error: Invalid directory format.") }
			}
			else { print("error: No directory entry.") }
		}
		else { print("error: No file header.") }
		
	}

	func copyToPath(path: String) -> Bool {
		self.lock.lock()
		defer { self.lock.unlock() }

		let fileManager = NSFileManager.defaultManager()
		let directoryPath = (path as NSString).stringByDeletingLastPathComponent
		do {
			if !fileManager.fileExistsAtPath(directoryPath) {
				try fileManager.createDirectoryAtPath(directoryPath, withIntermediateDirectories: true, attributes: nil)
			}
			if !fileManager.fileExistsAtPath(path) {
				fileManager.createFileAtPath(path, contents: nil, attributes: nil)
			}
		}
		catch let error { print("Cannot prepare directory or file: \(error)") ; return false }
		guard let destinationFileHandle = NSFileHandle(forUpdatingAtPath: path)
		else { print("Cannot open file: \(path)") ; return false }
		var destinationDirectory = [String: UInt64]()
		var destinationFileHeader = self.fileHeader
		
		// header
		destinationFileHandle.seekToFileOffset(0)
		destinationFileHeader.writeHeader(destinationFileHandle)

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
		let directoryData = self.encodeDirectory(destinationDirectory)
		self.writeChunk(fileHandle: destinationFileHandle, offset: destinationOffset, chunkType: .directory, data: directoryData)
		
		// update file header
		destinationFileHeader.directoryOffset = destinationOffset
		destinationFileHeader.deletedLength = 0
		destinationFileHandle.seekToFileOffset(0)
		destinationFileHeader.writeHeader(destinationFileHandle)
		return true
	}

	func rollback() {
		self.lock.lock()
		defer { self.lock.unlock() }

		let fileManager = NSFileManager.defaultManager()

		if fileManager.fileExistsAtPath(self.backupFilePath) {
			// directory may have already been overwritten, so salvage from backup file
			if let backupFileHandle = NSFileHandle(forReadingAtPath: self.backupFilePath) {
				backupFileHandle.seekToFileOffset(0)
				if let backupHeader = FileHeader(fileHandle: backupFileHandle) {
					// rollback file header
					fileHandle.seekToFileOffset(0)
					backupHeader.writeHeader(fileHandle)
				
					let offset = UInt64(sizeof(FileHeader))
					if let data = self.readChunk(fileHandle: backupFileHandle, offset: offset, chunkType: .directory) {
						if let directory = self.decodeDirectory(data) {
							self.directory = directory
							self.writeChunk(fileHandle: self.fileHandle, offset: self.fileHeader.directoryOffset, chunkType: .directory, data: data)
							self.fileHandle.truncateFileAtOffset(self.fileHandle.offsetInFile)
						}
						else { print("Failed to decode directory.") }
					}
					else { print("Failed to load backup directory.") }
				}
				else { print("Failed to load backup file header.") }
			}
			else { print("Failed to create NSFileHandle.") }
		}
		needsCommit = false
	}

	func commit() {
		self.lock.lock()
		defer { self.lock.unlock() }

		let directoryData = self.encodeDirectory(self.directory)
		self.fileHandle.seekToEndOfFile()
		let offset = self.fileHandle.offsetInFile
		self.writeChunk(fileHandle: fileHandle, offset: offset, chunkType: .directory, data: directoryData)
		fileHeader.directoryOffset = offset
		fileHandle.seekToFileOffset(0)
		fileHeader.writeHeader(fileHandle)

		let fileManager = NSFileManager.defaultManager()
		if !readonly && fileManager.fileExistsAtPath(self.backupFilePath) {
			if let backupFileHandle = NSFileHandle(forUpdatingAtPath: self.backupFilePath) {
				backupFileHandle.seekToFileOffset(0)
				fileHeader.writeHeader(backupFileHandle)
				let offset = backupFileHandle.offsetInFile
				let data = self.encodeDirectory(self.directory)
				self.writeChunk(fileHandle: backupFileHandle, offset: offset, chunkType: .directory, data: data)
				backupFileHandle.truncateFileAtOffset(backupFileHandle.offsetInFile)
			}
		}

		needsCommit = false
	}

}


















