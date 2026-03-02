import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/body_blog_entry.dart';
import '../models/capture_entry.dart';

/// Snapshot of database metadata for the debug panel.
class DbInfo {
  final String path;
  final int schemaVersion;
  final int entryCount;
  final int captureCount;
  final String? oldestDate;
  final String? newestDate;

  const DbInfo({
    required this.path,
    required this.schemaVersion,
    required this.entryCount,
    this.captureCount = 0,
    this.oldestDate,
    this.newestDate,
  });
}

/// SQLite persistence layer for [BodyBlogEntry] and [CaptureEntry] records.
///
/// One row per calendar day (PK = ISO date string "yyyy-MM-dd") for body blog entries.
/// One row per capture (PK = capture ID) for captures.
/// Callers never interact with raw SQL — use the typed helpers below.
class LocalDbService {
  static const _dbName = 'bodypress.db';
  static const _tableEntries = 'entries';
  static const _tableSettings = 'settings';
  static const _tableCaptures = 'captures';
  static const _schemaVersion = 7;

  Database? _db;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);

    return openDatabase(
      fullPath,
      version: _schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableEntries (
        date         TEXT    PRIMARY KEY,
        headline     TEXT    NOT NULL,
        summary      TEXT    NOT NULL,
        full_body    TEXT    NOT NULL,
        mood         TEXT    NOT NULL,
        mood_emoji   TEXT    NOT NULL,
        tags         TEXT    NOT NULL DEFAULT '[]',
        user_note    TEXT,
        user_mood    TEXT,
        snapshot     TEXT    NOT NULL DEFAULT '{}',
        ai_generated INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE $_tableSettings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $_tableCaptures (
        id               TEXT    PRIMARY KEY,
        timestamp        TEXT    NOT NULL,
        is_processed     INTEGER NOT NULL DEFAULT 0,
        user_note        TEXT,
        user_mood        TEXT,
        tags             TEXT    NOT NULL DEFAULT '[]',
        health_data      TEXT,
        environment_data TEXT,
        location_data    TEXT,
        calendar_events  TEXT    NOT NULL DEFAULT '[]',
        processed_at     TEXT,
        ai_insights      TEXT,
        source           TEXT    NOT NULL DEFAULT 'manual',
        trigger          TEXT,
        execution_duration_ms INTEGER,
        errors           TEXT    NOT NULL DEFAULT '[]',
        battery_level    INTEGER,
        ai_metadata      TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_captures_timestamp ON $_tableCaptures(timestamp DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_captures_processed ON $_tableCaptures(is_processed)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2: add settings table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableSettings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      // v2 → v3: add user_mood column
      // Guard against duplicate-column errors if the column was already
      // present from a partially-applied migration or a hot-restart.
      try {
        await db.execute(
          'ALTER TABLE $_tableEntries ADD COLUMN user_mood TEXT',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
    }
    if (oldVersion < 4) {
      // v3 → v4: add captures table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableCaptures (
          id               TEXT    PRIMARY KEY,
          timestamp        TEXT    NOT NULL,
          is_processed     INTEGER NOT NULL DEFAULT 0,
          user_note        TEXT,
          user_mood        TEXT,
          tags             TEXT    NOT NULL DEFAULT '[]',
          health_data      TEXT,
          environment_data TEXT,
          location_data    TEXT,
          calendar_events  TEXT    NOT NULL DEFAULT '[]',
          processed_at     TEXT,
          ai_insights      TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_captures_timestamp 
        ON $_tableCaptures(timestamp DESC)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_captures_processed 
        ON $_tableCaptures(is_processed)
      ''');
    }
    if (oldVersion < 5) {
      // v4 → v5: add background capture metadata columns
      final newCols = {
        'source': "TEXT NOT NULL DEFAULT 'manual'",
        'trigger': 'TEXT',
        'execution_duration_ms': 'INTEGER',
        'errors': "TEXT NOT NULL DEFAULT '[]'",
        'battery_level': 'INTEGER',
      };
      for (final entry in newCols.entries) {
        try {
          await db.execute(
            'ALTER TABLE $_tableCaptures ADD COLUMN ${entry.key} ${entry.value}',
          );
        } catch (e) {
          if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
        }
      }
    }
    if (oldVersion < 6) {
      // v5 → v6: add ai_generated column to entries table
      try {
        await db.execute(
          'ALTER TABLE $_tableEntries ADD COLUMN ai_generated INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
    }
    if (oldVersion < 7) {
      // v6 → v7: add AI metadata column to captures table
      try {
        await db.execute(
          'ALTER TABLE $_tableCaptures ADD COLUMN ai_metadata TEXT',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// "yyyy-MM-dd" key used as primary key.
  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> _toRow(BodyBlogEntry e) {
    final json = e.toJson();
    // toJson already encodes date as ISO string; convert to date-only key
    return {
      'date': _dateKey(e.date),
      'headline': json['headline'],
      'summary': json['summary'],
      'full_body': json['full_body'],
      'mood': json['mood'],
      'mood_emoji': json['mood_emoji'],
      'ai_generated': json['ai_generated'],
      'tags': json['tags'],
      'user_note': json['user_note'],
      'user_mood': json['user_mood'],
      'snapshot': json['snapshot'],
    };
  }

  static BodyBlogEntry _fromRow(Map<String, dynamic> row) {
    return BodyBlogEntry.fromJson({
      ...row,
      // fromJson expects ISO8601 date
      'date': '${row['date']}T00:00:00.000',
    });
  }

  // ── public API ────────────────────────────────────────────────────────────

  /// Insert or replace an entry (upsert by date).
  Future<void> saveEntry(BodyBlogEntry entry) async {
    final db = await _database;
    await db.insert(
      _tableEntries,
      _toRow(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load entry for a specific date, or `null` if not stored yet.
  Future<BodyBlogEntry?> loadEntry(DateTime date) async {
    final db = await _database;
    final rows = await db.query(
      _tableEntries,
      where: 'date = ?',
      whereArgs: [_dateKey(date)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Load all stored entries between [from] and [to] (inclusive), newest first.
  Future<List<BodyBlogEntry>> loadEntriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    final db = await _database;
    final rows = await db.query(
      _tableEntries,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [_dateKey(from), _dateKey(to)],
      orderBy: 'date DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Overwrite only the `user_note` and `user_mood` columns for a given date.
  /// Returns the updated entry, or `null` if the date does not exist.
  Future<BodyBlogEntry?> updateUserNote(
    DateTime date,
    String? note, {
    String? mood,
  }) async {
    final db = await _database;
    final count = await db.update(
      _tableEntries,
      {'user_note': note, 'user_mood': mood},
      where: 'date = ?',
      whereArgs: [_dateKey(date)],
    );
    if (count == 0) return null;
    return loadEntry(date);
  }

  /// Returns true when at least one journal entry exists in the database.
  /// Used to detect a first-time install vs a returning user.
  Future<bool> hasAnyEntries() async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableEntries LIMIT 1',
    );
    return (result.first['count'] as int? ?? 0) > 0;
  }

  /// Delete the persisted entry for [date] (no-op if absent).
  Future<void> deleteEntry(DateTime date) async {
    final db = await _database;
    await db.delete(
      _tableEntries,
      where: 'date = ?',
      whereArgs: [_dateKey(date)],
    );
  }

  /// Total number of stored entries.
  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_tableEntries',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Load the [n] most-recent entries, newest first.
  Future<List<BodyBlogEntry>> loadRecentEntries(int n) async {
    final db = await _database;
    final rows = await db.query(_tableEntries, orderBy: 'date DESC', limit: n);
    return rows.map(_fromRow).toList();
  }

  /// Filesystem path of the database file (useful for debug).
  Future<String> getDatabasePath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, _dbName);
  }

  /// Aggregate information about the database, used by the debug panel.
  Future<DbInfo> getDbInfo() async {
    final db = await _database;
    final entryCount =
        (await db.rawQuery(
              'SELECT COUNT(*) as c FROM $_tableEntries',
            )).first['c']
            as int? ??
        0;
    final captureCount =
        (await db.rawQuery(
              'SELECT COUNT(*) as c FROM $_tableCaptures',
            )).first['c']
            as int? ??
        0;
    final oldest =
        (await db.query(
              _tableEntries,
              orderBy: 'date ASC',
              limit: 1,
            )).firstOrNull?['date']
            as String?;
    final newest =
        (await db.query(
              _tableEntries,
              orderBy: 'date DESC',
              limit: 1,
            )).firstOrNull?['date']
            as String?;
    final dbPath = await getDatabasePath();
    return DbInfo(
      path: dbPath,
      schemaVersion: _schemaVersion,
      entryCount: entryCount,
      captureCount: captureCount,
      oldestDate: oldest,
      newestDate: newest,
    );
  }

  // ── settings ──────────────────────────────────────────────────────────────

  /// Persist an app-level setting.
  Future<void> setSetting(String key, String value) async {
    final db = await _database;
    await db.insert(_tableSettings, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retrieve a previously persisted setting, or `null` if not set.
  Future<String?> getSetting(String key) async {
    final db = await _database;
    final rows = await db.query(
      _tableSettings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  // ── debug ─────────────────────────────────────────────────────────────────

  /// Raw rows for the debug inspector — returns lightweight maps
  /// (excludes the large full_body and snapshot JSON columns).
  Future<List<Map<String, Object?>>> getDebugRows() async {
    final db = await _database;
    return db.query(
      _tableEntries,
      columns: ['date', 'mood', 'mood_emoji', 'tags', 'user_note', 'user_mood'],
      orderBy: 'date DESC',
    );
  }

  // ── captures ──────────────────────────────────────────────────────────────

  /// Save a capture entry (insert or replace).
  Future<void> saveCapture(CaptureEntry capture) async {
    final db = await _database;
    await db.insert(
      _tableCaptures,
      capture.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load a specific capture by ID.
  Future<CaptureEntry?> loadCapture(String id) async {
    final db = await _database;
    final rows = await db.query(
      _tableCaptures,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CaptureEntry.fromJson(rows.first);
  }

  /// Load captures, optionally filtered by processed status.
  /// Results are ordered by timestamp descending (newest first).
  Future<List<CaptureEntry>> loadCaptures({
    bool? isProcessed,
    int? limit,
  }) async {
    final db = await _database;

    String? where;
    List<Object?>? whereArgs;

    if (isProcessed != null) {
      where = 'is_processed = ?';
      whereArgs = [isProcessed ? 1 : 0];
    }

    final rows = await db.query(
      _tableCaptures,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return rows.map((row) => CaptureEntry.fromJson(row)).toList();
  }

  /// Load all captures for a specific calendar date, ordered by timestamp ASC.
  ///
  /// Uses SQLite's `date()` function to match on the local calendar date
  /// of the stored ISO-8601 timestamp.
  Future<List<CaptureEntry>> loadCapturesForDate(DateTime date) async {
    final db = await _database;
    final dateStr = _dateKey(date);
    final rows = await db.query(
      _tableCaptures,
      where: "date(timestamp) = ?",
      whereArgs: [dateStr],
      orderBy: 'timestamp ASC',
    );
    return rows.map((row) => CaptureEntry.fromJson(row)).toList();
  }

  /// Update only the [ai_metadata] column for an existing capture.
  ///
  /// More efficient than loading + re-saving a full [CaptureEntry] when the
  /// only thing that changed is the AI metadata.
  Future<void> updateCaptureAiMetadata(
    String captureId,
    String aiMetadataJson,
  ) async {
    final db = await _database;
    await db.update(
      _tableCaptures,
      {'ai_metadata': aiMetadataJson},
      where: 'id = ?',
      whereArgs: [captureId],
    );
  }

  /// Delete a capture by ID.
  Future<void> deleteCapture(String id) async {
    final db = await _database;
    await db.delete(_tableCaptures, where: 'id = ?', whereArgs: [id]);
  }

  /// Get count of captures, optionally filtered by processed status.
  Future<int> countCaptures({bool? isProcessed}) async {
    final db = await _database;

    String? where;
    List<Object?>? whereArgs;

    if (isProcessed != null) {
      where = 'is_processed = ?';
      whereArgs = [isProcessed ? 1 : 0];
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_tableCaptures${where != null ? ' WHERE $where' : ''}',
      whereArgs,
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Load only **unprocessed** captures for a specific calendar date.
  ///
  /// These are captures that have not yet been consumed by the AI journal
  /// generation pipeline.
  Future<List<CaptureEntry>> loadUnprocessedCapturesForDate(
    DateTime date,
  ) async {
    final db = await _database;
    final dateStr = _dateKey(date);
    final rows = await db.query(
      _tableCaptures,
      where: "date(timestamp) = ? AND is_processed = 0",
      whereArgs: [dateStr],
      orderBy: 'timestamp ASC',
    );
    return rows.map((row) => CaptureEntry.fromJson(row)).toList();
  }

  /// Mark a list of captures as processed by setting `is_processed = 1`
  /// and `processed_at` to the current time.
  ///
  /// Called after the AI successfully uses these captures to generate
  /// or update a journal entry.
  Future<void> markCapturesProcessed(List<String> captureIds) async {
    if (captureIds.isEmpty) return;
    final db = await _database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final id in captureIds) {
      batch.update(
        _tableCaptures,
        {'is_processed': 1, 'processed_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }
}
