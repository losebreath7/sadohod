import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sadohod/core/widgets/design.dart';
import 'package:sadohod/data/account.dart';
import 'package:sadohod/features/account/sadohodtsy_screen.dart';

void main() {
  testWidgets('header navigation and favorite heart share the live courier list',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = AccountStore.instance;
    account.token = 'courier-flow-session';
    account.couriers.clear();
    addTearDown(() { account.token = null; account.couriers.clear(); });
    final saved = <String>{};
    final writes = <bool>[];
    final profiles = [
      {'id':'courier-1','name':'Alpha courier','contacts':<String,String>{}},
      {'id':'courier-2','name':'Beta courier','contacts':<String,String>{}},
    ];
    final router = GoRouter(initialLocation:'/account',routes:[
      GoRoute(path:'/account',builder:(_,__)=>Scaffold(body:Builder(
        builder:(context)=>TextButton(onPressed:()=>context.push('/sadohodtsy'),
          child:const Text('open directory'))))),
      GoRoute(path:'/sadohodtsy',builder:(_,__)=>const Scaffold(body:SadohodtsyScreen())),
      GoRoute(path:'/sadohodtsy/:id',builder:(_,state)=>Scaffold(
        body:SadohodetsScreen(id:state.pathParameters['id']!))),
    ]);
    addTearDown(router.dispose);
    http.Response json(Map<String,dynamic> value)=>http.Response(
      jsonEncode(value),200,headers:{'content-type':'application/json; charset=utf-8'});
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp.router(routerConfig:router));
      await tester.tap(find.text('open directory'));
      await tester.pumpAndSettle();
      final headerHeart=find.byKey(const ValueKey('courier-directory-favorites'));
      final profileHeart=find.byKey(const ValueKey('courier-profile-favorite'));
      bool filled(Finder heart)=>tester.widget<FavoriteHeartGlyph>(
        find.descendant(of:heart,matching:find.byType(FavoriteHeartGlyph))).filled;
      expect(find.byType(RoundBack),findsOneWidget);
      expect(find.text('любимые'),findsNothing);
      expect(tester.getCenter(find.text('садоходцы')).dx,closeTo(195,1));
      expect(filled(headerHeart),isFalse);
      await tester.tap(find.text('Alpha courier'));
      await tester.pumpAndSettle();
      expect(filled(profileHeart),isFalse);
      await tester.tap(profileHeart);
      await tester.pumpAndSettle();
      expect(filled(profileHeart),isTrue);
      expect(saved,{'courier-1'});
      await tester.tap(find.byType(RoundBack));
      await tester.pumpAndSettle();
      await tester.tap(headerHeart);
      await tester.pumpAndSettle();
      expect(filled(headerHeart),isTrue);
      expect(find.text('Alpha courier'),findsOneWidget);
      expect(find.text('Beta courier'),findsNothing);
      await tester.tap(find.text('Alpha courier'));
      await tester.pumpAndSettle();
      expect(filled(profileHeart),isTrue);
      await tester.tap(profileHeart);
      await tester.pumpAndSettle();
      expect(filled(profileHeart),isFalse);
      await tester.tap(find.byType(RoundBack));
      await tester.pumpAndSettle();
      expect(find.text('Пока нет любимых садоходцев'),findsOneWidget);
      expect(writes,[true,false]);
      await tester.tap(headerHeart);
      await tester.pumpAndSettle();
      expect(find.text('Beta courier'),findsOneWidget);
      await tester.tap(find.byType(RoundBack));
      await tester.pumpAndSettle();
      expect(find.text('open directory'),findsOneWidget);
      expect(tester.takeException(),isNull);
    },()=>MockClient((request) async {
      final path=request.url.path;
      if(path=='/api/v1/account') return json({'couriers':saved.toList()});
      if(path=='/api/v1/account/favorite'){
        final body=jsonDecode(request.body) as Map<String,dynamic>;
        expect(body['kind'],'courier');
        expect(body['id'],'courier-1');
        final value=body['saved'] as bool;
        writes.add(value);
        value?saved.add('courier-1'):saved.remove('courier-1');
        return json({'saved':value});
      }
      if(path=='/api/v1/sadohodets') return json({'items':profiles});
      if(path.endsWith('/my-review')) return json({'item':null});
      if(path.endsWith('/reviews')) return json({'rating':null,'review_count':0,'items':[]});
      if(path=='/api/v1/sadohodets/courier-1') return json(profiles.first);
      throw StateError('Unexpected ${request.method} $path');
    }));
  });
}
