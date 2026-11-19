import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sadohod_shared_core/device_preview_shell.dart';
import 'package:sadohod/features/seller/review_flowers.dart';
import 'package:sadohod/features/seller/seller_reviews_panel.dart';

void main() {
  Future<void> mountReviews(
    WidgetTester tester, {
    required Future<Map<String, dynamic>> Function() public,
    Future<Map<String, dynamic>> Function()? mine,
    Future<void> Function(int, String, List<String>)? save,
    bool signedIn = false,
    bool frame = false,
    double width = 390,
    double height = 844,
  }) async {
    if (frame) SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: frame
          ? (context, child) =>
              SadohodDevicePreviewShell(forcePreview: true, child: child!)
          : null,
      home: Scaffold(
      body: SingleChildScrollView(
        child: SellerReviewsPanel(
          sellerId: 'seller-1',
          sellerName: 'martini felesk',
          publicLoader: public,
          myLoader: mine,
          submitOverride: save,
          loggedIn: signedIn,
        ),
      ),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('empty reviews show first add card without fabricated rating',
      (tester) async {
    await mountReviews(tester, public: () async => {
      'count': 0, 'average': null, 'items': [],
    });
    expect(find.text('нет отзывов'), findsOneWidget);
    expect(find.byKey(const ValueKey('seller-review-add')), findsOneWidget);
    expect(find.byType(ReviewRatingFlowers), findsNothing);
    expect(find.byKey(const ValueKey('seller-reviews-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add review card matches Figma size, avatar and name position',
      (tester) async {
    await mountReviews(tester, public: () async => {
      'count': 0, 'average': null, 'items': [],
    });
    final card = find.byKey(const ValueKey('seller-review-add'));
    final cardTopLeft = tester.getTopLeft(card);
    expect(tester.getSize(card).width, 135);
    expect(tester.getSize(card).height, 85);
    final avatar = find.descendant(
      of: card, matching: find.byType(SvgPicture));
    expect(avatar, findsOneWidget);
    final avatarTopLeft = tester.getTopLeft(avatar);
    expect(avatarTopLeft.dx - cardTopLeft.dx, closeTo(6, .1));
    expect(avatarTopLeft.dy - cardTopLeft.dy, closeTo(5, .1));
    expect(tester.getSize(avatar).width, closeTo(13.5, .1));
    expect(tester.getSize(avatar).height, closeTo(13.5, .1));
    final label = find.descendant(of: card,
      matching: find.text('имя фамилия'));
    expect(label, findsOneWidget);
    expect(tester.getTopLeft(label).dx - cardTopLeft.dx, closeTo(23, .1));
    expect(find.descendant(of: card, matching: find.text('+')),
      findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rating flowers render original SVG assets in Figma order',
      (tester) async {
    await mountReviews(tester, public: () async => {
      'count': 2, 'average': 3.5, 'items': [],
    });
    final flowers = tester.widgetList<ReviewFlower>(
      find.byType(ReviewFlower)).toList();
    expect(flowers.map((flower) => flower.index).toList(),
      [0, 1, 2, 3, 4]);
    for (final asset in reviewFlowerAssets) {
      expect(asset.startsWith('assets/figma/review_'), isTrue);
      expect(asset.endsWith('.svg'), isTrue);
    }
    expect(find.byType(SvgPicture), findsAtLeastNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fractional public score is not rounded to a whole flower',
      (tester) async {
    await mountReviews(tester, public: () async => {
      'count': 2, 'average': 3.5, 'items': [
        {'id': 'rev1', 'name': 'Оля', 'rating': 3,
         'text': 'Продавец ответил быстро', 'photos': []},
        {'id': 'rev2', 'name': 'Нина', 'rating': 4,
         'text': 'Всё понравилось', 'photos': []},
      ],
    });
    expect(find.text('3.5'), findsOneWidget);
    final rating = tester.widget<ReviewRatingFlowers>(
      find.byType(ReviewRatingFlowers));
    expect(rating.rating, 3.5);
    final flowers = tester.widgetList<ReviewFlower>(
      find.byType(ReviewFlower)).toList();
    expect(flowers.length, 5);
    expect(flowers.map((f) => f.fill).toList(), [1, 1, 1, .5, 0]);
    expect(find.byKey(const ValueKey('seller-review-rev1')), findsOneWidget);
    expect(find.byKey(const ValueKey('seller-review-rev2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending own review visible only to author and not in average',
      (tester) async {
    await mountReviews(tester, signedIn: true,
      public: () async => {'count': 0, 'average': null, 'items': []},
      mine: () async => {'hidden': false, 'item': {
        'id': 'own-pending', 'name': 'Мария',
        'rating': 5, 'text': 'Отзыв ещё проверяют',
        'moderation_status': 'pending', 'photos': [],
      }},
    );
    expect(find.text('нет отзывов'), findsOneWidget);
    expect(find.text('на модерации'), findsOneWidget);
    expect(find.byKey(const ValueKey('seller-review-own-pending')), findsOneWidget);
    expect(find.byType(ReviewRatingFlowers), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected own review is distinctly labelled without public score',
      (tester) async {
    await mountReviews(tester, signedIn: true,
      public: () async => {'count': 0, 'average': null, 'items': []},
      mine: () async => {'hidden': false, 'item': {
        'id': 'own-rejected', 'name': 'Мария',
        'rating': 2, 'text': 'Отзыв отклонён модератором',
        'moderation_status': 'rejected', 'photos': [],
      }},
    );
    expect(find.text('отзыв отклонен'), findsOneWidget);
    expect(find.text('на модерации'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Approved own review hides report but other review permits it',
      (tester) async {
    final own = {
      'id': 'my-approved-review',
      'name': 'losebreath',
      'rating': 5,
      'text': 'Мой опубликованный отзыв',
      'moderation_status': 'approved',
      'photos': [],
    };
    final other = {
      'id': 'different-buyer-review',
      'name': 'Ирина',
      'rating': 4,
      'text': 'Отзыв другого пользователя',
      'moderation_status': 'approved',
      'photos': [],
    };
    await mountReviews(tester, signedIn: true,
      public: () async => {
        'count': 2, 'average': 4.5, 'items': [own, other],
      },
      mine: () async => {'item': own, 'hidden': false},
    );
    await tester.tap(find.byKey(const ValueKey('seller-review-my-approved-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seller-review-detail-dialog')), findsOneWidget);
    expect(find.descendant(
      of: find.byKey(const ValueKey('seller-review-detail-dialog')),
      matching: find.text('Мой опубликованный отзыв'),
    ), findsOneWidget);
    expect(find.text('пожаловаться'), findsNothing);
    expect(find.text('закрыть'), findsOneWidget);
    await tester.tap(find.text('закрыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('seller-review-different-buyer-review')));
    await tester.pumpAndSettle();
    expect(find.descendant(
      of: find.byKey(const ValueKey('seller-review-detail-dialog')),
      matching: find.text('Отзыв другого пользователя'),
    ), findsOneWidget);
    expect(find.text('пожаловаться'), findsOneWidget);
    await tester.tap(find.text('закрыть'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Review detail modal uses phone viewport inside desktop browser',
      (tester) async {
    await mountReviews(tester,
      frame: true,
      width: 1440,
      height: 1000,
      public: () async => {
        'count': 1, 'average': 5.0, 'items': [
          {'id': 'other', 'name': 'Ирина', 'rating': 5,
            'text': 'Хороший продавец', 'photos': []},
        ],
      },
    );
    await tester.tap(find.byKey(const ValueKey('seller-review-other')));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('seller-review-detail-dialog'));
    expect(dialog, findsOneWidget);
    expect(MediaQuery.sizeOf(tester.element(dialog)), const Size(402, 874));
    expect(tester.getSize(dialog).width, lessThanOrEqualTo(402));
    expect(tester.getSize(dialog).height, lessThanOrEqualTo(874));
    expect(find.text('закрыть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Review detail modal fits a compact phone', (tester) async {
    await mountReviews(tester,
      width: 320,
      height: 640,
      public: () async => {
        'count': 1, 'average': 3.0, 'items': [
          {'id': 'other', 'name': 'Ирина', 'rating': 3,
            'text': 'Отзыв', 'photos': []},
        ],
      },
    );
    await tester.tap(find.byKey(const ValueKey('seller-review-other')));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('seller-review-detail-dialog'));
    final bounds = tester.getRect(dialog);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(320));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(640));
    expect(find.text('закрыть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submit, acknowledge, return to seller without reopening editor',
      (tester) async {
    Map<String, dynamic>? own;
    var submits = 0;
    await mountReviews(tester, signedIn: true,
      public: () async => {'count': 0, 'average': null, 'items': []},
      mine: () async => {'item': own, 'hidden': false},
      save: (rating, text, photos) async {
        submits++;
        expect(rating, 4);
        expect(text, 'Приятный продавец');
        own = {'id': 'own-new', 'name': 'Мария', 'rating': rating,
          'text': text, 'photos': photos, 'moderation_status': 'pending'};
      },
    );
    await tester.tap(find.byKey(const ValueKey('seller-review-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-compose-sheet')), findsOneWidget);
    expect(find.text('martini felesk'), findsOneWidget);
    expect(find.text('Отправить на проверку'), findsOneWidget);
    final submitButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('submit-seller-review')));
    final shape = submitButton.style!.shape!.resolve({});
    expect(shape, isA<RoundedRectangleBorder>());
    expect((shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(999));
    await tester.tap(find.byKey(const ValueKey('submit-seller-review')));
    await tester.pump();
    expect(find.text('Выберите оценку'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-rating-4')));
    await tester.enterText(find.byKey(const ValueKey('review-comment')),
      'Приятный продавец');
    await tester.ensureVisible(find.byKey(const ValueKey('submit-seller-review')));
    await tester.tap(find.byKey(const ValueKey('submit-seller-review')));
    await tester.pumpAndSettle();
    expect(submits, 1);
    expect(find.byKey(const ValueKey('review-submitted-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-compose-sheet')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('review-confirm-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-submitted-sheet')), findsNothing);
    expect(find.byKey(const ValueKey('review-compose-sheet')), findsNothing);
    expect(find.byKey(const ValueKey('seller-review-own-new')), findsOneWidget);
    expect(find.text('на модерации'), findsOneWidget);
    expect(find.text('нет отзывов'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
