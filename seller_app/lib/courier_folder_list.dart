import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'courier_swipe_actions.dart';

class CourierArchiveEntry extends StatelessWidget {
  const CourierArchiveEntry({super.key, required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(height: 52, child: Row(children: [
      const SizedBox(width: 16),
      const Icon(Icons.archive_outlined, size: 20, color: SellerColors.brown),
      const SizedBox(width: 12),
      const Expanded(child: Text('архив', style: TextStyle(
        fontFamily: SadohodFont.family, fontSize: 14, color: SellerColors.brown))),
      Text('$count', style: const TextStyle(color: SellerColors.muted, fontSize: 12)),
      const SizedBox(width: 8),
      const Icon(Icons.chevron_right, color: SellerColors.muted, size: 18),
      const SizedBox(width: 12),
    ])),
  );
}

class CourierFolderList extends StatefulWidget {
  const CourierFolderList({super.key, required this.folders, required this.archived,
    required this.onOpen, required this.onArchive, required this.onDelete, this.busy = false});
  final List<Map<String, dynamic>> folders;
  final bool archived, busy;
  final Future<void> Function(Map) onOpen, onArchive, onDelete;
  @override
  State<CourierFolderList> createState() => _CourierFolderListState();
}

class _CourierFolderListState extends State<CourierFolderList> {
  String? opened;
  @override
  Widget build(BuildContext context) => Column(children: [
    for (final entry in widget.folders)
      Padding(
        key: ValueKey(entry['id']),
        padding: const EdgeInsets.only(bottom: 18),
        child: _SwipeFolderRow(
          folder: entry, archived: widget.archived, busy: widget.busy,
          opened: opened == entry['id'].toString(),
          onReveal: (show) => setState(() => opened = show ? entry['id'].toString() : null),
          onOpen: () => widget.onOpen(entry),
          onArchive: () async {
            setState(() => opened = null);
            await widget.onArchive(entry);
          },
          onDelete: () async {
            setState(() => opened = null);
            await widget.onDelete(entry);
          },
        ),
      ),
  ]);
}

class _SwipeFolderRow extends StatefulWidget {
  const _SwipeFolderRow({required this.folder, required this.archived,
    required this.busy, required this.opened, required this.onReveal,
    required this.onOpen, required this.onArchive, required this.onDelete});
  final Map folder;
  final bool archived, busy, opened;
  final ValueChanged<bool> onReveal;
  final VoidCallback onOpen, onArchive, onDelete;
  @override
  State<_SwipeFolderRow> createState() => _SwipeFolderRowState();
}

class _SwipeFolderRowState extends State<_SwipeFolderRow> {
  static const double height = CourierSwipeAction.height;
  static const double reveal = CourierSwipeAction.reveal;
  double? drag;
  double get shift => drag ?? (widget.opened ? reveal : 0);
  @override
  Widget build(BuildContext context) {
    final note = (widget.folder['note'] ?? '').toString().trim();
    final counts = "${widget.folder['collected_count'] ?? 0}/${widget.folder['count'] ?? 0}";
    return SizedBox(height: height, child: ClipRect(child: Stack(children: [
      if (widget.opened || drag != null)
        Positioned(right: 0, top: 0, bottom: 0, child: Row(children: [
          CourierSwipeAction(icon: widget.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            label: widget.archived ? 'Вернуть из архива' : 'В архив', onTap: widget.busy ? null : widget.onArchive),
          const SizedBox(width: CourierSwipeAction.gap),
          CourierSwipeAction(remove: true, label: 'Удалить папку', onTap: widget.busy ? null : widget.onDelete),
        ])),
      Positioned.fill(child: TweenAnimationBuilder<double>(
        tween: Tween(end: shift), duration: drag == null ? SadohodMotion.standard : Duration.zero,
        builder: (_, x, child) => Padding(padding: EdgeInsets.only(right: x), child: child),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.busy ? null : (_) => setState(() => drag = shift),
          onHorizontalDragUpdate: widget.busy ? null : (d) => setState(() => drag = (shift - d.delta.dx).clamp(0.0, reveal).toDouble()),
          onHorizontalDragEnd: widget.busy ? null : (d) {
            final velocity = d.primaryVelocity ?? 0;
            final show = velocity.abs() > 300 ? velocity < 0 : shift > reveal / 2;
            setState(() => drag = null);
            widget.onReveal(show);
          },
          onHorizontalDragCancel: () => setState(() => drag = null),
          child: Material(
            color: widget.opened || drag != null ? const Color(0xffd9d9d9) : SellerColors.background,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              onTap: widget.busy ? null : () {
                if (widget.opened) { widget.onReveal(false); } else { widget.onOpen(); }
              },
              borderRadius: BorderRadius.circular(15),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((widget.folder['name'] ?? '').toString(), maxLines: 1,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(
                        fontFamily: SadohodFont.family, fontSize: 14, color: SellerColors.brown)),
                    const SizedBox(height: 3),
                    Text(note.isEmpty ? counts : '$note • $counts', maxLines: 1,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(
                        fontFamily: SadohodFont.family, fontSize: 12, color: SellerColors.brown)),
                  ]),
              ),
            ),
          ),
        ),
      )),
    ])));
  }

}
