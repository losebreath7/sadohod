import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/build_info.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'product_actions.dart';
import 'draft_store.dart';
import 'draft_form.dart';
import 'seller_telegram_chat.dart';

import 'package:sadohod_shared_core/chat_widgets.dart';

const beige = Color(0xFFF0EFEB), brown = Color(0xFF48352D);
const muted = Color(0xFFA5A5A5),
    blue = Color(0xFFA5BCD6),
    red = Color(0xFF670D10);
const preview = bool.fromEnvironment('FIGMA_PREVIEW');
typedef RowData = Map<String, dynamic>;

// The API may omit status for already approved pavilion records.
// Explicit pending/rejected statuses must never unlock the product catalogue.
bool isApprovedPavilion(RowData pavilion) {
  final status = '${pavilion['status'] ?? 'approved'}'.trim().toLowerCase();
  return status == 'approved' || status == 'active';
}

List<RowData> rows(dynamic value) => (value is List ? value : const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();
TextStyle type(double size, {bool bold = false, Color color = Colors.black}) =>
    TextStyle(
      fontFamily: 'Helvetica',
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color,
      height: 1.15,
    );
Widget label(
  String value,
  double size, {
  bool bold = false,
  Color color = Colors.black,
  TextAlign align = TextAlign.left,
}) => Text(
  value,
  style: type(size, bold: bold, color: color),
  textAlign: align,
);
Widget asset(String name, {double? width, double? height}) => SvgPicture.asset(
  'assets/figma/$name',
  width: width,
  height: height,
  fit: BoxFit.contain,
);
Widget tap(Widget child, VoidCallback? action, {String? name}) => Semantics(
  button: true,
  label: name,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: action,
    child: child,
  ),
);
Widget pill(
  String title,
  VoidCallback? action, {
  Color color = brown,
  String? icon,
}) => tap(
  Container(
    height: 48,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          asset(icon, width: 19, height: 19),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: label(title, 16, color: Colors.white, align: TextAlign.center),
        ),
      ],
    ),
  ),
  action,
  name: title,
);

/// The white background includes the system inset; the icon row never does.
class SellerTabBar extends StatelessWidget {
  const SellerTabBar({super.key, required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: tap(
                  Center(
                    child: asset(
                      i == 0
                          ? (index == 0 ? '83ac5.svg' : 'aa629.svg')
                          : i == 1
                          ? (index == 1 ? '342fc.svg' : 'c4e1e.svg')
                          : (index == 2 ? 'eb441.svg' : 'a5de6.svg'),
                      width: 27,
                      height: 27,
                    ),
                  ),
                  () => onSelect(i),
                  name: ['Магазины', 'Камера', 'Профиль'][i],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class V3Header extends StatelessWidget {
  const V3Header({
    super.key,
    required this.title,
    required this.back,
    this.trailing,
    this.large = false,
  });
  final String title;
  final VoidCallback back;
  final Widget? trailing;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final height = math.max(100.0, top + 44);
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.bottomCenter,
                child: asset(
                  'aa689.svg',
                  width: MediaQuery.sizeOf(context).width + 7.572,
                  height: height,
                ),
              ),
            ),
          ),
          Positioned(
            left: 60,
            right: 60,
            bottom: 8,
            child: label(
              title,
              large ? 22 : 16,
              bold: true,
              align: TextAlign.center,
            ),
          ),
          Positioned(
            left: 18,
            bottom: 5,
            width: 42,
            height: 42,
            child: tap(
              Align(
                alignment: Alignment.topCenter,
                child: label('‹', 30, bold: true),
              ),
              back,
              name: 'Назад',
            ),
          ),
          if (trailing != null)
            Positioned(
              right: 18,
              bottom: 3,
              width: 44,
              height: 44,
              child: Center(child: trailing!),
            ),
        ],
      ),
    );
  }
}

class V3Field extends StatelessWidget {
  const V3Field(
    this.title,
    this.controller, {
    super.key,
    this.keyboard,
    this.readOnly = false,
    this.showTitle = true,
    this.height = 60,
    this.onChanged,
  });
  final String title;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final bool readOnly;
  final bool showTitle;
  final double height;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(5),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Stack(
      children: [
        if (showTitle)
          Positioned(
            top: 8,
            left: 0,
            child: IgnorePointer(child: label(title, 12, color: muted)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            keyboardType: keyboard,
            onChanged: onChanged,
            maxLines: 1,
            textAlignVertical: TextAlignVertical.center,
            style: type(14),
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    ),
  );
}

class SellerV3 extends StatefulWidget {
  const SellerV3({super.key, required this.api, this.initialFrame});
  final SellerApi api;
  final String? initialFrame;
  @override
  State<SellerV3> createState() => _SellerV3State();
}

class _SellerV3State extends State<SellerV3> with WidgetsBindingObserver {
  String screen = 'welcome';
  final history =
      <
        ({
          String screen,
          bool searching,
          bool selecting,
          bool hidden,
          bool actions,
          String query,
        })
      >[];
  bool busy = false,
      loading = false,
      searching = false,
      selecting = false,
      hidden = false,
      actions = false;
  RowData account = {}, merchant = {}, pavilion = {}, product = {};
  List<RowData> pavilions = [], requests = [], products = [];
  final selected = <String>{}, destinations = <String>{};
  final controllers = <String, TextEditingController>{};
  final photos = <XFile>[];
  String? draftId;
  late final ProductActions productActions = ProductActions(widget.api);
  ProductSaveSession saveSession = ProductSaveSession();
  final deletedPhotos = <String>{};
  final photoReplacements = <XFile, String>{};
  RowData originalProduct = {};
  String initialPrice = '';
  final saleModes = <String>{'retail'};
  final listingModes = <String, Set<String>>{};
  final photoPages = <String, int>{};
  String? selectionPavilionId;
  String? saleFilter;
  final draftStore = DraftStore();
  final draftPhotoCache = <XFile, Future<String>>{};
  Future<void> draftWrites = Future.value();
  Timer? draftTimer;
  String? activeDraftKey;
  String? draftToken;
  bool restoringDraft = false,
      draftWarningShown = false,
      draftCompleted = false;
  String activeChatSection = 'поддержка';
  // Explicit initialFrame is a visual-test/preview entry point. No API calls
  // or draft writes should occur when rendering these static design frames.
  bool get testPreview => preview || widget.initialFrame != null;
  bool get isProductForm => screen == 'newProduct' || screen == 'editProduct';

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    scheduleDraft();
  }

  void scheduleDraft() {
    if (testPreview ||
        restoringDraft ||
        !isProductForm ||
        activeDraftKey == null ||
        !widget.api.signedIn)
      return;
    draftTimer?.cancel();
    draftTimer = Timer(const Duration(seconds: 1), () {
      persistDraft().catchError(draftFailure);
    });
  }

  void draftFailure(Object error) {
    if (!mounted || draftWarningShown) return;
    draftWarningShown = true;
    failure(
      Exception(
        'Не удалось сохранить форму на устройстве. Не закрывайте её до успешной отправки.',
      ),
    );
  }

  Future<void> persistDraft() {
    draftTimer?.cancel();
    if (testPreview ||
        restoringDraft ||
        activeDraftKey == null ||
        !isProductForm ||
        !widget.api.signedIn)
      return Future.value();
    final key = activeDraftKey!;
    final completed = draftCompleted;
    final session = ProductSaveSession()
      ..productId = saveSession.productId
      ..createKey = saveSession.createKey;
    session.photoKeys.addAll(saveSession.photoKeys);
    session.finishedPhotos.addAll(saveSession.finishedPhotos);
    session.requestKeys.addAll(saveSession.requestKeys);
    final form = DraftForm(
      title: c('title').text,
      price: c('price').text,
      initialPrice: initialPrice,
      product: Map<String, dynamic>.from(
        jsonDecode(jsonEncode(product)) as Map,
      ),
      original: Map<String, dynamic>.from(
        jsonDecode(jsonEncode(originalProduct)) as Map,
      ),
      destinations: Set.of(destinations),
      deleted: Set.of(deletedPhotos),
      photos: List.of(photos),
      replacements: Map.of(photoReplacements),
      session: session,
      saleModes: saleModes.toList(),
      listingEdits: {
        for (final id in listingModes.keys)
          id: {
            'priceText': c('price:$id').text,
            'sale_modes': listingModes[id]!.toList(),
          },
      },
    );
    final next = draftWrites.then((_) async {
      await draftStore.write(key, {
        ...await form.encode(draftPhotoCache),
        'completed': completed,
      });
      draftWarningShown = false;
    });
    draftWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  Future<void> checkpointDraft() async {
    try {
      await persistDraft();
    } catch (error) {
      draftFailure(error);
    }
  }

  String formKey(String form) {
    final email = '${account['email'] ?? ''}'.trim();
    if (email.isEmpty || !widget.api.signedIn)
      throw StateError('Сначала войдите в аккаунт.');
    return draftStore.key(widget.api.baseUrl, email, form);
  }

  Future<bool> restoreDraft(String form) async {
    if (testPreview) return false;
    await draftWrites;
    final token = widget.api.token;
    final key = formKey(form);
    activeDraftKey = key;
    final data = await draftStore.read(key);
    if (!mounted ||
        token != widget.api.token ||
        activeDraftKey != key ||
        data == null)
      return false;
    if (data['completed'] == true) {
      await draftStore.delete(key);
      return false;
    }
    final restored = DraftForm.decode(data);
    draftCompleted = false;
    restoringDraft = true;
    try {
      product = restored.product;
      originalProduct = restored.original;
      initialPrice = restored.initialPrice;
      saleModes
        ..clear()
        ..addAll(restored.saleModes);
      initializeListingFields();
      for (final entry in restored.listingEdits.entries) {
        c('price:${entry.key}').text = '${entry.value['priceText'] ?? ''}';
        listingModes[entry.key] = Set<String>.from(
          entry.value['sale_modes'] ?? ['retail'],
        );
      }
      c('title').text = restored.title;
      c('price').text = restored.price;
      photos
        ..clear()
        ..addAll(restored.photos);
      destinations
        ..clear()
        ..addAll(restored.destinations);
      deletedPhotos
        ..clear()
        ..addAll(restored.deleted);
      photoReplacements
        ..clear()
        ..addAll(restored.replacements);
      saveSession = restored.session;
      setState(() => screen = form == 'new' ? 'newProduct' : 'editProduct');
    } finally {
      restoringDraft = false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Незавершённый товар восстановлен'),
      ),
    );
    return true;
  }

  Future<void> openEditProduct(RowData value) async {
    if (busy) return;
    if (value['status'] == 'pending' ||
        rows(value['listings']).any((l) => l['status'] == 'pending')) {
      failure(
        Exception(
          'Товар на проверке. Изменения будут доступны после решения модератора.',
        ),
      );
      return;
    }
    try {
      await persistDraft();
      fillProduct(value);
      go('editProduct');
      if (!testPreview) {
        setState(() => busy = true);
        try {
          await restoreDraft('edit:${value['id']}');
        } finally {
          if (mounted) setState(() => busy = false);
        }
      }
    } catch (error) {
      draftFailure(error);
    }
  }

  Future<void> forgetDraft() async {
    draftTimer?.cancel();
    final key = activeDraftKey;
    activeDraftKey = null;
    await draftWrites;
    if (key != null) await draftStore.delete(key);
    draftPhotoCache.clear();
  }

  void authChanged() {
    if (draftToken == widget.api.token) return;
    draftToken = widget.api.token;
    // Captured queued writes retain their original account key. No new snapshot
    // may be written with another account's credentials.
    draftTimer?.cancel();
    activeDraftKey = null;
    restoringDraft = true;
    account = {};
    product = {};
    originalProduct = {};
    photos.clear();
    destinations.clear();
    deletedPhotos.clear();
    photoReplacements.clear();
    draftPhotoCache.clear();
    saveSession = ProductSaveSession();
    c('title').clear();
    c('price').clear();
    saleModes
      ..clear()
      ..add('retail');
    listingModes.clear();
    restoringDraft = false;
    if (mounted && !widget.api.signedIn)
      setState(() {
        screen = 'welcome';
        history.clear();
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed)
      persistDraft().catchError(draftFailure);
    if (state == AppLifecycleState.resumed &&
        widget.api.signedIn &&
        !testPreview &&
        !busy &&
        !loading &&
        [
          'stores',
          'pending',
          'rejected',
          'approved',
          'emptyStores',
        ].contains(screen)) {
      reload(navigate: false);
    }
  }

  bool showSecondPhone = false;
  bool pavilionValidationError = false;
  TextEditingController c(String key) => controllers.putIfAbsent(key, () {
    final controller = TextEditingController();
    if (key.startsWith('price:')) controller.addListener(scheduleDraft);
    return controller;
  });
  String get name => '${account['name'] ?? merchant['shop']?['name'] ?? ''}';
  String get home => !pavilions.any(isApprovedPavilion)
      ? (requests.isNotEmpty ? 'stores' : 'emptyStores')
      : (products.isEmpty ? 'emptyProducts' : 'catalog');
  @override
  void initState() {
    super.initState();
    draftToken = widget.api.token;
    widget.api.addListener(authChanged);
    WidgetsBinding.instance.addObserver(this);
    c('title').addListener(scheduleDraft);
    c('price').addListener(scheduleDraft);
    if (testPreview) {
      seed();
    } else if (widget.api.signedIn) {
      reload();
    }
  }

  @override
  void dispose() {
    persistDraft().catchError((Object _) {});
    draftTimer?.cancel();
    widget.api.removeListener(authChanged);
    WidgetsBinding.instance.removeObserver(this);
    for (final v in controllers.values) {
      v.dispose();
    }
    super.dispose();
  }

  void seed() {
    account = {'name': 'martini felesk', 'email': 'example@mail.ru'};
    merchant = {
      'shop': {'id': 'preview', 'name': 'martini felesk'},
    };
    pavilions = [
      for (var i = 1; i <= 4; i++)
        {
          'id': 'p$i',
          'zone': 'Вещевые ряды',
          'code': 'Б-2В-8$i',
          'status': 'approved',
        },
    ];
    requests = [
      {'id': 'r1', 'code': 'Б-2В-86', 'status': 'pending'},
      {
        'id': 'r2',
        'code': 'Б-2В-86',
        'status': 'rejected',
        'note': 'на фото не виден номер павильона.',
      },
    ];
    products = [
      for (var i = 0; i < 4; i++)
        {
          'id': 'v$i',
          'title': 'alo кроссовки',
          'category': 'Обувь',
          'images': [
            'asset:${['bfc4a.png', 'eb9f2.png', 'f46f5.png', '62cf6.png'][i]}',
          ],
          'status': 'approved',
          'listings': [
            {
              'id': 'l$i',
              'pavilion_id': 'p1',
              'price': 300,
              'status': 'approved',
              'pavilion': pavilions.first,
              'sale_modes': ['retail'],
            },
          ],
        },
    ];
    const map = {
      '366:15805': 'profile',
      '366:15855': 'address',
      '366:15903': 'pending',
      '366:15936': 'approved',
      '366:15969': 'capture',
      '366:16062': 'editProduct',
      '366:17304': 'newProduct',
      '366:16208': 'editProfile',
      '366:16277': 'catalog',
      '388:17542': 'select',
      '388:17641': 'selected',
      '395:18004': 'actions',
      '366:16333': 'stores',
      '366:17044': 'shop',
      '398:18182': 'hidden',
      '366:16467': 'rejected',
      '366:16501': 'fixAddress',
      '366:16552': 'manualAddress',
      '398:18347': 'selectHidden',
      '398:18420': 'selectedHidden',
      '398:18510': 'actionsHidden',
      '407:442': 'move',
      '407:521': 'duplicate',
      '410:497': 'delete',
      '419:530': 'emptyStores',
      '419:620': 'emptyProducts',
      '428:567': 'firstProduct',
      '440:569': 'search',
      '440:641': 'searchEmpty',
      '440:713': 'shopSearch',
      '440:785': 'shopSearchEmpty',
      '487:613': 'welcome',
      '487:614': 'email',
      '487:615': 'code',
      '487:616': 'name',
      '494:614': 'emailFilled',
      '494:630': 'codeFilled',
      '494:651': 'nameFilled',
    };
    screen =
        map[widget.initialFrame ?? Uri.base.queryParameters['screen']] ??
        'emptyStores';
    pavilion = pavilions.first;
    product = products.first;
    if (screen == 'emptyStores') {
      // Preview must reflect the first-run state, not the seeded catalogue.
      pavilions = [];
      requests = [];
      products = [];
      pavilion = {};
      product = {};
    }
    if (screen == 'emptyProducts') products = [];
    if (screen == 'delete' || screen == 'move' || screen == 'duplicate') {
      selected.addAll(products.map((p) => '${p['id']}'));
    }
    if (screen == 'firstProduct') {
      products = products.take(1).toList();
      screen = 'catalog';
    }
    if (screen.contains('Hidden') || screen == 'hidden') hidden = true;
    if ([
      'select',
      'selected',
      'actions',
      'selectHidden',
      'selectedHidden',
      'actionsHidden',
    ].contains(screen)) {
      selecting = true;
      if (screen.startsWith('selected') || screen.startsWith('actions'))
        selected.addAll(products.map((p) => '${p['id']}'));
      actions = screen.startsWith('actions');
      screen = 'catalog';
    }
    if ([
      'search',
      'searchEmpty',
      'shopSearch',
      'shopSearchEmpty',
    ].contains(screen)) {
      searching = true;
      if (!screen.endsWith('Empty')) products = products.take(1).toList();
      c('search').text = screen.endsWith('Empty') ? 'куртка' : 'alo';
      screen = screen.startsWith('shop') ? 'shop' : 'catalog';
    }
    if (screen == 'hidden') screen = 'shop';
    if (screen == 'emailFilled') {
      screen = 'email';
      c('email').text = 'example@mail.ru';
    }
    if (screen == 'codeFilled') {
      screen = 'code';
      c('code').text = '123456';
    }
    if (screen == 'nameFilled') {
      screen = 'name';
      c('name').text = 'Мартини';
    }
    if (screen == 'newProduct') {
      product = {};
    }
    if (screen == 'editProfile') fillProfile();
    if (screen == 'editProduct') fillProduct(product);
  }

  Future<bool> reload({bool navigate = true}) async {
    if (testPreview) return true;
    if (loading) return false;
    setState(() => loading = true);
    final token = widget.api.token;
    try {
      final loadedAccount = await widget.api.call('/account');
      final loadedMerchant = await widget.api.call('/merchant/me');
      if (!mounted || token != widget.api.token) return false;
      account = loadedAccount;
      merchant = loadedMerchant;
      if (merchant['shop'] != null) {
        final r = await Future.wait([
          widget.api.call('/merchant/pavilions'),
          widget.api.call('/merchant/products'),
        ]);
        if (!mounted || token != widget.api.token) return false;
        pavilions = rows(r[0]['items']);
        // Only confirmed trading locations unlock the product home screen.
        // Pending/rejected locations belong to the applications flow.
        pavilions = pavilions.where(isApprovedPavilion).toList();
        requests = rows(r[0]['requests'])
            .where((r) => r['status'] != 'approved')
            .map((r) => {...r, '_requestType': 'pavilion'})
            .toList();
        products = rows(r[1]['items']);
      } else {
        pavilions = [];
        requests = rows(merchant['applications'])
            .where((r) => r['status'] != 'approved')
            .map((r) => {...r, '_requestType': 'application'})
            .toList();
        products = [];
      }
      if (mounted)
        setState(() {
          loading = false;
          if (navigate) {
            history.clear();
            screen = name.trim().isEmpty ? 'name' : home;
          } else if (['pending', 'rejected', 'approved'].contains(screen)) {
            final matches = requests.where(
              (r) =>
                  r['id'] == pavilion['id'] &&
                  r['_requestType'] == pavilion['_requestType'],
            );
            if (matches.isNotEmpty) {
              pavilion = matches.first;
              screen = pavilion['status'] == 'rejected'
                  ? 'rejected'
                  : 'pending';
            } else {
              final confirmed = pavilions.where(
                (p) =>
                    '${p['zone']}'.trim().toLowerCase() ==
                        '${pavilion['zone']}'.trim().toLowerCase() &&
                    '${p['code']}'.trim().toLowerCase() ==
                        '${pavilion['code']}'.trim().toLowerCase(),
              );
              if (confirmed.isNotEmpty) {
                pavilion = confirmed.first;
                screen = 'approved';
              } else {
                screen = home;
              }
            }
          } else if (screen == 'emptyStores') {
            screen = home;
          }
        });
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        failure(e);
      }
      return false;
    }
  }

  void go(String next) {
    if (!testPreview &&
        next == 'address' &&
        merchant['shop'] == null &&
        requests.isNotEmpty)
      next = 'stores';
    // Pavilion approval is mandatory in both production and design previews.
    if (next == 'capture' && !pavilions.any(isApprovedPavilion)) {
      next = requests.isNotEmpty ? 'stores' : 'address';
    }
    if (next == 'address') {
      for (final key in [
        'zone',
        'building',
        'floor',
        'line',
        'number',
        'manual',
      ])
        c(key).clear();
    }
    if (isProductForm) persistDraft().catchError(draftFailure);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      history.add((
        screen: screen,
        searching: searching,
        selecting: selecting,
        hidden: hidden,
        actions: actions,
        query: c('search').text,
      ));
      screen = next;
      if (['shop', 'catalog', 'stores'].contains(next)) {
        selected.clear();
        selectionPavilionId = null;
        saleFilter = null;
        hidden = false;
      }
      searching = false;
      selecting = false;
      actions = false;
    });
    if (!testPreview &&
        !busy &&
        !loading &&
        ['stores', 'pending', 'rejected', 'approved'].contains(next)) {
      reload(navigate: false);
    }
  }

  void back() {
    if (isProductForm) persistDraft().catchError(draftFailure);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (actions) {
        actions = false;
      } else if (selecting) {
        selecting = false;
        selected.clear();
      } else if (searching) {
        searching = false;
        c('search').clear();
      } else {
        if (history.isNotEmpty) {
          final previous = history.removeLast();
          screen = previous.screen;
          searching = previous.searching;
          selecting = previous.selecting;
          hidden = previous.hidden;
          actions = previous.actions;
          c('search').text = previous.query;
        } else {
          screen = widget.api.signedIn || testPreview ? home : 'welcome';
        }
      }
    });
  }

  void returnToStores() {
    setState(() {
      history.clear();
      screen = 'stores';
      searching = false;
      selecting = false;
      actions = false;
    });
    if (!testPreview && !busy && !loading) reload(navigate: false);
  }

  Future<void> tab(int index) async {
    if (busy) return;
    try {
      await persistDraft();
    } catch (error) {
      draftFailure(error);
      return;
    }
    if (!testPreview && index != 2 && !await reload(navigate: false)) return;
    if (!mounted) return;
    setState(() {
      history.clear();
      selecting = false;
      searching = false;
      actions = false;
      hidden = false;
      saleFilter = null;
      selectionPavilionId = null;
      selected.clear();
      c('search').clear();
      screen = index == 2
          ? 'profile'
          : index == 1
          ? (pavilions.isEmpty
                ? (requests.isNotEmpty ? 'stores' : 'address')
                : 'capture')
          : home;
    });
    if (index == 1 && pavilions.isNotEmpty && !testPreview) {
      setState(() => busy = true);
      try {
        await restoreDraft('new');
      } catch (error) {
        draftFailure(error);
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
  }

  void failure(Object error) {
    debugPrint('Seller V3: $error');
    if (!mounted) return;
    final message = error.toString().replaceFirst(
      RegExp(r'^(Exception|Bad state): '),
      '',
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      if (e is SellerApiException && e.statusCode == 409)
        await reload(navigate: false);
      failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void missing([String section = '']) {
    if (section == 'поддержка' || section == 'сотрудничество') {
      activeChatSection = section;
      go('sellerChat');
    } else {
      go('missing');
    }
  }

  Future<void> auth() async => run(() async {
    if (screen == 'welcome') {
      go('email');
      return;
    }
    if (screen == 'email') {
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
          .hasMatch(c('email').text.trim()))
        return;
      if (!testPreview) await widget.api.requestCode(c('email').text);
      go('code');
    } else if (screen == 'code') {
      if (c('code').text.length != 6) return;
      if (!testPreview) {
        await widget.api.verify(c('email').text, c('code').text);
        await reload();
      } else
        go('name');
    } else if (screen == 'name') {
      if (c('name').text.trim().isEmpty) return;
      if (!testPreview)
        await widget.api.call(
          '/account/profile',
          method: 'POST',
          body: {'name': c('name').text.trim()},
        );
      account['name'] = c('name').text.trim();
      if (testPreview)
        go('emptyStores');
      else
        await reload();
    }
  });
  void fillProfile() {
    c('profileName').text = name;
    c('phone').text = '${merchant['shop']?['contact'] ?? ''}';
    c('phone2').clear();
    showSecondPhone = false;
    c('profileEmail').text = '${account['email'] ?? ''}';
  }

  void fillProduct(RowData p) {
    activeDraftKey = null;
    product = Map<String, dynamic>.from(p);
    originalProduct = Map<String, dynamic>.from(p);
    saveSession = ProductSaveSession();
    draftCompleted = false;
    deletedPhotos.clear();
    photoReplacements.clear();
    photos.clear();
    c('title').text = '${p['title'] ?? ''}';
    final ls = rows(p['listings']);
    c('price').text = ls.isEmpty ? '' : '${ls.first['price'] ?? ''}';
    saleModes
      ..clear()
      ..addAll(
        ls.isEmpty
            ? ['retail']
            : List<String>.from(ls.first['sale_modes'] ?? ['retail']),
      );
    initializeListingFields();
    initialPrice = c('price').text;
    destinations
      ..clear()
      ..addAll(ls.map((l) => '${l['pavilion_id']}'));
  }

  void initializeListingFields() {
    listingModes.clear();
    for (final l in rows(originalProduct['listings'])) {
      final id = '${l['pavilion_id']}';
      c('price:$id').text = '${l['price'] ?? ''}';
      listingModes[id] = Set<String>.from(l['sale_modes'] ?? ['retail']);
    }
  }

  int? parsePrice(String text) {
    if (text.trim().isEmpty) return null;
    final value = int.tryParse(text.trim());
    if (value == null || value < 0 || value > 100000000) {
      throw Exception(
        'Цена: целое число от 0 до 100 000 000 ₽ или пустое поле.',
      );
    }
    return value;
  }

  Widget saleModeFields(Set<String> modes) => Row(
    children: [
      for (final mode in ['wholesale', 'retail']) ...[
        tap(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: modes.contains(mode) ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: label(
              mode == 'wholesale' ? 'опт' : 'розница',
              12,
              color: modes.contains(mode) ? Colors.white : Colors.black,
            ),
          ),
          () => setState(() {
            if (modes.contains(mode)) {
              if (modes.length > 1) modes.remove(mode);
            } else {
              modes.add(mode);
            }
          }),
        ),
        const SizedBox(width: 8),
      ],
    ],
  );

  String address(RowData p) => '${p['code'] ?? ''}';
  Future<void> sendAddress() async => run(() async {
    final fixing = screen == 'fixAddress';
    final zone = c('zone').text.trim(),
        code = [
          c('building').text.trim(),
          c('floor').text.trim() + c('line').text.trim(),
          c('number').text.trim(),
        ].where((s) => s.isNotEmpty).join('-');
    if (screen == 'manualAddress') {
      throw StateError('API не поддерживает ручной адрес без номера павильона');
    }
    if (zone.isEmpty || c('number').text.trim().isEmpty) {
      throw Exception('Укажите торговую зону и номер павильона.');
    }
    final application = fixing
        ? pavilion['_requestType'] != 'pavilion'
        : merchant['shop'] == null;
    if (fixing && pavilion['id'] == null && !testPreview)
      throw Exception('Заявка не найдена. Откройте её из списка магазинов.');
    final payload = {'zone': zone, 'code': code};
    RowData result = {};
    if (!testPreview) {
      result = await widget.api.call(
        fixing
            ? (application
                  ? '/merchant/applications/${pavilion['id']}'
                  : '/merchant/pavilions/requests/${pavilion['id']}')
            : (application ? '/merchant/applications' : '/merchant/pavilions'),
        method: fixing ? 'PUT' : 'POST',
        body: application
            ? {
                ...payload,
                'shop_name': name,
                'contact': '${account['email'] ?? ''}',
              }
            : payload,
      );
    }
    pavilion = {
      ...payload,
      ...result,
      'status': 'pending',
      '_requestType': application ? 'application' : 'pavilion',
    };
    if (!testPreview) await reload(navigate: false);
    if (mounted)
      setState(() {
        history.clear();
        screen = 'pending';
      });
  });
  Future<void> pick({bool camera = false}) async => run(() async {
    if (screen != 'capture' && saveSession.photoKeys.isNotEmpty) {
      throw Exception(
        'Сначала повторите сохранение начатой загрузки. Фотографии можно изменить после её завершения.',
      );
    }
    final picker = ImagePicker();
    final chosen = camera
        ? [await picker.pickImage(source: ImageSource.camera)]
              .whereType<XFile>()
              .toList()
        : await picker.pickMultiImage();
    if (chosen.isEmpty) return;
    if (screen == 'capture') photos.clear();
    photos.addAll(chosen);
    if (mounted) {
      if (screen == 'capture') {
        if (!testPreview) activeDraftKey = formKey('new');
        product = {};
        originalProduct = {};
        saveSession = ProductSaveSession();
        draftCompleted = false;
        deletedPhotos.clear();
        photoReplacements.clear();
        initialPrice = '';
        draftId = null;
        c('title').clear();
        c('price').clear();
        saleModes
          ..clear()
          ..add('retail');
        listingModes.clear();
        destinations.clear();
        go('newProduct');
      } else
        setState(() {});
    }
  });
  void removePhoto(int index, int existingCount) {
    if (busy) return;
    if (saveSession.photoKeys.isNotEmpty) {
      failure(Exception('Сначала повторите сохранение начатой загрузки.'));
      return;
    }
    if (index >= existingCount) {
      setState(() => photos.removeAt(index - existingCount));
      return;
    }
    final items = rows(product['image_items']);
    if (items.length != existingCount) {
      failure(
        Exception('Обновите сервер до пакета 18 и откройте товар заново.'),
      );
      return;
    }
    deletedPhotos.add('${items[index]['id']}');
    final urls = List<String>.from(product['images'] ?? []);
    urls.removeAt(index);
    items.removeAt(index);
    setState(() {
      product['images'] = urls;
      product['image_items'] = items;
    });
  }

  Future<void> replaceProductPhoto(int index, int existingCount) async {
    if (busy) return;
    if (saveSession.photoKeys.isNotEmpty) {
      failure(Exception('Сначала повторите сохранение начатой загрузки.'));
      return;
    }
    final replacement = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (replacement == null || !mounted) return;
    if (index < existingCount) {
      final items = rows(product['image_items']);
      if (items.length != existingCount) {
        failure(Exception('Обновите сервер и откройте товар заново.'));
        return;
      }
      photoReplacements[replacement] = '${items[index]['id']}';
      removePhoto(index, existingCount);
      setState(() => photos.add(replacement));
    } else {
      final old = photos[index - existingCount];
      final originalId = photoReplacements.remove(old);
      if (originalId != null) photoReplacements[replacement] = originalId;
      setState(() => photos[index - existingCount] = replacement);
    }
  }

  Future<void> finishAction(String message) async {
    // Complete the operation before refreshing; a refresh error must not repeat it.
    if (!mounted) return;
    setState(() {
      selected.clear();
      destinations.clear();
      actions = false;
      selecting = false;
      history.clear();
      screen = 'catalog';
    });
    await reload(navigate: false);
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 2), content: Text(message)),
      );
  }

  Future<void> deleteProducts({bool single = false}) async => run(() async {
    final ids = single ? ['${product['id']}'] : selected.toList()
      ..sort();
    if (ids.isEmpty || ids.contains('null'))
      throw Exception('Выберите товары.');
    if (testPreview) {
      products.removeWhere((p) => ids.contains('${p['id']}'));
    } else {
      await productActions.batch('delete', {'product_ids': ids});
    }
    await finishAction('Товары удалены');
  });

  String get sourcePavilionId {
    if (selectionPavilionId != null) return selectionPavilionId!;
    Set<String>? common;
    for (final p in products.where((p) => selected.contains('${p['id']}'))) {
      final locations = rows(p['listings'])
          .map((l) => '${l['pavilion_id']}')
          .toSet();
      common = common == null ? locations : common.intersection(locations);
    }
    return common != null && common.length == 1 ? common.single : '';
  }

  Future<void> distributeProducts() async => run(() async {
    final duplicate = screen == 'duplicate';
    final ids = selected.toList()..sort();
    final targets = destinations.toList()..sort();
    if (ids.isEmpty || targets.isEmpty)
      throw Exception('Выберите товары и магазин назначения.');
    final source = sourcePavilionId;
    if (source.isEmpty)
      throw Exception('Откройте исходный магазин и выберите товары в нём.');
    if (duplicate && targets.length > 10)
      throw Exception('Можно выбрать не больше 10 павильонов.');
    if (!duplicate && targets.single == source)
      throw Exception('Выберите другой магазин.');
    if (!testPreview) {
      await productActions.batch(duplicate ? 'copy' : 'move', {
        'product_ids': ids,
        'source_pavilion_id': source,
        if (duplicate)
          'destination_pavilion_ids': targets
        else
          'destination_pavilion_id': targets.single,
      });
    }
    await finishAction(
      duplicate
          ? 'Копии опубликованы'
          : 'Товары перенесены. Публикация — после проверки',
    );
  });

  Future<void> saveProduct() async => run(() async {
    if (destinations.isEmpty) {
      setState(() => pavilionValidationError = true);
      return;
    }
    final price = parsePrice(c('price').text);
    final edits = <String, RowData>{
      for (final id in destinations.where(listingModes.containsKey))
        id: {
          'price': parsePrice(c('price:$id').text),
          'sale_modes': listingModes[id]!.toList(),
        },
    };
    if (testPreview) {
      final id =
          product['id'] ?? 'preview-${DateTime.now().microsecondsSinceEpoch}';
      products.removeWhere((p) => p['id'] == id);
      products.insert(0, {
        'id': id,
        'title': c('title').text,
        'images': [],
        'status': 'pending',
        'listings': [
          for (final destination in destinations)
            {'pavilion_id': destination, 'price': price, 'status': 'pending'},
        ],
      });
    } else {
      final saved = await productActions.save(
        session: saveSession,
        original: originalProduct,
        title: c('title').text,
        price: price,
        saleModes: saleModes.toList(),
        listingEdits: edits,
        priceChanged: c('price').text != initialPrice,
        destinations: Set.of(destinations),
        photos: List.of(photos),
        deletedPhotos: Set.of(deletedPhotos),
        replacements: Map.of(photoReplacements),
        checkpoint: checkpointDraft,
      );
      product = saved;
    }
    draftCompleted = true;
    await checkpointDraft();
    try {
      await forgetDraft();
    } catch (error) {
      draftFailure(error);
    }
    photos.clear();
    deletedPhotos.clear();
    photoReplacements.clear();
    draftId = null;
    saveSession = ProductSaveSession();
    await finishAction('Товар отправлен на модерацию');
  });
  List<RowData> get shown => products.where((p) {
    final ls = rows(p['listings']);
    final local = screen == 'shop'
        ? ls.where((l) => l['pavilion_id'] == pavilion['id']).toList()
        : ls;
    if (screen == 'shop' && local.isEmpty) return false;
    if (hidden && !local.any((l) => l['status'] == 'paused'))
      return testPreview;
    if (screen == 'shop' &&
        !hidden &&
        !(p['status'] == 'approved' &&
            local.any(
              (l) => l['published'] == true || l['status'] == 'approved',
            )))
      return false;
    if (saleFilter != null &&
        !local.any(
          (l) => (l['sale_modes'] as List? ?? []).contains(saleFilter),
        ))
      return false;
    if (screen == 'shop' &&
        !hidden &&
        local.isNotEmpty &&
        local.every((l) => l['status'] == 'paused'))
      return false;
    return !searching ||
        '${p['title']}'.toLowerCase().contains(c('search').text.toLowerCase());
  }).toList();
  @override
  Widget build(BuildContext context) {
    if (screen == 'missing')
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !busy) back();
        },
        child: const Scaffold(
          backgroundColor: Colors.white,
          body: Center(child: Text('дизайн в разработке')),
        ),
      );
    final authScreen = ['welcome', 'email', 'code', 'name'].contains(screen);
    final index = ['profile', 'editProfile', 'sellerChat'].contains(screen)
        ? 2
        : ['capture', 'newProduct', 'editProduct'].contains(screen)
        ? 1
        : 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy) back();
      },
      child: Scaffold(
        backgroundColor: beige,
        resizeToAvoidBottomInset: true,
        bottomNavigationBar: authScreen || selecting && selected.isEmpty
            ? null
            : SellerTabBar(
                index: index,
                onSelect: (index) {
                  if (!busy) tab(index);
                },
              ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  AbsorbPointer(absorbing: busy, child: body()),
                  if (actions) actionPanel(),
                  if (busy)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
      ),
    );
  }

  Widget body() {
    switch (screen) {
      case 'welcome':
      case 'email':
      case 'code':
      case 'name':
        return authBody();
      case 'profile':
        return profileBody();
      case 'editProfile':
        return profileEdit();
      case 'emptyStores':
        return emptyStores();
      case 'emptyProducts':
        return emptyProducts();
      case 'stores':
        return storeList();
      case 'address':
      case 'fixAddress':
      case 'manualAddress':
        return addressBody();
      case 'pending':
      case 'approved':
      case 'rejected':
        return statusBody();
      case 'capture':
        return captureBody();
      case 'newProduct':
      case 'editProduct':
        return productEditor();
      case 'move':
      case 'duplicate':
        return bulkBody();
      case 'sellerChat':
        return Column(
          children: [
            SadohodChatHeader(title: activeChatSection, onBack: back),
            Expanded(
              child: SellerTelegramChat(
                key: ValueKey(activeChatSection),
                api: widget.api,
                kind: activeChatSection == 'поддержка'
                    ? 'support'
                    : 'cooperation',
              ),
            ),
          ],
        );
      case 'delete':
        return Center(child: deleteDialog());
      default:
        return catalog();
    }
  }

  Widget page(
    String title,
    Widget content, {
    Widget? trailing,
    bool large = false,
    VoidCallback? onBack,
  }) => Column(
    children: [
      V3Header(
        title: title,
        back: onBack ?? back,
        trailing: trailing,
        large: large,
      ),
      Expanded(child: content),
    ],
  );
  Widget scroll(
    Widget child, {
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 30),
  }) => SingleChildScrollView(padding: padding, child: child);
  Widget authBody() {
    if (screen == 'welcome')
      return LayoutBuilder(
        builder: (ctx, b) => SingleChildScrollView(
          child: SizedBox(
            height: math.max(700, b.maxHeight),
            child: Stack(
              children: [
                Positioned(
                  top: 212,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: asset('72a36.svg', width: 90, height: 90),
                  ),
                ),
                Positioned(
                  top: 336,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: asset('cfac0.svg', width: 255, height: 34),
                  ),
                ),
                Positioned(
                  top: 387,
                  left: 30,
                  right: 30,
                  child: label(
                    'для продавцов',
                    15,
                    color: muted,
                    align: TextAlign.center,
                  ),
                ),
                Positioned(
                  left: 30,
                  right: 30,
                  bottom: 81,
                  child: pill('продолжить', auth),
                ),
              ],
            ),
          ),
        ),
      );
    final isEmail = screen == 'email', isCode = screen == 'code';
    return page(
      isEmail
          ? 'вход'
          : isCode
          ? 'подтвердить почту'
          : 'создать профиль',
      scroll(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: isEmail ? 50 : 53),
            label(
              isEmail
                  ? 'войти или зарегистрироваться'
                  : isCode
                  ? 'введите код из письма'
                  : 'как к вам обращаться?',
              20,
              bold: true,
            ),
            const SizedBox(height: 15),
            label(
              isEmail
                  ? 'Укажите почту — отправим код для входа.'
                  : isCode
                  ? 'Мы отправили 6-значный код на вашу почту.'
                  : 'Это имя будет отображаться в вашем профиле.',
              13,
              color: muted,
            ),
            const SizedBox(height: 48),
            if (isCode)
              codeInput()
            else
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: c(isEmail ? 'email' : 'name'),
                builder: (context, value, child) => V3Field(
                  isEmail ? 'email' : 'имя',
                  c(isEmail ? 'email' : 'name'),
                  showTitle: value.text.isEmpty,
                  keyboard: isEmail
                      ? TextInputType.emailAddress
                      : TextInputType.name,
                ),
              ),
            SizedBox(height: isCode ? 40 : 31),
            pill(
              isEmail
                  ? 'получить код'
                  : isCode
                  ? 'подтвердить'
                  : 'продолжить',
              auth,
            ),
            if (isCode) ...[
              const SizedBox(height: 25),
              Center(
                child: tap(
                  label('отправить код ещё раз', 13, color: brown),
                  () => run(() async {
                    if (!testPreview)
                      await widget.api.requestCode(c('email').text);
                    if (mounted)
                      await showDialog<void>(
                        context: context,
                        barrierColor: Colors.transparent,
                        builder: (ctx) => Center(
                          child: SizedBox(
                            width: 280,
                            child: pill(
                              'код отправлен повторно',
                              () => Navigator.pop(ctx),
                            ),
                          ),
                        ),
                      );
                  }),
                ),
              ),
              const SizedBox(height: 22),
              Center(
                child: tap(label('изменить почту', 13, color: muted), () {
                  c('code').clear();
                  back();
                }),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget codeInput() => SizedBox(
    height: 56,
    child: Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < 6; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: label(
                    c('code').text.length > i ? '•' : '',
                    23,
                    bold: true,
                    color: brown,
                  ),
                ),
              ),
            ],
          ],
        ),
        TextField(
          controller: c('code'),
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Colors.transparent),
          cursorColor: Colors.transparent,
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
          ),
        ),
      ],
    ),
  );
  Widget emptyStores() => LayoutBuilder(
    builder: (ctx, b) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: b.maxHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            30,
            math.max(220, MediaQuery.paddingOf(ctx).top + 140),
            30,
            40,
          ),
          child: Column(
            children: [
              label(
                'у вас пока нет магазинов',
                18,
                bold: true,
                align: TextAlign.center,
              ),
              const SizedBox(height: 13),
              label(
                'Добавьте магазин, чтобы размещать товары.',
                13,
                color: muted,
                align: TextAlign.center,
              ),
              const SizedBox(height: 61),
              pill('добавить магазин', () => go('address')),
            ],
          ),
        ),
      ),
    ),
  );
  Widget emptyProducts() => scroll(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 63),
        tap(
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: muted,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                label('мои магазины', 16, color: Colors.white),
                const Icon(Icons.chevron_right, color: Colors.white, size: 26),
              ],
            ),
          ),
          () => go('stores'),
          name: 'Мои магазины',
        ),
        const SizedBox(height: 18),
        pill('добавить первый товар', () => go('capture'), icon: 'd5d93.svg'),
        const SizedBox(height: 35),
        label('все товары', 16, bold: true),
        const SizedBox(height: 105),
        Center(child: label('товаров пока нет', 18, bold: true)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: label(
            'Добавьте первый товар, чтобы его увидели покупатели.',
            13,
            color: muted,
            align: TextAlign.center,
          ),
        ),
      ],
    ),
  );
  Widget profileBody() => scroll(
    Column(
      children: [
        const SizedBox(height: 39),
        SizedBox(
          height: 181,
          child: Stack(
            children: [
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: brown,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Positioned(
                top: 88,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 93,
                    height: 93,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        asset('5c616.svg', width: 93, height: 93),
                        asset('bc604.svg', width: 60, height: 60),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        label(name, 12, bold: true),
        const SizedBox(height: 50),
        for (final item in <List<String>>[
          ['профиль', '1b285.svg'],
          ['поддержка', '2f6e7.svg'],
          ['уведомления', '40c2b.svg'],
          ['настройки', 'f7cee.svg'],
          ['навигация', 'cdb5f.svg'],
          ['сотрудничество', '1aa37.svg'],
        ])
          tap(
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: asset(
                      item[1],
                      width: item[0] == 'профиль' ? 34.621 : 24,
                      height: item[0] == 'профиль' ? 34.621 : 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  label(item[0], 14, color: const Color(0xFF2C1B15)),
                ],
              ),
            ),
            () {
              if (item[0] == 'профиль') {
                fillProfile();
                go('editProfile');
              } else
                missing(item[0]);
            },
          ),
        const SizedBox(height: 24),
        label(SadohodBuild.label, 10, color: muted),
        const SizedBox(height: 12),
      ],
    ),
  );
  Widget profileEdit() => page(
    'профиль',
    scroll(
      Column(
        children: [
          const SizedBox(height: 17),
          SizedBox(
            height: 181,
            child: Stack(
              children: [
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: brown,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Positioned(
                  top: 88,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: tap(
                      SizedBox(
                        width: 93,
                        height: 93,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            asset('5c616.svg', width: 93, height: 93),
                            asset('9b01f.svg', width: 60, height: 60),
                            if (testPreview)
                              ClipOval(
                                child: SizedBox(
                                  width: 93,
                                  height: 93,
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: -2,
                                        top: -8,
                                        width: 98,
                                        height: 147,
                                        child: Image.asset(
                                          'assets/figma/d24f3.png',
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      missing,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          label(name, 12, bold: true),
          const SizedBox(height: 20),
          SizedBox(
            height: showSecondPhone ? 595 : 525,
            child: Stack(
              children: [
                for (final field in <(String, String, double)>[
                  ('имя', 'profileName', 0),
                  ('номер телефона', 'phone', 70),
                  ('телеграм', 'telegram', showSecondPhone ? 210 : 140),
                  ('вконтакте', 'vk', showSecondPhone ? 280 : 210),
                  ('whatsapp', 'whatsapp', showSecondPhone ? 350 : 280),
                  ('авито', 'avito', showSecondPhone ? 395 : 325),
                  ('сайт', 'website', showSecondPhone ? 465 : 395),
                  ('email', 'profileEmail', showSecondPhone ? 535 : 465),
                ])
                  Positioned(
                    left: 0,
                    right: 0,
                    top: field.$3,
                    child: Stack(
                      children: [
                        V3Field(
                          field.$1,
                          c(field.$2),
                          readOnly: field.$2 == 'profileEmail',
                          keyboard: field.$2 == 'phone'
                              ? TextInputType.phone
                              : null,
                        ),
                        if (field.$2 == 'phone' && !showSecondPhone)
                          Positioned(
                            top: 16,
                            right: 7,
                            width: 28,
                            height: 28,
                            child: tap(
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  asset('2858a.svg', width: 28, height: 28),
                                  label('+', 24, color: Colors.white),
                                ],
                              ),
                              () => setState(() => showSecondPhone = true),
                              name: 'Добавить номер телефона',
                            ),
                          ),
                      ],
                    ),
                  ),
                if (showSecondPhone)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 140,
                    child: Stack(
                      children: [
                        V3Field(
                          'дополнительный номер телефона',
                          c('phone2'),
                          keyboard: TextInputType.phone,
                        ),
                        Positioned(
                          top: 16,
                          right: 7,
                          width: 28,
                          height: 28,
                          child: tap(
                            const Icon(Icons.close, size: 19, color: muted),
                            () => setState(() {
                              c('phone2').clear();
                              showSecondPhone = false;
                            }),
                            name: 'Удалить дополнительный номер',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 31),
          pill('сохранить', () async {
            if (busy) return;
            final newName = c('profileName').text.trim();
            if (newName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Укажите имя продавца')),
              );
              return;
            }
            if (c('phone2').text.trim().isNotEmpty && !testPreview) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Сервер пока не поддерживает второй номер. Изменения не сохранены.',
                  ),
                ),
              );
              return;
            }
            if ([
                  'telegram',
                  'vk',
                  'whatsapp',
                  'avito',
                  'website',
                ].any((k) => c(k).text.trim().isNotEmpty) &&
                !testPreview) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Сервер пока не поддерживает сохранение ссылок. Изменения не сохранены.',
                  ),
                ),
              );
              return;
            }
            setState(() => busy = true);
            try {
              if (!testPreview) {
                await widget.api.call(
                  '/account/profile',
                  method: 'POST',
                  body: {'name': newName},
                );
                if (merchant['shop'] != null) {
                  await widget.api.call(
                    '/merchant/shop',
                    method: 'PUT',
                    body: {'name': newName, 'contact': c('phone').text.trim()},
                  );
                }
                await reload(navigate: false);
              }
              if (!mounted) return;
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() {
                account['name'] = newName;
                history.clear();
                screen = 'profile';
              });
            } catch (error) {
              debugPrint('Ошибка сохранения профиля: $error');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Не удалось сохранить профиль. Проверьте соединение и повторите попытку.',
                    ),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => busy = false);
            }
          }),
          const SizedBox(height: 30),
        ],
      ),
    ),
    large: true,
  );
  Widget storeList() => page(
    'мои магазины',
    scroll(
      Column(
        children: [
          const SizedBox(height: 36),
          for (final p in [...pavilions, ...requests]) ...[
            tap(
              Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: p['status'] == 'rejected'
                      ? red
                      : p['status'] == 'pending'
                      ? const Color(0xFFD9D9D9)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label(
                            address(p),
                            12,
                            bold: true,
                            color: p['status'] == 'rejected'
                                ? Colors.white
                                : Colors.black,
                          ),
                          const SizedBox(height: 10),
                          label(
                            name,
                            12,
                            color: p['status'] == 'rejected'
                                ? const Color(0xFFD9D9D9)
                                : const Color(0xFF595959),
                          ),
                        ],
                      ),
                    ),
                    label(
                      p['status'] == 'pending'
                          ? 'на проверке'
                          : p['status'] == 'rejected'
                          ? 'отклонен'
                          : '›',
                      p['status'] == 'approved' ? 24 : 12,
                      color: p['status'] == 'rejected'
                          ? Colors.white
                          : const Color(0xFF7D7D7D),
                    ),
                  ],
                ),
              ),
              () {
                pavilion = p;
                go(
                  p['status'] == 'pending'
                      ? 'pending'
                      : p['status'] == 'rejected'
                      ? 'rejected'
                      : 'shop',
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          tap(
            Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: label(
                      'добавить магазин',
                      12,
                      color: const Color(0xFF595959),
                    ),
                  ),
                  label('+', 28),
                ],
              ),
            ),
            () => go('address'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
    trailing: tap(asset('8974e.svg', width: 3, height: 13), missing),
  );
  Widget statusBody() {
    final pending = screen == 'pending', reject = screen == 'rejected';
    return page(
      pending
          ? 'магазин на проверке'
          : reject
          ? 'магазин не подтверждён'
          : 'магазин подтверждён',
      LayoutBuilder(
        builder: (ctx, b) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: b.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 93, 30, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label(address(pavilion), 22, bold: true),
                        const SizedBox(height: 12),
                        label(
                          pending
                              ? 'На проверке'
                              : reject
                              ? 'Проверка не пройдена'
                              : 'Подтверждён',
                          14,
                          bold: !reject,
                          color: reject
                              ? const Color(0xFFAB0216)
                              : const Color(0xFF595959),
                        ),
                        const SizedBox(height: 10),
                        label(
                          'Магазин: $name',
                          12,
                          color: const Color(0xFF595959),
                        ),
                        const SizedBox(height: 10),
                        label(
                          pending
                              ? 'Адрес отправлен на проверку. После подтверждения торговая точка станет доступна для товаров.'
                              : reject
                              ? 'Причина: ${pavilion['note'] ?? ''}'
                              : 'Адрес подтверждён. Теперь можно выбрать этот павильон при добавлении товара.',
                          12,
                          color: const Color(0xFF808080),
                        ),
                      ],
                    ),
                  ),
                  if (reject) ...[
                    const SizedBox(height: 32),
                    label(
                      'Исправь адрес или приложи другое фото.\nПосле этого заявку можно отправить снова.',
                      12,
                      color: const Color(0xFF808080),
                    ),
                  ],
                  SizedBox(
                    height: math.max(30, b.maxHeight - (reject ? 390 : 310)),
                  ),
                  pill(
                    pending
                        ? 'мои магазины'
                        : reject
                        ? 'исправить адрес'
                        : 'добавить товар',
                    () {
                      if (pending) {
                        returnToStores();
                        return;
                      }
                      if (reject) {
                        for (final key in [
                          'building',
                          'floor',
                          'line',
                          'number',
                        ])
                          c(key).clear();
                        c('zone').text = '${pavilion['zone'] ?? ''}';
                        final parts = address(pavilion).split('-');
                        final floorLine = parts.length == 3
                            ? RegExp(r'^(\d+)(.*)$').firstMatch(parts[1])
                            : null;
                        if (parts.length == 3 && floorLine != null) {
                          c('building').text = parts[0];
                          c('floor').text = floorLine.group(1)!;
                          c('line').text = floorLine.group(2)!;
                          c('number').text = parts[2];
                        } else {
                          // Legacy codes may not be decomposable; keep the exact address.
                          c('number').text = address(pavilion);
                        }
                      }
                      go(
                        pending
                            ? 'stores'
                            : reject
                            ? 'fixAddress'
                            : 'capture',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      onBack: pending ? returnToStores : null,
    );
  }

  Widget addressBody() {
    final fix = screen == 'fixAddress', manual = screen == 'manualAddress';
    return page(
      fix
          ? 'исправить адрес'
          : manual
          ? 'адрес не найден'
          : 'добавить магазин',
      scroll(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 11),
            if (fix || manual) ...[
              label(
                manual
                    ? 'Укажи расположение торговой точки вручную.'
                    : 'Исправь данные и отправь заявку ещё раз.',
                12,
                color: const Color(0xFF808080),
              ),
              const SizedBox(height: 18),
            ],
            if (manual)
              V3Field('указать адрес', c('manual'))
            else ...[
              if (!fix) ...[
                V3Field(
                  'название',
                  c('addressName')..text = name,
                  readOnly: true,
                ),
                const SizedBox(height: 11),
              ],
              for (final f in [
                ['торговая зона', 'zone'],
                ['корпус', 'building'],
                ['этаж', 'floor'],
                ['линия / ряд', 'line'],
                ['номер павильона', 'number'],
              ]) ...[V3Field(f[0], c(f[1])), const SizedBox(height: 11)],
            ],
            if (!fix && !manual) ...[
              const SizedBox(height: 17),
              tap(
                label(
                  'Адреса нет в справочнике?',
                  12,
                  color: const Color(0xFF7A7A7A),
                ),
                () => go('manualAddress'),
              ),
              const SizedBox(height: 25),
            ] else if (fix) ...[
              tap(
                Container(
                  height: 56,
                  color: Colors.white,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: label(
                    'добавить новое фото входа',
                    12,
                    color: const Color(0xFF808080),
                  ),
                ),
                missing,
              ),
              const SizedBox(height: 25),
            ] else
              const SizedBox(height: 380),
            pill(
              fix
                  ? 'отправить повторно'
                  : manual
                  ? 'отправить адрес'
                  : 'отправить на проверку',
              sendAddress,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget searchField() => Container(
    height: 32,
    decoration: BoxDecoration(
      color: const Color(0xFFD9D9D9),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const SizedBox(width: 17),
        asset('ba4c8.svg', width: 14, height: 14),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: c('search'),
            onChanged: (_) => setState(() {
              searching = true;
              selected.clear();
            }),
            style: type(12, color: Colors.white),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: 'поиск',
              hintStyle: type(12, color: Colors.white),
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (searching)
          tap(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: label('×', 20),
            ),
            () {
              setState(() {
                searching = false;
                c('search').clear();
              });
            },
          ),
      ],
    ),
  );
  Widget catalog() {
    final shop = screen == 'shop';
    final items = shown;
    final content = scroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selecting) ...[
            SizedBox(
              height: math.max(64, MediaQuery.paddingOf(context).top + 12),
            ),
            Row(
              children: [
                Expanded(child: searchField()),
                const SizedBox(width: 24),
                tap(label('×', 28), () {
                  setState(() {
                    selecting = false;
                    selected.clear();
                  });
                }),
              ],
            ),
            const SizedBox(height: 16),
            tap(
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: items.isNotEmpty && selected.length == items.length
                          ? blue
                          : Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  label('выбрать все (${items.length})', 10, color: muted),
                ],
              ),
              () => setState(() {
                if (selected.length == items.length) {
                  selected.clear();
                } else {
                  selected
                    ..clear()
                    ..addAll(items.take(20).map((p) => '${p['id']}'));
                  if (items.length > 20)
                    failure(
                      Exception('За один раз можно выбрать до 20 товаров.'),
                    );
                }
              }),
            ),
            const SizedBox(height: 10),
          ] else if (shop) ...[
            const SizedBox(height: 27),
            Row(
              children: [
                Expanded(
                  child: tap(
                    label(address(pavilion), 16, bold: true, color: brown),
                    () => go('approved'),
                  ),
                ),
                for (final mode in ['wholesale', 'retail']) ...[
                  tap(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: saleFilter == mode ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: label(
                        mode == 'wholesale' ? 'опт' : 'розница',
                        10,
                        color: saleFilter == mode ? Colors.white : Colors.black,
                      ),
                    ),
                    () => setState(() {
                      saleFilter = saleFilter == mode ? null : mode;
                      selected.clear();
                    }),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
            const SizedBox(height: 10),
            label(name, 14, color: brown),
            const SizedBox(height: 18),
            searchField(),
            const SizedBox(height: 16),
          ] else ...[
            SizedBox(
              height: math.max(68, MediaQuery.paddingOf(context).top + 6),
            ),
            tap(
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 27),
                decoration: BoxDecoration(
                  color: muted,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: label('мои магазины', 16, color: Colors.white),
                    ),
                    label('›', 30, bold: true, color: Colors.white),
                  ],
                ),
              ),
              () => go('stores'),
            ),
            const SizedBox(height: 13),
            pill('добавить товар', () => go('capture'), icon: 'd5d93.svg'),
            const SizedBox(height: 23),
            if (searching) ...[searchField(), const SizedBox(height: 18)],
          ],
          if (!selecting) ...[
            Row(
              children: [
                Expanded(
                  child: label(
                    searching ? 'результаты поиска' : 'все товары',
                    shop ? 12 : 16,
                    bold: true,
                  ),
                ),
                if (!searching && !shop)
                  tap(
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                        child: asset('a665b.svg', width: 16, height: 16),
                      ),
                    ),
                    () => setState(() => searching = true),
                  ),
                tap(
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: asset(
                        shop ? 'ac2f9.svg' : 'e36ac.svg',
                        width: 15,
                        height: 15,
                      ),
                    ),
                  ),
                  () => setState(() {
                    selecting = true;
                    selected.clear();
                    selectionPavilionId = screen == 'shop'
                        ? '${pavilion['id']}'
                        : null;
                  }),
                ),
                if (shop)
                  tap(
                    label('···', 20, bold: true),
                    () => setState(() {
                      selecting = true;
                      selected.clear();
                      selectionPavilionId = screen == 'shop'
                          ? '${pavilion['id']}'
                          : null;
                    }),
                  ),
              ],
            ),
            if (shop) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final isHidden in [false, true]) ...[
                    Expanded(
                      child: tap(
                        Container(
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hidden == isHidden
                                ? const Color(0xFFD9D9D9)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: label(
                            isHidden ? 'скрытые' : 'опубликованные',
                            10,
                            color: const Color(0xFF7D7D7D),
                          ),
                        ),
                        () => setState(() {
                          hidden = isHidden;
                          selected.clear();
                        }),
                      ),
                    ),
                    if (!isHidden) const SizedBox(width: 30),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 20),
          ],
          if (items.isEmpty && searching) ...[
            const SizedBox(height: 90),
            label('ничего не найдено', 18, bold: true, align: TextAlign.center),
            const SizedBox(height: 16),
            label(
              'Попробуйте другое название.',
              13,
              color: muted,
              align: TextAlign.center,
            ),
          ] else
            LayoutBuilder(
              builder: (ctx, b) {
                final width = (b.maxWidth - 30) / 2;
                final list = <Widget>[
                  if (shop && !hidden && !selecting && !searching)
                    tap(
                      Column(
                        children: [
                          Container(
                            width: width,
                            height: width,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD9D9D9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            alignment: Alignment.center,
                            child: label('+', 30, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          label(
                            'добавить товар',
                            10,
                            color: const Color(0xFF7D7D7D),
                          ),
                        ],
                      ),
                      () => go('capture'),
                    ),
                  for (final p in items) productCard(p, width),
                ];
                return Wrap(
                  spacing: 30,
                  runSpacing: 28,
                  children: [
                    for (final w in list) SizedBox(width: width, child: w),
                  ],
                );
              },
            ),
          const SizedBox(height: 100),
        ],
      ),
    );
    return Stack(
      children: [
        shop && !selecting
            ? page(
                'магазин',
                content,
                trailing: tap(
                  asset('18697.svg', width: 17, height: 17),
                  missing,
                ),
              )
            : content,
        if (selecting)
          Positioned(
            bottom: 24,
            left: 30,
            right: 30,
            child: tap(
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                decoration: BoxDecoration(
                  color: brown,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: label(
                        'выбрано : ${selected.length}',
                        14,
                        color: Colors.white,
                      ),
                    ),
                    label('действия  ⌃', 14, color: Colors.white),
                  ],
                ),
              ),
              () => setState(() => actions = true),
            ),
          ),
      ],
    );
  }

  String productStatus(RowData p, List<RowData> listings) {
    if (p['status'] == 'pending') return 'на проверке';
    if (p['status'] == 'rejected') return 'отклонён';
    if (p['status'] == 'draft') return 'не отправлен';
    if (listings.any(
      (l) => l['published'] == true || l['status'] == 'approved',
    ))
      return 'опубликован';
    if (listings.any((l) => l['status'] == 'pending')) return 'на проверке';
    if (listings.any((l) => l['status'] == 'rejected')) return 'отклонён';
    return 'скрыт';
  }

  Widget productCard(RowData p, double width) {
    final images = (p['images'] as List? ?? []).cast<String>();
    final ls = rows(p['listings'])
        .where((l) => screen != 'shop' || l['pavilion_id'] == pavilion['id'])
        .toList();
    return tap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: width,
            height: width,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: images.isEmpty
                      ? Container(color: const Color(0xFFD9D9D9))
                      : PageView(
                          key: ValueKey('gallery:${p['id']}'),
                          onPageChanged: (index) =>
                              setState(() => photoPages['${p['id']}'] = index),
                          children: [
                            for (final url in images) productImage(url, width),
                          ],
                        ),
                ),
                if (images.length > 1)
                  Positioned(
                    bottom: 7,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < images.length; i++)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: i == (photoPages['${p['id']}'] ?? 0)
                                  ? Colors.white
                                  : const Color(0xFFD9D9D9),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (hidden)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: .38),
                      child: Center(
                        child: asset('0b09a.svg', width: 40, height: 40),
                      ),
                    ),
                  ),
                if (selecting)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: selected.contains('${p['id']}')
                            ? blue
                            : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white),
                      ),
                      child: selected.contains('${p['id']}')
                          ? Center(child: label('✓', 16, color: Colors.white))
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (screen != 'shop')
            label(
              ls.isNotEmpty
                  ? address(
                      Map<String, dynamic>.from(ls.first['pavilion'] ?? {}),
                    )
                  : '',
              12,
            ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: label(
                  '${p['title']}',
                  10,
                  color: const Color(0xFF7D7D7D),
                ),
              ),
              if (screen == 'shop' && ls.isNotEmpty)
                label(
                  ls.first['price'] == null
                      ? 'цена не указана'
                      : '≈ ${ls.first['price']} ₽',
                  10,
                  color: muted,
                ),
              label(productStatus(p, ls), 10, color: muted),
            ],
          ),
        ],
      ),
      () {
        if (selecting) {
          setState(() {
            final id = '${p['id']}';
            if (selected.contains(id)) {
              selected.remove(id);
            } else if (selected.length < 20) {
              selected.add(id);
            } else {
              failure(Exception('За один раз можно выбрать до 20 товаров.'));
            }
          });
        } else {
          openEditProduct(p);
        }
      },
    );
  }

  Widget productImage(String url, double width) {
    if (url.startsWith('asset:')) {
      final file = url.substring(6);
      final crops = <String, List<double>>{
        'bfc4a.png': [-.204, -1.0551, 1.4811, 3.2198],
        'eb9f2.png': [-.0143, -.0337, 1.015, 1.1879],
        'f46f5.png': [0, -.5605, 1, 1.5677],
        '62cf6.png': [-.0004, -.06, 1.0008, 1.34],
      };
      final crop = crops[file];
      if (crop != null) {
        return SizedBox(
          width: width,
          height: width,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: crop[0] * width,
                  top: crop[1] * width,
                  width: crop[2] * width,
                  height: crop[3] * width,
                  child: Image.asset('assets/figma/$file', fit: BoxFit.fill),
                ),
              ],
            ),
          ),
        );
      }
      return Image.asset(
        'assets/figma/$file',
        width: width,
        height: width,
        fit: BoxFit.cover,
      );
    }
    return Image.network(
      url.startsWith('http') ? url : '${widget.api.baseUrl}$url',
      width: width,
      height: width,
      fit: BoxFit.cover,
      errorBuilder: (_, error, stack) =>
          Container(color: const Color(0xFFD9D9D9)),
    );
  }

  Widget actionPanel() => Positioned.fill(
    child: Stack(
      children: [
        Positioned.fill(
          child: tap(
            ColoredBox(color: Colors.black.withValues(alpha: .4)),
            () => setState(() => actions = false),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(30, 16, 30, 36),
            decoration: const BoxDecoration(
              color: beige,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: tap(
                    label('×', 26),
                    () => setState(() => actions = false),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: actionTile('перенести', '46c91.svg', brown, () {
                        destinations.clear();
                        go('move');
                      }),
                    ),
                    const SizedBox(width: 30),
                    Expanded(
                      child: actionTile('дублировать', '282b6.svg', blue, () {
                        destinations.clear();
                        go('duplicate');
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    Expanded(
                      child: actionTile(
                        hidden ? 'показать' : 'скрыть',
                        hidden ? 'a4ab0.svg' : '7c4d2.svg',
                        muted,
                        () => run(() async {
                          if (selected.isEmpty) return;
                          if (!testPreview) {
                            await productActions.batch(
                              hidden ? 'resume' : 'pause',
                              {
                                'product_ids': selected.toList()..sort(),
                                if (selectionPavilionId != null)
                                  'pavilion_id': selectionPavilionId,
                              },
                            );
                            await reload(navigate: false);
                          }
                          if (hidden && mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Товары отправлены на проверку перед публикацией',
                                ),
                              ),
                            );
                          setState(() {
                            actions = false;
                            selecting = false;
                            selected.clear();
                          });
                        }),
                      ),
                    ),
                    const SizedBox(width: 30),
                    Expanded(
                      child: actionTile('удалить', 'd6928.svg', red, () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => Center(child: deleteDialog()),
                        );
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget actionTile(
    String title,
    String icon,
    Color color,
    VoidCallback action,
  ) => tap(
    Container(
      height: 75,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          asset(icon, width: 24, height: 24),
          const SizedBox(height: 8),
          label(title, 16, color: Colors.white),
        ],
      ),
    ),
    action,
  );
  Widget deleteDialog() {
    final count = selected.isEmpty ? 1 : selected.length;
    final suffix = count % 10 == 1 && count % 100 != 11
        ? 'товар'
        : count % 10 >= 2 &&
              count % 10 <= 4 &&
              (count % 100 < 12 || count % 100 > 14)
        ? 'товара'
        : 'товаров';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 330,
        height: 200,
        child: Stack(
          children: [
            Positioned(
              left: 19,
              right: 19,
              top: 27,
              child: label(
                'вы точно хотите удалить $count $suffix?',
                15,
                bold: true,
                color: const Color(0xFF1F1F1F),
              ),
            ),
            Positioned(
              left: 19,
              right: 19,
              top: 55,
              child: label(
                'Карточки будут удалены из всех магазинов.\nВосстановить их не получится.',
                12,
                color: const Color(0xFFA3A3A3),
              ),
            ),
            Positioned(
              left: 19,
              right: 19,
              top: 110,
              height: 43,
              child: tap(
                Center(
                  child: label('отмена', 14, color: const Color(0xFF1A1A1A)),
                ),
                () {
                  if (screen == 'delete') {
                    back();
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            Positioned(
              left: 19,
              right: 19,
              top: 152,
              height: 43,
              child: tap(
                Center(
                  child: label('удалить', 14, color: const Color(0xFF5F0F10)),
                ),
                () {
                  if (screen != 'delete') Navigator.pop(context);
                  deleteProducts();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget bulkBody() {
    final duplicate = screen == 'duplicate';
    return page(
      duplicate ? 'дублировать товары' : 'перенести товары',
      LayoutBuilder(
        builder: (ctx, b) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 16, 30, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label(
                  duplicate
                      ? 'Будут созданы отдельные копии товаров в выбранных магазинах. Оригиналы останутся без изменений.'
                      : 'Товары будут убраны из исходного магазина и перемещены в выбранный. В остальных магазинах они останутся без изменений.',
                  12,
                  color: const Color(0xFF808080),
                ),
                const SizedBox(height: 25),
                label('Выбрано ${selected.length} товара', 12, color: muted),
                const SizedBox(height: 25),
                ...[
                  label('Из магазина', 12, color: muted),
                  const SizedBox(height: 12),
                  Container(
                    height: 60,
                    padding: const EdgeInsets.all(20),
                    color: Colors.white,
                    child: label(
                      address(
                        pavilions
                                .where((p) => '${p['id']}' == sourcePavilionId)
                                .firstOrNull ??
                            pavilion,
                      ),
                      14,
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
                label(
                  duplicate ? 'Разместить копии в магазинах' : 'В магазин',
                  12,
                  color: muted,
                ),
                const SizedBox(height: 12),
                for (final p in pavilions) ...[
                  tap(
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: label(address(p), 14)),
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: destinations.contains('${p['id']}')
                                  ? blue
                                  : Colors.white,
                              border: Border.all(
                                color: destinations.contains('${p['id']}')
                                    ? blue
                                    : muted,
                              ),
                              borderRadius: BorderRadius.circular(
                                duplicate ? 3 : 10,
                              ),
                            ),
                            child: destinations.contains('${p['id']}')
                                ? Center(
                                    child: label(
                                      duplicate ? '✓' : '•',
                                      14,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                    () => setState(() {
                      final id = '${p['id']}';
                      if (!duplicate) destinations.clear();
                      if (!destinations.add(id)) destinations.remove(id);
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 38),
                pill(
                  duplicate ? 'дублировать товары' : 'перенести товары',
                  distributeProducts,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget captureBody() => page(
    'добавить товар',
    LayoutBuilder(
      builder: (ctx, b) {
        final scaleX = b.maxWidth / 390;
        final scaleY = b.maxHeight / 632;
        // Figma image 17 is the supplied camera artwork, with the same clipping
        // as node 366:15990. Interactive regions launch native image picking.
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -24 * scaleX,
              top: 6 * scaleY,
              width: 439 * scaleX,
              height: 630 * scaleY,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: -.2418 * 630 * scaleY,
                      width: 439 * scaleX,
                      height: 1.5169 * 630 * scaleY,
                      child: Image.asset(
                        'assets/figma/045ce.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10 * scaleX,
              right: 10 * scaleX,
              top: 18 * scaleY,
              bottom: 130 * scaleY,
              child: tap(
                const SizedBox.expand(),
                () => pick(),
                name: 'Выбрать фотографии',
              ),
            ),
            Positioned(
              left: 160 * scaleX,
              top: 480 * scaleY,
              width: 70 * scaleX,
              height: 70 * scaleY,
              child: tap(
                const SizedBox.expand(),
                () => pick(camera: true),
                name: 'Снять фото',
              ),
            ),
            Positioned(
              left: 122 * scaleX,
              top: 552 * scaleY,
              width: 146 * scaleX,
              height: 48 * scaleY,
              child: tap(
                const SizedBox.expand(),
                () => pick(),
                name: 'из галереи',
              ),
            ),
          ],
        );
      },
    ),
  );
  Widget singleDeleteDialog() => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      width: 330,
      height: 201,
      child: Stack(
        children: [
          const Positioned(
            left: 19,
            right: 19,
            top: 18,
            child: Text(
              'удалить товар?',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          const Positioned(
            left: 19,
            right: 19,
            top: 57,
            child: Text(
              'Товар исчезнет из всех павильонов.\nВосстановить карточку будет нельзя.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Color(0xFF7A7A7A),
              ),
            ),
          ),
          for (final item in <(String, double, Color, VoidCallback)>[
            (
              'отмена',
              110,
              const Color(0xFF1A1A1A),
              () => Navigator.pop(context),
            ),
            (
              'удалить',
              152,
              const Color(0xFF5F0F10),
              () {
                Navigator.pop(context);
                deleteProducts(single: true);
              },
            ),
          ])
            Positioned(
              left: 19,
              right: 19,
              top: item.$2,
              height: 43,
              child: tap(
                Padding(
                  padding: const EdgeInsets.only(left: 9, top: 10),
                  child: Text(
                    item.$1,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: item.$3,
                    ),
                  ),
                ),
                item.$4,
              ),
            ),
        ],
      ),
    ),
  );
  Future<void> clearDraftForm() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 330,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  label('Очистить форму?', 16, bold: true),
                  const SizedBox(height: 14),
                  label(
                    'Несохранённые данные и выбранные фото будут удалены с устройства. Уже загруженный серверный черновик останется в каталоге.',
                    12,
                    color: muted,
                  ),
                  const SizedBox(height: 22),
                  tap(
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: label('отмена', 14),
                    ),
                    () => Navigator.pop(ctx, false),
                  ),
                  tap(
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: label('очистить форму', 14, color: red),
                    ),
                    () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await run(() async {
      await forgetDraft();
      restoringDraft = true;
      try {
        photos.clear();
        deletedPhotos.clear();
        photoReplacements.clear();
        destinations.clear();
        product = {};
        originalProduct = {};
        saveSession = ProductSaveSession();
        draftCompleted = false;
        initialPrice = '';
        draftId = null;
        c('title').clear();
        c('price').clear();
        saleModes
          ..clear()
          ..add('retail');
        listingModes.clear();
        history.clear();
        setState(() => screen = 'capture');
      } finally {
        restoringDraft = false;
      }
      if (!testPreview) activeDraftKey = formKey('new');
    });
  }

  Future<void> productMenu() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Center(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 330,
            height: 293,
            child: Stack(
              children: [
                const Positioned(
                  left: 19,
                  right: 19,
                  top: 18,
                  child: Text(
                    'действия с товаром',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                for (final item in <(String, double, Color, VoidCallback)>[
                  (
                    'изменить фотографии',
                    57,
                    const Color(0xFF1A1A1A),
                    () {
                      Navigator.pop(dialogContext);
                      pick();
                    },
                  ),
                  if (product['id'] != null &&
                      rows(product['listings']).any(
                        (l) =>
                            l['published'] == true || l['status'] == 'approved',
                      ))
                    (
                      'скрыть товар',
                      103,
                      const Color(0xFF1A1A1A),
                      () {
                        Navigator.pop(dialogContext);
                        run(() async {
                          if (product['id'] == null) {
                            missing();
                            return;
                          }
                          if (!testPreview) {
                            await productActions.batch('pause', {
                              'product_ids': ['${product['id']}'],
                            });
                            await reload(navigate: false);
                          }
                          back();
                        });
                      },
                    ),
                  if (product['id'] != null && product['status'] != 'pending')
                    (
                      'удалить товар',
                      149,
                      const Color(0xFF5F0F10),
                      () {
                        Navigator.pop(dialogContext);
                        selected
                          ..clear()
                          ..add('${product['id'] ?? 'draft'}');
                        showDialog<void>(
                          context: context,
                          builder: (_) => Center(child: singleDeleteDialog()),
                        );
                      },
                    ),
                  (
                    'Очистить форму',
                    195,
                    const Color(0xFF5F0F10),
                    () {
                      Navigator.pop(dialogContext);
                      clearDraftForm();
                    },
                  ),
                  (
                    'отмена',
                    241,
                    const Color(0xFF7A7A7A),
                    () => Navigator.pop(dialogContext),
                  ),
                ])
                  Positioned(
                    left: 19,
                    right: 19,
                    top: item.$2,
                    height: 43,
                    child: tap(
                      Padding(
                        padding: const EdgeInsets.only(left: 9, top: 10),
                        child: Text(
                          item.$1,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: item.$3,
                          ),
                        ),
                      ),
                      item.$4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget productEditor() {
    final edit = screen == 'editProduct';
    return page(
      edit ? 'изменить товар' : 'добавить товар',
      scroll(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 17),
            V3Field('название', c('title')),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(17, 14, 17, 20),
              constraints: const BoxConstraints(minHeight: 119),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label(
                    'павильон',
                    12,
                    color: pavilionValidationError ? red : muted,
                  ),
                  if (pavilionValidationError) ...[
                    const SizedBox(height: 6),
                    label('Выберите павильон', 12, color: red),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 10,
                    children: [
                      for (final p in pavilions)
                        tap(
                          Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              color: destinations.contains('${p['id']}')
                                  ? blue
                                  : muted,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Center(
                              widthFactor: 1,
                              child: label(address(p), 11, color: Colors.white),
                            ),
                          ),
                          () => setState(() {
                            final id = '${p['id']}';
                            if (!destinations.add(id)) destinations.remove(id);
                            if (edit && !listingModes.containsKey(id)) {
                              listingModes[id] = Set.of(saleModes);
                              c('price:$id').text = c('price').text;
                            }
                            if (destinations.isNotEmpty)
                              pavilionValidationError = false;
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (!edit || rows(originalProduct['listings']).isEmpty) ...[
              V3Field('цена', c('price'), keyboard: TextInputType.number),
              const SizedBox(height: 8),
              saleModeFields(saleModes),
            ] else ...[
              for (final id in destinations) ...[
                label(
                  address(
                    pavilions.where((p) => '${p['id']}' == id).firstOrNull ??
                        {},
                  ),
                  12,
                ),
                const SizedBox(height: 6),
                V3Field(
                  'цена',
                  listingModes.containsKey(id) ? c('price:$id') : c('price'),
                  keyboard: TextInputType.number,
                ),
                const SizedBox(height: 8),
                saleModeFields(listingModes[id] ?? saleModes),
                const SizedBox(height: 12),
              ],
            ],
            SizedBox(height: edit ? 22 : 8),
            LayoutBuilder(
              builder: (ctx, b) {
                final width = (b.maxWidth - 30) / 2;
                final urls = (product['images'] as List? ?? []).cast<String>();
                return Wrap(
                  spacing: 30,
                  runSpacing: 16,
                  children: [
                    for (var i = 0; i < urls.length + photos.length; i++)
                      SizedBox(
                        width: width,
                        height: width,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: i < urls.length
                                    ? productImage(urls[i], width)
                                    : FutureBuilder(
                                        future: photos[i - urls.length]
                                            .readAsBytes(),
                                        builder: (ctx, snapshot) =>
                                            snapshot.hasData
                                            ? Image.memory(
                                                snapshot.data!,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(color: muted),
                                      ),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: tap(
                                  const Icon(
                                    Icons.sync,
                                    color: Colors.white,
                                    size: 23,
                                  ),
                                  () => replaceProductPhoto(i, urls.length),
                                  name: 'Заменить фотографию',
                                ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: tap(
                                  asset('46d54.svg', width: 12, height: 12),
                                  () {
                                    removePhoto(i, urls.length);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(
                      width: width,
                      height: width,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Material(
                          color: muted,
                          child: InkWell(
                            onTap: () => pick(),
                            child: const Center(
                              child: Icon(
                                Icons.add,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (edit)
              Row(
                children: [
                  Expanded(
                    child: pill('удалить товар', () {
                      selected
                        ..clear()
                        ..add('${product['id']}');
                      showDialog<void>(
                        context: context,
                        builder: (_) => Center(child: singleDeleteDialog()),
                      );
                    }, color: red),
                  ),
                  const SizedBox(width: 30),
                  Expanded(child: pill('сохранить', saveProduct, color: blue)),
                ],
              )
            else
              pill('добавить', saveProduct),
            const SizedBox(height: 32),
          ],
        ),
      ),
      trailing: tap(
        asset(edit ? 'f5ab0.svg' : '8cf4e.svg', width: 24, height: 24),
        edit
            ? () => showDialog<void>(
                context: context,
                builder: (ctx) => Dialog(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IgnorePointer(
                            child: productCard(
                              product,
                              math.min(280, MediaQuery.sizeOf(ctx).width - 100),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('закрыть'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : productMenu,
        name: edit ? 'Просмотр товара' : 'Действия с товаром',
      ),
    );
  }
}
