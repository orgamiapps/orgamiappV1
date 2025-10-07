# Performance Optimization Quick Reference Guide

## 🎯 Quick Wins for Maximum Performance

### 1. Widget Building - Always Use These Patterns

#### ✅ DO: Use Selector instead of Consumer
```dart
// ❌ BAD - Rebuilds entire tree
Consumer<MyService>(
  builder: (context, service, child) => MyWidget(service),
);

// ✅ GOOD - Only rebuilds when specific data changes
Selector<MyService, MyData>(
  selector: (context, service) => service.myData,
  builder: (context, data, child) => MyWidget(data),
);
```

#### ✅ DO: Use const constructors
```dart
// ❌ BAD
Container(child: Text('Hello'))

// ✅ GOOD
const SizedBox(height: 16)
const Padding(padding: EdgeInsets.all(8))
```

#### ✅ DO: Extract widgets to avoid rebuilds
```dart
// ❌ BAD - Rebuilds on every parent rebuild
Widget build(BuildContext context) {
  return Column(
    children: items.map((item) => 
      Row(children: [Icon(item.icon), Text(item.name)])
    ).toList(),
  );
}

// ✅ GOOD - Widget is extracted and optimized
Widget build(BuildContext context) {
  return Column(
    children: items.map((item) => ItemWidget(item)).toList(),
  );
}

class ItemWidget extends StatelessWidget {
  final Item item;
  const ItemWidget(this.item);
  // ...
}
```

---

### 2. Lists and Grids

#### ✅ DO: Use BuildOptimization helpers
```dart
// ✅ GOOD - Optimized with RepaintBoundary and caching
BuildOptimization.optimizedListView(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemWidget(items[index]),
  itemExtent: 80.0, // Add if items have fixed height
);
```

#### ✅ DO: Use IndexedStack for tabs
```dart
// ❌ BAD - Rebuilds screen on every tab change
Widget _getScreen(int index) {
  switch (index) {
    case 0: return HomeScreen();
    case 1: return ProfileScreen();
  }
}

// ✅ GOOD - Maintains state, no rebuilds
late final List<Widget> _screens = [
  const HomeScreen(),
  const ProfileScreen(),
];

IndexedStack(
  index: _selectedIndex,
  children: _screens,
);
```

---

### 3. Images

#### ✅ DO: Use SafeNetworkImage with dimensions
```dart
// ✅ GOOD - Memory optimized
SafeNetworkImage(
  imageUrl: url,
  width: 200,
  height: 150,
  // Memory optimization happens automatically
);
```

---

### 4. State Management

#### ✅ DO: Only notify when state changes
```dart
// ❌ BAD - Always notifies
void updateData(String data) {
  _data = data;
  notifyListeners(); // Called every time
}

// ✅ GOOD - Conditional notification
void updateData(String data) {
  if (_data != data) {
    _data = data;
    notifyListeners(); // Only when changed
  }
}
```

#### ✅ DO: Use context.read() when not watching
```dart
// ❌ BAD - Triggers rebuilds
final service = context.watch<MyService>();

// ✅ GOOD - No rebuilds
final service = context.read<MyService>();
```

---

### 5. Navigation

#### ✅ DO: Use optimized routes
```dart
// ✅ GOOD - Faster transitions
RouterClass.nextScreenNormal(context, MyScreen());

// Or for custom routes
RouterClass.optimizedPageRoute(
  MyScreen(),
  useSlideTransition: true,
);
```

---

### 6. Performance Config

#### Import and use performance constants:
```dart
import 'package:attendus/Utils/performance_config.dart';

// Use configured values
duration: PerformanceConfig.shortAnimation,
debounce: PerformanceConfig.searchDebounce,
batchSize: PerformanceConfig.maxEventsPerBatch,
```

---

### 7. Caching

#### ✅ DO: Use OptimizedFirestoreHelper
```dart
// ✅ GOOD - Built-in caching
final user = await OptimizedFirestoreHelper.getOptimizedUser(userId);

// Get cache stats
final stats = OptimizedFirestoreHelper.getCacheStats();
print('Hit rate: ${stats['hitRate']}');
```

---

### 8. Heavy Computations

#### ✅ DO: Use RepaintBoundary
```dart
// ✅ GOOD - Isolates repaints
RepaintBoundary(
  child: ComplexAnimatedWidget(),
);

// Or use extension
ComplexAnimatedWidget().isolateRepaints();
```

---

## 🚫 Common Anti-Patterns to Avoid

### 1. ❌ Don't build widgets in loops without keys
```dart
// ❌ BAD
children: items.map((item) => Text(item)).toList()

// ✅ GOOD
children: items.map((item) => 
  Text(item, key: ValueKey(item))
).toList()
```

### 2. ❌ Don't use setState() for the entire screen
```dart
// ❌ BAD
setState(() {
  _counter++;
}); // Rebuilds entire screen

// ✅ GOOD - Use StatefulBuilder or Selector
StatefulBuilder(
  builder: (context, setState) {
    return Text('$_counter');
  },
);
```

### 3. ❌ Don't load large lists without pagination
```dart
// ❌ BAD
.limit(1000) // Loads 1000 items at once

// ✅ GOOD
.limit(PerformanceConfig.initialEventsLoad) // Loads 20 items
```

### 4. ❌ Don't use high-res images without size constraints
```dart
// ❌ BAD
CachedNetworkImage(imageUrl: url) // Full resolution

// ✅ GOOD
CachedNetworkImage(
  imageUrl: url,
  memCacheWidth: 400,
  memCacheHeight: 300,
)
```

---

## 📊 Performance Checklist

Before submitting code, ensure:

- [ ] All static widgets use `const`
- [ ] Lists use `itemExtent` when possible
- [ ] Images have size constraints
- [ ] Expensive widgets wrapped in `RepaintBoundary`
- [ ] Used `Selector` instead of `Consumer`
- [ ] Extracted reusable widgets
- [ ] Added keys to dynamic lists
- [ ] Implemented proper caching
- [ ] Used `context.read()` for actions
- [ ] Debounced search and input
- [ ] Paginated large datasets
- [ ] Lazy loaded services
- [ ] Added timeouts to network calls

---

## 🎓 Pro Tips

### Tip 1: Profile Before Optimizing
```dart
// Wrap suspicious code
Timeline.startSync('MyOperation');
// ... your code ...
Timeline.finishSync();
```

### Tip 2: Monitor Performance
```dart
if (kDebugMode) {
  PerformanceMonitor().startMonitoring();
}
```

### Tip 3: Check Cache Efficiency
```dart
// Periodically log cache stats
final stats = OptimizedFirestoreHelper.getCacheStats();
Logger.debug('Cache performance: ${stats['hitRate']}');
```

### Tip 4: Use DevTools
- Open Flutter DevTools
- Check Performance tab for jank
- Monitor Memory tab for leaks
- Use Timeline to find bottlenecks

---

## 🔥 Emergency Performance Fixes

If your screen is slow:

1. **Check for unnecessary rebuilds**
   - Add print statements in build methods
   - Use Flutter Inspector to highlight rebuilds

2. **Wrap expensive widgets**
   ```dart
   RepaintBoundary(child: ExpensiveWidget())
   ```

3. **Reduce list item count**
   ```dart
   .limit(20) // Load less initially
   ```

4. **Add keys to lists**
   ```dart
   ListView.builder(
     itemBuilder: (context, index) => 
       ItemWidget(key: ValueKey(items[index].id), item: items[index]),
   )
   ```

5. **Use Selector for state**
   ```dart
   Selector<Service, Data>(
     selector: (_, service) => service.data,
     builder: (_, data, __) => Widget(data),
   )
   ```

---

## 📚 Resources

### Files to Reference:
- `lib/Utils/build_optimization.dart` - Helper utilities
- `lib/Utils/performance_config.dart` - Performance constants
- `lib/screens/Premium/premium_upgrade_screen.dart` - Example usage
- `COMPREHENSIVE_PERFORMANCE_OPTIMIZATION.md` - Detailed guide

### Flutter Documentation:
- [Performance best practices](https://docs.flutter.dev/perf/best-practices)
- [Reducing widget rebuilds](https://docs.flutter.dev/development/data-and-backend/state-mgmt/simple)

---

**Quick Reference Version:** 1.0  
**Last Updated:** 2025-10-04  
**Print this and keep it handy!** 📎

