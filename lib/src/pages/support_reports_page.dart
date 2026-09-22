import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';

class SupportReportsPage extends StatefulWidget {
  final SidecarClient? client;

  const SupportReportsPage({super.key, required this.client});

  @override
  State<SupportReportsPage> createState() => _SupportReportsPageState();
}

class _SupportReportsPageState extends State<SupportReportsPage> {
  bool _loading = true;
  bool _unreadOnly = false;
  String _error = '';
  List<Map<String, dynamic>> _reports = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = widget.client;
    if (client == null) {
      setState(() {
        _loading = false;
        _error = 'Sidecar belum berjalan.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final reports = await client.supportReports(unreadOnly: _unreadOnly);
      if (!mounted) return;
      setState(() => _reports = reports);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('404') || raw.toLowerCase().contains('not found')) {
      return 'Endpoint laporan belum tersedia di server/sidecar. Pasang kontrak support report dari prompt backend.';
    }
    return raw.replaceFirst('Exception: ', '');
  }

  Future<void> _openChat(Map<String, dynamic> report) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupportReportChatPage(
          report: report,
          client: widget.client,
          onChanged: _load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: 'Laporan Error',
            subtitle:
                'Chat laporan dari mobile app semua role, termasuk gambar pendukung dan balasan admin.',
            icon: Icons.support_agent_outlined,
            actions: [
              FilterChip(
                label: const Text('Belum dibaca'),
                selected: _unreadOnly,
                onSelected: (v) {
                  setState(() => _unreadOnly = v);
                  _load();
                },
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Muat ulang',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_error.isNotEmpty) ...[
            _ErrorCard(message: _error),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _reports.isEmpty
                ? const ConsoleMessage(
                    icon: Icons.mark_chat_read_outlined,
                    text: 'Belum ada laporan error dari user.',
                  )
                : ListView.separated(
                    itemCount: _reports.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) => _ReportCard(
                      report: _reports[index],
                      client: widget.client,
                      onOpen: _openChat,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final SidecarClient? client;
  final ValueChanged<Map<String, dynamic>> onOpen;

  const _ReportCard({
    required this.report,
    required this.client,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final name = _text('full_name') ?? _text('name') ?? 'User';
    final role = _text('role') ?? _text('visitor_type') ?? '-';
    final email = _text('email') ?? _text('google_email') ?? '-';
    final message = _text('message') ?? _latestMessage() ?? '-';
    final status = _text('status') ?? 'open';
    final image =
        _text('image_url') ?? _text('photo_url') ?? _text('attachment_url');
    final created = _text('created_at') ?? _text('updated_at') ?? '';
    final replies = report['replies'] is List
        ? report['replies'] as List
        : report['messages'] is List
        ? report['messages'] as List
        : const [];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onOpen(report),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.panel.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              if (image != null && image.isNotEmpty) ...[
                SizedBox(
                  width: 76,
                  height: 76,
                  child: _SupportImagePreview(
                    client: client,
                    photoUrl: image,
                    height: 76,
                  ),
                ),
                const SizedBox(width: 14),
              ] else ...[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.brandGold.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.bug_report_outlined,
                    color: AppTheme.brandGold,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          _formatDateTime(created),
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$role • $email',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _StatusPill(status: status),
                        const SizedBox(width: 10),
                        Text(
                          '${replies.length} pesan',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => onOpen(report),
                          icon: const Icon(Icons.forum_outlined, size: 16),
                          label: const Text('Buka Chat'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _text(String key) {
    final value = report[key];
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? _latestMessage() {
    final messages = report['messages'];
    if (messages is! List || messages.isEmpty) return null;
    final last = messages.last;
    if (last is Map) return last['message']?.toString();
    return null;
  }
}

class SupportReportChatPage extends StatefulWidget {
  final Map<String, dynamic> report;
  final SidecarClient? client;
  final Future<void> Function()? onChanged;

  const SupportReportChatPage({
    super.key,
    required this.report,
    required this.client,
    this.onChanged,
  });

  @override
  State<SupportReportChatPage> createState() => _SupportReportChatPageState();
}

class _SupportReportChatPageState extends State<SupportReportChatPage> {
  final _reply = TextEditingController();
  late Map<String, dynamic> _report = widget.report;
  List<File> _attachments = const [];
  bool _sending = false;
  bool _closing = false;
  String _error = '';

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final client = widget.client;
    final id = _intOf(_report['id'] ?? _report['report_id']);
    final text = _reply.text.trim();
    if (client == null ||
        id == null ||
        (text.isEmpty && _attachments.isEmpty)) {
      return;
    }
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      final sentAttachments = _attachments;
      await client.replySupportReport(
        reportId: id,
        message: text,
        attachments: sentAttachments,
      );
      _reply.clear();
      _attachments = const [];
      await widget.onChanged?.call();
      setState(() {
        final messages = List<Map<String, dynamic>>.from(
          (_report['messages'] as List? ?? const []).whereType<Map>().map(
            (m) => Map<String, dynamic>.from(m),
          ),
        );
        messages.add({
          'sender_type': 'admin',
          'sender_name': 'admin',
          'message': text,
          'attachments': [
            for (final file in sentAttachments)
              {'filename': _fileNameOf(file.path), 'url': ''},
          ],
          'created_at': DateTime.now().toIso8601String(),
        });
        _report = {..._report, 'messages': messages, 'message': text};
      });
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || !mounted) return;
    setState(() {
      _attachments = [
        ..._attachments,
        for (final file in result.files)
          if (file.path != null) File(file.path!),
      ];
      _error = '';
    });
  }

  Future<void> _closeChat() async {
    final client = widget.client;
    final id = _intOf(_report['id'] ?? _report['report_id']);
    if (client == null || id == null) return;
    setState(() {
      _closing = true;
      _error = '';
    });
    try {
      await client.closeSupportReport(reportId: id);
      await widget.onChanged?.call();
      setState(() => _report = {..._report, 'status': 'closed'});
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final name =
        _text(_report, 'full_name') ?? _text(_report, 'name') ?? 'User';
    final role =
        _text(_report, 'role') ?? _text(_report, 'visitor_type') ?? '-';
    final email =
        _text(_report, 'email') ?? _text(_report, 'google_email') ?? '-';
    final status = _text(_report, 'status') ?? 'open';
    final closed = status.toLowerCase() == 'closed';
    final messages = _messagesOf(_report);
    return Scaffold(
      backgroundColor: const Color(0xFF0A1F45),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppTheme.brandGold,
              foregroundColor: AppTheme.bg,
              child: Icon(Icons.person_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '$role • $email',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
            _StatusPill(status: status),
            const SizedBox(width: 12),
            if (!closed)
              TextButton.icon(
                onPressed: _closing ? null : _closeChat,
                icon: _closing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline, size: 16),
                label: const Text('Akhiri'),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                children: [
                  for (final message in messages)
                    _ChatBubble(data: message, client: widget.client),
                ],
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _error,
                  style: const TextStyle(
                    color: AppTheme.badRed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (closed)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  'Sesi chat sudah diakhiri. Form balasan disembunyikan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              _AdminComposer(
                controller: _reply,
                sending: _sending,
                attachments: _attachments,
                onAttach: _pickFiles,
                onRemoveAttachment: (file) => setState(() {
                  _attachments = [
                    for (final item in _attachments)
                      if (item.path != file.path) item,
                  ];
                }),
                onSend: _send,
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final List<File> attachments;
  final VoidCallback onAttach;
  final ValueChanged<File> onRemoveAttachment;
  final VoidCallback onSend;

  const _AdminComposer({
    required this.controller,
    required this.sending,
    required this.attachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      color: const Color(0xFF0A1F45),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty) ...[
            _PickedAttachmentList(
              files: attachments,
              onRemove: onRemoveAttachment,
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Ketik balasan',
                    prefixIcon: IconButton(
                      tooltip: 'Tambah lampiran',
                      onPressed: sending ? null : onAttach,
                      icon: const Icon(Icons.attach_file),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FloatingActionButton.small(
                heroTag: 'admin_report_reply',
                onPressed: sending ? null : onSend,
                backgroundColor: AppTheme.brandGold,
                foregroundColor: AppTheme.bg,
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const _SendGlyph(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SendGlyph extends StatelessWidget {
  const _SendGlyph();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _SendGlyphPainter(color: AppTheme.bg),
    );
  }
}

class _SendGlyphPainter extends CustomPainter {
  final Color color;

  const _SendGlyphPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.14)
      ..lineTo(size.width * 0.90, size.height * 0.50)
      ..lineTo(size.width * 0.10, size.height * 0.86)
      ..lineTo(size.width * 0.24, size.height * 0.56)
      ..lineTo(size.width * 0.52, size.height * 0.50)
      ..lineTo(size.width * 0.24, size.height * 0.44)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SendGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _PickedAttachmentList extends StatelessWidget {
  final List<File> files;
  final ValueChanged<File> onRemove;

  const _PickedAttachmentList({required this.files, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final file in files)
          Chip(
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            deleteIconColor: Colors.white70,
            avatar: Icon(
              _looksLikeImage(file.path)
                  ? Icons.image_outlined
                  : Icons.insert_drive_file_outlined,
              color: Colors.white70,
              size: 18,
            ),
            label: SizedBox(
              width: 160,
              child: Text(
                _fileNameOf(file.path),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            onDeleted: () => onRemove(file),
          ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final SidecarClient? client;

  const _ChatBubble({required this.data, required this.client});

  @override
  Widget build(BuildContext context) {
    final sender = (_text(data, 'sender_type') ?? _text(data, 'role') ?? 'user')
        .toLowerCase();
    final fromAdmin = sender == 'admin';
    final text = _text(data, 'message') ?? '';
    final photoUrl =
        _text(data, 'photo_url') ??
        _text(data, 'image_url') ??
        _text(data, 'attachment_url');
    final attachments = _attachmentsOf(data, fallbackUrl: photoUrl);
    final created = _formatDateTime(_text(data, 'created_at'));
    return Align(
      alignment: fromAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.58,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 7),
        decoration: BoxDecoration(
          color: fromAdmin ? const Color(0xFFDDF7C8) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(fromAdmin ? 16 : 4),
            bottomRight: Radius.circular(fromAdmin ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!fromAdmin)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _text(data, 'sender_name') ?? 'User',
                  style: const TextStyle(
                    color: AppTheme.brandBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (text.isNotEmpty) ...[
              if (!fromAdmin) const SizedBox(height: 4),
              SelectableText(
                text,
                style: const TextStyle(
                  color: AppTheme.bg,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final attachment in attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _AttachmentPreview(
                    client: client,
                    attachment: attachment,
                  ),
                ),
            ],
            if (created.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                created,
                style: TextStyle(
                  color: AppTheme.bg.withValues(alpha: 0.48),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _text(Map<String, dynamic> data, String key) {
  final text = data[key]?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<Map<String, dynamic>> _messagesOf(Map<String, dynamic> report) {
  final messages = report['messages'];
  if (messages is List && messages.isNotEmpty) {
    return [
      for (final item in messages)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
  final message =
      _text(report, 'message') ?? _text(report, 'latest_message') ?? '';
  return [
    {
      'sender_type': 'user',
      'sender_name':
          _text(report, 'full_name') ?? _text(report, 'name') ?? 'User',
      'message': message,
      'photo_url':
          _text(report, 'photo_url') ??
          _text(report, 'image_url') ??
          _text(report, 'attachment_url'),
      'attachments': report['attachments'] ?? report['files'],
      'created_at': _text(report, 'created_at'),
    },
  ];
}

List<Map<String, String>> _attachmentsOf(
  Map<String, dynamic> data, {
  String? fallbackUrl,
}) {
  final raw = data['attachments'] ?? data['files'];
  final items = <Map<String, String>>[
    for (final item in raw is List ? raw : const [])
      if (item is Map)
        {
          'url':
              _text(Map<String, dynamic>.from(item), 'url') ??
              _text(Map<String, dynamic>.from(item), 'photo_url') ??
              _text(Map<String, dynamic>.from(item), 'file_url') ??
              _text(Map<String, dynamic>.from(item), 'path') ??
              '',
          'filename':
              _text(Map<String, dynamic>.from(item), 'filename') ??
              _text(Map<String, dynamic>.from(item), 'name') ??
              '',
          'mime_type':
              _text(Map<String, dynamic>.from(item), 'mime_type') ??
              _text(Map<String, dynamic>.from(item), 'content_type') ??
              '',
        }
      else if (item != null)
        {'url': item.toString(), 'filename': '', 'mime_type': ''},
  ];
  if (items.isEmpty && fallbackUrl != null && fallbackUrl.isNotEmpty) {
    items.add({'url': fallbackUrl, 'filename': '', 'mime_type': ''});
  }
  return items.where((item) => (item['url'] ?? '').isNotEmpty).toList();
}

class _AttachmentPreview extends StatelessWidget {
  final SidecarClient? client;
  final Map<String, String> attachment;

  const _AttachmentPreview({required this.client, required this.attachment});

  @override
  Widget build(BuildContext context) {
    final url = attachment['url'] ?? '';
    final filename = (attachment['filename'] ?? '').isEmpty
        ? url.split('/').last
        : attachment['filename']!;
    if (_looksLikeImage('$filename $url ${attachment['mime_type'] ?? ''}')) {
      return _SupportImagePreview(client: client, photoUrl: url);
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              filename.isEmpty ? 'Lampiran' : filename,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

bool _looksLikeImage(String value) {
  final lower = value.toLowerCase();
  return lower.contains('image/') ||
      lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.webp') ||
      lower.contains('.gif');
}

String _fileNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  return name.isEmpty ? 'lampiran' : name;
}

String _formatDateTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)} ${two(date.hour)}:${two(date.minute)}';
}

class _SupportImagePreview extends StatefulWidget {
  final SidecarClient? client;
  final String photoUrl;
  final double height;

  const _SupportImagePreview({
    required this.client,
    required this.photoUrl,
    this.height = 220,
  });

  @override
  State<_SupportImagePreview> createState() => _SupportImagePreviewState();
}

class _SupportImagePreviewState extends State<_SupportImagePreview> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.client?.photo(widget.photoUrl);
  }

  @override
  void didUpdateWidget(covariant _SupportImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.photoUrl != widget.photoUrl) {
      _future = widget.client?.photo(widget.photoUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.client == null || _future == null) {
      return _ImageFallback(
        text: 'Gambar: ${widget.photoUrl}',
        height: widget.height,
      );
    }
    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return _ImageFallback(
            text: 'Memuat gambar...',
            busy: true,
            height: widget.height,
          );
        }
        if (bytes == null || bytes.isEmpty) {
          return _ImageFallback(
            text: 'Gambar tidak bisa dimuat: ${widget.photoUrl}',
            height: widget.height,
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            bytes,
            height: widget.height,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final String text;
  final bool busy;
  final double height;

  const _ImageFallback({
    required this.text,
    this.busy = false,
    this.height = 96,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.image_not_supported_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(
                color: AppTheme.mutedStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final closed = status.toLowerCase() == 'closed';
    final color = closed ? const Color(0xFF33D69F) : AppTheme.brandGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.badRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.badRed.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.badRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.badRed,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
