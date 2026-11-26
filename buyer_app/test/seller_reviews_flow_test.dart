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
    bool courier = false,
    Future<void> Function()? remove,
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
          courier: courier,
          deleteOverride: remove,
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
    // AlertDialog's outer padding can fill the overlay; the inner
    // Material is the visible white card with the fixed phone-safe width.
    final card = find.descendant(
      of: dialog, matching: find.byType(Material),
    ).first;
    expect(tester.getSize(card).width, greaterThanOrEqualTo(320));
    expect(tester.getSize(card).width, lessThanOrEqualTo(402 - 40));
    expect(tester.getSize(card).height, lessThanOrEqualTo(874));
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
    final card = find.descendant(
      of: dialog, matching: find.byType(Material),
    ).first;
    final bounds = tester.getRect(card);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.width, greaterThanOrEqualTo(275));
    expect(bounds.width, lessThanOrEqualTo(320 - 40));
    expect(bounds.right, lessThanOrEqualTo(320));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(640));
    expect(find.text('закрыть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final status in ['approved', 'pending', 'rejected']) {
    testWidgets('One existing $status review hides new-review card', (
      tester,
    ) async {
      final own = <String, dynamic>{
        'id': 'my-review', 'name': 'Мария', 'rating': 4,
        'text': 'Уже оставленный отзыв', 'photos': [],
        'moderation_status': status,
      };
      await mountReviews(tester, signedIn: true,
        public: () async => {
          'count': status == 'approved' ? 1 : 0,
          'average': status == 'approved' ? 4.0 : null,
          'items': status == 'approved' ? [own] : [],
        },
        mine: () async => {'item': own, 'hidden': false},
      );
      expect(find.byKey(const ValueKey('seller-review-add')), findsNothing);
      expect(find.byKey(const ValueKey('seller-review-my-review')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final status in ['approved', 'pending', 'rejected']) {
    testWidgets('Own $status review is first left without plus or duplicate',
        (tester) async {
      final own = <String, dynamic>{
        'id': 'mine', 'name': 'losebreath', 'rating': 5,
        'text': 'мой отзыв', 'moderation_status': status, 'photos': [],
      };
      final other = <String, dynamic>{
        'id': 'other', 'name': 'Ирина', 'rating': 4,
        'text': 'отзыв другого', 'moderation_status': 'approved', 'photos': [],
      };
      await mountReviews(tester, signedIn: true,
        public: () async => {
          'count': status == 'approved' ? 2 : 1,
          'average': status == 'approved' ? 4.5 : 4.0,
          // Deliberately return the other review first to verify sort.
          'items': [other, if (status == 'approved') own],
        },
        mine: () async => {'item': own, 'hidden': false},
      );
      final mineCard = find.byKey(const ValueKey('seller-review-mine'));
      final otherCard = find.byKey(const ValueKey('seller-review-other'));
      expect(find.byKey(const ValueKey('seller-review-add')), findsNothing);
      expect(mineCard, findsOneWidget);
      expect(otherCard, findsOneWidget);
      expect(tester.getTopLeft(mineCard).dx,
          lessThan(tester.getTopLeft(otherCard).dx));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Own existing review can be edited, not added again', (
    tester,
  ) async {
    final own = <String, dynamic>{
      'id': 'one-review', 'name': 'Мария', 'rating': 4,
      'text': 'Первый отзыв', 'photos': [],
      'moderation_status': 'approved',
    };
    await mountReviews(tester, signedIn: true,
      public: () async => {
        'count': 1, 'average': 4.0, 'items': [own],
      },
      mine: () async => {'item': own, 'hidden': false},
    );
    expect(find.byKey(const ValueKey('seller-review-add')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('seller-review-one-review')));
    await tester.pumpAndSettle();
    expect(find.text('пожаловаться'), findsNothing);
    expect(find.text('редактировать'), findsOneWidget);
    await tester.tap(find.text('редактировать'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-compose-sheet')), findsOneWidget);
    expect(find.text('Редактировать отзыв'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('review-comment')),
    );
    expect(field.controller!.text, 'Первый отзыв');
    await tester.tap(find.byTooltip('Закрыть отзыв'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cannot create review when private review lookup fails', (
    tester,
  ) async {
    await mountReviews(tester, signedIn: true,
      public: () async => {'count': 0, 'average': null, 'items': []},
      mine: () async => throw StateError('Temporary private API failure'),
    );
    expect(find.byKey(const ValueKey('seller-review-add')), findsNothing);
    expect(find.text('Не удалось проверить ваш отзыв'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('No existing review still offers a single add card', (
    tester,
  ) async {
    await mountReviews(tester, signedIn: true,
      public: () async => {'count': 1, 'average': 4.0, 'items': [
        {'id': 'another-review', 'name': 'Другой пользователь', 'rating': 4,
         'text': 'Его отзыв', 'photos': []},
      ]},
      mine: () async => {'item': null, 'hidden': false},
    );
    expect(find.byKey(const ValueKey('seller-review-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('seller-review-another-review')), findsOneWidget);
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
  testWidgets('Courier uses the same review cards, flowers and text editor', (tester) async {
    final own = {'id':'mine','name':'Я','rating':5,'text':'Мой отзыв','moderation_status':'approved'};
    final other = {'id':'other','name':'Другой','rating':4,'text':'Хорошо','moderation_status':'approved'};
    await mountReviews(tester, courier:true, signedIn:true,
      public: () async => {'average':4.5,'items':[other,own]},
      mine: () async => {'item':own});
    final myCard = find.byKey(const ValueKey('seller-review-mine'));
    final otherCard = find.byKey(const ValueKey('seller-review-other'));
    expect(myCard,findsOneWidget);
    expect(tester.getSize(myCard),const Size(135,85));
    expect(tester.getTopLeft(myCard).dx,lessThan(tester.getTopLeft(otherCard).dx));
    expect(find.byType(ReviewRatingFlowers),findsOneWidget);
    await tester.tap(otherCard);
    await tester.pumpAndSettle();
    expect(find.text('пожаловаться'),findsNothing);
    await tester.tap(find.text('закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(myCard);
    await tester.pumpAndSettle();
    expect(find.text('удалить'),findsOneWidget);
    await tester.tap(find.text('редактировать'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-compose-sheet')),findsOneWidget);
    expect(find.byTooltip('Добавить фото к отзыву (0/3)'),findsNothing);
    await tester.tap(find.byTooltip('Закрыть отзыв'));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
  });

  testWidgets('Courier with no reviews shows the identical add card', (tester) async {
    await mountReviews(tester,courier:true,signedIn:true,
      public:() async => {'average':null,'items':[]},
      mine:() async => {'item':null});
    expect(find.text('нет отзывов'),findsOneWidget);
    final card=find.byKey(const ValueKey('seller-review-add'));
    expect(tester.getSize(card),const Size(135,85));
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-compose-sheet')),findsOneWidget);
    expect(find.byType(ReviewFlower),findsNWidgets(5));
    await tester.tap(find.byTooltip('Закрыть отзыв'));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
  });

}
