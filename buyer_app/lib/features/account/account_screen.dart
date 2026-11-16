import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/account.dart';
import '../../data/api.dart';
import '../../data/catalog.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final email = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final address = email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      setState(() => error = 'Проверьте адрес электронной почты');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await AccountStore.instance.ensureSessionStorageReady();
      await AccountStore.instance.request(
        '/auth/code',
        body: {'email': address},
      );
      if (mounted) context.push('/confirm', extra: address);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : e is AuthStorageUnavailable
              ? e.message
              : 'Не удалось отправить код. Проверьте соединение.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AccountStore.instance,
    builder: (context, _) {
      if (AccountStore.instance.signedIn) return const ProfileScreen();
      return ListView(
        padding: const EdgeInsets.fromLTRB(30, 23, 30, 30),
        children: [
          const Text(
            'личный кабинет',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: -.44,
            ),
          ),
          const SizedBox(height: 142),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!busy) send();
            },
            style: const TextStyle(fontSize: 12),
            decoration: emailDecoration('электронная почта'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          const SizedBox(height: 30),
          Center(
            child: SmallAction(
              busy ? 'отправляем…' : 'получить код',
              busy ? null : send,
            ),
          ),
        ],
      );
    },
  );
}

InputDecoration emailDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(fontSize: 12, color: Color(0xffa5a5a5)),
  fillColor: const Color(0xffeaeaea),
  filled: true,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 21, vertical: 13),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(24),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(24),
    borderSide: BorderSide.none,
  ),
);

class SmallAction extends StatelessWidget {
  const SmallAction(this.text, this.onPressed, {super.key});
  final String text;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      minimumSize: const Size(115, 40),
      shape: const StadiumBorder(),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
    ),
  );
}

class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({required this.email, super.key});
  final String email;
  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  final code = TextEditingController();
  final focus = FocusNode();
  bool busy = false;
  String? error;
  DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
  Timer? timer;
  int get remaining =>
      deadline.difference(DateTime.now()).inSeconds.clamp(0, 60);
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> submit({bool resend = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (resend) {
        await AccountStore.instance.ensureSessionStorageReady();
        await AccountStore.instance.request(
          '/auth/code',
          body: {'email': widget.email},
        );
        deadline = DateTime.now().add(const Duration(seconds: 60));
        code.clear();
      } else {
        await AccountStore.instance.verify(widget.email, code.text);
        if (mounted) context.go('/account');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : e is AuthStorageUnavailable
              ? e.message
              : 'Не удалось выполнить запрос. Проверьте соединение.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(30, 12, 30, 30),
    children: [
      Row(
        children: [
          const RoundBack(),
          const Expanded(
            child: Text(
              'подтверждение',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
      Text(
        'отправили код на ${widget.email}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xffa5a5a5)),
      ),
      TextButton(
        onPressed: () => context.pop(),
        child: const Text('Изменить почту', style: TextStyle(fontSize: 12)),
      ),
      const SizedBox(height: 76),
      Stack(
        children: [
          TextField(
            controller: code,
            focusNode: focus,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (code.text.length == 6) submit();
            },
            style: const TextStyle(color: Colors.transparent),
            cursorColor: Colors.transparent,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int i = 0; i < 6; i++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i == 5 ? 0 : 10),
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xffeaeaea),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        i < code.text.length ? code.text[i] : '',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            error!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: remaining == 0 && !busy ? () => submit(resend: true) : null,
        child: Text(
          remaining > 0
              ? 'Отправить повторно через 00:${remaining.toString().padLeft(2, '0')}'
              : 'Отправить код повторно',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      Center(
        child: SmallAction(
          busy ? 'подождите…' : 'войти',
          !busy && code.text.length == 6 ? () => submit() : null,
        ),
      ),
    ],
  );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AccountStore.instance,
    builder: (context, _) {
      final a = AccountStore.instance;
      final menu = <(String, String, String, double, double)>[
        ('34999', 'профиль', '/profile', 29, 29),
        ('3134f', 'избранные товары', '/favorites', 17, 14),
        ('045c1', 'любимые продавцы', '/favorite-sellers', 19, 17),
        ('57599', 'поддержка', '/support', 17, 17),
        ('e6ee6', 'настройки', '/settings', 20, 20),
        ('v082_menu_location', 'навигация', '/map', 17, 20),
        ('v082_menu_cooperation', 'сотрудничество', '/cooperation', 21, 14),
      ];
      return ListView(
        padding: const EdgeInsets.fromLTRB(30, 10, 30, 24),
        children: [
          SizedBox(height: 180, child: Stack(children: [
            Container(
              height: 150,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
              child: a.cover == null ? null : Image.memory(a.cover!, fit: BoxFit.cover, width: double.infinity),
            ),
            Positioned(bottom: 0, left: 0, right: 0,
              child: Center(child: CircleAvatar(
                radius: 46, backgroundColor: const Color(0xffdddddd),
                backgroundImage: a.avatar == null ? null : MemoryImage(a.avatar!),
                child: a.avatar == null ? const Icon(Icons.person, color: Color(0xff888888), size: 55) : null,
              )),
            ),
          ])),
          const SizedBox(height: 15),
          Text(a.name.isEmpty ? 'Пользователь' : a.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          if (a.syncError != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(a.syncError!, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 12))),
          const SizedBox(height: 35),
          for (final m in menu)
            InkWell(
              onTap: () => context.push(m.$3),
              child: SizedBox(height: 40, child: Row(children: [
                SizedBox(width: 29, height: 29, child: Center(child: SizedBox(
                  width: m.$4, height: m.$5, child: DesignIcon(m.$1)))),
                const SizedBox(width: 12),
                Text(m.$2, style: const TextStyle(fontSize: 12)),
              ])),
            ),
          const SizedBox(height: 35),
          Center(child: InkWell(onTap: () => context.push('/cooperation'),
            child: const Text('вы продавец?',
              style: TextStyle(fontSize: 12, color: Color(0xffa5a5a5))))),
        ],
      );
    },
  );
}
