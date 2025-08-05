# Personalized Event Recommendation System

## Overview

The personalized event recommendation system provides intelligent event suggestions based on user preferences, location, past behavior, and engagement patterns. The system uses a weighted scoring algorithm with ML-based engagement prediction to deliver highly relevant event recommendations.

## Architecture

### Core Components

1. **EventRecommendationHelper** (`lib/Firebase/EventRecommendationHelper.dart`)
   - Main recommendation engine
   - Weighted scoring algorithm
   - User preference analysis
   - Location-based scoring

2. **EngagementPredictor** (`lib/Firebase/EngagementPredictor.dart`)
   - ML-based engagement prediction
   - User behavior pattern analysis
   - Interaction tracking

3. **RecommendationAnalytics** (`lib/Firebase/RecommendationAnalytics.dart`)
   - Performance tracking
   - User interaction analytics
   - Recommendation insights

## Algorithm Details

### Weighted Scoring System

The recommendation algorithm uses a weighted scoring system with the following factors:

| Factor | Weight | Description |
|--------|--------|-------------|
| **Location** | 25% | Inverse distance from user's location |
| **Personalization** | 35% | Category matching, past attendance patterns |
| **Popularity** | 20% | Ticket sales, featured status, recency |
| **Recency** | 10% | Upcoming event priority |
| **Featured** | 10% | Featured event boost |

### Scoring Breakdown

#### 1. Location Score (25%)
- Uses Geolocator to calculate distance between user and event
- Inverse distance scoring (closer = higher score)
- Maximum distance considered: 100km
- Score range: 0.1 - 1.0

#### 2. Personalization Score (35%)
- **Category Matching (40%)**: Matches event categories with user's preferred categories
- **Past Attendance (30%)**: Analyzes user's past event attendance patterns
- **Time Preference (20%)**: Matches event time with user's preferred time slots
- **Day Preference (10%)**: Matches event day with user's preferred days

#### 3. Popularity Score (20%)
- **Ticket Sales Ratio (50%)**: Events with higher ticket sales get higher scores
- **Featured Status (30%)**: Featured events receive a boost
- **Creation Recency (20%)**: Newer events get a slight boost

#### 4. Recency Score (10%)
- Events happening soon get higher scores
- Scoring tiers:
  - ≤1 day: 1.0
  - ≤3 days: 0.9
  - ≤7 days: 0.8
  - ≤14 days: 0.7
  - ≤30 days: 0.6
  - >30 days: 0.5

#### 5. Featured Score (10%)
- Featured events get full score (1.0)
- Non-featured events get 0.0
- Considers feature end date

### ML Engagement Prediction

The system includes a simplified ML-based engagement prediction that analyzes:

- **Category Engagement**: User's interaction patterns with event categories
- **Time Engagement**: Preferred time slots based on past interactions
- **Location Engagement**: Preferred location zones
- **Social Engagement**: Preference for events with different attendance levels

## Implementation Details

### User Preference Analysis

The system analyzes user preferences by:

1. **Past Event Attendance**: Tracks events the user has attended
2. **Category Analysis**: Identifies most frequently attended event categories
3. **Time Pattern Analysis**: Determines preferred time slots (morning, afternoon, evening, night)
4. **Day Pattern Analysis**: Identifies preferred days of the week
5. **Location Analysis**: Tracks preferred location zones

### Caching Strategy

- **User Preferences Cache**: Cached for 30 minutes
- **Location Cache**: Cached for 30 minutes
- **Cache Invalidation**: Cleared when search terms, categories, or sort options change

### Analytics Integration

The system tracks:

- **Recommendations Shown**: When recommendations are displayed to users
- **User Interactions**: Clicks, views, and other interactions with recommended events
- **Performance Metrics**: Engagement rates and recommendation scores
- **User Feedback**: Like/dislike feedback on recommendations

## Usage

### Basic Usage

```dart
// Get personalized recommendations
List<EventModel> recommendations = await EventRecommendationHelper.getPersonalizedRecommendations(
  searchQuery: "workshop",
  categories: ["Educational", "Professional"],
  limit: 50,
);
```

### Analytics Tracking

```dart
// Track recommendations shown
RecommendationAnalytics.trackRecommendationsShown(
  eventIds: eventIds,
  searchQuery: searchQuery,
  categories: categories,
);

// Track user interaction
RecommendationAnalytics.trackRecommendationInteraction(
  eventId: eventId,
  interactionType: "view",
  position: 1,
);
```

### Engagement Prediction

```dart
// Predict engagement score
double engagementScore = await EngagementPredictor.predictEngagementScore(event);

// Track interaction
EngagementPredictor.trackInteraction(eventId, "view");
```

## Firestore Collections

### Required Collections

1. **Events** - Event data with categories, location, tickets, etc.
2. **Customers** - User profiles with preferences
3. **EventAttendance** - User attendance records
4. **EventInteractions** - User interaction tracking
5. **RecommendationAnalytics** - Recommendation performance data
6. **RecommendationPerformance** - Detailed performance metrics
7. **RecommendationFeedback** - User feedback on recommendations

### Data Structure Examples

#### EventInteractions
```json
{
  "userId": "user123",
  "eventId": "event456",
  "interactionType": "view",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### RecommendationAnalytics
```json
{
  "userId": "user123",
  "eventIds": ["event1", "event2", "event3"],
  "searchQuery": "workshop",
  "categories": ["Educational"],
  "timestamp": "2024-01-15T10:30:00Z",
  "type": "recommendations_shown"
}
```

## Performance Considerations

### Optimization Strategies

1. **Caching**: User preferences and location are cached for 30 minutes
2. **Batch Processing**: Multiple events are processed in batches
3. **Fallback System**: Falls back to basic recommendations if personalization fails
4. **Lazy Loading**: Recommendations are loaded as needed

### Scalability

- **Indexing**: Firestore queries are optimized with proper indexes
- **Pagination**: Results are limited to prevent performance issues
- **Error Handling**: Graceful degradation when services are unavailable

## Configuration

### Weights Configuration

You can adjust the scoring weights in `EventRecommendationHelper.dart`:

```dart
static const double LOCATION_WEIGHT = 0.25;
static const double PERSONALIZATION_WEIGHT = 0.35;
static const double POPULARITY_WEIGHT = 0.20;
static const double RECENCY_WEIGHT = 0.10;
static const double FEATURED_WEIGHT = 0.10;
```

### Cache Duration

Cache duration can be adjusted in the helper methods:

```dart
// Cache for 30 minutes
DateTime.now().difference(_lastCacheUpdate!).inMinutes < 30
```

## Testing

### Unit Tests

```dart
// Test recommendation scoring
test('should calculate correct personalized score', () async {
  EventModel event = createTestEvent();
  Map<String, dynamic> preferences = createTestPreferences();
  Position location = createTestLocation();
  
  double score = await EventRecommendationHelper._calculatePersonalizedScore(
    event: event,
    userPreferences: preferences,
    userLocation: location,
  );
  
  expect(score, greaterThan(0.0));
  expect(score, lessThanOrEqualTo(1.0));
});
```

### Integration Tests

```dart
// Test full recommendation flow
test('should return personalized recommendations', () async {
  List<EventModel> recommendations = await EventRecommendationHelper.getPersonalizedRecommendations(
    searchQuery: "test",
    limit: 10,
  );
  
  expect(recommendations, isNotEmpty);
  expect(recommendations.length, lessThanOrEqualTo(10));
});
```

## Future Enhancements

### Planned Improvements

1. **Advanced ML Integration**: Full ML Kit integration for better prediction
2. **Real-time Learning**: Continuous model updates based on user feedback
3. **A/B Testing**: Framework for testing different recommendation algorithms
4. **Social Features**: Friend-based recommendations and social proof
5. **Seasonal Adjustments**: Time-based recommendation adjustments

### Potential Features

- **Collaborative Filtering**: Recommendations based on similar users
- **Content-Based Filtering**: Deep analysis of event descriptions
- **Hybrid Approaches**: Combination of multiple recommendation strategies
- **Contextual Recommendations**: Location and time-aware suggestions

## Troubleshooting

### Common Issues

1. **No Recommendations**: Check user authentication and Firestore permissions
2. **Poor Performance**: Verify Firestore indexes and cache settings
3. **Inaccurate Scores**: Review user preference data and scoring weights
4. **Location Issues**: Ensure location permissions are granted

### Debug Mode

Enable debug logging by adding print statements in the helper methods:

```dart
print('User preferences: $userPreferences');
print('Location score: $locationScore');
print('Final score: $finalScore');
```

## Security Considerations

- **User Privacy**: Only track necessary interaction data
- **Data Retention**: Implement data retention policies
- **Permission Handling**: Proper location permission management
- **Error Handling**: Secure error messages without exposing sensitive data

## Dependencies

The recommendation system requires the following dependencies:

```yaml
dependencies:
  geolocator: ^11.0.0
  cloud_firestore: ^5.6.3
  firebase_auth: ^5.4.2
```

## Conclusion

The personalized event recommendation system provides intelligent, user-centric event suggestions that improve user engagement and satisfaction. The system is designed to be scalable, maintainable, and continuously improvable through analytics and user feedback. 