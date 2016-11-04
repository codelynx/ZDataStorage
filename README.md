![swift](https://img.shields.io/badge/swift-3.0-orange.svg) ![license](https://img.shields.io/badge/license-MIT-yellow.svg)

# ZDataStorage

ZDataStorage is a utility class to load and save multiple `NSData` or `String` into a single file, and can be retrieved or save with `key` string.  It is good for caching small but many data needed to be kept in app.  It is not suitable for managing large size of images, but it is suitable for managing many small size data.

## Overview

Here is the example of common usage of ZDataStorage.  NSData can be accessed by `[]` subscript operator.  String can also be accessed by `stringForKey()` or `setString(_:forKey)` methods.  String will be converted into UTF8 and saved as `NSData`, so that it could return `nil` if binary data cannot be converted to String.

```.swift
let path = // path to file
let storage =  ZDataStorage(path)

// Data を保存
let data = // NSData
storage["key"] = data

// Data を取得
if let data = storage["foo"] {
	print("\(data)")
}

// String を保存
storage.setString("Hello World", forKey: "bar")

// String を取得
if let string = storage.stringForKey("buz") {
	print("\(string)")
}
```

### Instantiate

Here is an example of instantiating ZDataStorage object.  When `readonly` is not specified, a file will be created at path and returns nil if it failed to create. Also it returns nil if given file exists but not a ZDataStorage file.

When `readonly` is specified, it fails if the file does not exist or the file is not a ZDataStorage file. Also once ZDataStorage object is instantiated with readonly mode, you cannot write any data into storage.

```.swift
// read & write
let storage1 =  ZDataStorage(path)!

// read only
let storage2 =  ZDataStorage(path, readonly: true)!
```

### Saving and Loading Data

`ZDataStorage` supports subscript operator for `NSData`, so you can save and load NSData by `[]` subscript operator as follows.

```.swift
// save NSData with key
let data = // some NSData
storage["foo"] = data

// load NSData with key
if let data = storage["bar"] {
	print("\(data)")
}
```

`ZDataStorage` also support string access to storage for convenience.

```.swift
// save String with key
let string = // some string
storage.setString(string, forKey:"foo")

// load String with key
if let string = storage.stringForKey("bar") {
	print("\(string)")
}
```

### Finding all keys

You may find all keys with `keys` property.

```.swift
let keys = storage.keys // [String]
```

### Commit

When you set some data into a storage, it is actually hasn't commited yet.  So when your app crashed at this point, unsaved data will be lost.  You may call `commit()` to commit all changes.

```.swift
storage["foo"] = data1
storage["bar"] = data2
storage.commit()
```

### Rollback

When you don't like to commit those changes, rather prefer go back to original, you may call `rollback()` to discard all changes to the very last commit.

```.swift
storage["foo"] = data1
storage["bar"] = data2
storage["buz"] = data3
storage.commit()

storage["bar"] = data4
storage["buz"] = nil
storage.rollback()

let foo = storage["foo"]  // data1
let bar = storage["bar"]  // data2
let buz = storage["buz"]  // data3
```

### Make a copy of storage

`ZDataStorage` always appending data to the end of the file.  Overwritten data never been reused or recycled.  So, it is a good idea to make a fresh copy without dead space time to time.

```.swift
let anotherPath = // ...
storage.copyToPath(anotherPath)
```

### Thread safe

`ZDataStorage` can be accessed from many threads.  It is thread safe.

### Feedback

If you have found any bugs or issues, please feel free to contact Kaz Yoshikawa [kaz@digitallynx.com](kaz@digitallynx.com)

### Environment

```.log
Xcode Version 8.1 (8B62)
Apple Swift version 3.0.1 (swiftlang-800.0.58.6 clang-800.0.42.1)
```


### License

The MIT License.

