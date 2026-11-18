import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'design_tokens.dart';

/// Shared presentation for all four Sadohod chats. The account API, message
/// polling and Telegram routing remain independent in the two applications.
///
/// Polls must repaint when Telegram delivery changes even if there is no new
/// message ID. Both applications use this same comparison.
bool sadohodChatMessagesChanged(
  List<Map<String, dynamic>> previous,
  List<Map<String, dynamic>> next,
) {
  if (previous.length != next.length) return true;
  for (var i = 0; i < next.length; i++) {
    if (previous[i]['id'] != next[i]['id'] ||
        (previous[i]['delivered'] == true) != (next[i]['delivered'] == true)) {
      return true;
    }
  }
  return false;
}
class SadohodChatHeader extends StatelessWidget {
  const SadohodChatHeader({
    super.key,
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // Seller provides its own top inset, while buyer's shell consumes it
    // using SafeArea. The visible header is identical in both cases.
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      height: topInset + 44,
      padding: EdgeInsets.only(top: topInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: SadohodFont.family, fontSize: 16,
                fontWeight: FontWeight.w700, color: Colors.black,
              ),
            ),
          ),
          Positioned(
            left: 14, top: 0, bottom: 0,
            child: Semantics(
              button: true, label: 'Назад',
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onBack,
                child: const SizedBox(
                  width: 46, height: 44,
                  child: Center(child: Icon(Icons.chevron_left, size: 29)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One shared composer for all four chats. The input decoration owns the
/// vertical spacing: there is no second layer of padding shifting the hint.
/// It starts as a 44px field, grows up to five lines, then scrolls internally.
class SadohodChatComposer extends StatelessWidget {
  const SadohodChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttachment,
    this.busy = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttachment;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      alignment: Alignment.bottomCenter,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Semantics(
              button: true, label: 'Прикрепить файл',
              child: InkWell(
                borderRadius: BorderRadius.circular(25),
                onTap: busy ? null : onAttachment,
                child: SizedBox(
                  width: 44, height: 44,
                  child: Center(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 34, height: 34,
                        child: Center(child: SvgPicture.asset(
                          'assets/figma/v083_chat_clip.svg',
                          width: 14, height: 20,
                        )),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: controller,
                  enabled: !busy,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 1,
                  maxLines: 5,
                  textAlignVertical: TextAlignVertical.center,
                  strutStyle: const StrutStyle(
                    fontFamily: SadohodFont.family, fontSize: 14,
                    height: 20 / 14, forceStrutHeight: true,
                  ),
                  style: const TextStyle(
                    fontFamily: SadohodFont.family, fontSize: 14,
                    height: 20 / 14, color: Colors.black,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'сообщение',
                    hintStyle: TextStyle(
                      fontFamily: SadohodFont.family, fontSize: 14,
                      color: Color(0xFFA5A5A5), height: 20 / 14,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3),
            Semantics(
              button: true, label: 'Отправить сообщение',
              child: InkWell(
                borderRadius: BorderRadius.circular(25),
                onTap: busy ? null : onSend,
                child: SizedBox(
                  width: 44, height: 44,
                  child: Center(
                    child: Opacity(
                      opacity: busy ? 0.45 : 1,
                      child: SvgPicture.asset(
                        'assets/figma/v083_chat_send.svg',
                        width: 34, height: 34,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrollable message area + composer. Explicit spacing before the app tab bar
/// works on both 700px Figma frames and an 874px iPhone preview. The keyboard
/// can shrink the list without altering the composer geometry.
class SadohodChatConversation extends StatelessWidget {
  const SadohodChatConversation({
    super.key,
    required this.patternAsset,
    required this.scrollController,
    required this.messages,
    required this.inputController,
    required this.onSend,
    required this.onAttachment,
    this.busy = false,
    this.error,
  });

  final String patternAsset;
  final ScrollController scrollController;
  final List<Map<String, dynamic>> messages;
  final TextEditingController inputController;
  final VoidCallback onSend;
  final VoidCallback onAttachment;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0EFEB),
        image: DecorationImage(
          image: AssetImage(patternAsset),
          repeat: ImageRepeat.repeat,
          fit: BoxFit.none,
          alignment: Alignment.topCenter,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              reverse: true,
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(8, 14, 6, 14),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final m = messages[messages.length - index - 1];
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: SadohodChatBubble(
                    text: m['text']?.toString() ?? '',
                    mine: m['staff'] != true,
                    attachment: m['attachment'] is Map
                        ? Map<String, dynamic>.from(m['attachment'] as Map)
                        : null,
                    sent: m['sent'] is num
                        ? (m['sent'] as num).toDouble() : null,
                    delivered: m['delivered'] == true,
                  ),
                );
              },
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
              child: Text(
                error!,
                style: const TextStyle(
                  fontSize: 12, color: Color(0xFF5F0F10),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: EdgeInsets.only(bottom: keyboardVisible ? 8 : 17, top: 6),
            child: SadohodChatComposer(
              controller: inputController,
              onSend: onSend,
              onAttachment: onAttachment,
              busy: busy,
            ),
          ),
        ],
      ),
    );
  }
}

/// Consistent message geometry: short text and metadata share a row, while
/// wrapped text uses its own row and the timestamp is pinned to bottom-right.
/// No floating overlay or guessed 83px suffix is used for text widths.
class SadohodChatBubble extends StatelessWidget {
  const SadohodChatBubble({
    super.key,
    required this.text,
    required this.mine,
    this.attachment,
    this.sent,
    this.delivered = false,
  });

  final String text;
  final bool mine;
  final Map<String, dynamic>? attachment;
  final double? sent;
  /// True only after the server confirms Telegram delivery (not read).
  /// A stored-but-pending message gets one gray check. A delivered message
  /// gets two gray checks; there is no unsupported blue "read" state.
  final bool delivered;

  String get displayTime {
    if (sent == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch((sent! * 1000).round());
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  double _textWidth(BuildContext context) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 14,
          height: 18 / 14),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final result = painter.width;
    painter.dispose();
    return result;
  }

  Widget _meta() => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(displayTime,
        style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 10,
          height: 1.2, color: Color(0xFF929292))),
      if (mine) ...[
        const SizedBox(width: 4),
        if (delivered)
          const Icon(Icons.done_all, size: 14,
            color: Color(0xFF929292), semanticLabel: 'Доставлено в Telegram')
        else
          const Icon(Icons.check, size: 12,
            color: Color(0xFF929292), semanticLabel: 'Отправлено'),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const sideInset = 20.0; // 10px on both sides of the bubble.
        const gap = 8.0;
        final maximum = (constraints.maxWidth - 27 - 8 - 8)
            .clamp(82.0, 291.0).toDouble();
        final measuredText = _textWidth(context);
        final metadataWidth = sent == null ? 0.0 : (mine ? 59.0 : 43.0);
        final oneLineWidth = measuredText + sideInset +
            (sent == null ? 0.0 : metadataWidth + gap);
        final file = attachment;
        final inlineMeta = file == null && sent != null &&
            !text.contains('\n') && oneLineWidth <= maximum;
        final desiredWidth = file != null
            ? 232.0
            : inlineMeta
                ? oneLineWidth
                : measuredText + sideInset;
        final width = desiredWidth.clamp(82.0, maximum).toDouble();
        final preview = file?['preview']?.toString() ?? '';
        final avatar = SvgPicture.asset('assets/figma/v083_chat_avatar.svg',
          width: 27, height: 28);

        const messageStyle = TextStyle(
          fontFamily: SadohodFont.family, fontSize: 14,
          height: 18 / 14, color: Colors.black,
        );

        Widget textAndTime() {
          if (sent == null) {
            return Text(text, style: messageStyle, softWrap: true);
          }
          if (inlineMeta) {
            return Row(
              // Without this, the time sits halfway up the 18px text line.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Text(text, style: messageStyle,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: gap),
                _meta(),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: messageStyle, softWrap: true),
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: _meta()),
            ],
          );
        }

        final bubble = Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: file == null
              ? textAndTime()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (preview.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.memory(
                          base64Decode(preview),
                          width: width - sideInset,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      Row(
                        children: [
                          const Icon(Icons.attach_file, size: 16),
                          const SizedBox(width: 5),
                          Expanded(child: Text(
                            file['filename']?.toString() ?? 'Файл',
                            maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          )),
                        ],
                      ),
                    if (sent != null) ...[
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight, child: _meta()),
                    ],
                  ],
                ),
        );

        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: mine
                ? [bubble, const SizedBox(width: 8), avatar]
                : [avatar, const SizedBox(width: 6), bubble],
          ),
        );
      },
    );
  }
}
