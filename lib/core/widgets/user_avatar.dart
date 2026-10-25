import 'dart:convert';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.photoB64,
    this.radius = 20,
  });

  final String name;
  final String? photoB64;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ImageProvider? image;
    if (photoB64 != null && photoB64!.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(photoB64!));
      } catch (_) {}
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: image,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.9,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
