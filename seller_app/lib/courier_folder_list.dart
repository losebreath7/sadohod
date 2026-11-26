import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'courier_swipe_row.dart';
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
          onReveal: (show) => setState(() {
            final id = entry['id'].toString();
            if (show) { opened = id; } else if (opened == id) { opened = null; }
          }),
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

class _SwipeFolderRow extends StatelessWidget {
  const _SwipeFolderRow({required this.folder, required this.archived,
    required this.busy, required this.opened, required this.onReveal,
    required this.onOpen, required this.onArchive, required this.onDelete});
  final Map folder;
  final bool archived, busy, opened;
  final ValueChanged<bool> onReveal;
  final VoidCallback onOpen, onArchive, onDelete;

  @override
  Widget build(BuildContext context) {
    final note = (folder['note'] ?? '').toString().trim();
    final counts = "${folder['collected_count'] ?? 0}/${folder['count'] ?? 0}";
    return CourierSwipeRow(
      opened: opened, busy: busy, onReveal: onReveal, onOpen: onOpen,
      // A small left shift keeps the client name readable on narrow phones.
      openLeft: -8,
      leadingAction: CourierSwipeAction(
        icon: archived ? Icons.unarchive_outlined : Icons.archive_outlined,
        label: archived ? 'Вернуть из архива' : 'В архив', onTap: busy ? null : onArchive),
      trailingAction: CourierSwipeAction(remove: true,
        label: 'Удалить папку', onTap: busy ? null : onDelete),
      content: (_) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((folder['name'] ?? '').toString(), maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(
                fontFamily: SadohodFont.family, fontSize: 14, color: SellerColors.brown)),
            const SizedBox(height: 3),
            Text(note.isEmpty ? counts : '$note • $counts', maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(
                fontFamily: SadohodFont.family, fontSize: 12, color: SellerColors.brown)),
          ]),
      ),
    );
  }
}
