import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/models/common.dart';
import 'package:flclashx/models/selector.dart';
import 'package:flclashx/widgets/flag.dart';
import 'package:flutter/foundation.dart';

const String kUnknownCountryCode = 'OTHER';

typedef ResolveServerCountryCallback = Future<String?> Function(String server);

const List<String> _preferredCountryOrder = <String>[
  'HK',
  'TW',
  'JP',
  'SG',
  'US',
  'KR',
  'GB',
  'MO',
  'DE',
  'NL',
  'FR',
  'CA',
  'AU',
  'RU',
  'MY',
  'TH',
  'IN',
  'VN',
  'PH',
  'ID',
  'TR',
  'AE',
  'IT',
  'ES',
  'CH',
  'SE',
  'IE',
  'BR',
  'AR',
  'ZA',
  'NZ',
  'PL',
  'UA',
  'FI',
  'NO',
  'AT',
  'BE',
  'PT',
  'IL',
  'MX',
  'CL',
  'RO',
  'HU',
  'CZ',
  'BG',
  'GR',
  'DK',
  'IS',
  'LU',
  'PK',
  'BD',
  'NG',
  'EG',
  'SA',
  'KZ',
  'CN',
];

final Map<String, int> _preferredCountryRank = <String, int>{
  for (var i = 0; i < _preferredCountryOrder.length; i++)
    _preferredCountryOrder[i]: i,
};

const Map<String, ({String zh, String en})> _countryNames =
    <String, ({String zh, String en})>{
  'HK': (zh: '香港', en: 'Hong Kong'),
  'TW': (zh: '台湾', en: 'Taiwan'),
  'MO': (zh: '澳门', en: 'Macao'),
  'JP': (zh: '日本', en: 'Japan'),
  'SG': (zh: '新加坡', en: 'Singapore'),
  'US': (zh: '美国', en: 'United States'),
  'KR': (zh: '韩国', en: 'South Korea'),
  'GB': (zh: '英国', en: 'United Kingdom'),
  'DE': (zh: '德国', en: 'Germany'),
  'FR': (zh: '法国', en: 'France'),
  'NL': (zh: '荷兰', en: 'Netherlands'),
  'CA': (zh: '加拿大', en: 'Canada'),
  'AU': (zh: '澳大利亚', en: 'Australia'),
  'RU': (zh: '俄罗斯', en: 'Russia'),
  'IN': (zh: '印度', en: 'India'),
  'MY': (zh: '马来西亚', en: 'Malaysia'),
  'TH': (zh: '泰国', en: 'Thailand'),
  'VN': (zh: '越南', en: 'Vietnam'),
  'PH': (zh: '菲律宾', en: 'Philippines'),
  'ID': (zh: '印尼', en: 'Indonesia'),
  'TR': (zh: '土耳其', en: 'Turkey'),
  'BR': (zh: '巴西', en: 'Brazil'),
  'AR': (zh: '阿根廷', en: 'Argentina'),
  'AE': (zh: '阿联酋', en: 'UAE'),
  'IT': (zh: '意大利', en: 'Italy'),
  'ES': (zh: '西班牙', en: 'Spain'),
  'CH': (zh: '瑞士', en: 'Switzerland'),
  'SE': (zh: '瑞典', en: 'Sweden'),
  'IE': (zh: '爱尔兰', en: 'Ireland'),
  'PL': (zh: '波兰', en: 'Poland'),
  'ZA': (zh: '南非', en: 'South Africa'),
  'UA': (zh: '乌克兰', en: 'Ukraine'),
  'FI': (zh: '芬兰', en: 'Finland'),
  'NO': (zh: '挪威', en: 'Norway'),
  'AT': (zh: '奥地利', en: 'Austria'),
  'BE': (zh: '比利时', en: 'Belgium'),
  'PT': (zh: '葡萄牙', en: 'Portugal'),
  'NZ': (zh: '新西兰', en: 'New Zealand'),
  'IL': (zh: '以色列', en: 'Israel'),
  'MX': (zh: '墨西哥', en: 'Mexico'),
  'CL': (zh: '智利', en: 'Chile'),
  'CO': (zh: '哥伦比亚', en: 'Colombia'),
  'PE': (zh: '秘鲁', en: 'Peru'),
  'RO': (zh: '罗马尼亚', en: 'Romania'),
  'HU': (zh: '匈牙利', en: 'Hungary'),
  'CZ': (zh: '捷克', en: 'Czechia'),
  'BG': (zh: '保加利亚', en: 'Bulgaria'),
  'GR': (zh: '希腊', en: 'Greece'),
  'DK': (zh: '丹麦', en: 'Denmark'),
  'IS': (zh: '冰岛', en: 'Iceland'),
  'LU': (zh: '卢森堡', en: 'Luxembourg'),
  'PK': (zh: '巴基斯坦', en: 'Pakistan'),
  'BD': (zh: '孟加拉', en: 'Bangladesh'),
  'NG': (zh: '尼日利亚', en: 'Nigeria'),
  'EG': (zh: '埃及', en: 'Egypt'),
  'SA': (zh: '沙特', en: 'Saudi Arabia'),
  'KZ': (zh: '哈萨克斯坦', en: 'Kazakhstan'),
  'KP': (zh: '朝鲜', en: 'North Korea'),
  'MN': (zh: '蒙古', en: 'Mongolia'),
  'KH': (zh: '柬埔寨', en: 'Cambodia'),
  'LA': (zh: '老挝', en: 'Laos'),
  'MM': (zh: '缅甸', en: 'Myanmar'),
  'NP': (zh: '尼泊尔', en: 'Nepal'),
  'LK': (zh: '斯里兰卡', en: 'Sri Lanka'),
  'CN': (zh: '中国', en: 'China'),
};

// Check overseas regions before 'CN' so cross-border transit names such as
// "深港专线" or "沪日IEPL" resolve to their destination country (HK/JP).
const List<(String, List<String>)> _zhKeywordsByCountry =
    <(String, List<String>)>[
  (
    'HK',
    <String>['香港', '深港', '沪港', '广港', '京港', '港专线', '九龙', '新界', '大埔', '将军澳'],
  ),
  (
    'TW',
    <String>['台湾', '台灣', '台北', '臺北', '新北', '台中', '高雄', '彰化', '桃园', '桃園', '新竹'],
  ),
  ('MO', <String>['澳门', '澳門']),
  (
    'JP',
    <String>[
      '日本',
      '东京',
      '東京',
      '大阪',
      '名古屋',
      '埼玉',
      '福冈',
      '福岡',
      '札幌',
      '横滨',
      '泉日',
      '沪日',
      '广日',
    ],
  ),
  ('SG', <String>['新加坡', '狮城', '獅城', '坡县']),
  (
    'US',
    <String>[
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
      '圣克拉拉',
      '弗里蒙特',
      '阿什本',
      '沪美',
      '广美',
    ],
  ),
  ('KR', <String>['韩国', '韓國', '首尔', '首爾', '釜山', '仁川', '春川']),
  (
    'GB',
    <String>['英国', '英國', '伦敦', '倫敦', '曼彻斯特', '伯明翰', '苏格兰', '爱丁堡', '考文垂'],
  ),
  ('DE', <String>['德国', '德國', '法兰克福', '慕尼黑', '柏林', '杜塞尔多夫', '纽伦堡']),
  ('FR', <String>['法国', '法國', '巴黎', '马赛', '斯特拉斯堡']),
  ('NL', <String>['荷兰', '荷蘭', '阿姆斯特丹', '鹿特丹']),
  ('CA', <String>['加拿大', '温哥华', '多伦多', '蒙特利尔', '渥太华']),
  ('AU', <String>['澳大利亚', '澳洲', '悉尼', '墨尔本', '布里斯班', '珀斯']),
  ('RU', <String>['俄罗斯', '俄羅斯', '莫斯科', '圣彼得堡', '新西伯利亚', '伯力', '海参崴']),
  ('IN', <String>['印度', '孟买', '新德里', '班加罗尔', '金奈']),
  ('MY', <String>['马来西亚', '馬來西亞', '大马', '吉隆坡', '柔佛']),
  ('TH', <String>['泰国', '泰國', '曼谷']),
  ('VN', <String>['越南', '河内', '胡志明']),
  ('PH', <String>['菲律宾', '菲律賓', '马尼拉']),
  ('ID', <String>['印尼', '印度尼西亚', '雅加达']),
  ('TR', <String>['土耳其', '伊斯坦布尔', '安卡拉']),
  ('BR', <String>['巴西', '圣保罗']),
  ('AR', <String>['阿根廷', '布宜诺斯艾利斯']),
  ('AE', <String>['阿联酋', '迪拜', '阿布扎比']),
  ('IT', <String>['意大利', '米兰', '罗马']),
  ('ES', <String>['西班牙', '马德里', '巴塞罗那']),
  ('CH', <String>['瑞士', '苏黎世', '日内瓦']),
  ('SE', <String>['瑞典', '斯德哥尔摩']),
  ('IE', <String>['爱尔兰', '都柏林']),
  ('PL', <String>['波兰', '华沙']),
  ('ZA', <String>['南非', '约翰内斯堡']),
  ('UA', <String>['乌克兰', '基辅']),
  ('FI', <String>['芬兰', '赫尔辛基']),
  ('NO', <String>['挪威', '奥斯陆']),
  ('AT', <String>['奥地利', '维也纳']),
  ('BE', <String>['比利时', '布鲁塞尔']),
  ('PT', <String>['葡萄牙', '里斯本']),
  ('NZ', <String>['新西兰', '奥克兰']),
  ('IL', <String>['以色列', '特拉维夫']),
  ('MX', <String>['墨西哥']),
  ('CL', <String>['智利', '圣地亚哥']),
  ('RO', <String>['罗马尼亚', '布加勒斯特']),
  ('HU', <String>['匈牙利', '布达佩斯']),
  ('CZ', <String>['捷克', '布拉格']),
  ('BG', <String>['保加利亚', '索非亚']),
  ('GR', <String>['希腊', '雅典']),
  ('DK', <String>['丹麦', '哥本哈根']),
  ('IS', <String>['冰岛', '雷克雅未克']),
  ('LU', <String>['卢森堡']),
  ('PK', <String>['巴基斯坦']),
  ('BD', <String>['孟加拉']),
  ('NG', <String>['尼日利亚']),
  ('EG', <String>['埃及', '开罗']),
  ('SA', <String>['沙特', '利雅得']),
  ('KZ', <String>['哈萨克斯坦', '阿拉木图']),
  ('KP', <String>['朝鲜', '平壤']),
  ('MN', <String>['蒙古', '乌兰巴托']),
  ('KH', <String>['柬埔寨', '金边']),
  ('LA', <String>['老挝', '万象']),
  ('MM', <String>['缅甸', '仰光']),
  ('NP', <String>['尼泊尔', '加德满都']),
  ('LK', <String>['斯里兰卡']),
  ('CN', <String>['中国', '中國', '大陆', '内蒙古']),
];

// Match longer, more specific Chinese country/city names before shorter
// prefixes (e.g. "印度尼西亚" -> ID before "印度" -> IN, "罗马尼亚" -> RO before
// "罗马" -> IT, "内蒙古" -> CN before "蒙古" -> MN), keeping table priority on ties.
final List<(String code, String keyword)> _sortedZhKeywords = () {
  final indexed = <({String code, String keyword, int order})>[];
  var order = 0;
  for (final (code, keywords) in _zhKeywordsByCountry) {
    for (final keyword in keywords) {
      indexed.add((code: code, keyword: keyword, order: order++));
    }
  }
  indexed.sort((a, b) {
    final lenCompare = b.keyword.length.compareTo(a.keyword.length);
    if (lenCompare != 0) return lenCompare;
    return a.order.compareTo(b.order);
  });
  return [for (final item in indexed) (item.code, item.keyword)];
}();

final List<(String, RegExp)> _englishPatternsByCountry = <(String, RegExp)>[
  (
    'HK',
    RegExp(r'(?<![A-Za-z])(hong\s*kong)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'TW',
    RegExp(
      r'(?<![A-Za-z])(taiwan|taipei|taichung|kaohsiung|hsinchu)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'MO',
    RegExp(r'(?<![A-Za-z])(macao|macau)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'JP',
    RegExp(
      r'(?<![A-Za-z])(japan|tokyo|osaka|nagoya|saitama|fukuoka|sapporo|yokohama)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'SG',
    RegExp(r'(?<![A-Za-z])(singapore)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'US',
    RegExp(
      r'(?<![A-Za-z])(united\s+states|america|los\s*angeles|san\s*jose|san\s*francisco|silicon\s*valley|seattle|new\s*york|chicago|dallas|phoenix|atlanta|portland|las\s*vegas|denver|miami|virginia|oregon|ashburn|fremont|santa\s*clara)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'KP',
    RegExp(
      r'(?<![A-Za-z])(north\s+korea|pyongyang)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'KR',
    RegExp(
      r'(?<![A-Za-z])(south\s+korea|korea|seoul|busan|incheon|chuncheon)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'GB',
    RegExp(
      r'(?<![A-Za-z])(united\s+kingdom|great\s+britain|britain|england|scotland|london|manchester|birmingham|edinburgh|coventry)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'DE',
    RegExp(
      r'(?<![A-Za-z])(germany|frankfurt|munich|berlin|dusseldorf|nuremberg)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'FR',
    RegExp(
      r'(?<![A-Za-z])(france|paris|marseille|strasbourg)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'NL',
    RegExp(
      r'(?<![A-Za-z])(netherlands|holland|amsterdam|rotterdam)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'CA',
    RegExp(
      r'(?<![A-Za-z])(canada|vancouver|toronto|montreal|ottawa)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'AU',
    RegExp(
      r'(?<![A-Za-z])(australia|sydney|melbourne|brisbane|perth)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'RU',
    RegExp(
      r'(?<![A-Za-z])(russia|moscow|saint\s+petersburg|novosibirsk|khabarovsk|vladivostok)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'IN',
    RegExp(
      r'(?<![A-Za-z])(india|mumbai|new\s+delhi|bangalore|chennai|hyderabad)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'MY',
    RegExp(
      r'(?<![A-Za-z])(malaysia|kuala\s+lumpur|johor)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'TH',
    RegExp(
      r'(?<![A-Za-z])(thailand|bangkok)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'VN',
    RegExp(
      r'(?<![A-Za-z])(vietnam|hanoi|ho\s+chi\s+minh)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'PH',
    RegExp(
      r'(?<![A-Za-z])(philippines|manila)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'ID',
    RegExp(
      r'(?<![A-Za-z])(indonesia|jakarta)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'TR',
    RegExp(
      r'(?<![A-Za-z])(turkey|turkiye|istanbul|ankara)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'BR',
    RegExp(
      r'(?<![A-Za-z])(brazil|sao\s+paulo)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'AR',
    RegExp(
      r'(?<![A-Za-z])(argentina|buenos\s+aires)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'AE',
    RegExp(
      r'(?<![A-Za-z])(united\s+arab\s+emirates|dubai|abu\s+dhabi)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'IT',
    RegExp(
      r'(?<![A-Za-z])(italy|milan|rome)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'ES',
    RegExp(
      r'(?<![A-Za-z])(spain|madrid|barcelona)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'CH',
    RegExp(
      r'(?<![A-Za-z])(switzerland|zurich|geneva)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'SE',
    RegExp(
      r'(?<![A-Za-z])(sweden|stockholm)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'IE',
    RegExp(
      r'(?<![A-Za-z])(ireland|dublin)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'PL',
    RegExp(
      r'(?<![A-Za-z])(poland|warsaw)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'ZA',
    RegExp(
      r'(?<![A-Za-z])(south\s+africa|johannesburg)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'UA',
    RegExp(
      r'(?<![A-Za-z])(ukraine|kyiv|kiev)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'FI',
    RegExp(
      r'(?<![A-Za-z])(finland|helsinki)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'NO',
    RegExp(
      r'(?<![A-Za-z])(norway|oslo)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'AT',
    RegExp(
      r'(?<![A-Za-z])(austria|vienna)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'BE',
    RegExp(
      r'(?<![A-Za-z])(belgium|brussels)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'PT',
    RegExp(
      r'(?<![A-Za-z])(portugal|lisbon)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'NZ',
    RegExp(
      r'(?<![A-Za-z])(new\s+zealand|auckland)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'IL',
    RegExp(
      r'(?<![A-Za-z])(israel|tel\s+aviv)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'MX',
    RegExp(r'(?<![A-Za-z])(mexico)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'CL',
    RegExp(r'(?<![A-Za-z])(chile|santiago)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'RO',
    RegExp(
      r'(?<![A-Za-z])(romania|bucharest)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'HU',
    RegExp(
      r'(?<![A-Za-z])(hungary|budapest)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'CZ',
    RegExp(
      r'(?<![A-Za-z])(czechia|czech|prague)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'DK',
    RegExp(
      r'(?<![A-Za-z])(denmark|copenhagen)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'IS',
    RegExp(
      r'(?<![A-Za-z])(iceland|reykjavik)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'LU',
    RegExp(r'(?<![A-Za-z])(luxembourg)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'GR',
    RegExp(r'(?<![A-Za-z])(greece|athens)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'BG',
    RegExp(r'(?<![A-Za-z])(bulgaria|sofia)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'CO',
    RegExp(r'(?<![A-Za-z])(colombia|bogota)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'PE',
    RegExp(r'(?<![A-Za-z])(peru|lima)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'PK',
    RegExp(
      r'(?<![A-Za-z])(pakistan|karachi)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'BD',
    RegExp(
      r'(?<![A-Za-z])(bangladesh|dhaka)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'NG',
    RegExp(r'(?<![A-Za-z])(nigeria|lagos)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'EG',
    RegExp(r'(?<![A-Za-z])(egypt|cairo)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'SA',
    RegExp(
      r'(?<![A-Za-z])(saudi\s+arabia|riyadh)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'KZ',
    RegExp(
      r'(?<![A-Za-z])(kazakhstan|almaty)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'MN',
    RegExp(
      r'(?<![A-Za-z])(mongolia|ulaanbaatar)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'KH',
    RegExp(
      r'(?<![A-Za-z])(cambodia|phnom\s+penh)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'LA',
    RegExp(r'(?<![A-Za-z])(laos|vientiane)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'MM',
    RegExp(r'(?<![A-Za-z])(myanmar|yangon)(?![A-Za-z])', caseSensitive: false),
  ),
  (
    'NP',
    RegExp(
      r'(?<![A-Za-z])(nepal|kathmandu)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'LK',
    RegExp(
      r'(?<![A-Za-z])(sri\s+lanka|colombo)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
  (
    'CN',
    RegExp(
      r'(?<![A-Za-z])(china|beijing|shanghai|shenzhen|guangzhou)(?![A-Za-z])',
      caseSensitive: false,
    ),
  ),
];

// Standalone ALL-CAPS ISO/airport codes (case-sensitive to avoid matching
// common English words such as "in", "it", "is", "no", "us", "at", "be").
final List<(String, RegExp)> _upperCodePatternsByCountry = <(String, RegExp)>[
  ('HK', RegExp(r'(?<![A-Za-z])(HK|HKG)(?![A-Za-z])')),
  ('TW', RegExp(r'(?<![A-Za-z])(TW|TWN|TPE|KHH)(?![A-Za-z])')),
  ('MO', RegExp(r'(?<![A-Za-z])(MO|MAC|MFM)(?![A-Za-z])')),
  ('JP', RegExp(r'(?<![A-Za-z])(JP|JPN|NRT|HND|KIX|TYO|OSA)(?![A-Za-z])')),
  ('SG', RegExp(r'(?<![A-Za-z])(SG|SGP|SIN)(?![A-Za-z])')),
  (
    'US',
    RegExp(
      r'(?<![A-Za-z])(US|USA|LAX|SJC|SFO|SEA|ORD|DFW|JFK|EWR|IAD|MIA|ATL|DEN|PHX|LAS|PDX|SLC)(?![A-Za-z])',
    ),
  ),
  ('KR', RegExp(r'(?<![A-Za-z])(KR|KOR|ICN|SEL|PUS)(?![A-Za-z])')),
  ('GB', RegExp(r'(?<![A-Za-z])(UK|GB|GBR|LHR|LON|MAN)(?![A-Za-z])')),
  ('DE', RegExp(r'(?<![A-Za-z])(DE|DEU|FRA|MUC|BER|DUS)(?![A-Za-z])')),
  ('FR', RegExp(r'(?<![A-Za-z])(FR|CDG|MRS)(?![A-Za-z])')),
  ('NL', RegExp(r'(?<![A-Za-z])(NL|NLD|AMS)(?![A-Za-z])')),
  ('CA', RegExp(r'(?<![A-Za-z])(CA|CAN|YVR|YYZ|YUL)(?![A-Za-z])')),
  ('AU', RegExp(r'(?<![A-Za-z])(AU|AUS|SYD|MEL|BNE|PER)(?![A-Za-z])')),
  ('RU', RegExp(r'(?<![A-Za-z])(RU|RUS|SVO|DME|LED|VVO|KHV)(?![A-Za-z])')),
  ('IN', RegExp(r'(?<![A-Za-z])(IND|BOM|DEL|BLR)(?![A-Za-z])')),
  ('MY', RegExp(r'(?<![A-Za-z])(MY|MYS|KUL)(?![A-Za-z])')),
  ('TH', RegExp(r'(?<![A-Za-z])(TH|THA|BKK)(?![A-Za-z])')),
  ('VN', RegExp(r'(?<![A-Za-z])(VN|VNM|HAN|SGN)(?![A-Za-z])')),
  ('PH', RegExp(r'(?<![A-Za-z])(PH|PHL|MNL)(?![A-Za-z])')),
  ('ID', RegExp(r'(?<![A-Za-z])(IDN|CGK)(?![A-Za-z])')),
  ('TR', RegExp(r'(?<![A-Za-z])(TR|TUR|IST)(?![A-Za-z])')),
  ('BR', RegExp(r'(?<![A-Za-z])(BR|BRA|GRU)(?![A-Za-z])')),
  ('AR', RegExp(r'(?<![A-Za-z])(AR|ARG|EZE)(?![A-Za-z])')),
  ('AE', RegExp(r'(?<![A-Za-z])(AE|ARE|DXB|AUH)(?![A-Za-z])')),
];

String? normalizeIsoCountryCode(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().toUpperCase();
  if (trimmed == 'UK') return 'GB';
  if (trimmed.length != 2) return null;
  final a = trimmed.codeUnitAt(0);
  final b = trimmed.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return null;
  if (const {'UN', 'EU', 'XX', 'ZZ', 'AA'}.contains(trimmed)) return null;
  return trimmed;
}

final RegExp _byteSizeUnitPattern = RegExp(
  r'\d+(?:\.\d+)?\s*(?:[KMGTPE]i?B|B)(?![A-Za-z])',
  caseSensitive: false,
);

String? inferCountryCodeFromText(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final flagCode = normalizeIsoCountryCode(flagToCountryCode(text));
  if (flagCode != null) return flagCode;
  for (final (code, keyword) in _sortedZhKeywords) {
    if (text.contains(keyword)) return code;
  }
  for (final (code, pattern) in _englishPatternsByCountry) {
    if (pattern.hasMatch(text)) return code;
  }
  final sanitizedForUpperCodes = text.replaceAll(_byteSizeUnitPattern, ' ');
  for (final (code, pattern) in _upperCodePatternsByCountry) {
    if (pattern.hasMatch(sanitizedForUpperCodes)) return code;
  }
  return null;
}

String nodeCountryEmoji(String code) {
  if (code == kUnknownCountryCode) return '🌐';
  final normalized = normalizeIsoCountryCode(code);
  if (normalized == null) return '🌐';
  return countryCodeToEmoji(normalized);
}

String nodeCountryName(
  String code, {
  Locale? locale,
  String? languageCode,
  String? fallbackOther,
}) {
  final effectiveLanguageCode = languageCode ?? locale?.languageCode ?? '';
  if (code == kUnknownCountryCode) {
    if (fallbackOther != null && fallbackOther.isNotEmpty) {
      return fallbackOther;
    }
    return effectiveLanguageCode.toLowerCase().startsWith('zh')
        ? '其他'
        : 'Other';
  }
  final normalized = normalizeIsoCountryCode(code);
  if (normalized == null) {
    return fallbackOther ?? 'Other';
  }
  final entry = _countryNames[normalized];
  if (entry == null) return normalized;
  final isZh = effectiveLanguageCode.toLowerCase().startsWith('zh');
  return isZh ? entry.zh : entry.en;
}

String formatNodeCountryBadge(
  String code, {
  Locale? locale,
  String? languageCode,
  String? fallbackOther,
}) =>
    '${nodeCountryEmoji(code)} ${nodeCountryName(code, locale: locale, languageCode: languageCode, fallbackOther: fallbackOther)}';

String formatNodeCountryChipLabel(
  String code,
  int count, {
  Locale? locale,
  String? languageCode,
  String? fallbackOther,
}) =>
    '${formatNodeCountryBadge(code, locale: locale, languageCode: languageCode, fallbackOther: fallbackOther)} ($count)';

List<String> sortCountryCodes(
  Iterable<String> codes,
  Map<String, int> counts,
) {
  final list = codes.toSet().toList()
    ..sort((a, b) {
      if (a == b) return 0;
      if (a == kUnknownCountryCode) return 1;
      if (b == kUnknownCountryCode) return -1;
      final countCompare = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      if (countCompare != 0) return countCompare;
      final rankA = _preferredCountryRank[a] ?? 999;
      final rankB = _preferredCountryRank[b] ?? 999;
      if (rankA != rankB) return rankA.compareTo(rankB);
      return a.compareTo(b);
    });
  return list;
}

String _normalizeServerHost(String rawServer) {
  var host = rawServer.trim().toLowerCase();
  if (host.startsWith('[') && host.endsWith(']') && host.length > 2) {
    host = host.substring(1, host.length - 1);
  }
  return host;
}

bool _isPublicRoutableIpv4Bytes(List<int> bytes) {
  if (bytes.length != 4) return false;
  final b0 = bytes[0];
  final b1 = bytes[1];
  final b2 = bytes[2];
  // 0.0.0.0/8 ("this" network)
  if (b0 == 0) return false;
  // 10.0.0.0/8 (RFC 1918 private)
  if (b0 == 10) return false;
  // 100.64.0.0/10 (RFC 6598 Carrier-Grade NAT / Tailscale)
  if (b0 == 100 && (b1 & 0xC0) == 64) return false;
  // 127.0.0.0/8 (loopback)
  if (b0 == 127) return false;
  // 169.254.0.0/16 (link-local)
  if (b0 == 169 && b1 == 254) return false;
  // 172.16.0.0/12 (RFC 1918 private)
  if (b0 == 172 && (b1 & 0xF0) == 16) return false;
  // 192.0.0.0/24 (IETF protocol assignments) & 192.0.2.0/24 (TEST-NET-1)
  if (b0 == 192 && b1 == 0 && (b2 == 0 || b2 == 2)) return false;
  // 192.168.0.0/16 (RFC 1918 private)
  if (b0 == 192 && b1 == 168) return false;
  // 198.18.0.0/15 (RFC 2544 benchmark & Clash/Mihomo default Fake-IP pool)
  if (b0 == 198 && (b1 == 18 || b1 == 19)) return false;
  // 198.51.100.0/24 (TEST-NET-2)
  if (b0 == 198 && b1 == 51 && b2 == 100) return false;
  // 203.0.113.0/24 (TEST-NET-3)
  if (b0 == 203 && b1 == 0 && b2 == 113) return false;
  // 224.0.0.0/4 (multicast) & 240.0.0.0/4 (reserved/broadcast)
  if (b0 >= 224) return false;
  return true;
}

/// Returns true only for globally routable unicast IPs, rejecting private,
/// loopback, link-local, CGNAT, documentation, multicast, and Clash/Mihomo
/// TUN Fake-IP ranges (`198.18.0.0/15`, `fc00::/7`).
bool isPublicRoutableIp(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return _isPublicRoutableIpv4Bytes(bytes);
  }
  if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
    // Unspecified ::
    if (bytes.every((b) => b == 0)) return false;
    // IPv4-mapped IPv6 ::ffff:0:0/96
    final isV4Mapped = bytes.take(10).every((b) => b == 0) &&
        bytes[10] == 0xFF &&
        bytes[11] == 0xFF;
    if (isV4Mapped) {
      return _isPublicRoutableIpv4Bytes(bytes.sublist(12, 16));
    }
    final b0 = bytes[0];
    final b1 = bytes[1];
    // Unique Local Address fc00::/7 (includes Mihomo IPv6 Fake-IP fc00::/18)
    if ((b0 & 0xFE) == 0xFC) return false;
    // Link-local fe80::/10
    if (b0 == 0xFE && (b1 & 0xC0) == 0x80) return false;
    // Multicast ff00::/8
    if (b0 == 0xFF) return false;
    // Documentation 2001:db8::/32
    if (b0 == 0x20 && b1 == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8) {
      return false;
    }
    return true;
  }
  return false;
}

Future<String?> defaultResolveServerCountry(String rawServer) async {
  final server = _normalizeServerHost(rawServer);
  if (server.isEmpty ||
      server == 'localhost' ||
      server.endsWith('.invalid') ||
      server.endsWith('.example') ||
      server.endsWith('.local') ||
      server.endsWith('.lan') ||
      server.endsWith('.test')) {
    return null;
  }
  if (ClashCore.existingInterface == null) return null;
  String? ip;
  final parsedIp = InternetAddress.tryParse(server);
  if (parsedIp != null) {
    if (!isPublicRoutableIp(parsedIp)) return null;
    ip = parsedIp.address;
  } else {
    try {
      final addresses = await InternetAddress.lookup(server)
          .timeout(const Duration(seconds: 2));
      final routable = addresses.where(isPublicRoutableIp).toList();
      final preferred = routable
              .where((a) => a.type == InternetAddressType.IPv4)
              .firstOrNull ??
          routable.firstOrNull;
      ip = preferred?.address;
    } catch (_) {
      return null;
    }
  }
  if (ip == null || ip.isEmpty) return null;
  try {
    final info = await clashCore
        .getCountryCode(ip)
        .timeout(const Duration(milliseconds: 1500));
    return normalizeIsoCountryCode(info?.countryCode);
  } catch (_) {
    return null;
  }
}

typedef DetectionCheckMetadata = ({
  int routingEpoch,
  int completedGeneration,
  int? completedRoutingEpoch,
});

typedef ConnectionOutboundTarget = ({
  String profileId,
  String proxyName,
  String? endpointKey,
  bool isDirectOrReject,
});

typedef ExitCalibrationEntry = ({
  String countryCode,
  String? endpointKey,
  String? server,
  String? configFingerprint,
});

Object? _canonicalizeProxyValue(Object? value, {bool isRoot = false}) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Map) {
    final keys = <String>[];
    final byStringKey = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (isRoot && key == 'name') continue;
      keys.add(key);
      byStringKey[key] = entry.value;
    }
    keys.sort();
    final sorted = <String, Object?>{};
    for (final key in keys) {
      final rawVal = byStringKey[key];
      if (isRoot && (key == 'type' || key == 'server') && rawVal is String) {
        sorted[key] = rawVal.trim().toLowerCase();
      } else if (isRoot && key == 'port') {
        final parsedPort = rawVal is int
            ? rawVal
            : rawVal is String
                ? int.tryParse(rawVal)
                : null;
        sorted[key] = parsedPort ?? _canonicalizeProxyValue(rawVal);
      } else {
        sorted[key] = _canonicalizeProxyValue(rawVal);
      }
    }
    return sorted;
  }
  if (value is Iterable) {
    return value.map(_canonicalizeProxyValue).toList();
  }
  return value.toString();
}

String _computeProxyConfigFingerprint(Map<Object?, Object?> proxy) {
  final canonical = _canonicalizeProxyValue(proxy, isRoot: true);
  return sha256
      .convert(utf8.encode('v1|cfg|${jsonEncode(canonical)}'))
      .toString()
      .substring(0, 32);
}

/// Resolves and caches proxy node countries using the aligned 3-tier pipeline:
/// 1. Live exit IP country from NetworkDetection (`detectionState` / `checkIp`)
///    strictly bound to proven outbound node ownership, central routing state,
///    proxy-running eligibility, request generation, and full proxy identity.
/// 2. Node server IP / domain resolution via Core `getCountryCode` (`geoip.metadb`)
/// 3. Node name and subscription profile name keyword/flag inference (`OTHER` fallback)
///
/// Server hostnames and credentials remain private and are never added to
/// `CatalogNode` or `ProfileCatalog` debug/JSON representations.
class NodeCountryResolver extends ChangeNotifier {
  NodeCountryResolver({
    ResolveServerCountryCallback? resolveServerCountry,
    this.detectionListenable,
    this.readDetectionMeta,
    this.isDetectionProxyEligible,
    this.resolveConnectionTarget,
    this.maxConcurrency = 4,
    DateTime Function()? clock,
  })  : _resolveServerCountry =
            resolveServerCountry ?? defaultResolveServerCountry,
        _clock = clock ?? DateTime.now {
    final initialMeta = readDetectionMeta?.call();
    if (initialMeta != null) {
      _lastSeenGeneration = initialMeta.completedGeneration;
    }
    final initialDetection = detectionListenable?.value;
    if (initialDetection?.ipInfo != null &&
        !(isDetectionProxyEligible?.call() ?? true)) {
      _directIneligibleIpInfo = initialDetection!.ipInfo;
    }
    detectionListenable?.addListener(_onDetectionChanged);
  }

  static const Duration connectionAttributionGraceWindow = Duration(seconds: 5);

  final ResolveServerCountryCallback _resolveServerCountry;
  final ValueListenable<NetworkDetectionState>? detectionListenable;
  final DetectionCheckMetadata Function()? readDetectionMeta;
  final bool Function()? isDetectionProxyEligible;
  final ConnectionOutboundTarget? Function()? resolveConnectionTarget;
  final int maxConcurrency;
  final DateTime Function() _clock;

  final Map<String, String> _endpointServers = <String, String>{};
  final Map<String, String> _nameServers = <String, String>{};
  final Map<String, String> _nameEndpointKeys = <String, String>{};
  final Map<String, String> _nameConfigFingerprints = <String, String>{};
  final Map<String, String> _serverCountryCache = <String, String>{};
  final Set<String> _pendingServers = <String>{};
  final Queue<String> _lookupQueue = Queue<String>();
  int _activeLookups = 0;
  bool _disposed = false;

  final Map<String, ExitCalibrationEntry> _exitCountryByNodeKey =
      <String, ExitCalibrationEntry>{};
  final Map<String, String?> _exitCountryByProfileConfig =
      <String, String?>{};
  (String, String)? _activeTarget;
  String? _activeEndpointKey;
  bool _awaitingFreshDetection = false;
  String? _staleIpAtSwitch;
  int _lastSeenGeneration = 0;
  IpInfo? _directIneligibleIpInfo;

  int _syntheticAttributionToken = 0;
  int? _pendingConnectionAttributionToken;
  int? _pendingConnectionAttributionRoutingEpoch;
  IpInfo? _pendingConnectionAttributionIpInfo;
  DateTime? _pendingConnectionAttributionDeadline;

  @override
  void dispose() {
    _disposed = true;
    detectionListenable?.removeListener(_onDetectionChanged);
    _lookupQueue.clear();
    _clearPendingConnectionAttribution();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearPendingConnectionAttribution() {
    _pendingConnectionAttributionToken = null;
    _pendingConnectionAttributionRoutingEpoch = null;
    _pendingConnectionAttributionIpInfo = null;
    _pendingConnectionAttributionDeadline = null;
  }

  bool _isCurrentDetectionProxyEligible(IpInfo info) {
    if (identical(info, _directIneligibleIpInfo)) return false;
    final eligible = isDetectionProxyEligible?.call() ?? true;
    if (!eligible) {
      _directIneligibleIpInfo = info;
      return false;
    }
    return true;
  }

  void onProxyRunningChanged({required bool isRunning}) {
    _clearPendingConnectionAttribution();
    if (!isRunning) {
      _activeTarget = null;
      _activeEndpointKey = null;
      final currentIp = detectionListenable?.value.ipInfo;
      if (currentIp != null) {
        _awaitingFreshDetection = true;
        _staleIpAtSwitch = currentIp.ip;
      }
    } else {
      final currentIp = detectionListenable?.value.ipInfo;
      if (currentIp != null && identical(currentIp, _directIneligibleIpInfo)) {
        _awaitingFreshDetection = true;
        _staleIpAtSwitch = currentIp.ip;
      }
    }
  }

  void invalidateProfile(String profileId) {
    final prefix = '$profileId|';
    var changed = false;
    _nameServers.removeWhere((key, _) {
      if (key.startsWith(prefix)) {
        changed = true;
        return true;
      }
      return false;
    });
    _nameEndpointKeys.removeWhere((key, _) {
      if (key.startsWith(prefix)) {
        changed = true;
        return true;
      }
      return false;
    });
    _nameConfigFingerprints.removeWhere((key, _) {
      if (key.startsWith(prefix)) {
        changed = true;
        return true;
      }
      return false;
    });
    _exitCountryByNodeKey.removeWhere((key, _) {
      if (key.startsWith(prefix)) {
        changed = true;
        return true;
      }
      return false;
    });
    _exitCountryByProfileConfig.removeWhere((key, _) {
      if (key.startsWith(prefix)) {
        changed = true;
        return true;
      }
      return false;
    });
    if (_activeTarget?.$1 == profileId) {
      _activeTarget = null;
      _activeEndpointKey = null;
      _clearPendingConnectionAttribution();
    }
    if (changed) _notify();
  }

  void clearProfiles() {
    final hadEntries = _nameServers.isNotEmpty ||
        _nameEndpointKeys.isNotEmpty ||
        _nameConfigFingerprints.isNotEmpty ||
        _exitCountryByNodeKey.isNotEmpty ||
        _exitCountryByProfileConfig.isNotEmpty;
    _nameServers.clear();
    _nameEndpointKeys.clear();
    _nameConfigFingerprints.clear();
    _exitCountryByNodeKey.clear();
    _exitCountryByProfileConfig.clear();
    _activeTarget = null;
    _activeEndpointKey = null;
    _clearPendingConnectionAttribution();
    if (hadEntries) _notify();
  }

  void markSwitchingNode() {
    _clearPendingConnectionAttribution();
    _awaitingFreshDetection = true;
    _staleIpAtSwitch = detectionListenable?.value.ipInfo?.ip;
  }

  /// Records a manual proxy selection initiated from any UI entry point
  /// (including classic `ProxyCard` when `NodeOverviewView` is unmounted),
  /// immediately revoking the previous outbound target so new exit detections
  /// cannot overwrite the previous node.
  void notifyManualProxySelection({
    required String? profileId,
    required String proxyName,
    String? endpointKey,
    bool unambiguous = false,
  }) {
    markSwitchingNode();
    if (!unambiguous ||
        profileId == null ||
        profileId.isEmpty ||
        proxyName.isEmpty ||
        proxyName == 'DIRECT' ||
        proxyName == 'REJECT') {
      _activeTarget = null;
      _activeEndpointKey = null;
      return;
    }
    _activeTarget = (profileId, proxyName);
    _activeEndpointKey = endpointKey ?? _nameEndpointKeys['$profileId|$proxyName'];
  }

  void recordExitCountry({
    required String profileId,
    required String proxyName,
    String? endpointKey,
    required String? countryCode,
    bool notify = true,
  }) {
    final normalized = normalizeIsoCountryCode(countryCode);
    if (normalized == null) return;
    final nodeKey = '$profileId|$proxyName';
    final effectiveEndpointKey =
        (endpointKey != null && endpointKey.isNotEmpty)
            ? endpointKey
            : _nameEndpointKeys[nodeKey];
    final currentServer = _nameServers[nodeKey];
    final currentFingerprint = _nameConfigFingerprints[nodeKey];
    final nextEntry = (
      countryCode: normalized,
      endpointKey: effectiveEndpointKey,
      server: currentServer,
      configFingerprint: currentFingerprint,
    );
    var changed = false;
    if (_exitCountryByNodeKey[nodeKey] != nextEntry) {
      _exitCountryByNodeKey[nodeKey] = nextEntry;
      changed = true;
    }
    if (currentFingerprint != null) {
      final configKey = '$profileId|$currentFingerprint';
      if (_exitCountryByProfileConfig.containsKey(configKey)) {
        final existingConfigCountry = _exitCountryByProfileConfig[configKey];
        if (existingConfigCountry != normalized) {
          // Multiple identical-config nodes produced different exit countries;
          // retain per-node entries, disable cross-name fallback for this config.
          if (existingConfigCountry != null) {
            _exitCountryByProfileConfig[configKey] = null;
            changed = true;
          }
        }
      } else {
        _exitCountryByProfileConfig[configKey] = normalized;
        changed = true;
      }
    }
    if (changed && notify) _notify();
  }

  void syncActiveNode({
    required String? profileId,
    String? proxyName,
    String? nodeName,
    String? endpointKey,
    bool isSwitching = false,
    bool isLiveActive = true,
    bool notify = true,
  }) {
    final effectiveNodeName = nodeName ?? proxyName;
    if (isSwitching ||
        !isLiveActive ||
        profileId == null ||
        profileId.isEmpty ||
        effectiveNodeName == null ||
        effectiveNodeName.isEmpty ||
        effectiveNodeName == 'DIRECT' ||
        effectiveNodeName == 'REJECT') {
      if (isSwitching || _activeTarget != null) {
        _clearPendingConnectionAttribution();
        final detection = detectionListenable?.value;
        if (detection != null &&
            !detection.isLoading &&
            !detection.isTesting &&
            detection.ipInfo != null) {
          _awaitingFreshDetection = true;
          _staleIpAtSwitch = detection.ipInfo!.ip;
        }
      }
      _activeTarget = null;
      _activeEndpointKey = null;
      return;
    }
    final nextTarget = (profileId, effectiveNodeName);
    final previousTarget = _activeTarget;
    final resolvedEndpoint =
        (endpointKey != null && endpointKey.isNotEmpty)
            ? endpointKey
            : _nameEndpointKeys['$profileId|$effectiveNodeName'];
    _activeTarget = nextTarget;
    _activeEndpointKey = resolvedEndpoint;
    final detection = detectionListenable?.value;
    if (previousTarget != null && previousTarget != nextTarget) {
      _clearPendingConnectionAttribution();
      if (detection != null &&
          !detection.isLoading &&
          !detection.isTesting &&
          detection.ipInfo != null) {
        _awaitingFreshDetection = true;
        _staleIpAtSwitch = detection.ipInfo!.ip;
      }
      return;
    }
    if (!_awaitingFreshDetection &&
        detection != null &&
        !detection.isLoading &&
        !detection.isTesting &&
        detection.ipInfo != null &&
        _isDetectionGenerationValidForCurrentRoute(allowPreexisting: true)) {
      _applyDetectionInfo(
        detection.ipInfo!,
        notify: notify,
        allowDeferredConnectionAttribution: false,
      );
    }
  }

  /// Re-evaluates exit attribution only when an unattributed proxy exit-IP
  /// check is still within its post-completion grace window waiting for Core
  /// connection telemetry. Never rebinds an already-attributed or old check.
  void onConnectionsUpdated({bool notify = true}) {
    final pendingToken = _pendingConnectionAttributionToken;
    final pendingIpInfo = _pendingConnectionAttributionIpInfo;
    final deadline = _pendingConnectionAttributionDeadline;
    if (pendingToken == null || pendingIpInfo == null || deadline == null) {
      return;
    }
    if (_awaitingFreshDetection || _clock().isAfter(deadline)) {
      _clearPendingConnectionAttribution();
      return;
    }
    final detection = detectionListenable?.value;
    if (detection == null ||
        detection.isLoading ||
        detection.isTesting ||
        !identical(detection.ipInfo, pendingIpInfo) ||
        !_isCurrentDetectionProxyEligible(pendingIpInfo)) {
      _clearPendingConnectionAttribution();
      return;
    }
    if (!_isDetectionGenerationValidForCurrentRoute(allowPreexisting: true)) {
      _clearPendingConnectionAttribution();
      return;
    }
    final meta = readDetectionMeta?.call();
    if (meta != null) {
      if (_pendingConnectionAttributionRoutingEpoch != null &&
          meta.routingEpoch != _pendingConnectionAttributionRoutingEpoch) {
        _clearPendingConnectionAttribution();
        return;
      }
      if (pendingToken > 0 && meta.completedGeneration != pendingToken) {
        _clearPendingConnectionAttribution();
        return;
      }
    }
    final observed = resolveConnectionTarget?.call();
    if (observed == null) return;
    _clearPendingConnectionAttribution();
    if (observed.isDirectOrReject) return;
    recordExitCountry(
      profileId: observed.profileId,
      proxyName: observed.proxyName,
      endpointKey: observed.endpointKey,
      countryCode: pendingIpInfo.countryCode,
      notify: notify,
    );
  }

  bool _isDetectionGenerationValidForCurrentRoute({
    required bool allowPreexisting,
  }) {
    final meta = readDetectionMeta?.call();
    if (meta == null) return true;
    if (meta.completedGeneration == 0) {
      return allowPreexisting;
    }
    return meta.completedRoutingEpoch != null &&
        meta.completedRoutingEpoch == meta.routingEpoch;
  }

  void _onDetectionChanged() {
    final detection = detectionListenable?.value;
    if (detection == null) return;
    if (detection.isLoading || detection.isTesting || detection.ipInfo == null) {
      _awaitingFreshDetection = false;
      _staleIpAtSwitch = null;
      _clearPendingConnectionAttribution();
      return;
    }
    if (!_isCurrentDetectionProxyEligible(detection.ipInfo!)) {
      _clearPendingConnectionAttribution();
      return;
    }
    final meta = readDetectionMeta?.call();
    if (meta != null && meta.completedGeneration != _lastSeenGeneration) {
      _lastSeenGeneration = meta.completedGeneration;
      if (meta.completedRoutingEpoch == null ||
          meta.completedRoutingEpoch != meta.routingEpoch) {
        // Check started under an earlier route before a switch; reject it.
        _awaitingFreshDetection = true;
        _staleIpAtSwitch = detection.ipInfo!.ip;
        _clearPendingConnectionAttribution();
        return;
      }
      _awaitingFreshDetection = false;
      _staleIpAtSwitch = null;
    } else if (_awaitingFreshDetection) {
      // Synthetic ValueNotifier write (e.g. widget/unit test without _checkIp):
      // accept if a distinct exit IP was published after the switch.
      if (detection.ipInfo!.ip == _staleIpAtSwitch) {
        return;
      }
      _awaitingFreshDetection = false;
      _staleIpAtSwitch = null;
    }
    _applyDetectionInfo(
      detection.ipInfo!,
      notify: true,
      allowDeferredConnectionAttribution: true,
    );
  }

  void _applyDetectionInfo(
    IpInfo info, {
    required bool notify,
    required bool allowDeferredConnectionAttribution,
  }) {
    if (!_isCurrentDetectionProxyEligible(info)) {
      _clearPendingConnectionAttribution();
      return;
    }
    final observed = resolveConnectionTarget?.call();
    if (observed != null) {
      _clearPendingConnectionAttribution();
      if (observed.isDirectOrReject) return;
      recordExitCountry(
        profileId: observed.profileId,
        proxyName: observed.proxyName,
        endpointKey: observed.endpointKey,
        countryCode: info.countryCode,
        notify: notify,
      );
      return;
    }
    final target = _activeTarget;
    if (target != null) {
      _clearPendingConnectionAttribution();
      recordExitCountry(
        profileId: target.$1,
        proxyName: target.$2,
        endpointKey: _activeEndpointKey,
        countryCode: info.countryCode,
        notify: notify,
      );
      return;
    }
    if (allowDeferredConnectionAttribution && resolveConnectionTarget != null) {
      final meta = readDetectionMeta?.call();
      final token = (meta != null && meta.completedGeneration > 0)
          ? meta.completedGeneration
          : --_syntheticAttributionToken;
      _pendingConnectionAttributionToken = token;
      _pendingConnectionAttributionRoutingEpoch = meta?.routingEpoch;
      _pendingConnectionAttributionIpInfo = info;
      _pendingConnectionAttributionDeadline =
          _clock().add(connectionAttributionGraceWindow);
    } else {
      _clearPendingConnectionAttribution();
    }
  }

  void registerFromRawConfig(String profileId, Map<String, dynamic> raw) {
    final rawProxies = raw['proxies'];
    if (rawProxies is! List) return;
    registerProxyMaps(profileId, rawProxies);
  }

  void registerProxyMaps(String profileId, Iterable<Object?> proxies) {
    final newServers = <String>{};
    var evictedStaleExit = false;
    for (final item in proxies) {
      if (item is! Map) continue;
      final name = item['name'];
      final type = item['type'];
      final server = item['server'];
      final rawPort = item['port'];
      final port = rawPort is int
          ? rawPort
          : rawPort is String
              ? int.tryParse(rawPort)
              : null;
      if (name is! String ||
          name.isEmpty ||
          type is! String ||
          type.isEmpty ||
          server is! String ||
          server.trim().isEmpty) {
        continue;
      }
      final normalizedServer = _normalizeServerHost(server);
      if (normalizedServer.isEmpty) continue;
      final nodeKey = '$profileId|$name';
      final previousServer = _nameServers[nodeKey];
      final previousEndpointKey = _nameEndpointKeys[nodeKey];
      final previousFingerprint = _nameConfigFingerprints[nodeKey];
      final configFingerprint = _computeProxyConfigFingerprint(item);
      _nameServers[nodeKey] = normalizedServer;
      _nameConfigFingerprints[nodeKey] = configFingerprint;
      String? endpointKey;
      if (port != null && port >= 1 && port <= 65535) {
        final endpoint = '$type|${server.toLowerCase()}|$port';
        endpointKey = sha256
            .convert(utf8.encode('v1|$endpoint'))
            .toString()
            .substring(0, 32);
        _endpointServers[endpointKey] = normalizedServer;
        _nameEndpointKeys[nodeKey] = endpointKey;
      } else {
        _nameEndpointKeys.remove(nodeKey);
      }
      final existingExit = _exitCountryByNodeKey[nodeKey];
      if (existingExit != null) {
        final endpointChanged = existingExit.endpointKey != endpointKey &&
            (existingExit.endpointKey != null || previousEndpointKey != null);
        final serverChanged = (existingExit.server != null &&
                existingExit.server != normalizedServer) ||
            (previousServer != null && previousServer != normalizedServer);
        final configChanged = (existingExit.configFingerprint != null &&
                existingExit.configFingerprint != configFingerprint) ||
            (previousFingerprint != null &&
                previousFingerprint != configFingerprint);
        if (endpointChanged || serverChanged || configChanged) {
          _exitCountryByNodeKey.remove(nodeKey);
          if (existingExit.configFingerprint != null) {
            _exitCountryByProfileConfig
                .remove('$profileId|${existingExit.configFingerprint}');
          }
          evictedStaleExit = true;
        }
      }
      if (!_serverCountryCache.containsKey(normalizedServer) &&
          !_pendingServers.contains(normalizedServer)) {
        newServers.add(normalizedServer);
      }
    }
    if (evictedStaleExit) {
      _notify();
    }
    for (final server in newServers) {
      _pendingServers.add(server);
      _lookupQueue.add(server);
    }
    _pumpLookups();
  }

  void _pumpLookups() {
    while (!_disposed &&
        _activeLookups < maxConcurrency &&
        _lookupQueue.isNotEmpty) {
      final server = _lookupQueue.removeFirst();
      _activeLookups++;
      unawaited(_lookupServer(server));
    }
  }

  Future<void> _lookupServer(String server) async {
    try {
      final code = normalizeIsoCountryCode(await _resolveServerCountry(server));
      if (_disposed) return;
      if (code != null) {
        final changed = _serverCountryCache[server] != code;
        _serverCountryCache[server] = code;
        if (changed) {
          _notify();
        }
      }
    } catch (_) {
      // Leave uncached so subsequent profile/runtime evaluations can retry.
    } finally {
      _pendingServers.remove(server);
      _activeLookups--;
      if (!_disposed) {
        _pumpLookups();
      }
    }
  }

  String resolveCountryCode({
    required String profileId,
    required String? profileLabel,
    required String nodeName,
    String? endpointKey,
    bool isLiveActive = false,
    bool inUse = false,
  }) {
    final nodeKey = '$profileId|$nodeName';
    final registeredEndpointKey = _nameEndpointKeys[nodeKey];
    final effectiveEndpointKey =
        (endpointKey != null && endpointKey.isNotEmpty)
            ? endpointKey
            : registeredEndpointKey;
    final currentServer = _nameServers[nodeKey];
    final currentFingerprint = _nameConfigFingerprints[nodeKey];

    final exitByNode = _exitCountryByNodeKey[nodeKey];
    if (exitByNode != null) {
      final callerEndpointMatches = endpointKey == null ||
          endpointKey.isEmpty ||
          exitByNode.endpointKey == null ||
          exitByNode.endpointKey == endpointKey;
      final registeredEndpointMatches = registeredEndpointKey == null ||
          exitByNode.endpointKey == null ||
          exitByNode.endpointKey == registeredEndpointKey;
      final serverMatches = exitByNode.server == null ||
          currentServer == null ||
          exitByNode.server == currentServer;
      final fingerprintMatches = exitByNode.configFingerprint == null ||
          currentFingerprint == null ||
          exitByNode.configFingerprint == currentFingerprint;
      if (callerEndpointMatches &&
          registeredEndpointMatches &&
          serverMatches &&
          fingerprintMatches) {
        return exitByNode.countryCode;
      }
    }

    if (currentFingerprint != null) {
      final exitByConfig =
          _exitCountryByProfileConfig['$profileId|$currentFingerprint'];
      if (exitByConfig != null && exitByConfig.isNotEmpty) {
        return exitByConfig;
      }
    }

    final server = (effectiveEndpointKey != null &&
                effectiveEndpointKey.isNotEmpty
            ? _endpointServers[effectiveEndpointKey]
            : null) ??
        currentServer;
    final rawServerCountry = server == null ? null : _serverCountryCache[server];
    final serverCountry =
        rawServerCountry != null && rawServerCountry.isNotEmpty
            ? rawServerCountry
            : null;
    if (serverCountry != null && serverCountry != 'CN') {
      return serverCountry;
    }

    final nameCountry = inferCountryCodeFromText(nodeName);
    if (nameCountry != null) {
      return nameCountry;
    }

    final profileCountry = inferCountryCodeFromText(profileLabel);
    if (profileCountry != null && profileCountry != 'CN') {
      return profileCountry;
    }
    if (serverCountry != null) {
      return serverCountry;
    }
    if (profileCountry != null) {
      return profileCountry;
    }
    return kUnknownCountryCode;
  }
}
