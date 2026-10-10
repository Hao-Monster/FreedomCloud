import 'dart:math' as math;

import 'package:flclashx/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Operator-authored Markdown, never a WebView or arbitrary HTML renderer.
class PurchasePlanContent extends StatelessWidget {
  const PurchasePlanContent({super.key, required this.data, this.openLink})
      : _textStyle = null;

  const PurchasePlanContent._underlined({
    required this.data,
    required this.openLink,
    required TextStyle textStyle,
  }) : _textStyle = textStyle;

  final String data;
  final Future<void> Function(Uri)? openLink;
  final TextStyle? _textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: data,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: const [_LiteralHtmlBlockSyntax()],
      inlineSyntaxes: [_UnderlineSyntax()],
      builders: {
        'u': _UnderlineBuilder(openLink),
        'a': _LinkBuilder(openLink),
        'img': _ImagePlaceholderBuilder(),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: _textStyle ?? theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        h1: theme.textTheme.titleMedium,
        h2: theme.textTheme.titleSmall,
        h3: theme.textTheme.titleSmall,
        h4: theme.textTheme.titleSmall,
        h5: theme.textTheme.titleSmall,
        h6: theme.textTheme.titleSmall,
        blockSpacing: 10,
        listIndent: _listIndent(context, theme),
        // Wide tables remain available by scrolling, including at 2x text.
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableScrollbarThumbVisibility: true,
        tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant),
        tableCellsPadding: const EdgeInsets.all(8),
      ),
    );
  }

  double _listIndent(BuildContext context, ThemeData theme) {
    final scaler = MediaQuery.textScalerOf(context);
    final markers =
        RegExp(r'^\s*(\d{1,9})[.)]\s', multiLine: true).allMatches(data);
    var largestStart = 1;
    var count = 0;
    for (final marker in markers) {
      largestStart = math.max(largestStart, int.parse(marker.group(1)!));
      count++;
    }
    // Include automatic numbering; source may use "1." on every list item.
    // Measure the actual font instead of assuming a number and dot fit at 2x.
    final painter = TextPainter(
      text: TextSpan(
          text: '${largestStart + count}.', style: theme.textTheme.bodyMedium),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final indent =
        math.max(22 * scaler.scale(1), painter.width + scaler.scale(6));
    painter.dispose();
    return indent;
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

String _imageLabel(BuildContext context, md.Element image) => [
      AppLocalizations.of(context).purchasePlanImageNotLoaded,
      if (image.attributes['alt']?.isNotEmpty ?? false)
        image.attributes['alt']!,
    ].join(' · ');

class _ImagePlaceholderBuilder extends MarkdownElementBuilder {
  // Override before URI parsing: no network, file, asset, or data image loaders,
  // including for malformed URLs.
  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
          TextStyle? preferredStyle, TextStyle? parentStyle) =>
      Text(_imageLabel(context, element),
          style: Theme.of(context).textTheme.bodySmall);
}

// Match the web editor's sole HTML extension: an exact, attribute-free pair.
// Its body is parsed as Markdown separately, retaining emphasis and safe links.
// All other raw HTML stays inert text, as in the Markdown package itself.
class _UnderlineSyntax extends md.InlineSyntax {
  _UnderlineSyntax() : super(r'<u>', startCharacter: 60);

  final _noClosingTag = Expando<bool>();

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    // Scan an unmatched tail only once per paragraph, not once per <u>.
    final end = (_noClosingTag[parser] ?? false)
        ? -1
        : parser.source.indexOf('</u>', match.end);
    if (end == -1) {
      _noClosingTag[parser] = true;
      parser.addNode(md.Text('<u>'));
      return true;
    }
    final source = parser.source.substring(match.end, end);
    final element = md.Element(
      'u',
      md.InlineParser(source, parser.document).parse(),
    )..attributes['data-markdown'] = source;
    parser.addNode(element);
    parser.consume(end + 4 - parser.pos);
    return false;
  }
}

class _UnderlineBuilder extends MarkdownElementBuilder {
  _UnderlineBuilder(this.openLink);

  final Future<void> Function(Uri)? openLink;

  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final style = parentStyle ?? DefaultTextStyle.of(context).style;
    return PurchasePlanContent._underlined(
      data: element.attributes['data-markdown']!,
      openLink: openLink,
      textStyle: style.copyWith(
        decoration: TextDecoration.combine([
          if (style.decoration != null) style.decoration!,
          TextDecoration.underline,
        ]),
      ),
    );
  }
}

class _LinkBuilder extends MarkdownElementBuilder {
  _LinkBuilder(this.openLink);

  final Future<void> Function(Uri)? openLink;

  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final href = element.attributes['href'];
    final uri = href == null ? null : Uri.tryParse(href);
    // textContent alone drops image alt text and creates empty linked images.
    String labelFor(md.Node node) => node is md.Element
        ? node.tag == 'img'
            ? _imageLabel(context, node)
            : (node.children ?? const []).map(labelFor).join()
        : node.textContent;
    final label = labelFor(element);
    if (openLink == null ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return Text(label, style: parentStyle);
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
        textStyle: parentStyle?.copyWith(decoration: TextDecoration.underline),
      ),
      child: Text(label),
    );
  }
}
