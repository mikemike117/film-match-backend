import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'dart:convert';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:dotenv/dotenv.dart';
import 'dart:async';

// Правильный путь к вашему mongodb.dart.
import 'package:film_match_backend/database/mongodb.dart';

void main() {
  runZonedGuarded(() async {
    // Загружаем переменные окружения из файла .env.
    final env = DotEnv(includePlatformEnvironment: true)..load();

    // Подключаемся к базе данных MongoDB, используя ваш класс MongoDB
    await MongoDB.connect(env); // Передаем env в connect

    final app = Router();

    // Маршрут для проверки работоспособности сервера
    app.get('/health', (Request request) => Response.ok('Server is running!'));

    // Маршруты для работы с фильмами. (Оставьте как есть, если они нужны)
    app.get('/movies', (Request request) async {
      try {
        final movies = await MongoDB.wishlists.find().toList(); // Пример
        return Response.ok(
          json.encode(movies),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        print('Error getting movies: $e');
        return Response.internalServerError(body: e.toString());
      }
    });

    app.post('/movies', (Request request) async {
      try {
        final body = await request.readAsString();
        final result = await MongoDB.wishlists.insertOne( // Пример
          {'data': body, 'createdAt': DateTime.now()},
        );
        return Response.ok(
          result.toString(),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        print('Error posting movie: $e');
        return Response.internalServerError(body: e.toString());
      }
    });

    app.delete('/movies/<id>', (Request request, String id) async {
      try {
        final result = await MongoDB.wishlists.deleteOne( // Пример
          where.id(ObjectId.fromHexString(id)),
        );
        return Response.ok(
          result.toString(),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        print('Error deleting movie: $e');
        return Response.internalServerError(body: e.toString());
      }
    });

    // Маршруты для работы с избранным (wishlist)
    app.get('/wishlist/<userId>', (Request request, String userId) async {
      try {
        final wishlistDoc = await MongoDB.wishlists.findOne({'userId': userId});
        if (wishlistDoc == null) {
          // Если списка избранного для пользователя нет, возвращаем пустой список
          return Response.ok(jsonEncode({'userId': userId, 'movieIds': [], 'skippedMovieIds': []}), headers: {'Content-Type': 'application/json'});
        }
        return Response.ok(jsonEncode(wishlistDoc), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        print('Error getting wishlist: $e');
        return Response.internalServerError(body: e.toString());
      }
    });

    app.post('/wishlist/<userId>', (Request request, String userId) async {
      try {
        final payload = await request.readAsString();
        final data = jsonDecode(payload);
        final movieId = data['id'] as String?;
        final title = data['title'] as String?;
        final posterPath = data['posterPath'] as String?;
        final year = data['year'] as String?;

        if (movieId == null || title == null) {
          return Response(400, body: jsonEncode({'message': 'movieId and title required'}), headers: {'Content-Type': 'application/json'});
        }

        final item = {
          'id': movieId,
          'title': title,
          'posterPath': posterPath,
          'year': year,
          'addedAt': DateTime.now().toIso8601String(),
        };

        final result = await MongoDB.wishlists.updateOne(
          where.eq('userId', userId),
          modify.addToSet('movieIds', item),
          upsert: true,
        );

        return Response.ok(jsonEncode({'message': 'Movie added to wishlist'}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        print('Error adding movie to wishlist: $e');
        return Response.internalServerError(body: e.toString());
      }
    });

    app.delete('/wishlist/<userId>/<movieId>', (Request request, String userId, String movieId) async {
      try {
        final result = await MongoDB.wishlists.updateOne(
          where.eq('userId', userId),
          modify.pull('movieIds', {'id': movieId}),
        );

        return Response.ok(jsonEncode({'message': 'Movie removed from wishlist'}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        print('Error removing movie from wishlist: $e');
        return Response.internalServerError(body: e.toString());
      }
    });

    // НОВЫЕ Маршруты для пропущенных фильмов (skipped) - УБЕДИТЕСЬ, ЧТО ЭТОТ БЛОК ПРИСУТСТВУЕТ!
    app.post('/skipped/<userId>', (Request request, String userId) async {
      try {
        final payload = await request.readAsString();
        final data = jsonDecode(payload);
        final movieId = data['id'] as String?;
        final title = data['title'] as String?;
        final posterPath = data['posterPath'] as String?;
        final year = data['year'] as String?;

        if (movieId == null || title == null) {
          return Response(400, body: jsonEncode({'message': 'movieId and title required'}), headers: {'Content-Type': 'application/json'});
        }

        final item = {
          'id': movieId,
          'title': title,
          'posterPath': posterPath,
          'year': year,
          'skippedAt': DateTime.now().toIso8601String(),
        };

        final result = await MongoDB.wishlists.updateOne(
          where.eq('userId', userId),
          modify.addToSet('skippedMovieIds', item), // Добавляем в новый массив skippedMovieIds
          upsert: true,
        );

        return Response.ok(jsonEncode({'message': 'Movie skipped and saved'}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        print('Error skipping movie: $e'); // Добавляем логирование
        return Response.internalServerError(body: e.toString());
      }
    });

    app.delete('/skipped/<userId>/<movieId>', (Request request, String userId, String movieId) async {
      try {
        final result = await MongoDB.wishlists.updateOne(
          where.eq('userId', userId),
          modify.pull('skippedMovieIds', {'id': movieId}), // Удаляем из skippedMovieIds
        );

        return Response.ok(jsonEncode({'message': 'Skipped movie undone'}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        print('Error undoing skipped movie: $e'); // Добавляем логирование
        return Response.internalServerError(body: e.toString());
      }
    });

    final handler = Pipeline()
        .addMiddleware(logRequests())  // Middleware для логирования запросов
        .addMiddleware((innerHandler) {
          return (request) async {
            print('Incoming request path: ${request.url.path}'); // Добавляем новый лог
            return innerHandler(request);
          };
        })
        .addMiddleware(corsHeaders()) // Middleware для обработки CORS
        .addHandler(app);            // Основной обработчик маршрутов

    final port = int.parse(env['PORT'] ?? '8080');
    final server = await shelf_io.serve(handler, 'localhost', port);
    
    print('Server running on port ${server.port}');
  }, (error, stack) {
    print('Unhandled error in main: $error');
    print('Stack trace: $stack');
  });
}