import 'package:flutter/material.dart';

/// Public seller layout shared by the buyer and courier roles.
class PublicSellerBody extends StatelessWidget {
  const PublicSellerBody({
    super.key, required this.name, required this.addresses,
    required this.contacts, required this.reviews, required this.products,
    this.note, this.coverColor = Colors.black, this.ink = Colors.black,
  });
  final String name;
  final List<String> addresses;
  final Widget contacts, reviews, products;
  final Widget? note;
  final Color coverColor, ink;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(30, 10, 30, 30),
    children: [
      SizedBox(height: 134, child: Stack(clipBehavior: Clip.none, children: [
        Container(height: 100, decoration: BoxDecoration(
          color: coverColor, borderRadius: BorderRadius.circular(10))),
        const Positioned(left: 15, top: 73, child: CircleAvatar(
          radius: 23, backgroundColor: Color(0xffdddddd),
          child: Icon(Icons.person, color: Color(0xff888888), size: 28))),
      ])),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ink)),
          const SizedBox(height: 8),
          contacts,
        ])),
        const SizedBox(width: 10),
        SizedBox(width: 104, child: Column(crossAxisAlignment: CrossAxisAlignment.end,
          children: [for (final code in addresses)
            Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ink))])),
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
