import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

class ZashboardLimits {
  const ZashboardLimits({
    this.downloadBytes = 32 * 1024 * 1024,
    this.fileBytes = 16 * 1024 * 1024,
    this.totalBytes = 128 * 1024 * 1024,
    this.entries = 4096,
    this.timeout = const Duration(seconds: 60),
  });

  final int downloadBytes;
  final int fileBytes;
  final int totalBytes;
  final int entries;
  final Duration timeout;
}

String _safeZipName(String original) {
  final name = original.replaceAll(r'\', '/');
  if (name.isEmpty || name.length > 1024 || name.startsWith('/')) {
    throw const FormatException('Invalid archive path');
  }
  final parts = name.split('/');
  if (parts.last.isEmpty) parts.removeLast();
  for (final part in parts) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(part) ||
        RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
                caseSensitive: false)
            .hasMatch(part)) {
      throw const FormatException('Unsafe archive path');
    }
  }
  return parts.join('/');
}

// Bound the actual central-directory count before the decoder allocates an
// object for every header. The dashboard fits classic, single-disk ZIP limits.
int _checkDirectory(Uint8List bytes, ZashboardLimits limits) {
  if (bytes.length > limits.downloadBytes || bytes.length < 22) {
    throw const FormatException(
        'Archive download budget exceeded or truncated');
  }
  final data = ByteData.sublistView(bytes);
  int u16(int offset) => data.getUint16(offset, Endian.little);
  int u32(int offset) => data.getUint32(offset, Endian.little);
  var end = bytes.length - 22;
  final minimum = (bytes.length - 65557).clamp(0, bytes.length);
  while (end >= minimum) {
    if (u32(end) == 0x06054b50 && end + 22 + u16(end + 20) == bytes.length) {
      break;
    }
    end--;
  }
  if (end < minimum ||
      u16(end + 4) != 0 ||
      u16(end + 6) != 0 ||
      u16(end + 8) != u16(end + 10) ||
      u16(end + 20) != 0 ||
      (end >= 20 && u32(end - 20) == 0x07064b50)) {
    throw const FormatException('Unsupported or invalid ZIP directory');
  }
  final count = u16(end + 10);
  final length = u32(end + 12);
  final start = u32(end + 16);
  if (count == 0 ||
      count > limits.entries ||
      count == 0xffff ||
      start + length != end) {
    throw const FormatException('Invalid ZIP directory size or entry budget');
  }
  var position = start;
  var actual = 0;
  var declaredTotal = 0;
  final localOffsets = <int>{};
  while (position < end) {
    if (++actual > limits.entries ||
        position + 46 > end ||
        u32(position) != 0x02014b50) {
      throw const FormatException('Invalid ZIP directory entry');
    }
    final nameBytes = u16(position + 28);
    final entryEnd =
        position + 46 + nameBytes + u16(position + 30) + u16(position + 32);
    final local = u32(position + 42);
    final flags = u16(position + 8);
    final method = u16(position + 10);
    final compressed = u32(position + 20);
    final uncompressed = u32(position + 24);
    declaredTotal += uncompressed;
    if (entryEnd > end ||
        nameBytes == 0 ||
        nameBytes > 1024 ||
        !localOffsets.add(local) ||
        local + 30 > start ||
        u32(local) != 0x04034b50 ||
        u16(local + 26) != nameBytes ||
        u16(local + 6) != flags ||
        (flags & 0x41) != 0 ||
        u16(local + 8) != method ||
        (method != 0 && method != 8) ||
        u16(position + 34) != 0 ||
        compressed > limits.downloadBytes ||
        uncompressed > limits.fileBytes ||
        declaredTotal > limits.totalBytes) {
      throw const FormatException('Invalid or over-budget ZIP headers');
    }
    final content = local + 30 + nameBytes + u16(local + 28);
    final contentEnd = content + compressed;
    if (contentEnd > start ||
        ((flags & 8) == 0 &&
            (u32(local + 18) != compressed ||
                u32(local + 22) != uncompressed ||
                u32(local + 14) != u32(position + 16)))) {
      throw const FormatException('ZIP local content exceeds its bounds');
    }
    for (var i = 0; i < nameBytes; i++) {
      if (bytes[local + 30 + i] != bytes[position + 46 + i]) {
        throw const FormatException('ZIP local filename mismatch');
      }
    }
    if ((flags & 8) != 0) {
      var descriptor = contentEnd;
      if (descriptor + 4 <= start && u32(descriptor) == 0x08074b50) {
        descriptor += 4;
      }
      if (descriptor + 12 > start ||
          u32(descriptor) != u32(position + 16) ||
          u32(descriptor + 4) != compressed ||
          u32(descriptor + 8) != uncompressed) {
        throw const FormatException('Invalid ZIP data descriptor');
      }
    }
    position = entryEnd;
  }
  if (position != end || actual != count) {
    throw const FormatException('ZIP entry count mismatch');
  }
  return count;
}

/// Only writes to the caller's newly created, empty staging directory.
Future<void> extractZashboardArchive(
  Uint8List bytes,
  Directory staging, {
  ZashboardLimits limits = const ZashboardLimits(),
  required void Function() checkCancelled,
}) async {
  checkCancelled();
  final count = _checkDirectory(bytes, limits);
  // Preflight rejects archive comments: archive 4.x otherwise searches them
  // for a second EOCD signature and can parse a different directory.
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  if (directory.fileHeaders.length != count) {
    throw const FormatException('ZIP decoder directory mismatch');
  }
  final names = <String>{};
  final files = <String, ZipFileHeader>{};
  var total = 0;
  for (final header in directory.fileHeaders) {
    checkCancelled();
    final name = _safeZipName(header.filename);
    final file = header.file;
    final type = (header.externalFileAttributes >> 16) & 0xf000;
    if (file == null ||
        _safeZipName(file.filename) != name ||
        !names.add(name.toLowerCase()) ||
        (type != 0 && type != 0x8000 && type != 0x4000) ||
        (header.generalPurposeBitFlag & 1) != 0 ||
        (file.flags & 1) != 0 ||
        header.diskNumberStart != 0 ||
        (header.compressionMethod != 0 && header.compressionMethod != 8) ||
        header.uncompressedSize != file.uncompressedSize ||
        header.uncompressedSize > limits.fileBytes ||
        header.compressedSize > limits.downloadBytes) {
      throw const FormatException(
          'Unsupported, duplicate or oversized ZIP entry');
    }
    total += header.uncompressedSize;
    if (total > limits.totalBytes) {
      throw const FormatException('Archive extraction budget exceeded');
    }
    if (header.filename.endsWith('/') ||
        header.filename.endsWith(r'\') ||
        type == 0x4000) {
      continue;
    }
    files[name] = header;
  }
  final indexes = files.keys
      .where((name) => p.posix.basename(name) == 'index.html')
      .toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  if (indexes.isEmpty) throw const FormatException('Dashboard index missing');
  final parent = p.posix.dirname(indexes.first);
  final prefix = parent == '.' ? '' : '$parent/';
  for (final entry in files.entries) {
    checkCancelled();
    if (!entry.key.startsWith(prefix)) continue;
    final relative = entry.key.substring(prefix.length);
    final outputPath = p.normalize(p.join(staging.path, relative));
    if (!p.isWithin(staging.path, outputPath)) {
      throw const FormatException('Archive path escapes staging directory');
    }
    final header = entry.value;
    final output = _ZipOutput(header.uncompressedSize, checkCancelled);
    final raw = header.file!.getStream(decompress: false);
    if (header.compressionMethod == 8) {
      // The Dart inflater uses a small sliding window and writes through the
      // bounded sink. Never trust claimed sizes by using unbounded readBytes().
      const ZLibDecoderWeb().decodeStream(raw, output, raw: true);
    } else {
      output.writeStream(raw);
    }
    if (output.length != header.uncompressedSize ||
        getCrc32(output.getBytes()) != header.crc32) {
      throw const FormatException('ZIP content size or CRC mismatch');
    }
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    checkCancelled();
    await file.writeAsBytes(output.getBytes());
  }
  checkCancelled();
  if (!await File(p.join(staging.path, 'index.html')).exists()) {
    throw const FormatException('Dashboard index was not extracted');
  }
}

class _ZipOutput extends OutputStream {
  _ZipOutput(int size, this.checkCancelled)
      : _bytes = Uint8List(size),
        super(byteOrder: ByteOrder.littleEndian);
  final Uint8List _bytes;
  final void Function() checkCancelled;
  @override
  int length = 0;

  void _reserve(int count) {
    checkCancelled();
    if (count < 0 || count > _bytes.length - length) {
      throw const FormatException('ZIP content exceeds declared size');
    }
  }

  @override
  void writeByte(int value) {
    _reserve(1);
    _bytes[length++] = value;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _reserve(count);
    _bytes.setRange(this.length, this.length + count, bytes);
    this.length += count;
  }

  @override
  void writeStream(InputStream stream) {
    _reserve(stream.length);
    writeBytes(stream.toUint8List());
  }

  @override
  Uint8List subset(int start, [int? end]) =>
      Uint8List.sublistView(_bytes, start, end ?? length);
  @override
  void clear() => length = 0;
  @override
  void flush() {}
}
