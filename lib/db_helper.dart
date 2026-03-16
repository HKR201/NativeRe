import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;
  DBHelper._init();

  // သင့်ရဲ့ Supabase Keys များ
  final String supabaseUrl = 'https://btwbbjijrbyxbjlhtpqf.supabase.co';
  final String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0d2JiamlqcmJ5eGJqbGh0cHFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzODIwNjEsImV4cCI6MjA4ODk1ODA2MX0.jkVvPfaEvhhWDg7zTdjKnll5gDqeyNBy3Eli4cxmbhQ';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('realestate.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE properties (
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, property_type TEXT, owner_name TEXT, 
        land_type TEXT, house_type TEXT, dim_front REAL, dim_back REAL, dim_left REAL, dim_right REAL,
        status TEXT, asking_price REAL, bottom_price REAL, location TEXT, map_link TEXT, 
        image_path TEXT, remark TEXT, is_synced INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE buyers (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, phone TEXT, budget REAL, 
        requirement TEXT, location TEXT, remark TEXT, is_synced INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE owners (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, phone TEXT, remark TEXT, 
        is_synced INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0
      )
    ''');
  }

  // --- CRUD Operations ---
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await instance.database;
    data['is_synced'] = 0; // Local မှာထည့်တိုင်း 0 အဖြစ်မှတ်မယ်
    return await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> readAll(String table) async {
    final db = await instance.database;
    return await db.query(table, where: 'is_deleted = ?', whereArgs: [0], orderBy: 'id DESC');
  }

  Future<int> update(String table, Map<String, dynamic> data, int id) async {
    final db = await instance.database;
    data['is_synced'] = 0;
    return await db.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String table, int id) async {
    final db = await instance.database;
    return await db.update(table, {'is_deleted': 1, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }

  // --- SUPABASE SYNC LOGIC (Optimization Included) ---
  Future<String> syncData() async {
    try {
      final db = await instance.database;
      final headers = {
        'apikey': supabaseKey,
        'Authorization': 'Bearer $supabaseKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation'
      };

      List<String> tables = ['properties', 'buyers', 'owners'];
      int pushCount = 0;
      int pullCount = 0;

      for (String table in tables) {
        // 1. PUSH (Local မှ Cloud သို့)
        final unsynced = await db.query(table, where: 'is_synced = ?', whereArgs: [0]);
        for (var row in unsynced) {
          Map<String, dynamic> data = Map.from(row);
          int localId = data.remove('id');
          int isDeleted = data.remove('is_deleted');
          data.remove('is_synced');

          if (isDeleted == 1) {
            // Delete in cloud based on specific fields (e.g., title or name)
            String queryParam = table == 'properties' ? 'title=eq.${data['title']}' : 'name=eq.${data['name']}';
            await http.delete(Uri.parse('$supabaseUrl/rest/v1/$table?$queryParam'), headers: headers);
          } else {
            // Insert/Update in cloud
            await http.post(Uri.parse('$supabaseUrl/rest/v1/$table'), headers: headers, body: jsonEncode(data));
          }
          await db.update(table, {'is_synced': 1}, where: 'id = ?', whereArgs: [localId]);
          pushCount++;
        }

        // 2. PULL (Cloud မှ Local သို့)
        final response = await http.get(Uri.parse('$supabaseUrl/rest/v1/$table'), headers: headers);
        if (response.statusCode == 200) {
          List<dynamic> cloudData = jsonDecode(response.body);
          for (var cRow in cloudData) {
            Map<String, dynamic> cMap = Map<String, dynamic>.from(cRow);
            cMap['is_synced'] = 1; // Cloud ကလာတာမို့ 1 ထားမယ်
            cMap.remove('id'); // Cloud ID ကိုဖယ်မယ်
            
            // Check if exists locally
            String checkField = table == 'properties' ? 'title' : 'name';
            var existing = await db.query(table, where: '$checkField = ?', whereArgs: [cMap[checkField]]);
            
            if (existing.isEmpty) {
              await db.insert(table, cMap);
              pullCount++;
            }
          }
        }
      }
      return "Sync Successful: Pushed $pushCount, Pulled $pullCount items.";
    } catch (e) {
      return "Sync Error: $e";
    }
  }
}
