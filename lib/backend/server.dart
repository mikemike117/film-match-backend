import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'database_service.dart';
import 'dart:convert';
import 'package:firebase_admin/firebase_admin.dart';
import 'package:firebase_admin/auth.dart';

class BackendServer {
  final DatabaseService _dbService = DatabaseService();
  late final Router _router;
  // Removed: late final DbCollection _openedLogsCollection;

  BackendServer() {
    // Initialize Firebase Admin SDK
    FirebaseAdmin.instance.initializeApp(AppOptions(
      credential: ApplicationDefaultCredential.fromPath('D:\\\\project_dart\\\\dart_movies\\\\film_match_backend\\\\service_account_key.json'), // Ваш путь к ключу сервисного аккаунта
    ));

    _router = Router()
      ..get('/health', _healthCheck)
      // Protected routes
      ..get('/wishlist/<userId>', _getWishlist)
      ..post('/wishlist/<userId>', _addToWishlist)
      ..delete('/wishlist/<userId>/<movieId>', _removeFromWishlist)
      ..post('/skipped/<userId>', _skipMovie)
      ..delete('/skipped/<userId>/<movieId>', _undoSkipMovie);
      // Removed: Opened logs routes
  }

  // Middleware for Firebase ID Token verification
  Future<Response> _authMiddleware(Request request) async {
    // Exclude /health from authentication
    if (request.url.pathSegments.isNotEmpty && request.url.pathSegments.first == 'health') {
      return await _router(request);
    }

    final authHeader = request.headers['authorization'];
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return Response.forbidden('No authorization token provided.');
    }

    final idToken = authHeader.substring(7); // Remove 'Bearer ' prefix

    try {
      final decodedToken = await FirebaseAuth.instance.verifyIdToken(idToken);
      final userId = decodedToken.uid;
      // Attach the verified userId to the request context
      final newRequest = request.change(context: {'userId': userId});
      return await _router(newRequest);
    } on FirebaseAuthException catch (e) {
      return Response.forbidden('Invalid or expired token: ${e.message}');
    } catch (e) {
      return Response.internalServerError(body: 'Authentication error: $e');
    }
  }

  Future<void> start() async {
    // Connect to the database
    await _dbService.connect();
    // Removed: _openedLogsCollection initialization and index creation

    // Create the handler pipeline with authentication middleware
    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_authMiddleware); // Apply authentication middleware first

    // Start the server
    final server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      8080,
    );

    print('Server running on port ${server.port}');
  }

  // Route handlers (now expecting userId from request context)
  Response _healthCheck(Request request) {
    return Response.ok('Server is running!');
  }

  Future<Response> _getWishlist(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) {
      return Response.badRequest(body: 'User ID not found in context.');
    }

    try {
      final wishlistDoc = await _dbService.getCollection('wishlists').findOne(
        where.eq('userId', userId),
      );

      if (wishlistDoc == null) {
        return Response.ok(
          json.encode({'userId': userId, 'movieIds': [], 'skippedMovieIds': []}),
          headers: {'content-type': 'application/json'},
        );
      }

      final List<dynamic> movieIds = wishlistDoc['movieIds'] ?? [];
      final List<dynamic> skippedMovieIds = wishlistDoc['skippedMovieIds'] ?? [];

      print('Backend: Sending wishlist data for user $userId: movieIds = $movieIds, skippedMovieIds = $skippedMovieIds');
      return Response.ok(
        json.encode({'userId': userId, 'movieIds': movieIds, 'skippedMovieIds': skippedMovieIds}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> _addToWishlist(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) {
      return Response.badRequest(body: 'User ID not found in context.');
    }

    try {
      final body = await request.readAsString();
      final movieData = json.decode(body) as Map<String, dynamic>;

      final result = await _dbService.getCollection('wishlists').updateOne(
        where.eq('userId', userId),
        modify.addToSet('movieIds', movieData), // Store full movie object
        upsert: true,
      );

      return Response.ok(
        result.toString(),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('Error adding movie to wishlist: $e');
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> _removeFromWishlist(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) {
      return Response.badRequest(body: 'User ID not found in context.');
    }

    final movieId = request.params['movieId'];
    if (movieId == null) {
      return Response.badRequest(body: 'Movie ID is required.');
    }

    try {
      final result = await _dbService.getCollection('wishlists').updateOne(
        where.eq('userId', userId),
        modify.pull('movieIds', {'id': movieId}), // Pull by movie ID within the object
      );

      return Response.ok(
        result.toString(),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('Error removing movie from wishlist: $e');
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> _skipMovie(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) {
      return Response.badRequest(body: 'User ID not found in context.');
    }

    try {
      final body = await request.readAsString();
      final movieData = json.decode(body) as Map<String, dynamic>;

      final result = await _dbService.getCollection('wishlists').updateOne(
        where.eq('userId', userId),
        modify.addToSet('skippedMovieIds', movieData), // Store full movie object
        upsert: true,
      );

      return Response.ok(
        json.encode({'message': 'Movie skipped and saved'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('Error skipping movie: $e');
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> _undoSkipMovie(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) {
      return Response.badRequest(body: 'User ID not found in context.');
    }

    final movieId = request.params['movieId'];
    if (movieId == null) {
      return Response.badRequest(body: 'Movie ID is required.');
    }

    try {
      final result = await _dbService.getCollection('wishlists').updateOne(
        where.eq('userId', userId),
        modify.pull('skippedMovieIds', {'id': movieId}), // Pull by movie ID within the object
      );

      return Response.ok(
        json.encode({'message': 'Skipped movie undone'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('Error undoing skipped movie: $e');
      return Response.internalServerError(body: e.toString());
    }
  }
} 