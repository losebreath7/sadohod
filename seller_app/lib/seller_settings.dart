import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/build_info.dart';

import 'api.dart';

/// Matches the buyer settings structure, using the seller palette.
class SellerSettingsPage extends StatefulWidget {
  const SellerSettingsPage({
    super.key,
    required this.api,
    required this.onSignedOut,
    required this.onOpenInfo,
    required this.onOpenSupport,
  });

  final SellerApi api;
  final VoidCallback onSignedOut;
  final ValueChanged<String> onOpenInfo;
  final VoidCallback onOpenSupport;

  @override
  State<SellerSettingsPage> createState() => _SellerSettingsPageState();
}

class _SellerSettingsPageState extends State<SellerSettingsPage> {
  static const accent = Color(0xFF5F0F10);
  static const ink = Color(0xFF2C1B15);
  bool busy = false;

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  void clearCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    message('Кэш изображений очищен. Товары и вход сохранены.');
  }

  Future<void> signOut() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.api.call('/auth/logout', method: 'POST');
      await widget.api.logout();
      if (mounted) widget.onSignedOut();
    } catch (_) {
      message('Не удалось выйти. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteAccount() async {
    if (busy) return;
    // Both applications share the same Buyer account. DELETE /account is
    // destructive for the buyer too and can orphan active merchant data.
    // Do not call it from the seller app before a dedicated deletion workflow
    // has been designed and verified.
    final openSupport = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удаление кабинета продавца'),
        content: const Text(
          'Кабинет продавца связан с общим аккаунтом покупателя. '
          'Автоматическое удаление сейчас недоступно: можно потерять доступ '
          'к павильонам, товарам и заявкам. '
          'Напишите в поддержку для безопасного удаления кабинета. '
          'До обработки обращения данные не удаляются.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Написать в поддержку',
              style: TextStyle(color: accent),
            ),
          ),
        ],
      ),
    );
    if (openSupport == true && mounted) widget.onOpenSupport();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 25, 22, 24),
    children: [
      _SettingsGroup(children: [
        _SettingsTile(
          icon: Icons.language,
          name: 'Язык',
          value: 'Русский',
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Язык'),
              content: const Text(
                'Русский — единственный доступный язык первой версии.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Понятно'),
                ),
              ],
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.dark_mode_outlined,
          name: 'Тема',
          value: 'Светлая',
          onTap: () => message(
            'Тёмная тема появится после адаптации всех экранов.',
          ),
        ),
      ]),
      const SizedBox(height: 18),
      _SettingsGroup(children: [
        _SettingsTile(
          icon: Icons.storage_outlined,
          name: 'Очистить кэш',
          onTap: clearCache,
        ),
      ]),
      const SizedBox(height: 18),
      _SettingsGroup(children: [
        _SettingsTile(
          icon: Icons.info_outline,
          name: 'О приложении',
          onTap: () => widget.onOpenInfo('about'),
        ),
        _SettingsTile(
          icon: Icons.description_outlined,
          name: 'Пользовательское соглашение',
          onTap: () => widget.onOpenInfo('terms'),
        ),
        _SettingsTile(
          icon: Icons.shield_outlined,
          name: 'Политика конфиденциальности',
          onTap: () => widget.onOpenInfo('privacy'),
        ),
      ]),
      const SizedBox(height: 35),
      SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: busy ? null : signOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            side: const BorderSide(color: Color(0xFFD8D1CB)),
            shape: const StadiumBorder(),
          ),
          child: Text(busy ? 'подождите…' : 'выйти из аккаунта'),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: busy ? null : deleteAccount,
          child: const Text(
            'удалить аккаунт',
            style: TextStyle(color: accent, fontSize: 12),
          ),
        ),
      ),
    ],
  );
}

class SellerSettingsInfoPage extends StatelessWidget {
  const SellerSettingsInfoPage({super.key, required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(30),
    children: [
      Text(
        kind == 'about'
            ? 'Садоход · ${SadohodBuild.label}\n\nПриложение для продавцов рынка Садовод.'
            : 'Документ готовится к публикации перед публичным запуском приложения.',
        style: const TextStyle(
          fontFamily: SadohodFont.family,
          fontSize: 14,
          color: Color(0xFF2C1B15),
          height: 1.5,
        ),
      ),
    ],
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE8E0DB)),
    ),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, indent: 42, color: Color(0xFFE8E0DB)),
          children[i],
        ],
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.name,
    required this.onTap,
    this.value,
  });
  final IconData icon;
  final String name;
  final VoidCallback onTap;
  final String? value;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 59,
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF48352D), size: 24),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontFamily: SadohodFont.family,
                color: Color(0xFF2C1B15),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (value != null)
            Text(
              value!,
              style: const TextStyle(
                fontFamily: SadohodFont.family,
                fontSize: 12,
                color: Color(0xFF7B6F68),
              ),
            ),
          const SizedBox(width: 7),
          const Icon(Icons.chevron_right, size: 19, color: Color(0xFF48352D)),
        ],
      ),
    ),
  );
}
