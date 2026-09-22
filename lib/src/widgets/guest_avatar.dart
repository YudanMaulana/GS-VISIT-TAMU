import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../sidecar_client.dart';
import '../theme.dart';

/// A stored guest photo, fetched through the sidecar.
///
/// The GUI has no direct route to the server by design (the sidecar owns that
/// connection), so a photo cannot be handed to `Image.network` — it arrives as
/// bytes over loopback instead. Failures degrade to an initial-letter
/// placeholder rather than an error box: a guest with a missing photo is a
/// normal thing to see in a list, not a fault worth shouting about.
class GuestAvatar extends StatefulWidget {
  final SidecarClient? client;
  final String photoUrl;
  final String name;
  final double size;

  const GuestAvatar({
    super.key,
    required this.client,
    required this.photoUrl,
    required this.name,
    this.size = 44,
  });

  /// Bytes already fetched this session, keyed by photo_url. Photos are
  /// immutable for the console's lifetime — it can edit profile text but not
  /// replace a face — so a plain never-evicted cache is safe here. That stops
  /// being true the day photo replacement is added: this would then need
  /// invalidating on save.
  static final Map<String, Uint8List?> _cache = {};

  @override
  State<GuestAvatar> createState() => _GuestAvatarState();
}

class _GuestAvatarState extends State<GuestAvatar> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GuestAvatar old) {
    super.didUpdateWidget(old);
    if (old.photoUrl != widget.photoUrl) _load();
  }

  Future<void> _load() async {
    final url = widget.photoUrl;
    if (url.isEmpty) {
      setState(() => _bytes = null);
      return;
    }
    if (GuestAvatar._cache.containsKey(url)) {
      setState(() => _bytes = GuestAvatar._cache[url]);
      return;
    }
    final client = widget.client;
    if (client == null) return;
    setState(() => _loading = true);
    final bytes = await client.photo(url);
    GuestAvatar._cache[url] = bytes;
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim()[0].toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(s * 0.22),
      child: SizedBox(
        width: s,
        height: s,
        child: _bytes != null
            ? Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true)
            : Container(
                color: AppTheme.panelAlt,
                alignment: Alignment.center,
                child: _loading
                    ? SizedBox(
                        width: s * 0.35,
                        height: s * 0.35,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.muted,
                        ),
                      )
                    : Text(
                        initial,
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: s * 0.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
      ),
    );
  }
}
