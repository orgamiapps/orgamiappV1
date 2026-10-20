import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Services/artifact_download_service.dart';
import 'package:attendus/Services/event_share_service.dart';
import 'package:attendus/Services/event_qr_image.dart';
import 'package:attendus/Services/event_qr_actions.dart' as actions;

Future<void> showEventQrShare(BuildContext context, EventModel event) {
  final animation = MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null;
  if (MediaQuery.sizeOf(context).width < 600) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: animation,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareQRDialog(singleEvent: event),
    );
  }
  return showDialog<void>(
    context: context,
    animationStyle: animation,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: ShareQRDialog(singleEvent: event),
    ),
  );
}

class ShareQRDialog extends StatefulWidget {
  final EventModel singleEvent;
  final Future<Uint8List> Function(EventModel, EventQrFormat) imageRenderer;
  const ShareQRDialog({
    super.key,
    required this.singleEvent,
    this.imageRenderer = EventQrImage.render,
  });
  @override
  State<ShareQRDialog> createState() => _ShareQRDialogState();
}

class _ShareQRDialogState extends State<ShareQRDialog> {
  final Map<EventQrFormat, Uint8List> _images = {};
  EventQrFormat _format = EventQrFormat.card;
  bool _preparing = true;
  bool _busy = false;
  String? _message;
  bool _fallback = false;
  Uint8List? get _bytes => _images[_format];
  String get _filename => EventQrImage.filename(widget.singleEvent, _format);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    if (!mounted) return;
    setState(() {
      _preparing = true;
      _message = null;
    });
    try {
      final images = <EventQrFormat, Uint8List>{};
      for (final format in EventQrFormat.values) {
        images[format] = await widget.imageRenderer(widget.singleEvent, format);
      }
      if (mounted) setState(() => _images.addAll(images));
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not prepare the images. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  void _feedback(String message, {bool fallback = false}) {
    if (mounted) {
      setState(() {
        _message = message;
        _fallback = fallback;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      _feedback(
        'Could not complete that action. Please retry, or save the image instead.',
        fallback: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() => _run(() async {
    final result = await actions.copyQrImage(_bytes!);
    if (result == actions.EventQrActionResult.completed) {
      _feedback('Image copied. Paste it into your message or document.');
    } else {
      _feedback(
        'Image copying is unavailable or was blocked. Save the image to attach it instead.',
        fallback: true,
      );
    }
  });

  Future<void> _share() => _run(() async {
    final result = await actions.shareQrImage(
      _bytes!,
      _filename,
      'You’re invited: ${widget.singleEvent.title}',
      EventShareService.shareText(widget.singleEvent),
      artifactShareOrigin(context),
    );
    switch (result) {
      case actions.EventQrActionResult.completed:
      case actions.EventQrActionResult.unavailable:
        _feedback('Finish sharing in your selected app.');
      case actions.EventQrActionResult.dismissed:
        break;
      case actions.EventQrActionResult.unsupported:
        _feedback(
          'Image sharing is unavailable in this browser. Save the image and attach it to a text or email. You can also copy the link.',
          fallback: true,
        );
      case actions.EventQrActionResult.failed:
        _feedback(
          'Could not share the image. Try again, or save it to attach to your message.',
          fallback: true,
        );
    }
  });

  Future<void> _save() => _run(() async {
    final result = await downloadArtifact(
      _bytes!,
      _filename,
      'image/png',
      sharePositionOrigin: artifactShareOrigin(context),
    );
    if (result.status != ArtifactDownloadStatus.dismissed) {
      _feedback(result.message, fallback: true);
    }
  });

  Future<void> _copyLink() => _run(() async {
    try {
      await EventShareService.copyLink(widget.singleEvent);
      _feedback('Event link copied.');
    } catch (_) {
      _feedback(
        'Could not copy the link. Select the link below and copy it manually.',
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final ready = !_preparing && _bytes != null && !_busy;
    final url = EventShareService.eventUri(widget.singleEvent.id).toString();
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Align(
      alignment: mobile ? Alignment.bottomCenter : Alignment.center,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Share event',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF142C40),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close sharing',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Text(
                    'Invite people with a QR image that opens your event details.',
                    style: TextStyle(color: Color(0xFF526171), height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<EventQrFormat>(
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: EventQrFormat.card,
                        label: Text('Event card'),
                      ),
                      ButtonSegment(
                        value: EventQrFormat.qrOnly,
                        label: Text('QR only'),
                      ),
                    ],
                    selected: {_format},
                    onSelectionChanged: _busy
                        ? null
                        : (selection) => setState(() {
                            _format = selection.single;
                            _message = null;
                            _fallback = false;
                          }),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F6F7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _preparing
                        ? const SizedBox(
                            height: 220,
                            child: Center(
                              child: CircularProgressIndicator(
                                semanticsLabel: 'Preparing QR images',
                              ),
                            ),
                          )
                        : _bytes == null
                        ? TextButton.icon(
                            onPressed: _prepare,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry image preparation'),
                          )
                        : Semantics(
                            label:
                                '${_format == EventQrFormat.card ? 'Event card' : 'QR code'} for ${widget.singleEvent.title}. Opens $url',
                            image: true,
                            child: ExcludeSemantics(
                              child: Image.memory(
                                _bytes!,
                                height: 280,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Scan to view event • Does not check anyone in',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF526171)),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: ready ? _share : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 52),
                      backgroundColor: const Color(0xFF13776C),
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share image'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: ready ? _save : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Save image'),
                      ),
                      OutlinedButton.icon(
                        onPressed: ready ? _copy : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy image'),
                      ),
                    ],
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(semanticsLabel: 'Working'),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ),
                  if (_fallback && _bytes != null && actions.canPreviewQrImage)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              if (actions.previewQrImage(_bytes!, _filename)) {
                                _feedback(
                                  'In the image tab, touch and hold the image to save it, or right-click on a computer.',
                                  fallback: true,
                                );
                              } else {
                                _feedback(
                                  'The image tab was blocked. Allow pop-ups for this site and try again.',
                                  fallback: true,
                                );
                              }
                            },
                      child: const Text('Open image to save manually'),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  SelectableText(
                    url,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF526171),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _copyLink,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.link),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
