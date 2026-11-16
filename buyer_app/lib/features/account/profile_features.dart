import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/build_info.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sadohod_shared_core/chat_widgets.dart';

import '../../core/widgets/design.dart';
import '../../data/account.dart';
import '../../data/api.dart';

class _BuyerPageTop extends StatelessWidget {
  const _BuyerPageTop(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Container(
    height: 75,
    decoration: const BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
    padding: const EdgeInsets.fromLTRB(30, 37, 30, 5),
    child: Row(children: [
      const RoundBack(),
      Expanded(child: Text(title, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
      const SizedBox(width: 32),
    ]),
  );
}

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _name = TextEditingController(text: AccountStore.instance.name);
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _pickMedia(String kind) async {
    if (_busy) return;
    try {
      final xfile = await ImagePicker().pickImage(source: ImageSource.gallery,
        maxWidth: kind == 'cover' ? 1600 : 640,
        maxHeight: kind == 'cover' ? 900 : 640,
        imageQuality: 70);
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      if (bytes.length > 1500000) throw const FormatException('Выберите изображение меньше 1,5 МБ');
      setState(() { _busy = true; _error = null; });
      await AccountStore.instance.saveMedia(kind, bytes);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message
        : e is FormatException ? e.message : 'Не удалось сохранить фотографию.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await AccountStore.instance.saveName(_name.text.trim());
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Не удалось сохранить профиль');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AccountStore.instance,
    builder: (context, _) {
      final a = AccountStore.instance;
      return ColoredBox(color: const Color(0xfff1f1f1), child: Column(children: [
        const _BuyerPageTop('профиль'),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(30, 15, 30, 30), children: [
          SizedBox(height: 195, child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            GestureDetector(onTap: _busy ? null : () => _pickMedia('cover'),
              child: Container(
                width: double.infinity, height: 150,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                child: Stack(fit: StackFit.expand, children: [
                  if (a.cover != null) Image.memory(a.cover!, fit: BoxFit.cover),
                  const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.image_outlined, size: 23, color: Colors.white),
                    SizedBox(height: 10),
                    Text('редактировать обложку', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ])),
                ]),
              ),
            ),
            Positioned(bottom: 0, child: GestureDetector(
              onTap: _busy ? null : () => _pickMedia('avatar'),
              child: Stack(clipBehavior: Clip.none, children: [
                CircleAvatar(radius: 47, backgroundColor: const Color(0xffdddddd),
                  backgroundImage: a.avatar != null ? MemoryImage(a.avatar!) : null,
                  child: a.avatar == null
                    ? const Icon(Icons.person, size: 47, color: Color(0xff969696)) : null),
                const Positioned(right: 0, bottom: 0, child: CircleAvatar(
                  radius: 17, backgroundColor: Colors.black,
                  child: Icon(Icons.photo_camera_outlined, color: Colors.white, size: 20))),
              ]),
            )),
          ])),
          const SizedBox(height: 25),
          _FieldCard(label: 'Имя', child: TextField(controller: _name, maxLength: 80,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(counterText: '', hintText: 'Имя',
              filled: false, border: InputBorder.none, enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero))),
          const SizedBox(height: 12),
          _FieldCard(label: 'Email', child: InkWell(
            onTap: () => context.push('/change-email'),
            child: Row(children: [
              Expanded(child: Text(a.email, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14))),
              const Icon(Icons.chevron_right, size: 20),
            ]),
          )),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
          const SizedBox(height: 58),
          SizedBox(height: 52, child: FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: Colors.black, shape: const StadiumBorder()),
            child: Text(_busy ? 'сохраняем…' : 'сохранить', style: const TextStyle(fontSize: 16)),
          )),
        ])),
      ]));
    },
  );
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 76),
    padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffeaeaea))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xff6c6c6c))),
      const SizedBox(height: 8), child,
    ]),
  );
}

class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});
  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;
  @override
  void dispose() { _email.dispose(); _code.dispose(); super.dispose(); }
  Future<void> _send() async {
    setState(() { _busy = true; _error = null; });
    try {
      await AccountStore.instance.requestEmailChange(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Не удалось отправить код');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _confirm() async {
    setState(() { _busy = true; _error = null; });
    try {
      await AccountStore.instance.confirmEmailChange(_email.text.trim(), _code.text.trim());
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Неверный код');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => ColoredBox(color: const Color(0xfff1f1f1), child: Column(children: [
    const _BuyerPageTop('сменить почту'),
    Expanded(child: ListView(padding: const EdgeInsets.all(30), children: [
      const Text('Новый адрес нужно подтвердить кодом из письма.', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 20),
      _FieldCard(label: 'Новая почта', child: TextField(controller: _email,
        enabled: !_sent, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(filled: false, border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero))),
      if (_sent) ...[
        const SizedBox(height: 15),
        _FieldCard(label: 'Шестизначный код', child: TextField(controller: _code,
          keyboardType: TextInputType.number, maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(filled: false, border: InputBorder.none, counterText: '',
            isDense: true, contentPadding: EdgeInsets.zero))),
      ],
      const SizedBox(height: 20),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
      FilledButton(onPressed: _busy ? null : _sent ? _confirm : _send,
        style: FilledButton.styleFrom(backgroundColor: Colors.black),
        child: Text(_busy ? 'пожалуйста, подождите…' : _sent ? 'подтвердить' : 'получить код')),
    ])),
  ]));
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  String _language = 'Русский';

  Future<void> _clearCache() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Кэш изображений очищен. Избранное и вход сохранены.')));
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try { await AccountStore.instance.logout(); if (mounted) context.go('/account'); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось выйти. Попробуйте ещё раз.'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _deleteAccount() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text('Будут удалены профиль, сохранённые товары и продавцы. Восстановить их после удаления нельзя.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AccountStore.instance.logout(delete: true);
      if (mounted) context.go('/account');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Не удалось удалить аккаунт. Повтори попытку позже.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f1f1),
    child: Column(children: [
      const _BuyerPageTop('настройки'),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(22, 25, 22, 24), children: [
        _SettingsGroup(children: [
          _SettingsTile(icon: Icons.notifications_none, name: 'Уведомления', onTap: () => context.push('/notifications')),
          _SettingsTile(icon: Icons.language, name: 'Язык', value: _language,
            onTap: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Язык'),
              content: const Text('Русский — единственный доступный язык первой версии.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))],
            ))),
          _SettingsTile(icon: Icons.dark_mode_outlined, name: 'Тема', value: 'Светлая',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Тёмная тема появится после адаптации всех экранов.')))),
        ]),
        const SizedBox(height: 18),
        _SettingsGroup(children: [
          _SettingsTile(icon: Icons.storage_outlined, name: 'Очистить кэш', onTap: _clearCache),
        ]),
        const SizedBox(height: 18),
        _SettingsGroup(children: [
          _SettingsTile(icon: Icons.info_outline, name: 'О приложении', onTap: () => context.push('/about')),
          _SettingsTile(icon: Icons.description_outlined, name: 'Пользовательское соглашение',
            onTap: () => context.push('/legal/terms')),
          _SettingsTile(icon: Icons.shield_outlined, name: 'Политика конфиденциальности',
            onTap: () => context.push('/legal/privacy')),
        ]),
        const SizedBox(height: 35),
        SizedBox(height: 48, child: OutlinedButton(
          onPressed: _busy ? null : _logout,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.black,
            side: const BorderSide(color: Color(0xffc9c9c9)), shape: const StadiumBorder()),
          child: Text(_busy ? 'подождите…' : 'выйти из аккаунта'),
        )),
        const SizedBox(height: 12),
        Center(child: TextButton(
          onPressed: _busy ? null : _deleteAccount,
          child: const Text('удалить аккаунт',
            style: TextStyle(color: Color(0xff9a4141), fontSize: 12)),
        )),
      ])),
    ]),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xffeaeaea))),
    child: Column(children: [for (int i = 0; i < children.length; i++) ...[
      if (i > 0) const Divider(height: 1, indent: 42, color: Color(0xffeaeaea)),
      children[i],
    ]]),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.name, required this.onTap, this.value});
  final IconData icon;
  final String name;
  final VoidCallback onTap;
  final String? value;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(height: 59, child: Row(children: [
      Icon(icon, color: Colors.black, size: 24),
      const SizedBox(width: 15),
      Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      if (value != null) Text(value!, style: const TextStyle(fontSize: 12, color: Color(0xff6c6c6c))),
      const SizedBox(width: 7), const Icon(Icons.chevron_right, size: 19),
    ])),
  );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final enabled = <String, bool>{
    'Избранное': true,
    'Любимые продавцы': true,
    'Акции и подборки': false,
    'Обновления приложения': true,
  };
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      for (final key in enabled.keys.toList()) enabled[key] = p.getBool('notifications.$key') ?? enabled[key]!;
    });
  }
  Future<void> _toggle(String key, bool state) async {
    setState(() => enabled[key] = state);
    final p = await SharedPreferences.getInstance();
    await p.setBool('notifications.$key', state);
  }
  @override
  Widget build(BuildContext context) => ColoredBox(color: const Color(0xfff1f1f1), child: Column(children: [
    const _BuyerPageTop('уведомления'),
    Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(22, 35, 22, 30), children: [
      _SettingsGroup(children: [
        for (final item in [
          ('Избранное', 'Обновления по сохранённым товарам', Icons.favorite_border),
          ('Любимые продавцы', 'Новинки и обновления', Icons.storefront_outlined),
          ('Акции и подборки', 'Интересные предложения', Icons.campaign_outlined),
          ('Обновления приложения', 'Новые функции и улучшения', Icons.info_outline),
        ])
          SizedBox(height: 75, child: Row(children: [
            Icon(item.$3, color: Colors.black, size: 24),
            const SizedBox(width: 15),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                Text(item.$2, style: const TextStyle(fontSize: 11, color: Color(0xff6c6c6c))),
              ])),
            Switch(value: enabled[item.$1] ?? false,
              onChanged: (value) => _toggle(item.$1, value),
              activeThumbColor: Colors.white, activeTrackColor: Colors.black),
          ])),
      ]),
      const SizedBox(height: 16),
      const Text('Предпочтения сохранены. Push-уведомления будут доступны после подключения сервиса рассылки.',
        style: TextStyle(color: Color(0xff6c6c6c), fontSize: 11)),
    ])),
  ]));
}

class BuyerInfoScreen extends StatelessWidget {
  const BuyerInfoScreen(this.kind, {super.key});
  final String kind;
  @override
  Widget build(BuildContext context) {
    final legal = kind != 'about';
    final title = kind == 'about' ? 'о приложении'
      : kind == 'terms' ? 'пользовательское соглашение' : 'конфиденциальность';
    return ColoredBox(color: const Color(0xfff1f1f1), child: Column(children: [
      _BuyerPageTop(title),
      Expanded(child: ListView(padding: const EdgeInsets.all(30), children: [
        Text(legal ? 'Документ готовится к публикации перед публичным запуском приложения.'
          : 'Садоход · ${SadohodBuild.label}\n\nПоиск товаров и павильонов рынка Садовод. Каталог и адреса в тестовой версии демонстрационные.',
          style: const TextStyle(fontSize: 14, height: 1.5)),
      ])),
    ]));
  }
}

/// Customer support and cooperation chats share the approved Figma layout.
/// Messages are ordered oldest to newest by the API, but rendered in a
/// reverse ListView: the newest message sits immediately above the composer.
/// Only messages returned by the server are shown (no fabricated manager replies).
class BuyerChatScreen extends StatefulWidget {
  const BuyerChatScreen({required this.kind, super.key});
  final String kind;

  @override
  State<BuyerChatScreen> createState() => _BuyerChatScreenState();
}

class _BuyerChatScreenState extends State<BuyerChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _busy = false;
  bool _loading = false;
  String? _error;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _load(jumpToLatest: true);
    // New Telegram manager replies become visible while the chat is open.
    _poller = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_busy) _load();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _moveToLatest({required bool immediately}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // In a reverse ListView, scroll position 0 is the *bottom* of the chat.
      if (immediately) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic);
      }
    });
  }

  Future<void> _load({bool jumpToLatest = false}) async {
    if (!AccountStore.instance.signedIn || _loading) return;
    _loading = true;
    try {
      final data = await AccountStore.instance.request(
        '/account/messages?kind=${widget.kind}&with_greeting=true', method: 'GET');
      if (!mounted) return;
      final newer = (data['items'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>().toList();
      final previousLast = _messages.isEmpty ? '' : _messages.last['id']?.toString() ?? '';
      final nextLast = newer.isEmpty ? '' : newer.last['id']?.toString() ?? '';
      // Avoid rebuilding and jumping a chat that hasn't changed.
      final changed = previousLast != nextLast || _messages.length != newer.length || jumpToLatest;
      // A previously failed GET must not leave a stale red error behind after
      // a successful poll when the number and IDs of messages are unchanged.
      if (changed || _error == 'Не удалось загрузить переписку') {
        setState(() {
          if (changed) _messages = newer;
          if (_error == 'Не удалось загрузить переписку') _error = null;
        });
        if (jumpToLatest) _moveToLatest(immediately: true);
        else if (previousLast != nextLast) _moveToLatest(immediately: false);
      }
    } catch (_) {
      // Polling failures are transient on mobile networks. Preserve already
      // loaded history and let the next poll retry without changing the layout.
      if (mounted && _messages.isEmpty && jumpToLatest) {
        setState(() => _error = 'Не удалось загрузить переписку');
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _send() async {
    final message = _input.text.trim();
    if (message.isEmpty || _busy) return;
    if (!AccountStore.instance.signedIn) {
      context.go('/account');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await AccountStore.instance.request('/account/messages',
        body: {'kind': widget.kind, 'text': message, 'auto_ack': true});
      _input.clear();
      await _load();
      _moveToLatest(immediately: false);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException
        ? e.message : 'Не удалось отправить сообщение');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAttachment() async {
    if (_busy) return;
    if (!AccountStore.instance.signedIn) {
      context.go('/account');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty || bytes.length > 3000000) {
        throw const FormatException('Файл должен быть меньше 3 МБ');
      }
      setState(() { _busy = true; _error = null; });
      await AccountStore.instance.request('/account/messages/attachment', body: {
        'kind': widget.kind, 'filename': file.name,
        'data': base64Encode(bytes), 'auto_ack': true,
        // File uploads are separate from the text composer, as in the mockup.
        // The user's typed draft stays in the field and can be sent afterwards.
        'text': '',
      });
      await _load();
      _moveToLatest(immediately: false);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message
        : e is FormatException ? e.message
        : 'Не удалось прикрепить файл');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SadohodChatHeader(
        title: widget.kind == 'support' ? 'поддержка' : 'сотрудничество',
        onBack: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/account');
          }
        },
      ),
      Expanded(
        child: SadohodChatConversation(
          patternAsset: widget.kind == 'support'
              ? 'assets/figma/v082_support_pattern.png'
              : 'assets/figma/v082_cooperation_pattern.png',
          scrollController: _scroll,
          messages: _messages,
          inputController: _input,
          busy: _busy,
          error: _error,
          onSend: _send,
          onAttachment: _pickAttachment,
        ),
      ),
    ],
  );
}

