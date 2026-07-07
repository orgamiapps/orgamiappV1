import 'package:attendus/Utils/logger.dart';

/// On-device Natural Language Processing service using rule-based parsing
/// Provides query parsing for event search without external API calls
class OnDeviceNLPService {
  static OnDeviceNLPService? _instance;
  static OnDeviceNLPService get instance => _instance ??= OnDeviceNLPService._();
  
  OnDeviceNLPService._();

  bool _isInitialized = false;
  
  // Vocabulary removed as it's not used in rule-based parsing

  /// Category mappings for classification - aligned with app categories
  static const Map<String, List<String>> _categoryMappings = {
    'Social & Networking': ['networking', 'business', 'professional', 'career', 'meetup', 'social', 'connect', 'network', 'professional development', 'colleagues'],
    'Entertainment': ['music', 'concert', 'band', 'singer', 'song', 'gaming', 'game', 'esports', 'video', 'show', 'performance', 'entertainment', 'fun', 'party', 'festival', 'comedy', 'theater'],
    'Sports & Fitness': ['sports', 'fitness', 'gym', 'exercise', 'running', 'workout', 'athletic', 'training', 'health', 'wellness', 'yoga', 'dance', 'outdoor', 'recreation'],
    'Education & Learning': ['education', 'learning', 'workshop', 'training', 'course', 'seminar', 'conference', 'lecture', 'book', 'club', 'reading', 'literature', 'study', 'academic', 'skill'],
    'Arts & Culture': ['art', 'painting', 'drawing', 'creative', 'artist', 'culture', 'museum', 'gallery', 'exhibition', 'crafts', 'design', 'photography', 'sculpture', 'cultural'],
    'Food & Dining': ['food', 'cooking', 'restaurant', 'dining', 'culinary', 'chef', 'recipe', 'tasting', 'wine', 'drink', 'meal', 'cuisine', 'foodie', 'kitchen'],
    'Technology': ['tech', 'technology', 'programming', 'coding', 'developer', 'software', 'hardware', 'digital', 'innovation', 'startup', 'ai', 'data', 'computer', 'mobile'],
    'Community & Charity': ['community', 'charity', 'volunteer', 'nonprofit', 'service', 'family', 'kids', 'children', 'parent', 'local', 'neighborhood', 'civic', 'fundraising', 'support', 'help'],
  };

  /// Initialize the NLP service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Initialize rule-based NLP service
      _isInitialized = true;
      Logger.success('OnDeviceNLPService initialized successfully');
      return true;
    } catch (e) {
      Logger.error('Failed to initialize OnDeviceNLPService', e);
      return false;
    }
  }

  /// Parse a natural language query into structured search intent
  Future<Map<String, dynamic>> parseQuery(String query) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // For now, use enhanced rule-based parsing
      // In production, this would use the ONNX model
      return _parseQueryRuleBased(query);
    } catch (e) {
      Logger.error('Error parsing query with NLP service', e);
      return _fallbackParse(query);
    }
  }

  /// Enhanced rule-based query parsing
  Map<String, dynamic> _parseQueryRuleBased(String query) {
    final queryLower = query.toLowerCase().trim();
    final tokens = _tokenize(queryLower);
    
    // Extract categories using keyword matching and context
    final categories = <String>[];
    final keywords = <String>[];
    
    // Process tokens for category detection
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      
      // Skip common words
      if (_isCommonWord(token)) continue;
      
      // Add to keywords if meaningful
      if (token.length > 2) {
        keywords.add(token);
      }
      
      // Category detection with context
      for (final category in _categoryMappings.keys) {
        final categoryTokens = _categoryMappings[category]!;
        
        if (categoryTokens.contains(token)) {
          categories.add(category);
          continue;
        }
        
        // Check for compound matches (e.g., "book club")
        if (i < tokens.length - 1) {
          final compound = '$token ${tokens[i + 1]}';
          if (categoryTokens.any((ct) => compound.contains(ct))) {
            categories.add(category);
          }
        }
      }
    }

    // Location intent detection
    final nearMe = _detectLocationIntent(queryLower);
    
    // Radius extraction
    final radiusKm = _extractRadius(queryLower, nearMe);
    
    // Date range detection
    final dateRange = _extractDateRange(queryLower);
    
    // Remove duplicates and limit results
    final uniqueCategories = categories.toSet().take(5).toList();
    final uniqueKeywords = keywords.toSet().take(5).toList();

    return {
      'categories': uniqueCategories,
      'keywords': uniqueKeywords,
      'nearMe': nearMe,
      'radiusKm': radiusKm,
      'dateRange': dateRange,
      'confidence': _calculateConfidence(uniqueCategories, uniqueKeywords, nearMe),
    };
  }

  /// Tokenize query into words
  List<String> _tokenize(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  /// Check if a word is common and should be filtered
  bool _isCommonWord(String word) {
    const commonWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 
      'for', 'of', 'with', 'by', 'from', 'up', 'about', 'into', 'over',
      'after', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have',
      'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should',
      'may', 'might', 'must', 'can', 'i', 'you', 'he', 'she', 'it', 'we',
      'they', 'him', 'her', 'us', 'them', 'my', 'your', 'his',
      'its', 'our', 'their', 'this', 'that', 'these', 'those', 'what',
      'where', 'when', 'why', 'how', 'find', 'search', 'looking', 'want'
    };
    return commonWords.contains(word);
  }

  /// Detect location intent in query
  bool _detectLocationIntent(String query) {
    const locationKeywords = [
      'near me', 'around me', 'close by', 'nearby', 'local', 'in my area',
      'close to me', 'around here', 'in the area', 'vicinity'
    ];
    
    return locationKeywords.any((keyword) => query.contains(keyword));
  }

  /// Extract radius from query
  double _extractRadius(String query, bool nearMe) {
    if (!nearMe) return 0.0;
    
    // Look for distance mentions
    final radiusMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(km|kilometers?|miles?|mi)')
        .firstMatch(query);
    
    if (radiusMatch != null) {
      final value = double.tryParse(radiusMatch.group(1)!) ?? 25.0;
      final unit = radiusMatch.group(2)!.toLowerCase();
      
      // Convert miles to km
      if (unit.startsWith('m') && unit != 'meters') {
        return value * 1.60934; // miles to km
      }
      return value;
    }
    
    return 25.0; // default radius
  }

  /// Extract date range from query
  Map<String, String> _extractDateRange(String query) {
    final now = DateTime.now();
    final dateRange = <String, String>{};
    
    if (query.contains('today')) {
      final today = DateTime(now.year, now.month, now.day);
      dateRange['start'] = today.toIso8601String();
      dateRange['end'] = today.add(const Duration(days: 1)).toIso8601String();
    } else if (query.contains('tomorrow')) {
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      dateRange['start'] = tomorrow.toIso8601String();
      dateRange['end'] = tomorrow.add(const Duration(days: 1)).toIso8601String();
    } else if (query.contains('this week')) {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 7));
      dateRange['start'] = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day).toIso8601String();
      dateRange['end'] = DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day).toIso8601String();
    } else if (query.contains('weekend')) {
      final daysUntilSaturday = 6 - now.weekday;
      final saturday = now.add(Duration(days: daysUntilSaturday));
      final sunday = saturday.add(const Duration(days: 1));
      dateRange['start'] = DateTime(saturday.year, saturday.month, saturday.day).toIso8601String();
      dateRange['end'] = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59).toIso8601String();
    } else if (query.contains('next week')) {
      final daysUntilNextMonday = 8 - now.weekday;
      final nextMonday = now.add(Duration(days: daysUntilNextMonday));
      final nextSunday = nextMonday.add(const Duration(days: 6));
      dateRange['start'] = DateTime(nextMonday.year, nextMonday.month, nextMonday.day).toIso8601String();
      dateRange['end'] = DateTime(nextSunday.year, nextSunday.month, nextSunday.day, 23, 59, 59).toIso8601String();
    }
    
    return dateRange;
  }

  /// Calculate confidence score for the parsing
  double _calculateConfidence(List<String> categories, List<String> keywords, bool nearMe) {
    double confidence = 0.5; // base confidence
    
    // Boost confidence based on detected categories
    confidence += categories.length * 0.1;
    
    // Boost confidence based on meaningful keywords
    confidence += keywords.length * 0.05;
    
    // Boost confidence for location queries
    if (nearMe) confidence += 0.1;
    
    return (confidence * 100).clamp(0, 100);
  }

  /// Fallback parsing for error cases
  Map<String, dynamic> _fallbackParse(String query) {
    final queryLower = query.toLowerCase();
    final keywords = queryLower
        .split(RegExp(r'[^\w]+'))
        .where((word) => word.length > 2 && !_isCommonWord(word))
        .take(5)
        .toList();

    return {
      'categories': <String>[],
      'keywords': keywords,
      'nearMe': queryLower.contains('near') || queryLower.contains('local'),
      'radiusKm': 25.0,
      'dateRange': <String, String>{},
      'confidence': 30.0,
    };
  }

  /// Dispose resources
  void dispose() {
    try {
      _isInitialized = false;
      Logger.debug('OnDeviceNLPService disposed');
    } catch (e) {
      Logger.error('Error disposing OnDeviceNLPService', e);
    }
  }
}
