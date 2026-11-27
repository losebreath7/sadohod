import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/header_back_button.dart';
import 'package:sadohod_shared_core/catalog_widgets.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'api.dart';
import 'sadohodets_api.dart';
import 'courier_buyer_design.dart';
import 'seller_v3.dart' show V3Field, V3Header, asset;
import 'seller_settings.dart';
import 'seller_telegram_chat.dart';
import 'seller_notifications.dart';
import 'courier_product_screen.dart';
import 'courier_seller_screen.dart';
import 'package:sadohod_shared_core/catalog_search.dart';
import 'courier_folder_items.dart';
import 'courier_folder_list.dart';
import 'package:sadohod_shared_core/build_info.dart';
import 'courier_navigation_guide.dart';
import 'package:sadohod_shared_core/product_share_actions.dart';
import 'dart:convert';
import 'dart:async';

class SadohodetsCabinet extends StatefulWidget {
  const SadohodetsCabinet({
    super.key,
    required this.api,
    required this.initialName,
    required this.onBack,
  });
  final SellerApi api;
  final String initialName;
  final VoidCallback onBack;
  @override
  State<SadohodetsCabinet> createState() => _CabinetState();
}

class _CabinetState extends State<SadohodetsCabinet>
    with WidgetsBindingObserver {
  late final api = SadohodetsApi(widget.api);
  final name = TextEditingController();
  final email = TextEditingController();
  bool secondPhone = false;
  final description = TextEditingController();
  final contacts = {
    for (final k in [
      'phone',
      'phone2',
      'telegram',
      'vk',
      'whatsapp',
    ])
      k: TextEditingController(),
  };
  static const labels = {
    'phone': 'номер телефона',
    'phone2': 'дополнительный номер телефона',
    'telegram': 'телеграм',
    'vk': 'вконтакте',
    'whatsapp': 'whatsapp',
  };
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> folders = [];
  List<Map<String, dynamic>> archivedFolders = [];
  bool viewingArchive = false;

  Future<void> refreshFolders() async {
    final lists = await Future.wait([api.folders(), api.folders(archived: true)]);
    folders = lists[0];
    archivedFolders = lists[1];
  }

  Future<void> archiveFolder(Map entry) async {
    if (busy) return;
    final archived = entry['archived'] != true;
    await run(() async {
      await api.setArchived(entry['id'].toString(), archived);
      await refreshFolders();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(archived ? 'Папка в архиве' : 'Папка возвращена из архива'),
      ));
    });
  }

  Future<void> deleteClientFolder(Map entry) async {
    if (busy || !await confirm('Удалить папку и все товары в ней?')) return;
    if (!mounted) return;
    await run(() async {
      await api.deleteFolder(entry['id'].toString());
      await refreshFolders();
    });
  }
  Map<String, dynamic>? folder;
  final media = <String, Uint8List>{};
  bool busy = true;
  bool loaded = false;
  String? error;
  int selectedTab = 0;
  bool get showFolders => selectedTab == 1;
  bool settings = false;
  bool editing = false;
  void openPage(String title, Widget content) { Navigator.of(context).push(MaterialPageRoute<void>(builder: (ctx) => Scaffold(backgroundColor: SellerColors.background, body: Column(children:[V3Header(title:title,back:()=>Navigator.pop(ctx)),Expanded(child:content)])))); }
  void openSettings() {final navigator=Navigator.of(context,rootNavigator:true);openPage('настройки', SellerSettingsPage(api:widget.api,courier:true,onSignedOut:(){navigator.popUntil((route)=>route.isFirst);},onOpenInfo:(kind)=>openPage(kind=='about'?'о приложении':kind=='terms'?'пользовательское соглашение':'конфиденциальность',SellerSettingsInfoPage(kind:kind))));}
  void openNotifications() => openPage('уведомления',SellerNotificationsPage(api:widget.api,courier:true,onOpenPavilions:(){},onOpenProduct:(id) async {try{final product=await widget.api.call('/products/${Uri.encodeComponent(id)}');if(mounted)await openProduct(product);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}));
  void openNavigation() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: MarketNavigationGuideScreen())));

  final search = TextEditingController();
  Timer? _searchDebounce;
  bool _searchPending = false;
  int _searchRevision = 0;
  late Future<CatalogSearchResults<Map<String,dynamic>>> products = catalog();
  Future<CatalogSearchResults<Map<String,dynamic>>> catalog([String query = '']) async {
    final rows = <Map<String, dynamic>>[];
    if (query.trim().isNotEmpty) {
      final r = await widget.api.call(
        '/search/text?q=${Uri.encodeQueryComponent(query.trim())}&limit=100',
      );
      return CatalogSearchResults((r['items'] as List).cast<Map<String,dynamic>>(),
        sellers:(r['sellers'] as List? ?? const []).whereType<Map>().map(SellerSearchHit.fromJson).toList());
    }
    for (var offset = 0; ; offset += 500) {
      final r = await widget.api.call('/products?limit=500&offset=$offset');
      final batch = (r['items'] as List).cast<Map<String, dynamic>>();
      rows.addAll(batch);
      if (batch.length < 500) return CatalogSearchResults(rows);
    }
  }

  // Typing uses the same ranked server endpoint as buyer text search.
  void searchChanged(String value) {
    _searchDebounce?.cancel();
    final revision = ++_searchRevision;
    final query = value.trim();
    if (query.isEmpty) {
      _requestCatalog('');
      return;
    }
    setState(() => _searchPending = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || revision != _searchRevision) return;
      _requestCatalog(query);
    });
  }

  void _requestCatalog(String query) {
    if (!mounted) return;
    final request = catalog(query);
    // Observe failures even if the user has switched away from FutureBuilder.
    unawaited(request.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    setState(() {
      _searchPending = false;
      products = request;
    });
  }

  void searchFor(String q) {
    _searchDebounce?.cancel();
    ++_searchRevision;
    FocusManager.instance.primaryFocus?.unfocus();
    if (search.text != q) {
      search.value = TextEditingValue(text: q,
        selection: TextSelection.collapsed(offset: q.length));
    }
    _requestCatalog(q.trim());
  }

  Future<void> photoSearch() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      _searchDebounce?.cancel();
      ++_searchRevision;
      search.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.api.baseUrl}/api/v1/search/image'),
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'query.jpg'),
      );
      final result = Future<CatalogSearchResults<Map<String,dynamic>>>(() async {
        final response = await http.Response.fromStream(
          await request.send().timeout(const Duration(seconds: 60)),
        );
        if (response.statusCode != 200)
          throw Exception('Поиск по фото недоступен');
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
        return CatalogSearchResults((data['items'] as List)
            .map((e) => (e['product'] as Map).cast<String, dynamic>())
            .toList());
      });
      unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      if (mounted) setState(() {
        _searchPending = false;
        products = result;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> ensureProfile() async {
    if (profile == null) {
      profile = await api.saveProfile(
        name: widget.initialName.trim().isEmpty
            ? 'Садоходец'
            : widget.initialName.trim(),
        contacts: {},
      );
    }
  }

  Future<void> chooseFolder(String product) async {
    final selected = folders.isEmpty
        ? ''
        : await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('В папку клиента'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: const Text('Создать папку'),
                ),
                for (final f in folders)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, f['id']),
                    child: Text(f['name']),
                  ),
              ],
            ),
          );
    if (selected == null || !mounted) return;
    if (selected.isEmpty) {
      await editFolder(null, product);
    } else {
      await run(() => addToFolder(selected, product));
    }
  }

  Future<void> addToFolder(String id, String product) async {
    final added = await api.addItem(id, product);
    if (folder?['id'] == id) folder = await api.folder(id);
    await refreshFolders();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(added ? 'Товар добавлен' : 'Уже в папке')),
      );
  }

  Future<String?> askText(
    String title, {
    String initial = '',
    int limit = 250,
  }) {
    var value = initial;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          maxLength: limit,
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, value.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> addLink() async {
    final id = folder!['id'] as String;
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {}
    if (!mounted) return;
    var product = productIdFromShareLink(text ?? '');
    if (product == null) {
      final input = await askText('Вставьте ссылку на товар', limit: 500);
      if (input == null || !mounted) return;
      product = productIdFromShareLink(input);
    }
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нужна ссылка из карточки товара Садохода'),
        ),
      );
      return;
    }
    final pid = product;
    await run(() => addToFolder(id, pid));
  }

  Widget productCard(Map p) {
    final offers = p['offers'] as List? ?? const [];
    final offer = offers.isEmpty ? null : offers.first as Map?;
    final seller = offer?['seller'] as Map? ?? p['seller'] as Map? ?? const {};
    final pavilion = offer?['pavilion'] as Map? ?? const {};
    final address = (pavilion['code'] ?? seller['pavilion'] ?? p['pavilion'] ?? '').toString();
    final zone = (pavilion['zone'] ?? seller['zone'] ?? '').toString();
    final images = (p['images'] as List? ?? const [])
        .whereType<String>().where((path) => path.isNotEmpty).toList();
    if (images.isEmpty && p['image'] is String) images.add(p['image'] as String);
    final price = p['price'];
    return SadohodCatalogTile(
      photos: images.map((path) => path.startsWith('/') ? '${widget.api.baseUrl}$path' : path).toList(),
      address: address,
      zone: zone,
      title: (p['title'] ?? '').toString().trim().isEmpty ? 'Без названия' : p['title'].toString(),
      price: price is num ? price.toInt() : null,
      ink: SellerColors.brown,
      muted: SellerColors.muted,
      onOpen: () => openProduct(p),
      saveAction: Semantics(
        button: true, label: 'В папку клиента',
        child: InkWell(
          onTap: () => chooseFolder('${p['id']}'),
          child: const Align(alignment: Alignment.topRight,
            child: Icon(Icons.folder_outlined, size: 16, color: SellerColors.brown)),
        ),
      ),
    );
  }
  Future<void> openProduct(Map p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourierProductScreen(api:widget.api, initial:p.cast<String,dynamic>(), onFolder:()=>chooseFolder('${p['id']}'), onAddProduct:chooseFolder)));
  }

  Widget home() => CustomScrollView(
    slivers: [
      SliverPersistentHeader(
        pinned: true,
        delegate: CourierHomeHeader(
          header: BuyerHeaderLayout.of(context),
          controller: search,
          onChanged: searchChanged,
          onSubmitted: searchFor,
          onPhotoTap: photoSearch,
          onLogoTap: () => searchFor(''),
          onTag: searchFor,
          tags: const [
            'брюки',
            'верхняя одежда',
            'головные уборы',
            'футболки',
            'обувь',
          ],
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(30, 21, 30, 30),
        sliver: SliverToBoxAdapter(
          child: FutureBuilder<CatalogSearchResults<Map<String,dynamic>>>(
            future: products,
            builder: (context, snapshot) {
              if (_searchPending || snapshot.connectionState != ConnectionState.done)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError)
                return TextButton(
                  onPressed: () => searchFor(search.text),
                  child: const Text('Не удалось загрузить. Повторить'),
                );
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final result = snapshot.data!;
              final rows = result.products;
              if (rows.isEmpty && result.sellers.isEmpty)
                return const Center(child: Text('Ничего не найдено'));
              return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                if(result.sellers.isNotEmpty) SellerSearchStrip(
                  sellers:result.sellers,ink:SellerColors.brown,
                  onOpen:(seller)=>Navigator.of(context).push(MaterialPageRoute<void>(
                    builder:(_)=>CourierSellerScreen(api:widget.api,sellerId:seller.id,onAddProduct:chooseFolder)))),
                if(result.sellers.isNotEmpty && rows.isNotEmpty) const Padding(padding:EdgeInsets.only(bottom:12),
                  child:Text('товары',style:TextStyle(fontSize:14,fontWeight:FontWeight.w700,color:SellerColors.brown))),
                if(rows.isNotEmpty) SadohodCatalogGrid(itemCount:rows.length,itemBuilder:(_,i)=>productCard(rows[i])),
              ]);
            },
          ),
        ),
      ),
    ],
  );
  Widget profileMenu() => ListView(
    padding: const EdgeInsets.fromLTRB(30, 0, 30, 24),
    children: [
      SizedBox(height: (MediaQuery.paddingOf(context).top + 24).clamp(94.0, double.infinity).toDouble()),
      SizedBox(
        height: 181,
        child: Stack(
          children: [
            Container(
              height: 150,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: SellerColors.brown,
                borderRadius: BorderRadius.circular(10),
              ),
              child: media['cover'] == null
                  ? null
                  : Image.memory(media['cover']!, fit: BoxFit.cover),
            ),
            Positioned(
              top: 88,
              left: 0,
              right: 0,
              child: Center(
                child: CircleAvatar(
                  radius: 46.5,
                  backgroundColor: const Color(0xffdddddd),
                  backgroundImage: media['avatar'] == null
                      ? null
                      : MemoryImage(media['avatar']!),
                  child: media['avatar'] == null
                      ? const Icon(
                          Icons.person_outline,
                          size: 55,
                          color: Color(0xff888888),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 15),
      Text(
        profile?['name']?.toString() ?? widget.initialName,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 50),
      for (final item in <(String,String,VoidCallback)>[
        ('1b285.svg','профиль',()=>setState(()=>editing=true)),
        ('2f6e7.svg','поддержка',()=>openPage('поддержка',SellerTelegramChat(api:widget.api,kind:'support'))),
        ('40c2b.svg','уведомления',openNotifications),
        ('f7cee.svg','настройки',openSettings),
        ('cdb5f.svg','навигация',openNavigation),
        ('1aa37.svg','сотрудничество',()=>openPage('сотрудничество',SellerTelegramChat(api:widget.api,kind:'cooperation'))),
      ]) InkWell(onTap:item.$3,child:SizedBox(height:44,child:Row(children:[SizedBox(width:30,height:30,child:Center(child:asset(item.$1,width:item.$2=='профиль'?30:24,height:item.$2=='профиль'?30:24))),const SizedBox(width:14),Text(item.$2,style:const TextStyle(fontSize:14,color:Color(0xff2c1b15)))]))),
      const SizedBox(height:24),
      Text(SadohodBuild.label,textAlign:TextAlign.center,style:const TextStyle(fontSize:10,color:SellerColors.muted)),
    ],
  );
  Widget tabBar() => ColoredBox(
    color: Colors.white,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: selectedTab == i,
                  label: ['Поиск', 'Папки', 'Профиль'][i],
                  child: InkWell(
                    onTap: busy ? null : () => selectTab(i),
                    child: Center(
                      child: i == 1
                          ? Icon(
                              Icons.folder_outlined,
                              size: 29,
                              color: selectedTab == i
                                  ? SellerColors.brown
                                  : SellerColors.muted,
                            )
                          : SizedBox(
                              width: i == 0 ? 27 : 33,
                              height: i == 0 ? 27 : 33,
                              child: DesignIcon(
                                i == 0
                                    ? 'v082_tab_search'
                                    : selectedTab == 2
                                    ? '8be73'
                                    : 'f3a3d',
                                color: selectedTab == i
                                    ? SellerColors.brown
                                    : SellerColors.muted,
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
  void selectTab(int index) {
    setState(() {
      selectedTab = index;
      folder = null;
      viewingArchive = false;
      settings = false;
      editing = false;
    });
  }

  Future<void> signOut() => run(() async {
    await widget.api.call('/auth/logout', method: 'POST');
    await widget.api.logout();
  });
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    name.text = widget.initialName;
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    search.dispose();
    name.dispose();
    email.dispose();
    description.dispose();
    for (final c in contacts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && profile != null)
      api.profile().ignore();
  }

  Future<void> load() => run(() async {
    final account = await widget.api.call('/account');
    if (!mounted) return;
    email.text = account['email']?.toString() ?? '';
    final p = await api.profile();
    if (!mounted) return;
    profile = p;
    if (p != null) {
      name.text = p['name']?.toString() ?? '';
      description.text = p['description']?.toString() ?? '';
      final values = p['contacts'] as Map? ?? {};
      for (final k in contacts.keys) {
        contacts[k]!.text = values[k]?.toString() ?? '';
      }
      secondPhone = contacts['phone2']!.text.isNotEmpty;
      await refreshFolders();
      for (final kind in ['avatar', 'cover']) {
        if (p[kind] == null) continue;
        final response = await http
            .get(
              Uri.parse(
                '${widget.api.baseUrl}/api/v1/sadohodets/me/media/$kind',
              ),
              headers: {'Authorization': 'Bearer ${widget.api.token}'},
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) media[kind] = response.bodyBytes;
      }
    }
    loaded = true;
  });
  Future<void> save({bool publish = false}) => run(() async {
    profile = await api.saveProfile(
      name: name.text.trim(),
      description: description.text.trim(),
      contacts: {
        for (final e in contacts.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      },
    );
    if (publish) profile = await api.publication(true);
    await refreshFolders();
  });
  Future<void> pick(String kind) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 75,
    );
    if (image == null || !mounted) return;
    await run(() async {
      final bytes = await image.readAsBytes();
      await ensureProfile();
      profile = await api.uploadMedia(kind, bytes);
      media[kind] = bytes;
    });
  }

  Future<bool> confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> editFolder([
    Map<String, dynamic>? existing,
    String? product,
  ]) async {
    var client = existing?['name']?.toString() ?? '';
    var note = existing?['note']?.toString() ?? '';
    var clientLink = existing?['client_link']?.toString() ?? '';
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Новая папка' : 'Редактировать папку'),
        scrollable: true,
        content: Form(key: formKey, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: client,
              autofocus: true,
              onChanged: (v) => client = v,
              decoration: const InputDecoration(labelText: 'Имя клиента'),
            ),
            TextFormField(
              initialValue: note,
              onChanged: (v) => note = v,
              decoration: const InputDecoration(labelText: 'Заметка'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: clientLink,
              keyboardType: TextInputType.url,
              onChanged: (v) => clientLink = v,
              validator: (v) => (v ?? '').trim().isEmpty || clientContactUri(v!) != null
                  ? null : 'Введите HTTPS-ссылку',
              decoration: const InputDecoration(
                labelText: 'Ссылка на клиента',
                hintText: 'https://t.me/…',
              ),
            ),
          ],
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await run(() async {
      await ensureProfile();
      if (existing == null) {
        await api.createFolder(client.trim(), note.trim(), productId: product, clientLink: clientContactUri(clientLink)?.toString() ?? '');
        await refreshFolders();
        if (mounted && product != null)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Добавлено в папку «${client.trim()}»')),
          );
      } else {
        await api.editFolder(existing['id'], client.trim(), note.trim(), clientLink: clientContactUri(clientLink)?.toString() ?? '');
        await refreshFolders();
        folder = await api.folder(existing['id']);
      }
    });
  }

  Future<void> openClientContact() async {
    final uri = clientContactUri(folder?['client_link']?.toString() ?? '');
    if (uri == null) {
      await editFolder(folder);
      return;
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) { /* Show a useful error rather than silently failing. */ }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть ссылку на клиента')),
    );
  }

  Widget field(String title, TextEditingController c, {int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: V3Field(title, c),
      );
  Widget action(String title, VoidCallback? callback) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: busy ? null : callback,
        style: FilledButton.styleFrom(
          backgroundColor: SellerColors.brown,
          foregroundColor: Colors.white,
        ),
        child: Text(title),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: selectedTab == 0
            ? home()
            : selectedTab == 2 && !editing && !settings
            ? profileMenu()
            : SafeArea(
                top: !editing && folder == null && !viewingArchive,
                bottom: false,
                child: Column(
                  children: [
                    if (editing)
                      V3Header(title: 'профиль', back: () {
                        if (!busy) setState(() => editing = false);
                      })
                    else if (folder != null)
                      CourierFolderHeader(
                        title: folder!['name']?.toString() ?? '',
                        onBack: () {
                          if (!busy) setState(() => folder = null);
                        },
                      ),
                    if (viewingArchive && folder == null && !editing)
                      CourierFolderHeader(title: 'архив', onBack: () {
                        if (!busy) setState(() => viewingArchive = false);
                      }),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          error!,
                          style: const TextStyle(color: SellerColors.danger),
                        ),
                      ),
                    if (!loaded)
                      Expanded(
                        child: Center(
                          child: TextButton(
                            onPressed: busy ? null : load,
                            child: const Text('Повторить'),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: busy,
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(folder != null ? 0 : 30, 12, folder != null ? 0 : 30, 24),
                            children: [
                              const SizedBox(height: 16),
                              if (settings) ...[
                                action('Выйти из аккаунта', signOut),
                              ] else if (folder != null) ...[
                                Padding(padding: const EdgeInsets.symmetric(horizontal: 30),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Row(children: [
                                  Expanded(child: Text(
                                    (folder!['note'] ?? '').toString(),
                                    style: const TextStyle(fontSize: 14, color: SellerColors.brown),
                                  )),
                                  Semantics(label: 'Редактировать папку', button: true,
                                    child: InkWell(onTap: () => editFolder(folder),
                                      child: const SizedBox(width: 36, height: 36,
                                        child: Center(child: Icon(Icons.edit, size: 14, color: SellerColors.brown))),
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 4),
                                SizedBox(height: 48, child: OutlinedButton(
                                  onPressed: busy ? null : openClientContact,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: SellerColors.brown,
                                    side: const BorderSide(color: SellerColors.brown),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.link, size: 18),
                                    const SizedBox(width: 8),
                                    Text(clientContactUri(folder!['client_link']?.toString() ?? '') == null
                                        ? 'добавить ссылку на клиента' : 'связаться с клиентом'),
                                  ]),
                                )),
                                const SizedBox(height: 8),
                                if (folder!['archived'] != true)
                                  action('Добавить по ссылке', addLink)
                                else action('Вернуть из архива', () async {
                                  final entry = folder!;
                                  await archiveFolder(entry);
                                  if (mounted && error == null) setState(() {
                                    folder = null;
                                    viewingArchive = false;
                                  });
                                }),
                                  ])),
                                const SizedBox(height: 46),
                                CourierFolderItems(
                                  key: ValueKey(folder!['id']),
                                  items: (folder!['items'] as List).cast<Map>(),
                                  baseUrl: widget.api.baseUrl,
                                  busy: busy,
                                  onOpen: (item) async {
                                    final product = item['product'];
                                    if (product is Map) await openProduct(product);
                                  },
                                  onQuantity: (item, value) => updateFolderItem(item, quantity: value),
                                  onCollected: (item) => updateFolderItem(item, collected: item['collected'] != true),
                                  onRemove: (item) => updateFolderItem(item, remove: true),
                                ),
                              ] else if (showFolders) ...[
                                if (!viewingArchive) ...[
                                  action('Создать папку', () => editFolder()),
                                  const SizedBox(height: 20),
                                  if (archivedFolders.isNotEmpty)
                                    CourierArchiveEntry(
                                      count: archivedFolders.length,
                                      onTap: () => setState(() => viewingArchive = true),
                                    ),
                                ],
                                if (viewingArchive && archivedFolders.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 32),
                                    child: Text('Архив пуст', textAlign: TextAlign.center,
                                      style: TextStyle(color: SellerColors.muted)),
                                  ),
                                CourierFolderList(
                                  key: ValueKey(viewingArchive),
                                  folders: viewingArchive ? archivedFolders : folders,
                                  archived: viewingArchive,
                                  busy: busy,
                                  onOpen: (entry) => run(() async {
                                    folder = await api.folder(entry['id'].toString());
                                  }),
                                  onArchive: archiveFolder,
                                  onDelete: deleteClientFolder,
                                ),
                              ] else ...[
                                SizedBox(height:181,child:Stack(children:[
                                  GestureDetector(onTap:()=>pick('cover'),child:Container(height:150,width:double.infinity,clipBehavior:Clip.antiAlias,decoration:BoxDecoration(color:SellerColors.brown,borderRadius:BorderRadius.circular(10)),child:media['cover']==null?const Center(child:Icon(Icons.add_a_photo_outlined,color:Colors.white)):Image.memory(media['cover']!,fit:BoxFit.cover))),
                                  Positioned(top:88,left:0,right:0,child:Center(child:GestureDetector(onTap:()=>pick('avatar'),child:CircleAvatar(radius:46.5,backgroundColor:Colors.white,backgroundImage:media['avatar']==null?null:MemoryImage(media['avatar']!),child:media['avatar']==null?const Icon(Icons.add_a_photo_outlined,size:30,color:SellerColors.brown):null)))),
                                ])),
                                const SizedBox(height:15),
                                Text(name.text,textAlign:TextAlign.center,style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
                                const SizedBox(height:20),
                                field('имя', name),
                                Stack(children: [field(labels['phone']!, contacts['phone']!), if (!secondPhone) Positioned(right: 8, top: 8, child: IconButton(onPressed: () => setState(() => secondPhone = true), icon: const Icon(Icons.add_circle))) ]),
                                if (secondPhone) Stack(children: [field(labels['phone2']!, contacts['phone2']!), Positioned(right: 8, top: 8, child: IconButton(onPressed: () => setState(() {secondPhone = false; contacts['phone2']!.clear();}), icon: const Icon(Icons.close))) ]),
                                for (final k in ['telegram','vk','whatsapp']) field(labels[k]!, contacts[k]!),
                                V3Field('email', email, readOnly: true),
                                const SizedBox(height: 20),
                                const Text(
                                  'Для публикации нужен хотя бы один контакт.',
                                ),
                                action('Сохранить', () => save()),
                                if (profile?['published'] == true)
                                  action(
                                    'Скрыть анкету',
                                    () => run(() async {
                                      profile = await api.publication(false);
                                    }),
                                  )
                                else
                                  action(
                                    'Опубликовать',
                                    () => save(publish: true),
                                  ),
                                if (profile != null)
                                  TextButton(
                                    onPressed: () async {
                                      if (await confirm(
                                        'Удалить анкету и папки клиентов?',
                                      ))
                                        await run(() async {
                                          await api.deleteProfile();
                                          profile = null;
                                          folders = [];
                                          archivedFolders = [];
                                          viewingArchive = false;
                                          media.clear();
                                          selectedTab = 2;
                                          description.clear();
                                          for (final c in contacts.values) {
                                            c.clear();
                                          }
                                        });
                                    },
                                    child: const Text('Удалить анкету'),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      tabBar(),
    ],
  );
  Future<void> updateFolderItem(Map item, {int? quantity, bool? collected, bool remove = false}) async {
    if (busy || folder == null) return;
    final id = folder!['id'].toString();
    final pid = item['product_id'].toString();
    await run(() async {
      if (remove) {
        await api.removeItem(id, pid);
      } else if (quantity != null) {
        await api.setQuantity(id, pid, quantity);
      } else if (collected != null) {
        await api.setCollected(id, pid, collected);
      }
      folder = await api.folder(id);
      await refreshFolders();
    });
  }
}

/// The open folder has the same full-bleed compact header geometry as
/// the buyer product page. The header owns the top inset exactly once.
class CourierFolderHeader extends StatelessWidget {
  const CourierFolderHeader({
    super.key, required this.title, required this.onBack,
  });
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final layout = BuyerHeaderLayout.of(context);
    return Container(
      key: const ValueKey('courier-folder-header'),
      height: layout.height,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, layout.contentTop, 14, BuyerHeaderLayout.gap),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: Row(children: [
        SadohodBackButton(onBack: onBack, color: SellerColors.brown),
        Expanded(child: Text(title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: BuyerProductType.detailAddress.copyWith(color: SellerColors.brown))),
        const SizedBox(width: SadohodBackButton.width),
      ]),
    );
  }
}

/// External client links are never public and must not invoke arbitrary schemes.
Uri? clientContactUri(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.length > 2048 || RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(value)) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority ||
      !uri.host.contains('.') || uri.userInfo.isNotEmpty) return null;
  return uri;
}
