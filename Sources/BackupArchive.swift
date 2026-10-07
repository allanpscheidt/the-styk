import Foundation
import Darwin
import zlib

/// Deliberately small ZIP reader: classic ZIP, regular files/directories, store/deflate.
/// No extractor runs before validation. Both metadata and actual inflated bytes are bounded.
enum BackupArchive {
    struct Limits {
        var archiveBytes = 64 * 1024 * 1024
        var totalBytes = 128 * 1024 * 1024
        var entryBytes = 5 * 1024 * 1024
        var entries = 20_010
        var pathDepth = 3
        var compressionRatio = 200
        var seconds: TimeInterval = 30
    }

    enum Failure: Error { case invalidArchive, limitExceeded, compressionRatioExceeded, timedOut, ioFailure }

    private struct Entry {
        let path: String
        let name: Data
        let flags: UInt16
        let method: UInt16
        let checksum: UInt32
        let compressed: Int
        let expanded: Int
        let localOffset: Int
        let isDirectory: Bool
        var payload = 0
    }

    static func extract(_ source: URL, to destination: URL, limits: Limits = Limits()) throws {
        let deadline = Date().addingTimeInterval(limits.seconds)
        try checkDeadline(deadline)
        let bytes = try BackupFiles.read(source, maxBytes: limits.archiveBytes, deadline: deadline)
        let entries = try inspect(bytes, limits: limits, deadline: deadline)
        let free = try destination.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        let expanded = entries.reduce(0) { $0 + $1.expanded }
        // Include room for files, directory metadata, and the commit preparation.
        guard Int64(free) > Int64(expanded) + 16 * 1024 * 1024 else { throw Failure.limitExceeded }
        try BackupFiles.createPrivateDirectory(destination)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: destination) } }
        var actualTotal = 0
        for i in entries.indices {
            try checkDeadline(deadline)
            let entry = entries[i]
            let target = destination.appendingPathComponent(entry.path, isDirectory: entry.isDirectory)
            if entry.isDirectory {
                try BackupFiles.createPrivateDirectories(target, under: destination)
                continue
            }
            try BackupFiles.createPrivateDirectories(target.deletingLastPathComponent(), under: destination)
            let output = try expand(entry, bytes: bytes, deadline: deadline, limits: limits,
                                    remainingTotal: limits.totalBytes - actualTotal)
            actualTotal += output.count
            try BackupFiles.writeNew(output, to: target)
        }
        complete = true
    }

    private static func inspect(_ bytes: Data, limits: Limits, deadline: Date) throws -> [Entry] {
        guard bytes.count >= 22 else { throw Failure.invalidArchive }
        var end: Int?
        for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1) {
            if u32(bytes, offset) == 0x06054b50,
               offset + 22 + Int(u16(bytes, offset + 20)) == bytes.count {
                end = offset
                break
            }
        }
        guard let eocd = end, u16(bytes, eocd + 4) == 0, u16(bytes, eocd + 6) == 0,
              u16(bytes, eocd + 8) == u16(bytes, eocd + 10) else { throw Failure.invalidArchive }
        let count = Int(u16(bytes, eocd + 10))
        let centralSize = Int(u32(bytes, eocd + 12))
        let centralOffset = Int(u32(bytes, eocd + 16))
        guard count > 0, count < 65_535, count <= limits.entries,
              centralOffset <= eocd, centralSize == eocd - centralOffset else { throw Failure.limitExceeded }
        var result: [Entry] = []
        var names = Set<String>()
        var offset = centralOffset
        var total = 0
        for _ in 0..<count {
            try checkDeadline(deadline)
            guard offset <= eocd - 46, u32(bytes, offset) == 0x02014b50 else { throw Failure.invalidArchive }
            let nameLength = Int(u16(bytes, offset + 28))
            let extraLength = Int(u16(bytes, offset + 30))
            let commentLength = Int(u16(bytes, offset + 32))
            let recordSize = 46 + nameLength + extraLength + commentLength
            guard nameLength > 0, nameLength <= 512, recordSize <= eocd - offset,
                  u16(bytes, offset + 34) == 0 else { throw Failure.invalidArchive }
            let name = bytes.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            guard let path = String(data: name, encoding: .utf8),
                  !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
                  !path.contains(":"), path.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace || $0 == " " })
            else { throw Failure.invalidArchive }
            let directory = path.hasSuffix("/")
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            let parts = directory ? Array(components.dropLast()) : components
            guard !parts.isEmpty, parts.count <= limits.pathDepth,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  names.insert(path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))).inserted
            else { throw Failure.invalidArchive }
            let flags = u16(bytes, offset + 8)
            let method = u16(bytes, offset + 10)
            // Encryption, patched data, masked headers, and unsupported features are rejected.
            guard flags & ~UInt16(0x080e) == 0, flags & 1 == 0,
                  method == 0 || method == 8 else { throw Failure.invalidArchive }
            let mode = u32(bytes, offset + 38) >> 16
            let fileType = mode & 0o170000
            guard fileType == 0 || fileType == (directory ? 0o040000 : 0o100000),
                  u32(bytes, offset + 38) & 0x10 == 0 || directory else { throw Failure.invalidArchive }
            let compressed = Int(u32(bytes, offset + 20))
            let expanded = Int(u32(bytes, offset + 24))
            let checksum = u32(bytes, offset + 16)
            let local = Int(u32(bytes, offset + 42))
            guard compressed != Int(UInt32.max), expanded != Int(UInt32.max), local != Int(UInt32.max),
                  expanded <= limits.entryBytes, expanded <= limits.totalBytes - total,
                  !directory || (expanded == 0 && compressed == 0 && checksum == 0),
                  method != 0 || compressed == expanded else { throw Failure.limitExceeded }
            guard expanded == 0 || (compressed > 0 && expanded <= compressed * limits.compressionRatio) else {
                throw Failure.compressionRatioExceeded
            }
            try validateExtras(bytes, at: offset + 46 + nameLength, count: extraLength)
            total += expanded
            result.append(Entry(path: path, name: name, flags: flags, method: method,
                                checksum: checksum, compressed: compressed, expanded: expanded,
                                localOffset: local, isDirectory: directory))
            offset += recordSize
        }
        guard offset == eocd else { throw Failure.invalidArchive }

        var ranges: [Range<Int>] = []
        for i in result.indices {
            try checkDeadline(deadline)
            let entry = result[i]
            let local = entry.localOffset
            guard local <= centralOffset - 30, u32(bytes, local) == 0x04034b50,
                  u16(bytes, local + 6) == entry.flags, u16(bytes, local + 8) == entry.method else {
                throw Failure.invalidArchive
            }
            let nameLength = Int(u16(bytes, local + 26))
            let extraLength = Int(u16(bytes, local + 28))
            let payload = local + 30 + nameLength + extraLength
            guard payload <= centralOffset, entry.compressed <= centralOffset - payload,
                  nameLength == entry.name.count,
                  bytes.subdata(in: (local + 30)..<(local + 30 + nameLength)) == entry.name else {
                throw Failure.invalidArchive
            }
            if entry.flags & 8 == 0 {
                guard u32(bytes, local + 14) == entry.checksum,
                      u32(bytes, local + 18) == UInt32(entry.compressed),
                      u32(bytes, local + 22) == UInt32(entry.expanded) else { throw Failure.invalidArchive }
            }
            try validateExtras(bytes, at: local + 30 + nameLength, count: extraLength)
            result[i].payload = payload
            ranges.append(local..<(payload + entry.compressed))
        }
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        for i in 1..<sorted.count where sorted[i - 1].upperBound > sorted[i].lowerBound {
            throw Failure.invalidArchive
        }
        // No file may be the parent of a second entry.
        let files = Set(result.filter { !$0.isDirectory }.map { $0.path.lowercased() })
        for entry in result {
            var components = entry.path.lowercased().split(separator: "/")
            while components.count > 1 {
                components.removeLast()
                guard !files.contains(components.joined(separator: "/")) else { throw Failure.invalidArchive }
            }
        }
        return result
    }

    private static func expand(_ entry: Entry, bytes: Data, deadline: Date, limits: Limits,
                               remainingTotal: Int) throws -> Data {
        let input = bytes.subdata(in: entry.payload..<(entry.payload + entry.compressed))
        var output = Data()
        if entry.method == 0 {
            output = input
        } else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
            else { throw Failure.invalidArchive }
            defer { inflateEnd(&stream) }
            try input.withUnsafeBytes { buffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: buffer.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                let chunkSize = 32_768
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                while true {
                    try checkDeadline(deadline)
                    let beforeInput = stream.avail_in
                    let status = chunk.withUnsafeMutableBytes { out -> Int32 in
                        stream.next_out = out.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(chunkSize)
                        return inflate(&stream, Z_NO_FLUSH)
                    }
                    let produced = chunk.count - Int(stream.avail_out)
                    guard produced <= entry.expanded - output.count,
                          produced <= remainingTotal - output.count,
                          produced <= limits.entryBytes - output.count else { throw Failure.limitExceeded }
                    output.append(contentsOf: chunk.prefix(produced))
                    if status == Z_STREAM_END {
                        guard stream.avail_in == 0 else { throw Failure.invalidArchive }
                        break
                    }
                    guard status == Z_OK, produced > 0 || stream.avail_in < beforeInput else {
                        throw Failure.invalidArchive
                    }
                }
            }
        }
        try checkDeadline(deadline)
        let checksum = output.withUnsafeBytes { buffer in
            crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(output.count))
        }
        guard output.count == entry.expanded, UInt32(checksum) == entry.checksum else { throw Failure.invalidArchive }
        return output
    }

    private static func validateExtras(_ bytes: Data, at offset: Int, count: Int) throws {
        var cursor = offset
        let end = offset + count
        while cursor < end {
            guard end - cursor >= 4 else { throw Failure.invalidArchive }
            let tag = u16(bytes, cursor)
            let size = Int(u16(bytes, cursor + 2))
            guard size <= end - cursor - 4, tag != 1 else { throw Failure.invalidArchive }
            cursor += 4 + size
        }
    }

    private static func checkDeadline(_ deadline: Date) throws {
        guard Date() < deadline else { throw Failure.timedOut }
    }

    private static func u16(_ bytes: Data, _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
    private static func u32(_ bytes: Data, _ offset: Int) -> UInt32 {
        UInt32(u16(bytes, offset)) | UInt32(u16(bytes, offset + 2)) << 16
    }
}

/// No-follow, bounded I/O and owner-only staging. These routines never accept links.
enum BackupFiles {
    static func read(_ url: URL, maxBytes: Int, deadline: Date? = nil) throws -> Data {
        // A selected FIFO must not block before fstat can reject its file type.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw BackupArchive.Failure.ioFailure }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maxBytes else { throw BackupArchive.Failure.limitExceeded }
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 32_768)
        while true {
            if let end = deadline, Date() >= end { throw BackupArchive.Failure.timedOut }
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count == 0 { break }
            guard count > 0, count <= maxBytes - result.count else { throw BackupArchive.Failure.limitExceeded }
            result.append(contentsOf: chunk.prefix(count))
        }
        return result
    }

    static func writeNew(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BackupArchive.Failure.ioFailure }
        defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw BackupArchive.Failure.ioFailure }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw BackupArchive.Failure.ioFailure }
    }

    static func createPrivateDirectory(_ url: URL) throws {
        guard mkdir(url.path, 0o700) == 0 else { throw BackupArchive.Failure.ioFailure }
    }

    static func createPrivateDirectories(_ url: URL, under root: URL) throws {
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { throw BackupArchive.Failure.invalidArchive }
        var current = root
        for part in url.path.dropFirst(root.path.count).split(separator: "/") {
            current.appendPathComponent(String(part), isDirectory: true)
            var info = stat()
            if lstat(current.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { throw BackupArchive.Failure.ioFailure }
            } else {
                try createPrivateDirectory(current)
            }
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR && info.st_uid == getuid()
    }

    static func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BackupArchive.Failure.ioFailure }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw BackupArchive.Failure.ioFailure }
    }
}
