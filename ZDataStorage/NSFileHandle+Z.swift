//
//	NSFileHandle+Z.swift
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
//


import Foundation

extension NSFileHandle {

	// read write as is

	private func read<T>() -> T? {
		let data = self.readDataOfLength(sizeof(T))
		if data.length == sizeof(T) {
			let value = UnsafePointer<T>(data.bytes)
			return value.memory
		}
		return nil
	}

	private func write<T>(value: T) {
		var value = value
		let data = NSData(bytes: &value, length: sizeof(T))
		self.writeData(data)
	}

	// unsigned integers
	
	public func readUInt16() -> UInt16? {
		if let value = self.read() as UInt16? {
			return CFSwapInt16BigToHost(value)
		}
		return nil
	}

	public func writeUInt16(value: UInt16) {
		let value16 = CFSwapInt16HostToBig(value)
		self.write(value16)
	}
	
	public func readUInt32() -> UInt32? {
		if let value = self.read() as UInt32? {
			return CFSwapInt32BigToHost(value)
		}
		return nil
	}

	public func writeUInt32(value: UInt32) {
		let value = CFSwapInt32HostToBig(value)
		self.write(value)
	}

	public func readUInt64() -> UInt64? {
		if let value = self.read() as UInt64? {
			return CFSwapInt64BigToHost(value)
		}
		return nil
	}

	public func writeUInt64(value: UInt64) {
		let value = CFSwapInt64HostToBig(value)
		self.write(value)
	}

	// signed integers

	public func readInt16() -> Int16? {
		if let value = self.readInt16() {
			return Int16(value)
		}
		return nil
	}

	public func writeInt16(value: Int16) {
		self.write(CFSwapInt16HostToBig(UInt16(value)))
	}

	public func readInt32() -> Int32? {
		if let value = self.readUInt32() {
			return Int32(value)
		}
		return nil
	}

	public func writeInt32(value: Int32) {
		self.write(CFSwapInt32HostToBig(UInt32(value)))
	}

	public func readInt64() -> Int64? {
		if let value = self.readUInt64() {
			return Int64(value)
		}
		return nil
	}

	public func writeInt64(value: Int64) {
		self.write(CFSwapInt64HostToBig(UInt64(value)))
	}

	// float and double

	public func readFloat() -> Float? {
		switch UInt32(CFByteOrderGetCurrent()) {
		case CFByteOrderLittleEndian.rawValue:
			if let value = self.read() as CFSwappedFloat32? {
				return CFConvertFloat32SwappedToHost(value)
			}
		case CFByteOrderBigEndian.rawValue:
			return self.read() as Float?
		default: fatalError("Unknown Endian")
		}
		return nil
	}
	
	public func writeFloat(value: Float) {
		switch UInt32(CFByteOrderGetCurrent()) {
		case CFByteOrderLittleEndian.rawValue:
			self.write(CFConvertFloat32HostToSwapped(value))
		case CFByteOrderBigEndian.rawValue:
			self.write(value)
		default: fatalError("Unknown Endian")
		}
	}

	public func readDouble() -> Double? {
		switch UInt32(CFByteOrderGetCurrent()) {
		case CFByteOrderLittleEndian.rawValue:
			if let value = self.read() as CFSwappedFloat64? {
				return CFConvertFloat64SwappedToHost(value)
			}
		case CFByteOrderBigEndian.rawValue:
			return self.read() as Float64?
		default: fatalError("Unknown Endian")
		}
		return nil
	}
	
	public func writeDouble(value: Double) {
		switch UInt32(CFByteOrderGetCurrent()) {
		case CFByteOrderLittleEndian.rawValue:
			self.write(CFConvertFloat64HostToSwapped(value))
		case CFByteOrderBigEndian.rawValue:
			self.write(value)
		default: fatalError("Unknown Endian")
		}
	}
	
}















