// test/widget/nubia_skeleton_loader_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/widgets/nubia_skeleton_loader.dart';
import 'package:shimmer/shimmer.dart';

/// Golden test du NubiaSkeletonLoader.
///
/// Régénérer avec :
///   flutter test --update-goldens test/widget/nubia_skeleton_loader_test.dart
void main() {
  group('NubiaSkeletonLoader', () {
    testWidgets('affiche un widget Shimmer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaSkeletonLoader(height: 80),
            ),
          ),
        ),
      );

      expect(find.byType(NubiaSkeletonLoader), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('golden snapshot — shimmer loader', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NubiaSkeletonLoader(height: 20),
                  SizedBox(height: 8),
                  NubiaSkeletonLoader(height: 20, width: 200),
                  SizedBox(height: 8),
                  NubiaSkeletonLoader(height: 80),
                ],
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/nubia_skeleton_loader.png'),
      );
    });
  });
}
