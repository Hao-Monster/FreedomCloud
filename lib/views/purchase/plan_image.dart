import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flclashx/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Unauthenticated, bounded raster rendering for operator-authored plan text.
class PurchasePlanImage extends StatefulWidget {
  const PurchasePlanImage({
    super.key,
    required this.source,
    required this.alt,
    required this.maxWidth,
  }) : assert(maxWidth > 0 && maxWidth < double.infinity,
            'Plan images require a positive, finite card width');

  final String source;
  final String alt;
  final double maxWidth;

  @visibleForTesting
  static ({int activeLoads, int queuedLoads, int reservedPixels, int decodes})
      get debugResources => (
            activeLoads: _ImageResources.activeLoads,
            queuedLoads: _ImageResources.queue.length,
            reservedPixels: _ImageResources.reservedPixels,
            decodes: _ImageResources.decodes,
          );

  @override
  State<PurchasePlanImage> createState() => _PurchasePlanImageState();
}

class _PurchasePlanImageState extends State<PurchasePlanImage> {
  _ImageLoad? _load;
  _LoadedImage? _image;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(PurchasePlanImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _start();
  }

  void _start() {
    _load?.cancel();
    _load = null;
    _image?.dispose();
    _image = null;
    final uri = _imageUri(widget.source);
    if (uri == null) return;
    final load = _ImageLoad(uri);
    _load = load;
    unawaited(_read(load));
  }

  Future<void> _read(_ImageLoad load) async {
    try {
      final image = await load.read();
      if (!mounted || _load != load) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      // URLs can contain private query parameters. Keep network and codec
      // errors out of UI/logs, with the same readable fallback for all failures.
      if (mounted && _load == load) setState(() => _image = null);
    } finally {
      load.cancel();
      if (_load == load) _load = null;
    }
  }

  @override
  void dispose() {
    _load?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image?.image;
    if (image == null) {
      return Text(
        [
          AppLocalizations.of(context).purchasePlanImageNotLoaded,
          if (widget.alt.isNotEmpty) widget.alt,
        ].join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Semantics(
      image: true,
      label: widget.alt,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: RawImage(
          image: image,
          width: math.min(widget.maxWidth, image.width.toDouble()),
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

Uri? _imageUri(String source) {
  // Uri parsing normalizes some malformed strings (including backslashes).
  // Reject them before creating even a client, not after a network attempt.
  if (source.isEmpty || RegExp(r'[\x00-\x20\x7f\\]').hasMatch(source)) {
    return null;
  }
  final uri = Uri.tryParse(source);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.host.contains('%') ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

class _ImageUnavailable implements Exception {
  const _ImageUnavailable();
}

// Card contents are mounted eagerly. Per-file bounds alone cannot protect a
// page with dozens of images, so limit active work and all retained rasters.
class _ImageResources {
  static const _maxLoads = 4;
  static const _maxPixels = 16 * 1024 * 1024;
  static final queue = Queue<_LoadSlot>();
  static int activeLoads = 0;
  static int reservedPixels = 0;
  static int decodes = 0;

  static _LoadSlot acquire() {
    final slot = _LoadSlot();
    queue.addLast(slot);
    drain();
    return slot;
  }

  static void drain() {
    while (activeLoads < _maxLoads && queue.isNotEmpty) {
      final slot = queue.removeFirst();
      activeLoads++;
      slot
        ..active = true
        ..ready.complete();
    }
  }

  static bool reserve(int pixels) {
    if (reservedPixels + pixels > _maxPixels) return false;
    reservedPixels += pixels;
    return true;
  }

  static void releasePixels(int pixels) => reservedPixels -= pixels;
}

class _LoadSlot {
  final ready = Completer<void>();
  bool active = false;
  bool released = false;

  void release() {
    if (released) return;
    released = true;
    if (active) {
      _ImageResources.activeLoads--;
    } else {
      _ImageResources.queue.remove(this);
      ready.complete();
    }
    _ImageResources.drain();
  }
}

class _LoadedImage {
  _LoadedImage(this.image, this.pixels);
  final ui.Image image;
  final int pixels;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
    _ImageResources.releasePixels(pixels);
  }
}

class _ImageLoad {
  _ImageLoad(this.uri);

  static const _maxBytes = 4 * 1024 * 1024;
  static const _maxSourceDimension = 8192;
  static const _maxSourcePixels = 16 * 1024 * 1024;
  static const _maxDecodedDimension = 2048;
  static const _rasterTypes = {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/bmp',
    'image/x-ms-bmp',
    'application/octet-stream',
  };

  final Uri uri;
  final _cancelled = Completer<void>();
  HttpClient? _client;
  HttpClientRequest? _request;
  StreamSubscription<List<int>>? _subscription;
  _LoadSlot? _slot;
  bool _workStarted = false;

  bool get _isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (_isCancelled) return;
    _cancelled.complete();
    unawaited(_subscription?.cancel());
    _request?.abort();
    _client?.close(force: true);
    if (!_workStarted) _slot?.release();
  }

  void _checkActive() {
    if (_isCancelled) throw const _ImageUnavailable();
  }

  Future<T> _active<T>(Future<T> future) => Future.any([
        future,
        _cancelled.future.then<T>((_) => throw const _ImageUnavailable()),
      ]);

  Future<_LoadedImage> read() async {
    final slot = _ImageResources.acquire();
    _slot = slot;
    try {
      await _active(slot.ready.future);
      _checkActive();
      _workStarted = true;
      // Queue time does not consume a request's timeout. A cancelled native
      // decode retains its slot/reservation until that decode actually exits.
      return await _download().whenComplete(slot.release).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          cancel();
          throw const _ImageUnavailable();
        },
      );
    } finally {
      if (!_workStarted) slot.release();
    }
  }

  Future<_LoadedImage> _download() async {
    // HttpClient inherits the app's routing override. Do not inherit its
    // trust-all certificate callback or reuse any authenticated API client.
    final client = HttpClient()
      ..badCertificateCallback = ((_, __, ___) => false)
      ..connectionTimeout = const Duration(seconds: 10)
      ..autoUncompress = false
      ..authenticate = null;
    _client = client;
    final request = await _active(client.getUrl(uri).then((request) {
      if (_isCancelled) request.abort();
      _request = request;
      return request;
    }));
    _checkActive();
    request
      ..followRedirects = false
      ..maxRedirects = 0
      ..cookies.clear();
    [
      HttpHeaders.authorizationHeader,
      HttpHeaders.cookieHeader,
      HttpHeaders.refererHeader,
    ].forEach(request.headers.removeAll);
    request.headers.set(HttpHeaders.acceptHeader, 'image/*');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await _active(request.close());
    _checkActive();
    final mime = response.headers.contentType?.mimeType.toLowerCase();
    final encoding = response.headers
        .value(HttpHeaders.contentEncodingHeader)
        ?.toLowerCase();
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > _maxBytes ||
        (mime != null && !_rasterTypes.contains(mime)) ||
        (encoding != null && encoding != 'identity')) {
      throw const _ImageUnavailable();
    }

    final bytes = BytesBuilder(copy: false);
    final downloaded = Completer<Uint8List>();
    _subscription = response.listen(
      (chunk) {
        if (downloaded.isCompleted) return;
        if (bytes.length + chunk.length > _maxBytes) {
          downloaded.completeError(const _ImageUnavailable());
          return;
        }
        bytes.add(chunk);
      },
      onError: (Object error) {
        if (!downloaded.isCompleted) downloaded.completeError(error);
      },
      onDone: () {
        if (!downloaded.isCompleted) downloaded.complete(bytes.takeBytes());
      },
      cancelOnError: true,
    );
    final encoded = await _active(downloaded.future);
    _checkActive();
    return _decode(encoded);
  }

  Future<_LoadedImage> _decode(Uint8List encoded) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    var reservedPixels = 0;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
      _checkActive();
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      _checkActive();
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 ||
          height <= 0 ||
          width > _maxSourceDimension ||
          height > _maxSourceDimension ||
          width * height > _maxSourcePixels) {
        throw const _ImageUnavailable();
      }
      final scale =
          math.min(1.0, _maxDecodedDimension / math.max(width, height));
      final targetWidth = math.max(1, (width * scale).floor());
      final targetHeight = math.max(1, (height * scale).floor());
      final pixels = targetWidth * targetHeight;
      if (!_ImageResources.reserve(pixels)) throw const _ImageUnavailable();
      reservedPixels = pixels;
      _ImageResources.decodes++;
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      _checkActive();
      // A static first frame bounds animation work and retained decoded memory.
      image = (await codec.getNextFrame()).image;
      _checkActive();
      return _LoadedImage(image, reservedPixels);
    } catch (_) {
      image?.dispose();
      if (reservedPixels > 0) _ImageResources.releasePixels(reservedPixels);
      rethrow;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
