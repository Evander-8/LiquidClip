/**
 * [INPUT]: 依赖系统 libsqlite3（SQLite3 + External-Content FTS5 trigram）、ClipItem 与 ClipGroup 模型
 * [OUTPUT]: 提供线程安全的增量存储与异步全文检索引擎 SQLiteStore，支持 WAL、Triggers 自动同步 FTS5、版本迁移与混合查询
 * [POS]: 底层持久化数据库引擎，专由 StorageManager 持有并调度
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.liquidclip.sqlite", qos: .utility)
    
    public init?(databaseURL: URL) {
        var openedDB: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &openedDB, flags, nil) == SQLITE_OK,
              let db = openedDB else {
            if let openedDB = openedDB {
                sqlite3_close(openedDB)
            }
            print("Failed to open SQLite database at \(databaseURL.path)")
            return nil
        }
        self.db = db
        
        let ok = dbQueue.sync { () -> Bool in
            Self.exec(db: db, sql: "PRAGMA journal_mode = WAL;")
            Self.exec(db: db, sql: "PRAGMA synchronous = NORMAL;")
            Self.exec(db: db, sql: "PRAGMA temp_store = MEMORY;")
            Self.exec(db: db, sql: "PRAGMA recursive_triggers = ON;")
            return Self.createSchema(db: db)
        }
        if !ok {
            sqlite3_close(db)
            self.db = nil
            return nil
        }
    }
    
    deinit {
        if let db = db {
            sqlite3_close_v2(db)
        }
    }
    
    // MARK: - Schema Creation
    
    private static func createSchema(db: OpaquePointer) -> Bool {
        let baseStatements = [
            """
            CREATE TABLE IF NOT EXISTS groups (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                icon TEXT NOT NULL,
                color_hex TEXT,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                plain_text TEXT,
                html_text TEXT,
                image_file_name TEXT,
                image_hash TEXT,
                ocr_text TEXT,
                image_width REAL,
                image_height REAL,
                file_paths_json TEXT,
                file_names TEXT,
                color_hex TEXT,
                source_app_name TEXT,
                source_app_bundle_id TEXT,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                group_id TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                cached_char_count INTEGER,
                cached_line_count INTEGER,
                cached_word_count INTEGER,
                cached_display_title TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_clips_created_at ON clips(created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_clips_image_hash ON clips(image_hash);",
            "CREATE INDEX IF NOT EXISTS idx_clips_group_id ON clips(group_id);"
        ]
        for sql in baseStatements {
            if !exec(db: db, sql: sql) {
                return false
            }
        }

        let currentVersion = queryUserVersion(db: db)
        if currentVersion < 2 {
            let migrationStatements = [
                "DROP TRIGGER IF EXISTS clips_ai;",
                "DROP TRIGGER IF EXISTS clips_ad;",
                "DROP TRIGGER IF EXISTS clips_au;",
                "DROP TABLE IF EXISTS clips_fts;",
                """
                CREATE VIRTUAL TABLE clips_fts USING fts5(
                    plain_text,
                    ocr_text,
                    source_app_name,
                    color_hex,
                    file_names,
                    content='clips',
                    content_rowid='rowid',
                    tokenize='trigram'
                );
                """,
                """
                CREATE TRIGGER clips_ai AFTER INSERT ON clips BEGIN
                    INSERT INTO clips_fts(rowid, plain_text, ocr_text, source_app_name, color_hex, file_names)
                    VALUES (new.rowid, new.plain_text, new.ocr_text, new.source_app_name, new.color_hex, new.file_names);
                END;
                """,
                """
                CREATE TRIGGER clips_ad AFTER DELETE ON clips BEGIN
                    INSERT INTO clips_fts(clips_fts, rowid, plain_text, ocr_text, source_app_name, color_hex, file_names)
                    VALUES ('delete', old.rowid, old.plain_text, old.ocr_text, old.source_app_name, old.color_hex, old.file_names);
                END;
                """,
                """
                CREATE TRIGGER clips_au AFTER UPDATE ON clips BEGIN
                    INSERT INTO clips_fts(clips_fts, rowid, plain_text, ocr_text, source_app_name, color_hex, file_names)
                    VALUES ('delete', old.rowid, old.plain_text, old.ocr_text, old.source_app_name, old.color_hex, old.file_names);
                    INSERT INTO clips_fts(rowid, plain_text, ocr_text, source_app_name, color_hex, file_names)
                    VALUES (new.rowid, new.plain_text, new.ocr_text, new.source_app_name, new.color_hex, new.file_names);
                END;
                """,
                "INSERT INTO clips_fts(clips_fts) VALUES('rebuild');",
                "PRAGMA user_version = 2;"
            ]
            guard exec(db: db, sql: "BEGIN IMMEDIATE;") else { return false }
            for sql in migrationStatements {
                if !exec(db: db, sql: sql) {
                    exec(db: db, sql: "ROLLBACK;")
                    return false
                }
            }
            guard exec(db: db, sql: "COMMIT;") else {
                exec(db: db, sql: "ROLLBACK;")
                return false
            }
            exec(db: db, sql: "VACUUM;")
        }
        return true
    }

    private static func queryUserVersion(db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
    
    // MARK: - Read Queries
    
    public func loadAllGroups() -> [ClipGroup] {
        dbQueue.sync {
            guard let db = db else { return [] }
            let sql = "SELECT id, name, icon, color_hex, created_at FROM groups ORDER BY created_at ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }
            
            var result: [ClipGroup] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idStr = columnText(stmt, 0), let uuid = UUID(uuidString: idStr) else { continue }
                let name = columnText(stmt, 1) ?? "分组"
                let icon = columnText(stmt, 2) ?? "folder.fill"
                let colorHex = columnText(stmt, 3)
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                result.append(ClipGroup(id: uuid, name: name, icon: icon, colorHex: colorHex, createdAt: createdAt))
            }
            return result
        }
    }
    
    public func loadAllClips() -> [ClipItem] {
        dbQueue.sync {
            guard let db = db else { return [] }
            let sql = """
            SELECT id, type, plain_text, html_text, image_file_name, image_hash, ocr_text,
                   image_width, image_height, file_paths_json, color_hex, source_app_name,
                   source_app_bundle_id, is_pinned, group_id, created_at, updated_at,
                   cached_char_count, cached_line_count, cached_word_count, cached_display_title
            FROM clips
            ORDER BY created_at DESC;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }
            
            var result: [ClipItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idStr = columnText(stmt, 0),
                      let uuid = UUID(uuidString: idStr),
                      let typeRaw = columnText(stmt, 1),
                      let type = ClipType(rawValue: typeRaw) else {
                    continue
                }
                let filePaths: [String]?
                if let jsonStr = columnText(stmt, 9), let data = jsonStr.data(using: .utf8) {
                    filePaths = try? JSONDecoder().decode([String].self, from: data)
                } else {
                    filePaths = nil
                }
                let groupId = columnText(stmt, 14).flatMap { UUID(uuidString: $0) }
                
                var item = ClipItem(
                    id: uuid,
                    type: type,
                    plainText: columnText(stmt, 2),
                    htmlText: columnText(stmt, 3),
                    imageFileName: columnText(stmt, 4),
                    imageHash: columnText(stmt, 5),
                    ocrText: columnText(stmt, 6),
                    imageWidth: columnOptionalDouble(stmt, 7),
                    imageHeight: columnOptionalDouble(stmt, 8),
                    filePaths: filePaths,
                    colorHex: columnText(stmt, 10),
                    sourceAppName: columnText(stmt, 11),
                    sourceAppBundleId: columnText(stmt, 12),
                    isPinned: sqlite3_column_int(stmt, 13) != 0,
                    groupId: groupId,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 15)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 16)),
                    cachedCharCount: columnOptionalInt(stmt, 17),
                    cachedLineCount: columnOptionalInt(stmt, 18),
                    cachedWordCount: columnOptionalInt(stmt, 19),
                    cachedDisplayTitle: columnText(stmt, 20)
                )
                item.populateCachedMetricsIfNeeded()
                result.append(item)
            }
            return result
        }
    }
    
    /// Hybrid External-Content FTS5 trigram + LIKE search (sync). Returns matching clip UUIDs.
    public func searchClipIds(query: String) -> Set<UUID> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        return dbQueue.sync {
            guard let db = db else { return [] }
            return Self.executeSearch(db: db, trimmed: trimmed)
        }
    }

    /// Hybrid External-Content FTS5 trigram + LIKE search (async on dbQueue).
    public func searchClipIdsAsync(query: String) async -> Set<UUID> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: Self.executeSearch(db: db, trimmed: trimmed))
            }
        }
    }

    private static func executeSearch(db: OpaquePointer, trimmed: String) -> Set<UUID> {
        if trimmed.count >= 3 {
            let escaped = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let ftsSQL = "SELECT c.id FROM clips_fts f JOIN clips c ON c.rowid = f.rowid WHERE clips_fts MATCH ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, ftsSQL, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, escaped, -1, SQLITE_TRANSIENT)
                var ids = Set<UUID>()
                var stepped = false
                while true {
                    let rc = sqlite3_step(stmt)
                    if rc == SQLITE_ROW {
                        stepped = true
                        if let idStr = columnText(stmt, 0), let uuid = UUID(uuidString: idStr) {
                            ids.insert(uuid)
                        }
                    } else if rc == SQLITE_DONE {
                        stepped = true
                        break
                    } else {
                        stepped = false
                        break
                    }
                }
                if stepped {
                    return ids
                }
            }
        }
        
        // Short query (< 3 chars) or FTS fallback via parameterized LIKE
        let likeEscaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(likeEscaped)%"
        let likeSQL = """
        SELECT id FROM clips
        WHERE plain_text LIKE ?1 ESCAPE '\\'
           OR ocr_text LIKE ?1 ESCAPE '\\'
           OR source_app_name LIKE ?1 ESCAPE '\\'
           OR color_hex LIKE ?1 ESCAPE '\\'
           OR file_names LIKE ?1 ESCAPE '\\';
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, likeSQL, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
        
        var ids = Set<UUID>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idStr = columnText(stmt, 0), let uuid = UUID(uuidString: idStr) {
                ids.insert(uuid)
            }
        }
        return ids
    }
    
    // MARK: - Incremental Mutations & Migration
    
    public func replaceAll(groups: [ClipGroup], clips: [ClipItem]) {
        dbQueue.sync {
            guard let db = db else { return }
            Self.exec(db: db, sql: "BEGIN IMMEDIATE;")
            Self.exec(db: db, sql: "DELETE FROM clips;")
            Self.exec(db: db, sql: "DELETE FROM groups;")
            for group in groups {
                Self.upsertGroupInternal(db: db, group: group)
            }
            for clip in clips {
                Self.upsertClipInternal(db: db, item: clip)
            }
            Self.exec(db: db, sql: "COMMIT;")
        }
    }
    
    public func upsertGroup(_ group: ClipGroup) {
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            Self.upsertGroupInternal(db: db, group: group)
        }
    }
    
    public func deleteGroup(id: UUID) {
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            Self.exec(db: db, sql: "BEGIN IMMEDIATE;")
            var stmt1: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM groups WHERE id = ?;", -1, &stmt1, nil) == SQLITE_OK, let stmt1 = stmt1 {
                sqlite3_bind_text(stmt1, 1, id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt1)
                sqlite3_finalize(stmt1)
            }
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE clips SET group_id = NULL WHERE group_id = ?;", -1, &stmt2, nil) == SQLITE_OK, let stmt2 = stmt2 {
                sqlite3_bind_text(stmt2, 1, id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt2)
                sqlite3_finalize(stmt2)
            }
            Self.exec(db: db, sql: "COMMIT;")
        }
    }
    
    public func upsertClip(_ item: ClipItem) {
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            Self.exec(db: db, sql: "BEGIN IMMEDIATE;")
            Self.upsertClipInternal(db: db, item: item)
            Self.exec(db: db, sql: "COMMIT;")
        }
    }
    
    public func deleteClips(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            Self.exec(db: db, sql: "BEGIN IMMEDIATE;")
            var delClipStmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?;", -1, &delClipStmt, nil)
            for id in ids {
                let idStr = id.uuidString
                if let s = delClipStmt {
                    sqlite3_reset(s)
                    sqlite3_bind_text(s, 1, idStr, -1, SQLITE_TRANSIENT)
                    sqlite3_step(s)
                }
            }
            if let s = delClipStmt { sqlite3_finalize(s) }
            Self.exec(db: db, sql: "COMMIT;")
        }
    }
    
    public func updateClipPin(id: UUID, isPinned: Bool) {
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE clips SET is_pinned = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
                sqlite3_bind_int(stmt, 1, isPinned ? 1 : 0)
                sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }
    
    public func updateClipGroup(id: UUID, groupId: UUID?) {
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE clips SET group_id = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
                bindOptionalText(stmt, 1, groupId?.uuidString)
                sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }
    
    public func updateClipOCR(id: UUID, ocrText: String?) {
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE clips SET ocr_text = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
                bindOptionalText(stmt, 1, ocrText)
                sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }
    
    // MARK: - Internal SQLite Helpers
    
    private static func upsertGroupInternal(db: OpaquePointer, group: ClipGroup) {
        let sql = """
        INSERT OR REPLACE INTO groups (id, name, icon, color_hex, created_at)
        VALUES (?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, group.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, group.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, group.icon, -1, SQLITE_TRANSIENT)
        bindOptionalText(stmt, 4, group.colorHex)
        sqlite3_bind_double(stmt, 5, group.createdAt.timeIntervalSince1970)
        sqlite3_step(stmt)
    }
    
    private static func upsertClipInternal(db: OpaquePointer, item: ClipItem) {
        let filePathsJSON: String?
        if let paths = item.filePaths,
           let data = try? JSONEncoder().encode(paths) {
            filePathsJSON = String(data: data, encoding: .utf8)
        } else {
            filePathsJSON = nil
        }
        let fileNames: String?
        if let paths = item.filePaths, !paths.isEmpty {
            fileNames = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: " ")
        } else {
            fileNames = nil
        }
        
        let sql = """
        INSERT INTO clips (
            id, type, plain_text, html_text, image_file_name, image_hash, ocr_text,
            image_width, image_height, file_paths_json, file_names, color_hex,
            source_app_name, source_app_bundle_id, is_pinned, group_id,
            created_at, updated_at, cached_char_count, cached_line_count,
            cached_word_count, cached_display_title
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            type = excluded.type,
            plain_text = excluded.plain_text,
            html_text = excluded.html_text,
            image_file_name = excluded.image_file_name,
            image_hash = excluded.image_hash,
            ocr_text = excluded.ocr_text,
            image_width = excluded.image_width,
            image_height = excluded.image_height,
            file_paths_json = excluded.file_paths_json,
            file_names = excluded.file_names,
            color_hex = excluded.color_hex,
            source_app_name = excluded.source_app_name,
            source_app_bundle_id = excluded.source_app_bundle_id,
            is_pinned = excluded.is_pinned,
            group_id = excluded.group_id,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            cached_char_count = excluded.cached_char_count,
            cached_line_count = excluded.cached_line_count,
            cached_word_count = excluded.cached_word_count,
            cached_display_title = excluded.cached_display_title;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, item.type.rawValue, -1, SQLITE_TRANSIENT)
            bindOptionalText(stmt, 3, item.plainText)
            bindOptionalText(stmt, 4, item.htmlText)
            bindOptionalText(stmt, 5, item.imageFileName)
            bindOptionalText(stmt, 6, item.imageHash)
            bindOptionalText(stmt, 7, item.ocrText)
            bindOptionalDouble(stmt, 8, item.imageWidth)
            bindOptionalDouble(stmt, 9, item.imageHeight)
            bindOptionalText(stmt, 10, filePathsJSON)
            bindOptionalText(stmt, 11, fileNames)
            bindOptionalText(stmt, 12, item.colorHex)
            bindOptionalText(stmt, 13, item.sourceAppName)
            bindOptionalText(stmt, 14, item.sourceAppBundleId)
            sqlite3_bind_int(stmt, 15, item.isPinned ? 1 : 0)
            bindOptionalText(stmt, 16, item.groupId?.uuidString)
            sqlite3_bind_double(stmt, 17, item.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 18, item.updatedAt.timeIntervalSince1970)
            bindOptionalInt(stmt, 19, item.cachedCharCount)
            bindOptionalInt(stmt, 20, item.cachedLineCount)
            bindOptionalInt(stmt, 21, item.cachedWordCount)
            bindOptionalText(stmt, 22, item.cachedDisplayTitle)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
    
    @discardableResult
    private static func exec(db: OpaquePointer, sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQLite error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
            return false
        }
        return true
    }
}

private func bindOptionalText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
    if let value = value {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(stmt, index)
    }
}

private func bindOptionalDouble(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
    if let value = value {
        sqlite3_bind_double(stmt, index, value)
    } else {
        sqlite3_bind_null(stmt, index)
    }
}

private func bindOptionalInt(_ stmt: OpaquePointer, _ index: Int32, _ value: Int?) {
    if let value = value {
        sqlite3_bind_int64(stmt, index, Int64(value))
    } else {
        sqlite3_bind_null(stmt, index)
    }
}

private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
          let cStr = sqlite3_column_text(stmt, index) else {
        return nil
    }
    return String(cString: cStr)
}

private func columnOptionalDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
    guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
    return sqlite3_column_double(stmt, index)
}

private func columnOptionalInt(_ stmt: OpaquePointer, _ index: Int32) -> Int? {
    guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int64(stmt, index))
}
