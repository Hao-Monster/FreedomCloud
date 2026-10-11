import 'dart:math' as math;

import 'package:flclashx/views/purchase/plan_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Operator-authored Markdown, never a WebView or arbitrary HTML renderer.
class PurchasePlanContent extends StatelessWidget {
  const PurchasePlanContent({super.key, required this.data, this.openLink});

  final String data;
  final Future<void> Function(Uri)? openLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(constraints.maxWidth, 640.0);
      final inline = _InlineContent(openLink, width);
      return MarkdownBody(
        data: data,
        softLineBreak: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        blockSyntaxes: const [_LiteralHtmlBlockSyntax()],
        inlineSyntaxes: [_UnderlineSyntax()],
        builders: {
          'u': _UnderlineBuilder(inline),
          'a': _LinkBuilder(inline),
          'img': _ImageBuilder(inline),
        },
        bulletBuilder: (parameters) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            parameters.style == BulletStyle.orderedList
                ? '${parameters.index + 1}.'
                : '•',
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            softWrap: false,
          ),
        ),
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          h1: theme.textTheme.titleMedium,
          h2: theme.textTheme.titleSmall,
          h3: theme.textTheme.titleSmall,
          h4: theme.textTheme.titleSmall,
          h5: theme.textTheme.titleSmall,
          h6: theme.textTheme.titleSmall,
          blockSpacing: 10,
          listIndent: _listIndent(context, theme, width),
          // Wide tables remain available by scrolling, including at 2x text.
          tableColumnWidth: const IntrinsicColumnWidth(),
          tableScrollbarThumbVisibility: true,
          tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant),
          tableCellsPadding: const EdgeInsets.all(8),
        ),
      );
    });
  }

  double _listIndent(BuildContext context, ThemeData theme, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    // Inspect only block structure: code, HTML and ordinary text are not lists.
    // Inline parsing is unnecessary here and is done once by MarkdownBody.
    final nodes = md.BlockParser(
      data.split('\n').map(md.Line.new).toList(),
      md.Document(extensionSet: md.ExtensionSet.gitHubFlavored),
    ).parseLines();
    var largestIndex = 1;
    void visit(md.Node node) {
      if (node is! md.Element) return;
      if (node.tag == 'ol') {
        final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        final count = node.children
                ?.whereType<md.Element>()
                .where((child) => child.tag == 'li')
                .length ??
            0;
        largestIndex = math.max(largestIndex, start + count - 1);
      }
      node.children?.forEach(visit);
    }

    nodes.forEach(visit);
    // Include automatic numbering; source may use "1." on every list item.
    // Measure the actual font instead of assuming a number and dot fit at 2x.
    final painter = TextPainter(
      text: TextSpan(text: '$largestIndex.', style: theme.textTheme.bodyMedium),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final indent =
        math.max(22 * scaler.scale(1), painter.width + scaler.scale(6));
    painter.dispose();
    // Very large start numbers must not consume a narrow card's whole width.
    // The marker scales down, while the actual list content keeps its text size.
    return math.min(indent, width / 3);
  }
}

class _LiteralHtmlBlockSyntax extends md.HtmlBlockSyntax {
  const _LiteralHtmlBlockSyntax();

  // The renderer drops root-level Text nodes. Keep HTML blocks readable inside
  // a paragraph without parsing their tags, attributes, or Markdown contents.
  @override
  md.Node parse(md.BlockParser parser) =>
      md.Element('p', [super.parse(parser)]);
}

class _ImageBuilder extends MarkdownElementBuilder {
  _ImageBuilder(this.inline);
  final _InlineContent inline;

  // Validate the source in our bounded loader before any URI/image provider.
  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
          TextStyle? preferredStyle, TextStyle? parentStyle) =>
      inline.image(element);
}

// Match the web editor's sole HTML extension: an exact, attribute-free pair.
// Its body is parsed as inline Markdown, retaining emphasis and safe links.
// All other raw HTML stays inert text, as in the Markdown package itself.
class _UnderlineSyntax extends md.InlineSyntax {
  _UnderlineSyntax() : super(r'<u>', startCharacter: 60);

  final _closingTags = Expando<List<int>>();

  List<int> _findClosingTags(String source) {
    // A closing tag inside code or an escape is literal text. Index backtick
    // runs once, avoiding repeated scans of long unmatched-code tails.
    final runs = RegExp(r'`+').allMatches(source).toList();
    final nextRunEnd = <int, int>{};
    final codeEnds = <int, int>{};
    for (final run in runs.reversed) {
      final length = run.end - run.start;
      final next = nextRunEnd[length];
      if (next != null) codeEnds[run.start] = next;
      nextRunEnd[length] = run.end;
    }
    final tags = <int>[];
    var index = 0;
    while (index < source.length) {
      if (source.codeUnitAt(index) == 92) {
        index += 2; // Markdown escapes include '<' and '`'.
      } else if (codeEnds.containsKey(index)) {
        index = codeEnds[index]!;
      } else if (source.startsWith('</u>', index)) {
        tags.add(index);
        index += 4;
      } else {
        index++;
      }
    }
    return tags;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    // One index per paragraph, also bounding repeated unmatched <u> scans.
    final tags = _closingTags[parser] ??= _findClosingTags(parser.source);
    var low = 0;
    var high = tags.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (tags[middle] < match.end) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final end = low < tags.length ? tags[low] : -1;
    if (end == -1) {
      parser.addNode(md.Text('<u>'));
      return true;
    }
    final source = parser.source.substring(match.end, end);
    final element = md.Element(
      'u',
      md.InlineParser(source, parser.document).parse(),
    );
    parser.addNode(element);
    parser.consume(end + 4 - parser.pos);
    return false;
  }
}

class _UnderlineBuilder extends MarkdownElementBuilder {
  _UnderlineBuilder(this.inline);
  final _InlineContent inline;

  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final style = parentStyle ?? DefaultTextStyle.of(context).style;
    return inline.text(context, [element], style);
  }
}

class _LinkBuilder extends MarkdownElementBuilder {
  _LinkBuilder(this.inline);
  final _InlineContent inline;

  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
          TextStyle? preferredStyle, TextStyle? parentStyle) =>
      inline.link(
          context, element, parentStyle ?? DefaultTextStyle.of(context).style);
}

class _InlineContent {
  const _InlineContent(this.openLink, this.maxWidth);

  final Future<void> Function(Uri)? openLink;
  final double maxWidth;

  Widget image(md.Element element) => PurchasePlanImage(
        source: element.attributes['src'] ?? '',
        alt: element.attributes['alt'] ?? '',
        maxWidth: maxWidth,
      );

  TextStyle _decorate(TextStyle style, TextDecoration decoration) =>
      style.copyWith(
          decoration: TextDecoration.combine([
        if (style.decoration != null) style.decoration!,
        decoration,
      ]));

  Iterable<InlineSpan> _spans(
      BuildContext context, List<md.Node> nodes, TextStyle style) sync* {
    for (final node in nodes) {
      if (node is! md.Element) {
        yield TextSpan(text: node.textContent, style: style);
        continue;
      }
      if (node.tag == 'img' || node.tag == 'a') {
        yield WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: node.tag == 'img' ? image(node) : link(context, node, style),
        );
      } else if (node.tag == 'br') {
        yield TextSpan(text: '\n', style: style);
      } else {
        final childStyle = switch (node.tag) {
          'strong' => style.copyWith(fontWeight: FontWeight.bold),
          'em' => style.copyWith(fontStyle: FontStyle.italic),
          'del' => _decorate(style, TextDecoration.lineThrough),
          'u' => _decorate(style, TextDecoration.underline),
          'code' => style.copyWith(fontFamily: 'monospace'),
          _ => style,
        };
        yield* _spans(context, node.children ?? const [], childStyle);
      }
    }
  }

  Widget text(BuildContext context, List<md.Node> nodes, TextStyle style) =>
      // The Markdown renderer flattens Text widgets and can discard nested
      // decorations. Keep this inline AST intact, without reparsing it as blocks.
      Padding(
        padding: EdgeInsets.zero,
        child: Text.rich(
            TextSpan(children: _spans(context, nodes, style).toList())),
      );

  Widget link(BuildContext context, md.Element element, TextStyle style) {
    final href = element.attributes['href'];
    final uri = href == null ? null : Uri.tryParse(href);
    if (openLink == null ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return text(context, element.children ?? const [], style);
    }
    // A native button supports focus/keyboard activation as well as a tap.
    // Opening and error feedback use the purchase page's existing boundary.
    return TextButton(
      onPressed: () => openLink!(uri),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
      ),
      child: text(
          context,
          element.children ?? const [],
          _decorate(
              style.copyWith(color: Theme.of(context).colorScheme.primary),
              TextDecoration.underline)),
    );
  }
}
