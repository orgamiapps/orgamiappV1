import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

/// Service for on-device NLP using ONNX Runtime with DistilBERT
class OnnxNlpService {
  static const MethodChannel _channel = MethodChannel('attendus/onnx_nlp');
  static OnnxNlpService? _instance;
  static OnnxNlpService get instance => _instance ??= OnnxNlpService._();
  
  OnnxNlpService._();
  
  bool _isInitialized = false;
  Database? _database;
  Map<String, int>? _vocabulary;
  Map<String, dynamic>? _metadata;
  
  /// Initialize the ONNX model and SQLite database
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      Logger.debug('Initializing ONNX NLP Service...');
      
      // Load vocabulary and metadata
      await _loadVocabulary();
      await _loadMetadata();
      
      // Initialize native ONNX Runtime
      final result = await _channel.invokeMethod('initializeModel', {
        'modelPath': 'assets/models/distilbert_quantized.onnx',
      });
      
      if (result != true) {
        throw Exception('Failed to initialize ONNX model');
      }
      
      // Initialize SQLite database
      await _initializeDatabase();
      
      _isInitialized = true;
      Logger.success('✨ ONNX NLP Service initialized with AI model');
      return true;
    } catch (e) {
      Logger.error('Failed to initialize ONNX NLP Service', e);
      return false;
    }
  }
  
  /// Load tokenizer vocabulary
  Future<void> _loadVocabulary() async {
    try {
      final String vocabJson = await rootBundle.loadString('assets/models/vocab.json');
      _vocabulary = Map<String, int>.from(json.decode(vocabJson));
      Logger.debug('Loaded vocabulary with ${_vocabulary!.length} tokens');
    } catch (e) {
      Logger.error('Failed to load vocabulary', e);
      // Fall back to basic vocabulary
      _vocabulary = _getBasicVocabulary();
    }
  }
  
  /// Load model metadata
  Future<void> _loadMetadata() async {
    try {
      final String metadataJson = await rootBundle.loadString('assets/models/intent_metadata.json');
      _metadata = json.decode(metadataJson);
      Logger.debug('Loaded model metadata');
    } catch (e) {
      Logger.error('Failed to load metadata', e);
      _metadata = _getDefaultMetadata();
    }
  }
  
  /// Initialize SQLite database for event caching
  Future<void> _initializeDatabase() async {
    final databasePath = await getDatabasesPath();
    final dbPath = path.join(databasePath, 'events_cache.db');
    
    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        // Create events table with full-text search
        await db.execute('''
          CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            category TEXT,
            location_lat REAL,
            location_lng REAL,
            location_name TEXT,
            start_date INTEGER,
            end_date INTEGER,
            organizer TEXT,
            embeddings BLOB,
            created_at INTEGER DEFAULT (strftime('%s', 'now'))
          )
        ''');
        
        // Create FTS5 virtual table for text search
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
            title, description, category, location_name,
            content=events, content_rowid=rowid
          )
        ''');
        
        // Create indexes for performance
        await db.execute('CREATE INDEX IF NOT EXISTS idx_category ON events(category)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_start_date ON events(start_date)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_location ON events(location_lat, location_lng)');
        
        Logger.debug('SQLite database initialized with FTS5');
      },
    );
  }
  
  /// Parse natural language query using DistilBERT
  Future<Map<String, dynamic>> parseQuery(String query) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      // Tokenize the query
      final tokens = _tokenize(query);
      
      // Run inference through platform channel
      final Map<dynamic, dynamic> result = await _channel.invokeMethod('runInference', {
        'inputIds': tokens['input_ids'],
        'attentionMask': tokens['attention_mask'],
      });
      
      // Process model output to extract intent
      final intent = _processModelOutput(result, query);
      
      Logger.debug('🤖 AI parsed query: ${intent['categories']} | Near: ${intent['nearMe']}');
      
      return intent;
    } catch (e) {
      Logger.error('Error parsing query with ONNX', e);
      // Fall back to rule-based parsing
      return _fallbackParse(query);
    }
  }
  
  /// Tokenize input text for DistilBERT
  Map<String, List<int>> _tokenize(String text) {
    final vocab = _vocabulary ?? _getBasicVocabulary();
    final maxLength = _metadata?['max_sequence_length'] ?? 128;
    
    // Convert text to lowercase and split
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    
    // Convert words to token IDs
    List<int> inputIds = [101]; // [CLS] token
    for (final word in words) {
      if (inputIds.length >= maxLength - 1) break;
      inputIds.add(vocab[word] ?? vocab['[UNK]'] ?? 100);
    }
    inputIds.add(102); // [SEP] token
    
    // Pad to max length
    while (inputIds.length < maxLength) {
      inputIds.add(0); // [PAD] token
    }
    
    // Create attention mask
    final attentionMask = inputIds.map((id) => id != 0 ? 1 : 0).toList();
    
    return {
      'input_ids': inputIds,
      'attention_mask': attentionMask,
    };
  }
  
  /// Process model output to extract intent
  Map<String, dynamic> _processModelOutput(Map<dynamic, dynamic> output, String query) {
    final embeddings = output['embeddings'] as List<dynamic>?;
    final logits = output['logits'] as List<dynamic>?;
    
    // Extract categories from model predictions
    final categories = _extractCategories(logits);
    
    // Detect location intent
    final locationIntent = _detectLocationIntent(query, embeddings);
    
    // Detect time intent
    final timeIntent = _detectTimeIntent(query);
    
    // Calculate confidence score
    final confidence = _calculateConfidence(logits);
    
    return {
      'categories': categories,
      'keywords': _extractKeywords(query),
      'nearMe': locationIntent['nearMe'] ?? false,
      'radiusKm': locationIntent['radiusKm'] ?? 0,
      'dateRange': timeIntent,
      'confidence': confidence,
      'embeddings': embeddings,
    };
  }
  
  /// Extract event categories from model predictions
  List<String> _extractCategories(List<dynamic>? logits) {
    if (logits == null || logits.isEmpty) return [];
    
    final categories = _metadata?['categories'] as List<dynamic>? ?? [];
    final threshold = 0.3; // Confidence threshold
    
    List<String> predicted = [];
    for (int i = 0; i < logits.length && i < categories.length; i++) {
      if ((logits[i] as double) > threshold) {
        predicted.add(categories[i] as String);
      }
    }
    
    return predicted;
  }
  
  /// Detect location intent from query
  Map<String, dynamic> _detectLocationIntent(String query, List<dynamic>? embeddings) {
    final nearMePatterns = RegExp(
      r'near\s+me|around\s+me|close\s+by|nearby|local|in\s+my\s+area',
      caseSensitive: false,
    );
    
    final nearMe = nearMePatterns.hasMatch(query);
    
    // Extract radius if specified
    final radiusMatch = RegExp(r'(\d+)\s*(km|kilometers?|miles?|mi)', caseSensitive: false)
        .firstMatch(query);
    
    double radiusKm = nearMe ? 10.0 : 0.0; // Default 10km for "near me"
    if (radiusMatch != null) {
      final value = double.tryParse(radiusMatch.group(1)!) ?? 10;
      final unit = radiusMatch.group(2)!.toLowerCase();
      radiusKm = unit.startsWith('mi') ? value * 1.60934 : value;
    }
    
    return {
      'nearMe': nearMe,
      'radiusKm': radiusKm,
    };
  }
  
  /// Detect time intent from query
  Map<String, String> _detectTimeIntent(String query) {
    final now = DateTime.now();
    final queryLower = query.toLowerCase();
    
    if (queryLower.contains('today')) {
      return {
        'start': now.toIso8601String(),
        'end': now.add(const Duration(days: 1)).toIso8601String(),
      };
    } else if (queryLower.contains('tomorrow')) {
      final tomorrow = now.add(const Duration(days: 1));
      return {
        'start': tomorrow.toIso8601String(),
        'end': tomorrow.add(const Duration(days: 1)).toIso8601String(),
      };
    } else if (queryLower.contains('this weekend') || queryLower.contains('this week end')) {
      final daysToSaturday = 6 - now.weekday;
      final saturday = now.add(Duration(days: daysToSaturday));
      return {
        'start': saturday.toIso8601String(),
        'end': saturday.add(const Duration(days: 2)).toIso8601String(),
      };
    } else if (queryLower.contains('this week')) {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      return {
        'start': startOfWeek.toIso8601String(),
        'end': startOfWeek.add(const Duration(days: 7)).toIso8601String(),
      };
    } else if (queryLower.contains('next week')) {
      final nextWeek = now.add(const Duration(days: 7));
      final startOfNextWeek = nextWeek.subtract(Duration(days: nextWeek.weekday - 1));
      return {
        'start': startOfNextWeek.toIso8601String(),
        'end': startOfNextWeek.add(const Duration(days: 7)).toIso8601String(),
      };
    }
    
    return {};
  }
  
  /// Calculate confidence score from model output
  double _calculateConfidence(List<dynamic>? logits) {
    if (logits == null || logits.isEmpty) return 0.0;
    
    // Use softmax to get probability distribution
    double maxLogit = logits.reduce((a, b) => a > b ? a : b);
    double sumExp = 0.0;
    for (final logit in logits) {
      sumExp += (logit - maxLogit).exp();
    }
    
    // Return max probability as confidence
    return (1.0 / sumExp) * 100;
  }
  
  /// Extract keywords from query
  List<String> _extractKeywords(String query) {
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to',
      'for', 'of', 'with', 'by', 'find', 'search', 'show', 'get', 'event', 'events'
    };
    
    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length > 2 && !stopWords.contains(word))
        .take(5)
        .toList();
  }
  
  /// Query SQLite database for matching events
  Future<List<Map<String, dynamic>>> queryEvents({
    required Map<String, dynamic> intent,
    double? userLat,
    double? userLng,
    int limit = 50,
  }) async {
    if (_database == null) {
      await _initializeDatabase();
    }
    
    String query = 'SELECT * FROM events WHERE 1=1';
    List<dynamic> args = [];
    
    // Add category filter
    final categories = intent['categories'] as List<String>? ?? [];
    if (categories.isNotEmpty) {
      query += ' AND category IN (${categories.map((_) => '?').join(',')})';
      args.addAll(categories);
    }
    
    // Add date range filter
    final dateRange = intent['dateRange'] as Map<String, String>? ?? {};
    if (dateRange.containsKey('start')) {
      query += ' AND start_date >= ?';
      args.add(DateTime.parse(dateRange['start']!).millisecondsSinceEpoch);
    }
    if (dateRange.containsKey('end')) {
      query += ' AND end_date <= ?';
      args.add(DateTime.parse(dateRange['end']!).millisecondsSinceEpoch);
    }
    
    // Add location filter if near me
    if (intent['nearMe'] == true && userLat != null && userLng != null) {
      final radiusKm = intent['radiusKm'] ?? 10.0;
      // Use Haversine formula approximation
      final latDelta = radiusKm / 111.0; // ~111km per degree latitude
      final lngDelta = radiusKm / (111.0 * math.cos(userLat.abs() * math.pi / 180));
      
      query += ' AND location_lat BETWEEN ? AND ?';
      query += ' AND location_lng BETWEEN ? AND ?';
      args.addAll([
        userLat - latDelta,
        userLat + latDelta,
        userLng - lngDelta,
        userLng + lngDelta,
      ]);
    }
    
    // Add text search for keywords
    final keywords = intent['keywords'] as List<String>? ?? [];
    if (keywords.isNotEmpty) {
      final ftsQuery = keywords.join(' OR ');
      query = '''
        SELECT e.* FROM events e
        JOIN events_fts ON e.rowid = events_fts.rowid
        WHERE events_fts MATCH ?
        AND ($query)
      ''';
      args.insert(0, ftsQuery);
    }
    
    query += ' ORDER BY start_date ASC LIMIT ?';
    args.add(limit);
    
    try {
      final results = await _database!.rawQuery(query, args);
      Logger.debug('Found ${results.length} events matching AI query');
      return results;
    } catch (e) {
      Logger.error('Database query error', e);
      return [];
    }
  }
  
  /// Cache events in SQLite database
  Future<void> cacheEvents(List<Map<String, dynamic>> events) async {
    if (_database == null) return;
    
    final batch = _database!.batch();
    
    for (final event in events) {
      batch.insert(
        'events',
        {
          'id': event['id'],
          'title': event['title'],
          'description': event['description'],
          'category': event['category'],
          'location_lat': event['location']?['lat'],
          'location_lng': event['location']?['lng'],
          'location_name': event['location']?['name'],
          'start_date': event['startDate'] is String 
              ? DateTime.parse(event['startDate']).millisecondsSinceEpoch
              : event['startDate'],
          'end_date': event['endDate'] is String
              ? DateTime.parse(event['endDate']).millisecondsSinceEpoch
              : event['endDate'],
          'organizer': event['organizer'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit();
    Logger.debug('Cached ${events.length} events in SQLite');
  }
  
  /// Fallback rule-based parsing
  Map<String, dynamic> _fallbackParse(String query) {
    // Use simplified rule-based parsing as fallback
    return {
      'categories': [],
      'keywords': _extractKeywords(query),
      'nearMe': query.toLowerCase().contains('near me'),
      'radiusKm': 10.0,
      'dateRange': _detectTimeIntent(query),
      'confidence': 30.0,
    };
  }
  
  /// Get basic vocabulary for fallback
  Map<String, int> _getBasicVocabulary() {
    return {
      '[PAD]': 0,
      '[UNK]': 100,
      '[CLS]': 101,
      '[SEP]': 102,
      'find': 2003,
      'book': 2338,
      'club': 2252,
      'event': 2724,
      'near': 2379,
      'me': 2033,
      'concert': 4025,
      'music': 2189,
      'sports': 2998,
      'food': 2833,
      'workshop': 4930,
      'conference': 3034,
      'party': 2283,
      'networking': 9428,
      'art': 2396,
      'tech': 6627,
      'weekend': 5353,
      'today': 2651,
      'tomorrow': 4826,
      'this': 2023,
      'next': 2279,
      'week': 2733,
    };
  }
  
  /// Get default metadata
  Map<String, dynamic> _getDefaultMetadata() {
    return {
      'categories': [
        'Social & Networking', 'Entertainment', 'Sports & Fitness',
        'Education & Learning', 'Arts & Culture', 'Food & Dining', 
        'Technology', 'Community & Charity'
      ],
      'max_sequence_length': 128,
    };
  }
  
  /// Dispose resources
  void dispose() {
    _database?.close();
    _channel.invokeMethod('dispose');
    _isInitialized = false;
    Logger.debug('ONNX NLP Service disposed');
  }
}
