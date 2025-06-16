import 'package:mongo_dart/mongo_dart.dart';
import 'package:dotenv/dotenv.dart';

class MongoDB {
  static Db? _db;
  static DbCollection? _users;
  static DbCollection? _wishlists;

  static Future<void> connect(DotEnv env) async {
    if (_db == null) {
      _db = await Db.create(env['MONGODB_URI'] ?? 'mongodb://localhost:27017/film_match');
      await _db!.open();
      
      _users = _db!.collection('users');
      _wishlists = _db!.collection('wishlists');
      
      print('Connected to MongoDB');
    }
  }

  static DbCollection get users {
    if (_users == null) throw Exception('Database not connected');
    return _users!;
  }

  static DbCollection get wishlists {
    if (_wishlists == null) throw Exception('Database not connected');
    return _wishlists!;
  }

  static Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      _users = null;
      _wishlists = null;
    }
  }
} 