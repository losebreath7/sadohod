import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:flutter/services.dart';
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
import 'package:sadohod_shared_core/build_info.dart';
import 'package:sadohod_shared_core/market_addresses.dart';
import 'package:sadohod_shared_core/product_share_actions.dart';
import 'dart:convert';

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
    'phone2': 'дополнительный телефон',
    'telegram': 'Telegram',
    'vk': 'VK',
    'whatsapp': 'WhatsApp',
  };
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> folders = [];
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
  void openSettings() => openPage('настройки', SellerSettingsPage(api:widget.api,courier:true,onSignedOut:(){},onOpenInfo:(kind)=>openPage(kind=='about'?'о приложении':kind=='terms'?'пользовательское соглашение':'конфиденциальность',SellerSettingsInfoPage(kind:kind))));
  void openNotifications() => openPage('уведомления',SellerNotificationsPage(api:widget.api,onOpenPavilions:(){},onOpenProduct:(id) async {try{final product=await widget.api.call('/products/${Uri.encodeComponent(id)}');if(mounted)await openProduct(product);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}));
  void openNavigation() { final address=TextEditingController(); openPage('навигация', _CourierNavigation(controller:address)); }

  final search = TextEditingController();
  late Future<List<Map<String, dynamic>>> products = catalog();
  Future<List<Map<String, dynamic>>> catalog([String query = '']) async {
    final rows = <Map<String, dynamic>>[];
    if (query.trim().isNotEmpty) {
      final r = await widget.api.call(
        '/search/text?q=${Uri.encodeQueryComponent(query.trim())}&limit=100',
      );
      return (r['items'] as List).cast<Map<String, dynamic>>();
    }
    for (var offset = 0; ; offset += 500) {
      final r = await widget.api.call('/products?limit=500&offset=$offset');
      final batch = (r['items'] as List).cast<Map<String, dynamic>>();
      rows.addAll(batch);
      if (batch.length < 500) return rows;
    }
  }

  void searchFor(String q) {
    FocusManager.instance.primaryFocus?.unfocus();
    search.text = q;
    setState(() => products = catalog(q));
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
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.api.baseUrl}/api/v1/search/image'),
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'query.jpg'),
      );
      final result = Future<List<Map<String, dynamic>>>(() async {
        final response = await http.Response.fromStream(
          await request.send().timeout(const Duration(seconds: 60)),
        );
        if (response.statusCode != 200)
          throw Exception('Поиск по фото недоступен');
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
        return (data['items'] as List)
            .map((e) => (e['product'] as Map).cast<String, dynamic>())
            .toList();
      });
      if (mounted) setState(() => products = result);
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
    folders = await api.folders();
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

  String imageUrl(Map p) {
    final images = p['images'] as List? ?? [];
    final raw = (images.isEmpty ? p['image'] : images.first)?.toString() ?? '';
    return raw.startsWith('/') ? '${widget.api.baseUrl}$raw' : raw;
  }

  Widget productPhoto(Map p) => imageUrl(p).isEmpty
      ? const ColoredBox(
          color: Color(0xffdddddd),
          child: Center(child: Icon(Icons.image_outlined)),
        )
      : Image.network(
          imageUrl(p),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.image_outlined)),
        );
  Widget productCard(Map p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: GestureDetector(
          onTap: () => openProduct(p),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox.expand(child: productPhoto(p)),
          ),
        ),
      ),
      const SizedBox(height: 7),
      Text(
        '${p['title'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      if (p['price'] != null)
        Text(approximateRubles((p['price'] as num).toInt()), style: const TextStyle(fontSize: 12)),
      InkWell(
        onTap: () => chooseFolder('${p['id']}'),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16),
              SizedBox(width: 5),
              Text('В папку', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    ],
  );
  Future<void> openProduct(Map p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourierProductScreen(api:widget.api, initial:p.cast<String,dynamic>(), onFolder:()=>chooseFolder('${p['id']}'))));
  }

  Widget home() => CustomScrollView(
    slivers: [
      SliverPersistentHeader(
        pinned: true,
        delegate: CourierHomeHeader(
          header: BuyerHeaderLayout.of(context),
          controller: search,
          onChanged: (_) {},
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
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: products,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return TextButton(
                  onPressed: () => searchFor(search.text),
                  child: const Text('Не удалось загрузить. Повторить'),
                );
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!;
              if (rows.isEmpty)
                return const Center(child: Text('Товары не найдены'));
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: .65,
                ),
                itemCount: rows.length,
                itemBuilder: (_, i) => productCard(rows[i]),
              );
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
      folders = await api.folders();
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
    folders = await api.folders();
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Новая папка' : 'Редактировать папку'),
        scrollable: true,
        content: Column(
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await run(() async {
      await ensureProfile();
      if (existing == null) {
        await api.createFolder(client.trim(), note.trim(), productId: product);
        folders = await api.folders();
        if (mounted && product != null)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Добавлено в папку «${client.trim()}»')),
          );
      } else {
        await api.editFolder(existing['id'], client.trim(), note.trim());
        folders = await api.folders();
        folder = await api.folder(existing['id']);
      }
    });
  }

  Future<void> addProduct() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _ProductPicker(api: widget.api),
    );
    if (selected == null || !mounted || folder == null) return;
    await run(() async {
      final id = '${folder!['id']}';
      await api.addItem(id, selected);
      folder = await api.folder(id);
      folders = await api.folders();
    });
  }

  Widget field(String title, TextEditingController c, {int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
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
                bottom: false,
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (folder != null || settings || editing)
                          IconButton(
                            onPressed: busy
                                ? null
                                : () {
                                    setState(() {
                                      folder = null;
                                      settings = false;
                                      editing = false;
                                    });
                                  },
                            icon: const Icon(Icons.arrow_back),
                          )
                        else
                          const SizedBox(width: 48),
                        Expanded(
                          child: Text(
                            folder?['name']?.toString() ??
                                (settings
                                    ? 'настройки'
                                    : [
                                        'садоходец',
                                        'Папки',
                                        'профиль',
                                      ][selectedTab]),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
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
                            padding: const EdgeInsets.fromLTRB(30, 12, 30, 24),
                            children: [
                              const SizedBox(height: 16),
                              if (settings) ...[
                                action('Выйти из аккаунта', signOut),
                              ] else if (folder != null) ...[
                                Text('${folder!['note'] ?? ''}'),
                                TextButton(
                                  onPressed: () => editFolder(folder),
                                  child: const Text('Редактировать'),
                                ),
                                action('Добавить по ссылке', addLink),
                                TextButton(
                                  onPressed: addProduct,
                                  child: const Text('Найти в каталоге'),
                                ),
                                for (final raw in folder!['items'])
                                  _item(raw as Map),
                              ] else if (showFolders) ...[
                                action('Создать папку', () => editFolder()),
                                for (final f in folders)
                                  ListTile(
                                    title: Text('${f['name']}'),
                                    subtitle: Text(
                                      '${f['note'] ?? ''} • ${f['collected_count']}/${f['count']}',
                                    ),
                                    onTap: () => run(() async {
                                      folder = await api.folder('${f['id']}');
                                    }),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        if (await confirm('Удалить папку?'))
                                          await run(() async {
                                            await api.deleteFolder(
                                              '${f['id']}',
                                            );
                                            folders = await api.folders();
                                          });
                                      },
                                    ),
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
  Widget _item(Map item) {
    final product = item['product'] as Map?;
    final images = product?['images'] as List? ?? [];
    final url = images.isEmpty ? '' : images.first.toString();
    final id = '${folder!['id']}';
    final pid = '${item['product_id']}';
    final addresses = (product?['offers'] as List? ?? [])
        .map((o) => o['pavilion']?['code'])
        .whereType<String>()
        .toSet()
        .join(', ');
    final note = item['note']?.toString() ?? '';
    final title = product?['title']?.toString() ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 48,
        height: 54,
        child: product == null || url.isEmpty
            ? const Icon(Icons.image_not_supported_outlined)
            : productPhoto(product),
      ),
      title: Text(
        title.isNotEmpty ? title : product?['category'] ?? 'Товар недоступен',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (addresses.isNotEmpty) Text(addresses),
          if (product?['price'] is num) Text(approximateRubles((product!['price'] as num).toInt())),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final value = await askText(
                      'Заметка к товару',
                      initial: note,
                    );
                    if (value != null && mounted)
                      await run(() async {
                        await api.saveNote(id, pid, value);
                        folder = await api.folder(id);
                      });
                  },
            child: Text(note.isEmpty ? 'Добавить заметку' : note),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            semanticLabel: 'Собрано',
            value: item['collected'] == true,
            onChanged: busy
                ? null
                : (v) => run(() async {
                    await api.setCollected(id, pid, v!);
                    folder = await api.folder(id);
                    folders = await api.folders();
                  }),
          ),
          IconButton(
            tooltip: 'Убрать из папки',
            onPressed: busy
                ? null
                : () => run(() async {
                    await api.removeItem(id, pid);
                    folder = await api.folder(id);
                    folders = await api.folders();
                  }),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.api});
  final SellerApi api;
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final query = TextEditingController();
  List items = [];
  bool busy = false;
  String? error;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (query.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.call(
        '/search/text?q=${Uri.encodeQueryComponent(query.text.trim())}&limit=100',
      );
      if (mounted) setState(() => items = r['items'] as List? ?? []);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Добавить товар'),
    content: SizedBox(
      width: 340,
      height: 360,
      child: Column(
        children: [
          TextField(
            controller: query,
            onSubmitted: (_) => search(),
            decoration: InputDecoration(
              hintText: 'Поиск',
              suffixIcon: IconButton(
                onPressed: busy ? null : search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final item in items)
                  ListTile(
                    title: Text('${item['title'] ?? ''}'),
                    onTap: () => Navigator.pop(context, '${item['id']}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
    ],
  );
}

class _CourierNavigation extends StatefulWidget {
 const _CourierNavigation({required this.controller});
 final TextEditingController controller;
 @override State<_CourierNavigation> createState()=>_CourierNavigationState();
}
class _CourierNavigationState extends State<_CourierNavigation> {
 String result='';
 @override void dispose(){widget.controller.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(30),children:[
 const Text('Расшифровка адреса',style:TextStyle(fontSize:20,fontWeight:FontWeight.w600)),
 const SizedBox(height:16),V3Field('Введите адрес павильона',widget.controller,onChanged:(value)=>setState(()=>result=value.trim().isEmpty?'':parseMarketAddress(value).details)),
 const SizedBox(height:16),Text(result),]);
}
