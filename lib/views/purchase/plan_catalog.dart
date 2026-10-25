import 'dart:math' as math;

import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/views/purchase/plan_content.dart';
import 'package:flclashx/widgets/text.dart';
import 'package:flutter/material.dart';

final RegExp _planFlagEmojiPattern = RegExp(
  r'[\u{1F1E6}-\u{1F1FF}]{2}',
  unicode: true,
);

final RegExp _planByteUnitPattern = RegExp(
  r'\d+(?:\.\d+)?\s*(?:[KMGTPE]i?B|B)(?![A-Za-z])',
  caseSensitive: false,
);

final RegExp _planGlobalPattern = RegExp(
  r'(?<![A-Za-z])(global|worldwide|international|multi[-\s]?region)(?![A-Za-z])|全球|多国|国际|环球|全节点',
  caseSensitive: false,
);

final RegExp _planExplicitGlobalOverridePattern = RegExp(
  r'(?<![A-Za-z])(worldwide|multi[-\s]?region|all\s+(?:nodes|regions))(?![A-Za-z])|全球|多国|环球|全节点',
  caseSensitive: false,
);

const List<(String, List<String>)> _planZhRegionKeywords = [
  ('HK', ['中国香港', '中國香港', '香港', '深港', '沪港', '广港']),
  ('TW', ['中国台湾', '中國台灣', '台湾', '台灣', '台北', '新北', '台中', '高雄', '新竹']),
  ('MO', ['中国澳门', '中國澳門', '澳门', '澳門']),
  (
    'JP',
    ['日本', '东京', '東京', '大阪', '名古屋', '埼玉', '福冈', '札幌', '横滨', '泉日', '沪日', '广日']
  ),
  ('SG', ['新加坡', '狮城', '獅城', '坡县']),
  (
    'US',
    [
      '美国',
      '美國',
      '洛杉矶',
      '洛杉磯',
      '圣何塞',
      '聖荷西',
      '硅谷',
      '西雅图',
      '西雅圖',
      '芝加哥',
      '达拉斯',
      '纽约',
      '紐約',
      '凤凰城',
      '亚特兰大',
      '波特兰',
      '拉斯维加斯',
      '丹佛',
      '盐湖城',
      '迈阿密',
      '弗吉尼亚',
      '俄勒冈',
    ],
  ),
  ('KP', ['朝鲜', '平壤']),
  ('KR', ['韩国', '韓國', '首尔', '首爾', '釜山', '仁川', '春川']),
  ('GB', ['英国', '英國', '伦敦', '倫敦', '曼彻斯特', '伯明翰', '苏格兰', '爱丁堡']),
  ('DE', ['德国', '德國', '法兰克福', '慕尼黑', '柏林', '杜塞尔多夫']),
  ('FR', ['法国', '法國', '巴黎', '马赛']),
  ('NL', ['荷兰', '荷蘭', '阿姆斯特丹', '鹿特丹']),
  ('CA', ['加拿大', '温哥华', '多伦多', '蒙特利尔', '渥太华']),
  ('AU', ['澳大利亚', '澳洲', '悉尼', '墨尔本', '布里斯班', '珀斯']),
  ('RU', ['俄罗斯', '俄羅斯', '莫斯科', '圣彼得堡', '新西伯利亚', '伯力', '海参崴']),
  ('ID', ['印度尼西亚', '印尼', '雅加达']),
  ('IN', ['印度', '孟买', '新德里', '班加罗尔']),
  ('MY', ['马来西亚', '馬來西亞', '大马', '吉隆坡', '柔佛']),
  ('TH', ['泰国', '泰國', '曼谷']),
  ('VN', ['越南', '河内', '胡志明']),
  ('PH', ['菲律宾', '菲律賓', '马尼拉']),
  ('TR', ['土耳其', '伊斯坦布尔', '安卡拉']),
  ('BR', ['巴西', '圣保罗']),
  ('AR', ['阿根廷', '布宜诺斯艾利斯']),
  ('AE', ['阿联酋', '迪拜', '阿布扎比']),
  ('IT', ['意大利', '米兰', '罗马']),
  ('ES', ['西班牙', '马德里', '巴塞罗那']),
  ('CH', ['瑞士', '苏黎世', '日内瓦']),
  ('SE', ['瑞典', '斯德哥尔摩']),
  ('IE', ['爱尔兰', '都柏林']),
  ('PL', ['波兰', '华沙']),
  ('ZA', ['南非', '约翰内斯堡']),
  ('UA', ['乌克兰', '基辅']),
  ('FI', ['芬兰', '赫尔辛基']),
  ('NO', ['挪威', '奥斯陆']),
  ('AT', ['奥地利', '维也纳']),
  ('BE', ['比利时', '布鲁塞尔']),
  ('PT', ['葡萄牙', '里斯本']),
  ('NZ', ['新西兰', '奥克兰']),
  ('IL', ['以色列', '特拉维夫']),
  ('MX', ['墨西哥']),
  ('CL', ['智利', '圣地亚哥']),
  ('RO', ['罗马尼亚', '布加勒斯特']),
  ('CN', ['内蒙古', '中国', '中國']),
];

final List<(String, String)> _sortedPlanZhKeywords = () {
  final items = <({String code, String keyword, int order})>[];
  var order = 0;
  for (final (code, keywords) in _planZhRegionKeywords) {
    for (final keyword in keywords) {
      items.add((code: code, keyword: keyword, order: order++));
    }
  }
  items.sort((a, b) {
    final byLen = b.keyword.length.compareTo(a.keyword.length);
    return byLen != 0 ? byLen : a.order.compareTo(b.order);
  });
  return [for (final item in items) (item.code, item.keyword)];
}();

final List<(String, RegExp)> _planEnglishRegionPatterns = [
  (
    'HK',
    RegExp(r'(?<![A-Za-z])(hong\s*kong)(?![A-Za-z])', caseSensitive: false)
  ),
  (
    'TW',
    RegExp(r'(?<![A-Za-z])(taiwan|taipei|kaohsiung)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'MO',
    RegExp(r'(?<![A-Za-z])(macao|macau)(?![A-Za-z])', caseSensitive: false)
  ),
  (
    'JP',
    RegExp(
        r'(?<![A-Za-z])(japan|tokyo|osaka|nagoya|fukuoka|sapporo)(?![A-Za-z])',
        caseSensitive: false)
  ),
  ('SG', RegExp(r'(?<![A-Za-z])(singapore)(?![A-Za-z])', caseSensitive: false)),
  (
    'US',
    RegExp(
      r'(?<![A-Za-z])(united\s+states|america|los\s*angeles|san\s*jose|san\s*francisco|silicon\s*valley|seattle|new\s*york|chicago|dallas|miami)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'KP',
    RegExp(r'(?<![A-Za-z])(north\s+korea|pyongyang)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'KR',
    RegExp(
        r'(?<![A-Za-z])(south\s+korea|korea|seoul|busan|incheon)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'GB',
    RegExp(
        r'(?<![A-Za-z])(united\s+kingdom|great\s+britain|britain|england|london|manchester)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'DE',
    RegExp(r'(?<![A-Za-z])(germany|frankfurt|munich|berlin)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'FR',
    RegExp(r'(?<![A-Za-z])(france|paris|marseille)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'NL',
    RegExp(r'(?<![A-Za-z])(netherlands|amsterdam|rotterdam)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'CA',
    RegExp(r'(?<![A-Za-z])(canada|vancouver|toronto|montreal)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'AU',
    RegExp(r'(?<![A-Za-z])(australia|sydney|melbourne|brisbane)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'RU',
    RegExp(r'(?<![A-Za-z])(russia|moscow)(?![A-Za-z])', caseSensitive: false)
  ),
  (
    'ID',
    RegExp(r'(?<![A-Za-z])(indonesia|jakarta)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'IN',
    RegExp(r'(?<![A-Za-z])(india|mumbai)(?![A-Za-z])', caseSensitive: false)
  ),
  (
    'MY',
    RegExp(r'(?<![A-Za-z])(malaysia|kuala\s+lumpur)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'TH',
    RegExp(r'(?<![A-Za-z])(thailand|bangkok)(?![A-Za-z])', caseSensitive: false)
  ),
  (
    'VN',
    RegExp(r'(?<![A-Za-z])(vietnam|hanoi|saigon)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'PH',
    RegExp(r'(?<![A-Za-z])(philippines|manila)(?![A-Za-z])',
        caseSensitive: false)
  ),
  (
    'TR',
    RegExp(r'(?<![A-Za-z])(turkey|turkiye|istanbul)(?![A-Za-z])',
        caseSensitive: false)
  ),
  ('BR', RegExp(r'(?<![A-Za-z])(brazil)(?![A-Za-z])', caseSensitive: false)),
  ('AR', RegExp(r'(?<![A-Za-z])(argentina)(?![A-Za-z])', caseSensitive: false)),
  (
    'AE',
    RegExp(r'(?<![A-Za-z])(dubai|abu\s+dhabi)(?![A-Za-z])',
        caseSensitive: false)
  ),
];

// Excludes 2/3-letter uppercase tokens that collide with English marketing words
// in plan titles (e.g. "MY", "IN", "IT", "IS", "NO", "AT", "BE", "MO", "CAN", "ARE", "US$").
final List<(String, RegExp)> _planUpperCodePatterns = [
  ('HK', RegExp(r'(?<![A-Za-z])(HK|HKG)(?![A-Za-z])')),
  ('TW', RegExp(r'(?<![A-Za-z])(TW|TWN|TPE|KHH)(?![A-Za-z])')),
  ('MO', RegExp(r'(?<![A-Za-z])(MAC|MFM)(?![A-Za-z])')),
  ('JP', RegExp(r'(?<![A-Za-z])(JP|JPN|NRT|HND|KIX|TYO|OSA)(?![A-Za-z])')),
  ('SG', RegExp(r'(?<![A-Za-z])(SG|SGP|SIN)(?![A-Za-z])')),
  (
    'US',
    RegExp(r'(?<!JOIN\s)(?<![A-Za-z])(US|USA|LAX|SJC|SFO|SEA|JFK)(?![A-Za-z$])')
  ),
  ('KR', RegExp(r'(?<![A-Za-z])(KR|KOR|ICN|SEL)(?![A-Za-z])')),
  ('GB', RegExp(r'(?<![A-Za-z])(UK|GB|GBR|LHR)(?![A-Za-z])')),
  ('DE', RegExp(r'(?<![A-Za-z])(DEU|FRA|MUC|BER)(?![A-Za-z])')),
  ('FR', RegExp(r'(?<![A-Za-z])(CDG|MRS)(?![A-Za-z])')),
  ('NL', RegExp(r'(?<![A-Za-z])(NLD|AMS)(?![A-Za-z])')),
  ('CA', RegExp(r'(?<![A-Za-z])(YVR|YYZ)(?![A-Za-z])')),
  ('AU', RegExp(r'(?<![A-Za-z])(AUS|SYD|MEL)(?![A-Za-z])')),
  ('RU', RegExp(r'(?<![A-Za-z])(RUS|SVO)(?![A-Za-z])')),
  ('IN', RegExp(r'(?<![A-Za-z])(IND|BOM|DEL|BLR)(?![A-Za-z])')),
  ('MY', RegExp(r'(?<![A-Za-z])(MYS|KUL)(?![A-Za-z])')),
  ('TH', RegExp(r'(?<![A-Za-z])(THA|BKK)(?![A-Za-z])')),
  ('VN', RegExp(r'(?<![A-Za-z])(VNM|HAN|SGN)(?![A-Za-z])')),
  ('PH', RegExp(r'(?<![A-Za-z])(PHL|MNL)(?![A-Za-z])')),
  ('ID', RegExp(r'(?<![A-Za-z])(IDN|CGK)(?![A-Za-z])')),
  ('TR', RegExp(r'(?<![A-Za-z])(TUR|IST)(?![A-Za-z])')),
  ('BR', RegExp(r'(?<![A-Za-z])(BRA|GRU)(?![A-Za-z])')),
  ('AR', RegExp(r'(?<![A-Za-z])(ARG|EZE)(?![A-Za-z])')),
  ('AE', RegExp(r'(?<![A-Za-z])(UAE|DXB|AUH)(?![A-Za-z])')),
];

String? resolvePlanRegionBadge(String planName) {
  if (planName.trim().isEmpty) return null;
  final hits = <({int index, String code})>[];
  var masked = planName;

  for (final match in _planFlagEmojiPattern.allMatches(planName)) {
    final code = inferCountryCodeFromText(match.group(0));
    if (code != null) {
      hits.add((index: match.start, code: code));
    }
  }
  masked = masked.replaceAllMapped(
    _planFlagEmojiPattern,
    (m) => ' ' * m.group(0)!.length,
  );

  for (final (code, keyword) in _sortedPlanZhKeywords) {
    var searchFrom = 0;
    while (true) {
      final idx = masked.indexOf(keyword, searchFrom);
      if (idx < 0) break;
      hits.add((index: idx, code: code));
      masked = masked.replaceRange(
        idx,
        idx + keyword.length,
        ' ' * keyword.length,
      );
      searchFrom = idx + keyword.length;
    }
  }

  for (final (code, pattern) in _planEnglishRegionPatterns) {
    final matches = pattern.allMatches(masked).toList(growable: false);
    for (final match in matches) {
      hits.add((index: match.start, code: code));
      masked = masked.replaceRange(
        match.start,
        match.end,
        ' ' * (match.end - match.start),
      );
    }
  }

  final sanitizedUpper = masked.replaceAllMapped(
    _planByteUnitPattern,
    (m) => ' ' * m.group(0)!.length,
  );
  for (final (code, pattern) in _planUpperCodePatterns) {
    for (final match in pattern.allMatches(sanitizedUpper)) {
      hits.add((index: match.start, code: code));
    }
  }

  hits.sort((a, b) => a.index.compareTo(b.index));
  final distinctCodes = <String>[];
  for (final hit in hits) {
    if (!distinctCodes.contains(hit.code)) {
      distinctCodes.add(hit.code);
    }
  }

  if (_planExplicitGlobalOverridePattern.hasMatch(planName)) {
    return '🌐';
  }
  final isGlobal = _planGlobalPattern.hasMatch(planName);
  if (distinctCodes.isEmpty) {
    return isGlobal ? '🌐' : null;
  }
  if (distinctCodes.length == 1) {
    return nodeCountryEmoji(distinctCodes.first);
  }
  if (distinctCodes.length == 2) {
    return '${nodeCountryEmoji(distinctCodes[0])} ${nodeCountryEmoji(distinctCodes[1])}';
  }
  return '🌐';
}

final RegExp _backtickFenceOpenPattern = RegExp(r'^( {0,3})(`{3,})([^`]*)$');
final RegExp _tildeFenceOpenPattern = RegExp(r'^( {0,3})(~{3,})(.*)$');
final RegExp _thematicBreakPattern = RegExp(
  r'^ {0,3}(?:-\s*-\s*-[-\s]*|\*\s*\*\s*\*[\*\s]*|_\s*_\s*_[_\s]*)$',
);
final RegExp _atxHeadingPattern = RegExp(r'^ {0,3}#{1,6}(?:\s|$)');

RegExpMatch? _matchCodeFenceOpen(String line) =>
    _backtickFenceOpenPattern.firstMatch(line) ??
    _tildeFenceOpenPattern.firstMatch(line);

({bool collapsible, String preview}) summarizePlanMarkdown(
  String markdown, {
  int collapseThreshold = 6,
  int maxPreviewUnits = 5,
}) {
  final normalized = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final segments = <_MdSegment>[];

  var i = 0;
  while (i < lines.length) {
    if (lines[i].trim().isEmpty) {
      i++;
      continue;
    }

    final fenceMatch = _matchCodeFenceOpen(lines[i]);
    if (fenceMatch != null) {
      final openLine = lines[i];
      final fenceChars = fenceMatch.group(2)!;
      final fenceChar = fenceChars[0];
      final fenceLen = fenceChars.length;
      final closePattern = RegExp('^ {0,3}$fenceChar{$fenceLen,}\\s*\$');
      i++;
      final inner = <String>[];
      while (i < lines.length && !closePattern.hasMatch(lines[i])) {
        inner.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      segments.add(
        _CodeFenceSegment(
          openLine: openLine,
          innerLines: inner,
          closeLine: fenceChars,
        ),
      );
      continue;
    }

    if (i + 1 < lines.length &&
        lines[i].contains('|') &&
        _isGfmTableDelimiter(lines[i + 1])) {
      final header = lines[i];
      final delimiter = lines[i + 1];
      i += 2;
      final rows = <String>[];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          lines[i].contains('|')) {
        rows.add(lines[i]);
        i++;
      }
      segments.add(
        _TableSegment(header: header, delimiter: delimiter, rows: rows),
      );
      continue;
    }

    if (_thematicBreakPattern.hasMatch(lines[i])) {
      segments.add(_LinesSegment([lines[i]], fixedUnits: 1));
      i++;
      continue;
    }

    if (i + 1 < lines.length &&
        !RegExp(r'^ {0,3}(?:[-*+]\s|>|\d+[.)]\s)').hasMatch(lines[i]) &&
        !_atxHeadingPattern.hasMatch(lines[i]) &&
        RegExp(r'^ {0,3}(?:=+|-+)\s*$').hasMatch(lines[i + 1])) {
      segments.add(_LinesSegment([lines[i], lines[i + 1]], fixedUnits: 1));
      i += 2;
      continue;
    }

    final blockLines = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      if (blockLines.isNotEmpty) {
        if (_matchCodeFenceOpen(lines[i]) != null) break;
        if (i + 1 < lines.length &&
            lines[i].contains('|') &&
            _isGfmTableDelimiter(lines[i + 1])) {
          break;
        }
      }
      blockLines.add(lines[i]);
      i++;
    }
    segments.add(_LinesSegment(blockLines));
  }

  final totalUnits = segments.fold<int>(0, (sum, seg) => sum + seg.units);
  if (totalUnits <= collapseThreshold) {
    return (collapsible: false, preview: markdown);
  }

  final rendered = <String>[];
  var remaining = maxPreviewUnits;

  for (final seg in segments) {
    if (remaining <= 0) break;
    if (rendered.isNotEmpty && remaining < seg.minUnits) {
      break;
    }
    final budget = math.max(remaining, seg.minUnits);
    rendered.add(seg.render(maxUnits: budget));
    remaining -= math.min(seg.units, budget);
  }

  final preview = rendered.join('\n\n');
  final isTruncated = preview.trim() != normalized.trim();
  return (
    collapsible: isTruncated,
    preview: isTruncated ? preview : markdown,
  );
}

bool _isGfmTableDelimiter(String line) {
  final trimmed = line.trim();
  if (!trimmed.contains('|') || !trimmed.contains('-')) return false;
  var inner = trimmed;
  if (inner.startsWith('|')) inner = inner.substring(1);
  if (inner.endsWith('|')) inner = inner.substring(0, inner.length - 1);
  final cells = inner.split('|');
  if (cells.isEmpty) return false;
  return cells.every((cell) => RegExp(r'^\s*:?-+:?\s*$').hasMatch(cell));
}

String _closeTruncatedUnderlines(String fullBlock, String truncatedBlock) {
  if (!truncatedBlock.contains('<u>')) return truncatedBlock;
  final runs = RegExp(r'`+').allMatches(fullBlock).toList(growable: false);
  final events = <({int pos, bool isClose})>[];
  var index = 0;
  var runCursor = 0;

  while (index < fullBlock.length) {
    if (fullBlock.codeUnitAt(index) == 0x5C) {
      index += 2;
      continue;
    }
    if (fullBlock.codeUnitAt(index) == 0x60) {
      while (runCursor < runs.length && runs[runCursor].start < index) {
        runCursor++;
      }
      if (runCursor < runs.length && runs[runCursor].start == index) {
        final openRun = runs[runCursor];
        final len = openRun.end - openRun.start;
        int? closeEnd;
        for (var j = runCursor + 1; j < runs.length; j++) {
          if (runs[j].end - runs[j].start == len) {
            closeEnd = runs[j].end;
            runCursor = j + 1;
            break;
          }
        }
        index = closeEnd ?? openRun.end;
        continue;
      }
    }
    if (fullBlock.startsWith('<u>', index)) {
      events.add((pos: index, isClose: false));
      index += 3;
    } else if (fullBlock.startsWith('</u>', index)) {
      events.add((pos: index, isClose: true));
      index += 4;
    } else {
      index++;
    }
  }

  var severedCount = 0;
  var e = 0;
  while (e < events.length) {
    final current = events[e];
    if (current.isClose) {
      e++;
      continue;
    }
    var closeIdx = -1;
    for (var j = e + 1; j < events.length; j++) {
      if (events[j].isClose) {
        closeIdx = j;
        break;
      }
    }
    if (closeIdx < 0) break;
    final closePos = events[closeIdx].pos;
    if (current.pos < truncatedBlock.length &&
        closePos >= truncatedBlock.length) {
      severedCount++;
    }
    e = closeIdx + 1;
  }

  return severedCount > 0
      ? '$truncatedBlock${'</u>' * severedCount}'
      : truncatedBlock;
}

abstract class _MdSegment {
  int get units;
  int get minUnits => 1;
  String render({int? maxUnits});
}

class _CodeFenceSegment extends _MdSegment {
  _CodeFenceSegment({
    required this.openLine,
    required this.innerLines,
    required this.closeLine,
  });

  final String openLine;
  final List<String> innerLines;
  final String closeLine;

  @override
  int get units => math.max(1, innerLines.length);

  @override
  String render({int? maxUnits}) {
    if (maxUnits == null || innerLines.length <= maxUnits) {
      return [openLine, ...innerLines, closeLine].join('\n');
    }
    return [openLine, ...innerLines.take(maxUnits), closeLine].join('\n');
  }
}

class _TableSegment extends _MdSegment {
  _TableSegment({
    required this.header,
    required this.delimiter,
    required this.rows,
  });

  final String header;
  final String delimiter;
  final List<String> rows;

  @override
  int get units => 1 + rows.length;

  @override
  int get minUnits => rows.isEmpty ? 1 : 2;

  @override
  String render({int? maxUnits}) {
    if (maxUnits == null || units <= maxUnits) {
      return [header, delimiter, ...rows].join('\n');
    }
    final rowBudget = math.max(1, maxUnits - 1);
    return [header, delimiter, ...rows.take(rowBudget)].join('\n');
  }
}

class _LinesSegment extends _MdSegment {
  _LinesSegment(this.lines, {this.fixedUnits});

  final List<String> lines;
  final int? fixedUnits;

  @override
  int get units => fixedUnits ?? lines.length;

  @override
  String render({int? maxUnits}) {
    final fullBlock = lines.join('\n');
    if (fixedUnits != null || maxUnits == null || lines.length <= maxUnits) {
      return fullBlock;
    }
    final truncatedBlock = lines.take(maxUnits).join('\n');
    return _closeTruncatedUnderlines(fullBlock, truncatedBlock);
  }
}

enum _PlanCategoryFilter { all, period, onetime }

class PurchasePlanCatalog extends StatefulWidget {
  const PurchasePlanCatalog({
    super.key,
    required this.catalog,
    required this.loading,
    required this.failed,
    required this.retry,
    this.openLink,
    this.onAcquirePlan,
    this.collapsibleDetails = false,
  });

  final XboardPlanCatalog? catalog;
  final bool loading;
  final bool failed;
  final VoidCallback retry;
  final Future<void> Function(Uri)? openLink;
  final ValueChanged<XboardPlanOffer>? onAcquirePlan;
  final bool collapsibleDetails;

  @override
  State<PurchasePlanCatalog> createState() => _PurchasePlanCatalogState();
}

class _PurchasePlanCatalogState extends State<PurchasePlanCatalog> {
  _PlanCategoryFilter _filter = _PlanCategoryFilter.all;

  static bool _hasRecurringPeriod(XboardPlanOffer plan) =>
      plan.prices.any((price) => price.period != 'onetime');

  static bool _hasOnetimePeriod(XboardPlanOffer plan) =>
      plan.prices.any((price) => price.period == 'onetime');

  List<XboardPlanOffer> _applyFilter(List<XboardPlanOffer> plans) =>
      switch (_filter) {
        _PlanCategoryFilter.all => plans,
        _PlanCategoryFilter.period =>
          plans.where(_hasRecurringPeriod).toList(growable: false),
        _PlanCategoryFilter.onetime =>
          plans.where(_hasOnetimePeriod).toList(growable: false),
      };

  @override
  void didUpdateWidget(covariant PurchasePlanCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final plans = widget.catalog?.plans ?? const <XboardPlanOffer>[];
    if (_filter != _PlanCategoryFilter.all &&
        plans.isNotEmpty &&
        _applyFilter(plans).isEmpty) {
      _filter = _PlanCategoryFilter.all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final plans = widget.catalog?.plans ?? const <XboardPlanOffer>[];
    final recurringCount = plans.where(_hasRecurringPeriod).length;
    final onetimeCount = plans.where(_hasOnetimePeriod).length;
    final hasMixedCategories = plans.length > 1 &&
        recurringCount > 0 &&
        onetimeCount > 0 &&
        (recurringCount < plans.length || onetimeCount < plans.length);
    final filteredPlans = hasMixedCategories ? _applyFilter(plans) : plans;

    return Column(
      key: const Key('purchase-plans'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l.purchaseAvailablePlans,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (!widget.loading && !widget.failed && hasMixedCategories)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    key: const Key('purchase-plans-filter-all'),
                    label: Text(l.purchaseFilterAll),
                    labelStyle: theme.textTheme.labelSmall,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    selected: _filter == _PlanCategoryFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = _PlanCategoryFilter.all),
                  ),
                  ChoiceChip(
                    key: const Key('purchase-plans-filter-period'),
                    label: Text(l.purchaseFilterPeriod),
                    labelStyle: theme.textTheme.labelSmall,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    selected: _filter == _PlanCategoryFilter.period,
                    onSelected: (_) =>
                        setState(() => _filter = _PlanCategoryFilter.period),
                  ),
                  ChoiceChip(
                    key: const Key('purchase-plans-filter-onetime'),
                    label: Text(l.purchaseFilterOnetime),
                    labelStyle: theme.textTheme.labelSmall,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    selected: _filter == _PlanCategoryFilter.onetime,
                    onSelected: (_) =>
                        setState(() => _filter = _PlanCategoryFilter.onetime),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l.purchasePlansDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (widget.loading)
          Semantics(
            liveRegion: true,
            label: l.purchasePlansLoading,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(
                key: Key('purchase-plans-loading'),
                minHeight: 6,
              ),
            ),
          )
        else if (widget.failed)
          _CatalogStateCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 20,
                      color: colors.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.purchasePlansError)),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  key: const Key('purchase-plans-retry'),
                  onPressed: widget.retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l.purchaseRefresh),
                ),
              ],
            ),
          )
        else if (plans.isEmpty)
          _CatalogStateCard(
            child: Row(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(l.purchasePlansEmpty)),
              ],
            ),
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final twoColumns = filteredPlans.length > 1 &&
                constraints.maxWidth >= 540 * textScale;
            final width = twoColumns
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final plan in filteredPlans)
                  SizedBox(
                    width: width,
                    child: _PlanCard(
                      key: Key('purchase-plan-${plan.id}'),
                      plan: plan,
                      openLink: widget.openLink,
                      onAcquirePlan: widget.onAcquirePlan,
                      collapsibleDetails: widget.collapsibleDetails,
                    ),
                  ),
              ],
            );
          }),
      ],
    );
  }
}

class _CatalogStateCard extends StatelessWidget {
  const _CatalogStateCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _PlanCard extends StatefulWidget {
  const _PlanCard({
    super.key,
    required this.plan,
    this.openLink,
    this.onAcquirePlan,
    this.collapsibleDetails = false,
  });

  final XboardPlanOffer plan;
  final Future<void> Function(Uri)? openLink;
  final ValueChanged<XboardPlanOffer>? onAcquirePlan;
  final bool collapsibleDetails;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _detailsExpanded = false;

  XboardPlanOffer get plan => widget.plan;

  @override
  void didUpdateWidget(covariant _PlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.id != widget.plan.id) {
      _detailsExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final regionBadge = resolvePlanRegionBadge(plan.name);
    final isSoldOut = plan.hasCapacityRemaining && plan.capacityRemaining == 0;
    final isLowStock = plan.hasCapacityRemaining &&
        plan.capacityRemaining != null &&
        plan.capacityRemaining! > 0 &&
        plan.capacityRemaining! <= 20;

    final markdownSummary = widget.collapsibleDetails
        ? summarizePlanMarkdown(plan.content)
        : (collapsible: false, preview: plan.content);
    final shouldCollapse = markdownSummary.collapsible;
    final previewMarkdown = shouldCollapse && !_detailsExpanded
        ? markdownSummary.preview
        : plan.content;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSoldOut
              ? colors.outlineVariant.withValues(alpha: 0.55)
              : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (regionBadge != null) ...[
                      Container(
                        key: Key('purchase-plan-flag-${plan.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              colors.secondaryContainer.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: EmojiText(
                          regionBadge,
                          style: const TextStyle(fontSize: 15, height: 1.1),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        plan.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isSoldOut || isLowStock)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isSoldOut
                          ? colors.errorContainer
                          : colors.tertiaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isSoldOut
                          ? l.purchasePlanSoldOut
                          : l.purchasePlanLowStock(plan.capacityRemaining!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSoldOut
                            ? colors.onErrorContainer
                            : colors.onTertiaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            if (plan.tags.any((tag) => tag.trim().isNotEmpty)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in plan.tags)
                    if (tag.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tag,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.data_usage_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${l.purchaseTraffic}: ${plan.transferGiB} GiB',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFamily: FontFamily.jetBrainsMono.value,
                            fontFamilyFallback: _cjkMonoFallback(theme),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (var index = 0; index < plan.prices.length; index++) ...[
                    if (index > 0) const SizedBox(height: 6),
                    _priceTile(
                      theme,
                      _period(l, plan.prices[index].period),
                      plan.prices[index].amount,
                      highlighted: index == 0,
                    ),
                  ],
                  if (plan.resetTrafficPrice != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    _priceTile(
                      theme,
                      l.purchasePlanResetPrice,
                      plan.resetTrafficPrice!,
                      highlighted: false,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SpecPill(
                  icon: Icons.speed_rounded,
                  text: '${l.purchasePlanSpeed}: '
                      '${_limit(l, plan.hasSpeedLimit, plan.speedLimit, unit: ' Mbps')}',
                ),
                _SpecPill(
                  icon: Icons.devices_rounded,
                  text: '${l.purchasePlanDevices}: '
                      '${_limit(l, plan.hasDeviceLimit, plan.deviceLimit)}',
                ),
                _SpecPill(
                  icon: Icons.autorenew_rounded,
                  text: '${l.purchasePlanTrafficReset}: ${_reset(l)}',
                ),
                _SpecPill(
                  icon: Icons.confirmation_number_outlined,
                  text: '${l.purchasePlanSalesCapacity}: '
                      '${!plan.hasCapacityRemaining ? l.purchasePlanNotProvided : plan.capacityRemaining?.toString() ?? l.purchasePlanUnlimited}',
                ),
              ],
            ),
            if (plan.content.trim().isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l.purchasePlanDetails,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (shouldCollapse)
                    MergeSemantics(
                      key: Key('purchase-plan-details-toggle-${plan.id}'),
                      child: Semantics(
                        button: true,
                        expanded: _detailsExpanded,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(
                            () => _detailsExpanded = !_detailsExpanded,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _detailsExpanded
                                        ? l.purchasePlanCollapseDetails
                                        : l.purchasePlanExpandDetails,
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  _detailsExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 18,
                                  color: colors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              PurchasePlanContent(
                data: previewMarkdown,
                openLink: widget.openLink,
              ),
            ],
            if (widget.onAcquirePlan != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                key: Key('purchase-plan-acquire-${plan.id}'),
                onPressed: isSoldOut ? null : () => widget.onAcquirePlan!(plan),
                icon: Icon(
                  isSoldOut ? Icons.block_rounded : Icons.card_giftcard_rounded,
                  size: 18,
                ),
                label: Text(l.purchaseAcquirePlanCode),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _cjkMonoFallback(ThemeData theme) => <String>[
        if (theme.textTheme.bodyMedium?.fontFamily case final String family)
          family,
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'sans-serif',
      ];

  Widget _priceTile(
    ThemeData theme,
    String label,
    int amount, {
    required bool highlighted,
  }) {
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.surface.withValues(alpha: 0.85)
            : colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _amount(amount),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: FontFamily.jetBrainsMono.value,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _limit(
    AppLocalizations l,
    bool provided,
    int? value, {
    String unit = '',
  }) {
    if (!provided) return l.purchasePlanNotProvided;
    return (value ?? 0) == 0 ? l.purchasePlanUnlimited : '$value$unit';
  }

  String _reset(AppLocalizations l) {
    if (!plan.hasResetTrafficMethod) return l.purchasePlanNotProvided;
    return switch (plan.resetTrafficMethod) {
      null => l.purchasePlanResetSystem,
      0 => l.purchasePlanResetMonthStart,
      1 => l.purchasePlanResetMonthlyExpiry,
      2 => l.purchasePlanResetNever,
      3 => l.purchasePlanResetYearStart,
      4 => l.purchasePlanResetYearlyExpiry,
      final code => l.purchasePlanResetUnknown(code),
    };
  }

  // Keep minor units as integers; converting through double can round prices.
  String _amount(int amount) =>
      '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';

  String _period(AppLocalizations l, String period) => switch (period) {
        'monthly' => l.purchasePeriodMonthly,
        'quarterly' => l.purchasePeriodQuarterly,
        'half_yearly' => l.purchasePeriodHalfYearly,
        'yearly' => l.purchasePeriodYearly,
        'two_yearly' => l.purchasePeriodTwoYearly,
        'three_yearly' => l.purchasePeriodThreeYearly,
        'onetime' => l.purchasePeriodOnetime,
        _ => period,
      };
}

class _SpecPill extends StatelessWidget {
  const _SpecPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
