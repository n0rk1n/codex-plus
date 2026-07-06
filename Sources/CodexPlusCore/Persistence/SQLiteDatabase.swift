import Foundation
import SQLite3

public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

public final class SQLiteDatabase: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: OpaquePointer

    public init(path: String) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database."
            sqlite3_close(database)
            throw SQLiteError.openDatabase(message)
        }

        self.handle = database
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(handle)
    }

    public func execute(_ sql: String) throws {
        try execute(sql, [])
    }

    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        try lock.withLock {
            let statement = try prepare(sql: sql)
            defer { sqlite3_finalize(statement) }

            try bind(bindings, to: statement)

            var rows: [[String: SQLiteValue]] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    rows.append(readRow(from: statement))
                    continue
                }

                guard result == SQLITE_DONE else {
                    throw SQLiteError.step(message: String(cString: sqlite3_errmsg(handle)))
                }

                return rows
            }
        }
    }

    func execute(_ sql: String, _ bindings: [SQLiteValue]) throws {
        try lock.withLock {
            let statement = try prepare(sql: sql)
            defer { sqlite3_finalize(statement) }

            try bind(bindings, to: statement)

            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                throw SQLiteError.step(message: String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private func prepare(sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(message: String(cString: sqlite3_errmsg(handle)), sql: sql)
        }

        return statement
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            let parameterIndex = Int32(index + 1)
            let result: Int32

            switch value {
            case .null:
                result = sqlite3_bind_null(statement, parameterIndex)
            case let .integer(integer):
                result = sqlite3_bind_int64(statement, parameterIndex, sqlite3_int64(integer))
            case let .real(real):
                result = sqlite3_bind_double(statement, parameterIndex, real)
            case let .text(text):
                var bindResult: Int32 = SQLITE_ERROR
                text.withCString { value in
                    bindResult = sqlite3_bind_text(statement, parameterIndex, value, -1, sqliteTransientDestructor)
                }
                result = bindResult
            }

            guard result == SQLITE_OK else {
                throw SQLiteError.bind(message: String(cString: sqlite3_errmsg(handle)), index: index)
            }
        }
    }

    private func readRow(from statement: OpaquePointer?) -> [String: SQLiteValue] {
        let columnCount = sqlite3_column_count(statement)
        var row: [String: SQLiteValue] = [:]
        row.reserveCapacity(Int(columnCount))

        for index in 0 ..< columnCount {
            let name = sqlite3_column_name(statement, index).map { String(cString: $0) } ?? ""
            row[name] = value(at: index, from: statement)
        }

        return row
    }

    private func value(at index: Int32, from statement: OpaquePointer?) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(Int64(sqlite3_column_int64(statement, index)))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            let text = sqlite3_column_text(statement, index).map { pointer in
                String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
            } ?? ""
            return .text(text)
        default:
            return .null
        }
    }
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private enum SQLiteError: Error, CustomStringConvertible {
    case openDatabase(String)
    case prepare(message: String, sql: String)
    case bind(message: String, index: Int)
    case step(message: String)

    var description: String {
        switch self {
        case let .openDatabase(message):
            return "SQLite open error: \(message)"
        case let .prepare(message, sql):
            return "SQLite prepare error: \(message). SQL: \(sql)"
        case let .bind(message, index):
            return "SQLite bind error at index \(index): \(message)"
        case let .step(message):
            return "SQLite step error: \(message)"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) throws -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
