import 'package:flutter/material.dart';

/// Public seller layout shared by the buyer and courier roles.
class PublicSellerBody extends StatelessWidget {
  const PublicSellerBody({
    super.key, required this.name, required this.addresses,
    required this.contacts, required this.reviews, required this.products,
    this.note, this.coverColor = Colors.black, this.ink = Colors.black,
    this.coverImage, this.avatarImage, this.subtitle,
  });
  final String name;
  final List<String> addresses;
  final Widget contacts, reviews, products;
  final Widget? note;
  final ImageProvider? coverImage, avatarImage;
  final Widget? subtitle;
  final Color coverColor, ink;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(30, 10, 30, 30),
    children: [
      SizedBox(height: 134, child: Stack(clipBehavior: Clip.none, children: [
        Container(height: 100, decoration: BoxDecoration(
          color: coverColor, borderRadius: BorderRadius.circular(10),
          image: coverImage == null ? null : DecorationImage(image: coverImage!, fit: BoxFit.cover))),
        Positioned(left: 15, top: 73, child: CircleAvatar(
          radius: 23, backgroundColor: const Color(0xffdddddd),
          backgroundImage: avatarImage,
          child: avatarImage == null
            ? const Icon(Icons.person, color: Color(0xff888888), size: 28) : null)),
      ])),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ink)),
          if (subtitle != null) ...[
            const SizedBox(height: 5), subtitle!,
          ],
          const SizedBox(height: 8),
          contacts,
        ])),
        if (addresses.isNotEmpty) ...[
          const SizedBox(width: 10),
          SizedBox(width: 104, child: Column(crossAxisAlignment: CrossAxisAlignment.end,
            children: [for (final code in addresses)
              Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ink))])),
        ],
      ]),
      const SizedBox(height: 20),
      if (note != null) note!,
      const SizedBox(height: 14),
      reviews,
      const SizedBox(height: 14),
      products,
    ],
  );
}
