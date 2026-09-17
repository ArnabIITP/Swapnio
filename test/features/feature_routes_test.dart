import 'package:flutter_test/flutter_test.dart';
import 'package:swapnio/features/feature_routes.dart';

void main() {
  test('all feature routes are registered', () {
    expect(
      featureRoutes.keys,
      containsAll([
        '/gamification',
        '/verification',
        '/progress',
        '/forum',
        '/analytics',
      ]),
    );
  });
}
