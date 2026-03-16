import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;
  DBHelper._init();

  final String supabaseUrl = 'https://btwbbjijrbyxbjlhtpqf.supabase.co';
  final String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0d2JiamlqcmJ5eGJqbGh0cHFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzODIwNjEsImV4cCI6MjA4ODk1ODA2MX0.jkVvPfaEvhhWDg7zTdjKnll5gDqeyNBy3Eli4cxmbhQ';

  final List<String> validPropCols = ['title', 'property_type', 'owner_name', 'land_type', 'house_type', 'dim_front', 'dim_back', 'dim_left', 'dim_right', 'status', 'asking_price', 'bottom_price', 'location', 'map_link', 'image_path', 'remark', 'is_synced', 'is_deleted', 'updated_at'];
  final List<String> validBuyerCols = ['name', 'phone', 'budget', 'requirement', 'location', 'remark', 'is_synced', 'is_deleted', 'updated_at'];
  final List<String> validOwnerCols = ['name', 'phone', 'remark', 'is_synced', 'is_deleted', 'updated_at'];

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('realestate.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE properties ADD COLUMN updated_at TEXT DEFAULT CURRENT_TIMESTAMP");
      await db.execute("ALTER TABLE buyers ADD COLUMN updated_at TEXT DEFAULT CURRENT_TIMESTAMP");
      await db.execute("ALTER TABLE owners ADD COLUMN updated_at TEXT DEFAULT CURRENT_TIMESTAMP");
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE properties (
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, property_type TEXT, owner_name TEXT, 
        land_type TEXT, house_type TEXT, dim_front REAL, dim_back REAL, dim_left REAL, dim_right REAL,
        status TEXT, asking_price REAL, bottom_price REAL, location TEXT, map_link TEXT, 
        image_path TEXT, remark TEXT, is_synced INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE buyers (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, phone TEXT, budget REAL, 
        requirement TEXT, location TEXT, remark TEXT, is_synced INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE owners (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, phone TEXT, remark TEXT, 
        is_synced INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  // --- Core CRUD ---
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await instance.database;
    data['is_synced'] = 0;
    data['updated_at'] = DateTime.now().toIso8601String();
    return await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> readAll(String table, {int isDeleted = 0}) async {
    final db = await instance.database;
    return await db.query(table, where: 'is_deleted = ?', whereArgs: [isDeleted], orderBy: 'updated_at DESC');
  }

  Future<int> update(String table, Map<String, dynamic> data, int id) async {
    final db = await instance.database;
    data['is_synced'] = 0;
    data['updated_at'] = DateTime.now().toIso8601String();
    return await db.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> softDelete(String table, int id) async {
    return await update(table, {'is_deleted': 1}, id);
  }

  Future<int> restore(String table, int id) async {
    return await update(table, {'is_deleted': 0}, id);
  }

  // --- HARD DELETE (Recycle Bin to Cloud) ---
  Future<void> hardDelete(String table, int id, Map<String, dynamic> data) async {
    final db = await instance.database;
    final headers = {'apikey': supabaseKey, 'Authorization': 'Bearer $supabaseKey'};
    
    // 1. Delete from Cloud first
    String queryParam = table == 'properties' ? 'title=eq.${data['title']}' : 'name=eq.${data['name']}';
    await http.delete(Uri.parse('$supabaseUrl/rest/v1/$table?$queryParam'), headers: headers);
    
    // 2. Delete Locally
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  // --- DYNAMIC DROPDOWN EXTRACTOR ---
  Future<List<String>> getUniqueValues(String table, String column) async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT DISTINCT $column FROM $table WHERE is_deleted=0 AND $column IS NOT NULL AND $column != ""');
    return result.map((e) => e[column].toString()).toList();
  }

  // --- JSON BACKUP / RESTORE ---
  Future<String> exportJson() async {
    try {
      final db = await instance.database;
      Map<String, dynamic> backup = {};
      for (String table in ['properties', 'buyers', 'owners']) {
        backup[table] = await db.query(table);
      }
      Directory? dir = await getExternalStorageDirectory();
      File file = File('${dir!.path}/tkr_backup.json');
      await file.writeAsString(jsonEncode(backup));
      return 'Backup Saved to: ${file.path}';
    } catch (e) { return 'Backup Error: $e'; }
  }

  Future<String> importJson(String jsonString) async {
    try {
      final db = await instance.database;
      Map<String, dynamic> data = jsonDecode(jsonString);
      for (String table in ['properties', 'buyers', 'owners']) {
        if (data.containsKey(table)) {
          await db.delete(table); // Clear existing
          for (var row in data[table]) {
            await db.insert(table, Map<String, dynamic>.from(row));
          }
        }
      }
      return 'Restore Successful!';
    } catch (e) { return 'Restore Error: $e'; }
  }

  // --- SUPABASE SYNC LOGIC ---
  Future<String> syncData() async {
    try {
      final db = await instance.database;
      final headers = {'apikey': supabaseKey, 'Authorization': 'Bearer $supabaseKey', 'Content-Type': 'application/json', 'Prefer': 'return=representation'};
      List<String> tables = ['properties', 'buyers', 'owners'];
      int pushCount = 0; int pullCount = 0;

      for (String table in tables) {
        // PUSH
        final unsynced = await db.query(table, where: 'is_synced = ?', whereArgs: [0]);
        for (var row in unsynced) {
          Map<String, dynamic> data = Map.from(row);
          int localId = data.remove('id');
          int isDeleted = data['is_deleted'] ?? 0;
          data.remove('is_synced');

          if (isDeleted == 1) {
            String queryParam = table == 'properties' ? 'title=eq.${data['title']}' : 'name=eq.${data['name']}';
            await http.delete(Uri.parse('$supabaseUrl/rest/v1/$table?$queryParam'), headers: headers);
          } else {
            await http.post(Uri.parse('$supabaseUrl/rest/v1/$table'), headers: headers, body: jsonEncode(data));
          }
          await db.update(table, {'is_synced': 1}, where: 'id = ?', whereArgs: [localId]);
          pushCount++;
        }

        // PULL
        final response = await http.get(Uri.parse('$supabaseUrl/rest/v1/$table'), headers: headers);
        if (response.statusCode == 200) {
          List<dynamic> cloudData = jsonDecode(response.body);
          for (var cRow in cloudData) {
            Map<String, dynamic> cMap = Map<String, dynamic>.from(cRow);
            List<String> validCols = table == 'properties' ? validPropCols : (table == 'buyers' ? validBuyerCols : validOwnerCols);
            cMap.removeWhere((key, value) => !validCols.contains(key));
            cMap['is_synced'] = 1;
            
            String checkField = table == 'properties' ? 'title' : 'name';
            var existing = await db.query(table, where: '$checkField = ?', whereArgs: [cMap[checkField]]);
            
            if (existing.isEmpty) {
              await db.insert(table, cMap);
              pullCount++;
            } else {
               // Update local if cloud has newer data based on ID
               await db.update(table, cMap, where: '$checkField = ?', whereArgs: [cMap[checkField]]);
            }
          }
        }
      }
      return "Sync Completed: $pushCount Pushed, $pullCount Pulled.";
    } catch (e) { return "Sync Error: $e"; }
  }
}
