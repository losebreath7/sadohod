import 'package:flutter/material.dart';
import '../core/widgets/device_preview_lab.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/design.dart';
import '../data/api.dart';
import '../data/catalog.dart';
import '../features/home/home_screen.dart';
import '../features/product/product_screen.dart';
import '../features/seller/seller_screen.dart';
import '../features/search/search_screen.dart';
import '../features/search/results_screen.dart';
import '../features/account/account_screen.dart';
import '../features/account/sadohodtsy_screen.dart';
import '../features/account/favorites_screen.dart';
import '../features/account/profile_features.dart';
import '../features/account/market_navigation_guide.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _AppShell(shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, s) => HomeScreen(
                initialCategory: s.uri.queryParameters['category'] ?? 'Все',
                initialQuery: s.uri.queryParameters['q'] ?? '',
                key: ValueKey(s.uri.toString()),
              ),
              routes: [],
            ),
            // Old catalogue links continue working, but the catalogue is now
            // part of the one home/feed tab, not a separate screen.
            GoRoute(
              path: '/catalog',
              redirect: (_, s) => '/home${s.uri.hasQuery ? '?${s.uri.query}' : ''}',
            ),
            GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            GoRoute(
              path: '/results',
              builder: (_, s) => ResultsScreen(
                query: s.extra is ImageSearchQuery
                    ? s.extra as ImageSearchQuery
                    : null,
                textQuery: s.uri.queryParameters['q'] ?? '',
              ),
            ),
            GoRoute(
              path: '/product/:id',
              builder: (_, s) => ProductScreen(id: s.pathParameters['id']!),
            ),
            GoRoute(
              path: '/seller/:id',
              builder: (_, s) => SellerScreen(id: s.pathParameters['id']!),
            ),
            GoRoute(
              path: '/map',
              builder: (_, s) => MapScreen(
                seller: s.extra is Seller ? s.extra as Seller : null,
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/favorites',
              builder: (_, _) => const FavoritesScreen(),
            ),
            GoRoute(
              path: '/favorite-sellers',
              builder: (_, _) => const FavoritesScreen(sellers: true),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
            GoRoute(
              path: '/confirm',
              builder: (_, s) => s.extra is String
                  ? ConfirmScreen(email: s.extra as String)
                  : const AccountScreen(),
            ),
            GoRoute(path: '/navigation',
              builder: (_, _) => const MarketNavigationGuideScreen()),
            GoRoute(path: '/navigation/:zone',
              builder: (_, s) => MarketNavigationZoneScreen(
                slug: s.pathParameters['zone'] ?? '',
              )),
            GoRoute(path: '/sadohodtsy', builder: (_, _) => const SadohodtsyScreen()),
            GoRoute(path: '/sadohodtsy/:id', builder: (_, s) => SadohodetsScreen(id: s.pathParameters['id']!)),
            GoRoute(path: '/profile', builder: (_, _) => const ProfileEditScreen()),
            GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
            GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
            GoRoute(path: '/change-email', builder: (_, _) => const ChangeEmailScreen()),
            GoRoute(path: '/support', builder: (_, _) => const BuyerChatScreen(kind: 'support')),
            GoRoute(path: '/cooperation', builder: (_, _) => const BuyerChatScreen(kind: 'cooperation')),
            GoRoute(path: '/about', builder: (_, _) => const BuyerInfoScreen('about')),
            GoRoute(path: '/legal/terms', builder: (_, _) => const BuyerInfoScreen('terms')),
            GoRoute(path: '/legal/privacy', builder: (_, _) => const BuyerInfoScreen('privacy')),
          ],
        ),
      ],
    ),
  ],
);

class SadohodApp extends StatelessWidget {
  const SadohodApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Садоход',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    routerConfig: appRouter,
    builder: (context, child) => const bool.fromEnvironment('FIGMA_PREVIEW')
        ? child!
        : BuyerDevicePreviewLab(child: child!),
  );
}

class _AppShell extends StatelessWidget {
  const _AppShell(this.shell);
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context) => Scaffold(
    // Figma top bars (75 px, home header 402→75 px) already include the
    // Dynamic Island/status-bar region. Adding the device's top SafeArea here
    // shifts every buyer screen down a second time (62 px on iPhone 16 Pro).
    // Keep the bottom SafeArea below unchanged for the system gesture area.
    body: SafeArea(top: false, bottom: false, child: shell),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        height: 60,
        color: Colors.white,
        child: Row(
          children: [
            for (int i = 0; i < 3; i++)
              Expanded(
                child: Semantics(
                  selected: shell.currentIndex == i,
                  button: true,
                  label: ['Поиск', 'Избранное', 'Личный кабинет'][i],
                  child: InkWell(
                    onTap: () => shell.goBranch(
                      i,
                      initialLocation: i == shell.currentIndex,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: [27.0, 29.167, 33.0][i],
                        height: [27.0, 24.15, 33.0][i],
                        child: DesignIcon(
                          [
                            'v082_tab_search',
                            '4dacc',
                            shell.currentIndex == 2 ? '8be73' : 'f3a3d',
                          ][i],
                          color: shell.currentIndex == i
                              ? Colors.black
                              : const Color(0xff6c6c6c),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
