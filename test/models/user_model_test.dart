import 'package:flutter_test/flutter_test.dart';
import 'package:swapnio/models/user_model.dart';

void main() {
  group('UserModel.fromMap', () {
    test('reads all fields from a Firestore-style map', () {
      final model = UserModel.fromMap({
        'email': 'a@b.com',
        'name': 'Arnab',
        'bio': 'builds things',
        'photoUrl': 'https://example.com/p.png',
        'skillsOffered': ['Flutter', 'Firebase'],
        'skillsWanted': ['Guitar'],
        'availability': ['Weekends'],
        'isAdmin': true,
        'rating': 4.5,
        'completedSwaps': 7,
      }, 'uid-1');

      expect(model.id, 'uid-1');
      expect(model.email, 'a@b.com');
      expect(model.name, 'Arnab');
      expect(model.skillsOffered, ['Flutter', 'Firebase']);
      expect(model.skillsWanted, ['Guitar']);
      expect(model.isAdmin, isTrue);
      expect(model.rating, 4.5);
      expect(model.completedSwaps, 7);
    });

    test('falls back to safe defaults for missing fields', () {
      final model = UserModel.fromMap({}, 'uid-2');

      expect(model.email, '');
      expect(model.name, '');
      expect(model.bio, '');
      expect(model.skillsOffered, isEmpty);
      expect(model.skillsWanted, isEmpty);
      expect(model.isAdmin, isFalse);
      expect(model.rating, 0.0);
      expect(model.completedSwaps, 0);
    });

    test('wraps a single skill string into a list', () {
      final model = UserModel.fromMap({'skillsOffered': 'Piano'}, 'uid-3');
      expect(model.skillsOffered, ['Piano']);
    });

    test('coerces numeric rating coming back as int', () {
      final model = UserModel.fromMap({'rating': 5}, 'uid-4');
      expect(model.rating, isA<double>());
      expect(model.rating, 5.0);
    });
  });

  group('UserModel.toMap / copyWith', () {
    test('toMap round-trips values including the id field', () {
      final model = UserModel(
        id: 'uid-5',
        email: 'x@y.com',
        name: 'Manab',
        skillsOffered: const ['UI'],
      );

      final map = model.toMap();
      expect(map['id'], 'uid-5');
      expect(map['name'], 'Manab');
      expect(map['skillsOffered'], ['UI']);

      final restored = UserModel.fromMap(map, 'uid-5');
      expect(restored.id, model.id);
      expect(restored.name, model.name);
      expect(restored.skillsOffered, model.skillsOffered);
    });

    test('copyWith only replaces provided fields', () {
      final model = UserModel(
        id: 'uid-6',
        email: 'a@a.com',
        name: 'Test User',
        rating: 4.0,
      );

      final updated = model.copyWith(name: 'Test User U', rating: 4.8);
      expect(updated.name, 'Test User U');
      expect(updated.rating, 4.8);
      expect(updated.email, 'a@a.com');
      expect(updated.id, 'uid-6');
    });
  });
}