import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/chat_widgets.dart';

import 'api.dart';

/// Seller support and cooperation: same approved chat components as buyer,
/// independent seller authentication, separate namespaces and brand pattern.
/// Page header and seller tab bar are owned by SellerV3.
class SellerTelegramChat extends StatefulWidget {
  const SellerTelegramChat({super.key, required this.api, required this.kind});
  final SellerApi api;
  final String kind;

  @override
  State<SellerTelegramChat> createState() => _SellerTelegramChatState();
}

class _SellerTelegramChatState extends State<SellerTelegramChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Timer? _poller;
  bool _busy = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(jumpToLatest: true);
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
    if (!widget.api.signedIn || _loading) return;
    _loading = true;
    try {
      final data = await widget.api.call('/merchant/chat/messages?kind=${widget.kind}');
      if (!mounted) return;
      final next = (data['items'] as List? ?? const [])
          .whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      final previousId = _messages.isEmpty ? '' : '${_messages.last['id']}';
      final nextId = next.isEmpty ? '' : '${next.last['id']}';
      final changed = jumpToLatest || sadohodChatMessagesChanged(_messages, next);
      if (changed || _error == 'Не удалось загрузить переписку') {
        setState(() {
          if (changed) _messages = next;
          if (_error == 'Не удалось загрузить переписку') _error = null;
        });
        if (jumpToLatest || previousId != nextId) {
          _moveToLatest(immediately: jumpToLatest);
        }
      }
    } catch (_) {
      if (mounted && _messages.isEmpty && jumpToLatest) {
        setState(() => _error = 'Не удалось загрузить переписку');
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.call('/merchant/chat/messages',
          method: 'POST', body: {'kind': widget.kind, 'text': text});
      _input.clear();
      await _load();
      _moveToLatest(immediately: false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAttachment() async {
    if (_busy) return;
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
      await widget.api.call('/merchant/chat/messages/attachment',
        method: 'POST', body: {
          'kind': widget.kind, 'filename': file.name,
          'data': base64Encode(bytes), 'text': '',
        });
      await _load();
      _moveToLatest(immediately: false);
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message
          : e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SadohodChatConversation(
    patternAsset: widget.kind == 'support'
        ? 'assets/figma/seller_support_pattern.png'
        : 'assets/figma/seller_cooperation_pattern.png',
    scrollController: _scroll,
    messages: _messages,
    inputController: _input,
    busy: _busy,
    error: _error,
    onSend: _send,
    onAttachment: _pickAttachment,
  );
}
