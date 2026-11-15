// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a ru locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'ru';

  static String m0(node) => "Узел: ${node}";

  static String m1(count) => "Правил: ${count}";

  static String m2(count) => "Узлов: ${count}";

  static String m3(label) =>
      "Вы уверены, что хотите удалить выбранные ${label}?";

  static String m4(label) => "Вы уверены, что хотите удалить текущий ${label}?";

  static String m5(label) => "${label} не может быть пустым";

  static String m6(label) => "Текущий ${label} уже существует";

  static String m7(time, elapsed) => "Проверка ${time} · ${elapsed}";

  static String m8(mb) => "IPC ОК · ${mb} МБ";

  static String m9(exitPart) => "Через прокси подтверждено${exitPart}";

  static String m10(node) => "Узел ${node} не прошёл проверку связи";

  static String m11(node) =>
      "Проба задержки узла ${node} не прошла, но реальный трафик работает";

  static String m12(node) => "Повышенная задержка узла ${node}";

  static String m13(count) => "Загружено (групп: ${count})";

  static String m14(days) => "Осталось ${days} дн.";

  static String m15(percent) => "Использовано ${percent}% трафика";

  static String m16(flag) => " · Выход ${flag}";

  static String m17(delay) => "Прямой режим · ${delay} мс";

  static String m18(node, delay, exitPart) =>
      "Узел ${node} · ${delay} мс${exitPart}";

  static String m19(available, tested, total) =>
      "Узлы: дост. ${available} / пров. ${tested} / всего ${total}";

  static String m20(count) => "Профилей: ${count}";

  static String m21(text) => "Объявление: ${text}";

  static String m22(profile, node, delay) =>
      "Автоподключение к лучшему узлу: ${profile} · ${node} (${delay} мс)";

  static String m23(profile, node, delay) =>
      "Умный выбор включён: ${profile} (лучший: ${node} · ${delay} мс)";

  static String m24(node) =>
      "Выбран узел ${node} (все узлы не прошли проверку задержки; обновите подписку или смените узел)";

  static String m25(node) =>
      "Выбран узел ${node}, но срок подписки истёк. Продлите или замените подписку";

  static String m26(node) => "Выбран узел ${node}, но трафик подписки исчерпан";

  static String m27(hours) => "Автообновление ${hours} ч.";

  static String m28(minutes) => "Автообновление ${minutes} мин.";

  static String m29(count) => "Ошибка ${count}";

  static String m30(count) => "Быстр. ${count}";

  static String m31(count) => "Медл. ${count}";

  static String m32(count) => "Не пров. ${count}";

  static String m33(completed, failed, untested, profiles) =>
      "Завершено ${completed} · Ошибок ${failed} · Не проверено ${untested} · Профилей с проблемами ${profiles}";

  static String m34(name) => "Активный: ${name}";

  static String m35(date) => "Истекает: ${date}";

  static String m36(days) => "осталось ${days} дн.";

  static String m37(hours) => "осталось ${hours} ч.";

  static String m38(count) => "Истекло: ${count}";

  static String m39(count) => "Скоро истечёт: ${count}";

  static String m40(provider) => "Файл профиля · ${provider}";

  static String m41(median) => "Медиана: ${median}";

  static String m42(median, best) => "Медиана: ${median} · Лучший: ${best}";

  static String m43(available, tested, total) =>
      "Доступно ${available} / проверено ${tested} / всего ${total}";

  static String m44(time) => "Проверка при последней активации: ${time}";

  static String m45(time) => "Синхронизация: ${time}";

  static String m46(time) => "Последняя проверка: ${time}";

  static String m47(profile, node) =>
      "Закреплён фиксированный узел: ${profile} · ${node}";

  static String m48(delay) => "Медиана: ${delay}";

  static String m49(count) => "Ещё типов проблем: ${count}";

  static String m50(available, total) => "Доступно ${available} / ${total}";

  static String m51(date) => "До ${date}";

  static String m52(count) => "Профилей: ${count}";

  static String m53(completed, total) => "${completed} / ${total}";

  static String m54(provider) => "${provider}: узлы появятся после активации";

  static String m55(profile) => "Прокси вкл · Умный: ${profile} (автоподбор)";

  static String m56(profile, node) =>
      "Прокси вкл · Умный: ${profile} · ${node}";

  static String m57(profile, node) => "Прокси включён · ${profile} · ${node}";

  static String m58(traffic) => "Остаток трафика: ${traffic}";

  static String m59(profile, node) => "Переключено на ${profile} · ${node}";

  static String m60(profile) => "Включён умный выбор: ${profile}";

  static String m61(profile, node) =>
      "Включён умный выбор: ${profile} (${node})";

  static String m62(used, total) => "Использовано ${used} из ${total}";

  static String m63(used) => "Использовано: ${used}";

  static String m64(label) => "Сейчас ${label} нет";

  static String m65(label) => "${label} должно быть числом";

  static String m66(label) => "${label} должен быть числом от 1024 до 49151";

  static String m67(seconds) =>
      "Слишком много запросов. Повторите через ${seconds} с.";

  static String m68(plan) => "Открыт магазин для «${plan}»";

  static String m69(plan, quota, price) =>
      "Здравствуйте! Хочу приобрести код активации для тарифа «${plan} · ${quota} GiB (${price})».";

  static String m70(count) => "Осталось: ${count}";

  static String m71(code) => "Неизвестное правило (${code})";

  static String m72(price) => "~${price} / ГБ";

  static String m73(seconds) => "Повтор через ${seconds}с";

  static String m74(periods) => "Период оплаты: ${periods}";

  static String m75(count) => "Лимит устройств: ${count}";

  static String m76(speed) => "Скорость: до ${speed} Мбит/с";

  static String m77(count) => "Выбрано ${count} элементов";

  static String m78(days) => "Ваша подписка истекает через ${days} дн.";

  static String m79(name) => "${name} печатает...";

  static String m80(reason) => "TUN: ${reason}";

  static String m81(label) => "${label} должен быть URL";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("О программе"),
    "accessControl": MessageLookupByLibrary.simpleMessage("Контроль доступа"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Только выбранные приложения будут использовать VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "Управление доступом приложений к прокси",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Выбранные приложения не будут использовать VPN",
    ),
    "account": MessageLookupByLibrary.simpleMessage("Аккаунт"),
    "action": MessageLookupByLibrary.simpleMessage("Действие"),
    "action_mode": MessageLookupByLibrary.simpleMessage("Переключить режим"),
    "action_proxy": MessageLookupByLibrary.simpleMessage("Системный прокси"),
    "action_start": MessageLookupByLibrary.simpleMessage("Старт/Стоп"),
    "action_tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "action_view": MessageLookupByLibrary.simpleMessage("Показать/Скрыть"),
    "add": MessageLookupByLibrary.simpleMessage("Добавить"),
    "addFromPhoneSubtitle": MessageLookupByLibrary.simpleMessage(
      "Сканировать QR-код телефоном",
    ),
    "addFromPhoneTitle": MessageLookupByLibrary.simpleMessage(
      "Добавить с телефона",
    ),
    "addProfile": MessageLookupByLibrary.simpleMessage("Добавить профиль"),
    "addRule": MessageLookupByLibrary.simpleMessage("Добавить правило"),
    "addedOriginRules": MessageLookupByLibrary.simpleMessage(
      "Добавить к оригинальным правилам",
    ),
    "address": MessageLookupByLibrary.simpleMessage("Адрес"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("Адрес сервера WebDAV"),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите действительный адрес WebDAV",
    ),
    "adminAutoLaunch": MessageLookupByLibrary.simpleMessage(
      "Автозапуск от имени администратора",
    ),
    "adminAutoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Запускать с правами администратора при старте системы",
    ),
    "ago": MessageLookupByLibrary.simpleMessage(" назад"),
    "agree": MessageLookupByLibrary.simpleMessage("Согласен"),
    "allApps": MessageLookupByLibrary.simpleMessage("Все приложения"),
    "allowBypass": MessageLookupByLibrary.simpleMessage("Разрешить обход VPN"),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage(
      "Некоторые приложения смогут обходить VPN",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("Разрешить LAN"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешить доступ к прокси из локальной сети",
    ),
    "announcement": MessageLookupByLibrary.simpleMessage("Объявление"),
    "app": MessageLookupByLibrary.simpleMessage("Приложение"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage(
      "Контроль доступа приложений",
    ),
    "appBrandName": MessageLookupByLibrary.simpleMessage("FreedomNet"),
    "appBrandTagline": MessageLookupByLibrary.simpleMessage(
      "Интеллектуальный сетевой клиент нового поколения",
    ),
    "appDesc": MessageLookupByLibrary.simpleMessage(
      "Обработка настроек, связанных с приложением",
    ),
    "application": MessageLookupByLibrary.simpleMessage("Настройки приложения"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage(
      "Стандартные настройки приложения",
    ),
    "auto": MessageLookupByLibrary.simpleMessage("Авто"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage(
      "Автопроверка обновлений",
    ),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage(
      "Проверять обновления при запуске",
    ),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage(
      "Автозакрытие соединений",
    ),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически закрывать соединения при смене сервера",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("Автозапуск приложения"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Запускать вместе с системой",
    ),
    "autoRun": MessageLookupByLibrary.simpleMessage("Автозапуск прокси"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически запускать прокси при открытии приложения",
    ),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage(
      "Автоматическая настройка системного DNS",
    ),
    "autoStart": MessageLookupByLibrary.simpleMessage("Автозапуск"),
    "autoStartDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешить автозапуск в фоне, чтобы VPN переживал перезагрузки и обновления (MIUI/EMUI и др.)",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("Автообновление"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления (минуты)",
    ),
    "backup": MessageLookupByLibrary.simpleMessage("Резервное копирование"),
    "backupAndRecovery": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование и восстановление",
    ),
    "backupAndRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "Синхронизация данных через WebDAV или файл",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование успешно",
    ),
    "basicConfig": MessageLookupByLibrary.simpleMessage("Конфигурация ядра"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Переопределение конфигурации ядра",
    ),
    "batteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Оптимизация батареи",
    ),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "Исключить приложение, чтобы система не убивала VPN в фоне",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("Привязать"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage(
      "Режим черного списка",
    ),
    "blacklistModeDesc": MessageLookupByLibrary.simpleMessage(
      "Выбранные приложения идут напрямую; остальные — через VPN.",
    ),
    "brandDialogSubtitle": MessageLookupByLibrary.simpleMessage(
      "О бренде и ключевых возможностях",
    ),
    "brandPillarModesBody": MessageLookupByLibrary.simpleMessage(
      "«Простой режим» обеспечивает мгновенный запуск TUN и системного прокси, а «Экспертный режим» открывает детальное управление маршрутами и диагностикой.",
    ),
    "brandPillarModesTitle": MessageLookupByLibrary.simpleMessage(
      "Два режима · От простоты к контролю",
    ),
    "brandPillarServiceBody": MessageLookupByLibrary.simpleMessage(
      "Наглядный учёт трафика и срока действия подписки, быстрая проверка и активация подарочных карт, синхронизация профилей и поддержка.",
    ),
    "brandPillarServiceTitle": MessageLookupByLibrary.simpleMessage(
      "Прозрачный трафик · Мгновенная активация",
    ),
    "brandPillarSmartBody": MessageLookupByLibrary.simpleMessage(
      "Параллельная проверка узлов, наглядная индикация задержки, подключение к самому быстрому узлу в один клик и фильтр по регионам.",
    ),
    "brandPillarSmartTitle": MessageLookupByLibrary.simpleMessage(
      "Умный выбор · Точный контроль задержки",
    ),
    "brandShowcaseBadge": MessageLookupByLibrary.simpleMessage(
      "FREEDOMNET · ФЛАГМАНСКИЙ КЛИЕНТ",
    ),
    "brandShowcaseHeroBody": MessageLookupByLibrary.simpleMessage(
      "FreedomNet обеспечивает стабильное и быстрое интеллектуальное ускорение сети для удалённой работы, ИИ-сервисов и потокового видео в один клик.",
    ),
    "brandShowcaseHeroTitle": MessageLookupByLibrary.simpleMessage(
      "Связь без границ и мгновенный отклик",
    ),
    "buyExtraTraffic": MessageLookupByLibrary.simpleMessage("Докупить трафик"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("Обход домена"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Действует только при включенном системном прокси",
    ),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "Кэш повреждён. Очистить его?",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Отмена"),
    "cancelFilterSystemApp": MessageLookupByLibrary.simpleMessage(
      "Отменить фильтрацию системных приложений",
    ),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage(
      "Отменить выбор всего",
    ),
    "change": MessageLookupByLibrary.simpleMessage("Сменить"),
    "changeServer": MessageLookupByLibrary.simpleMessage("Изменить сервер"),
    "checkError": MessageLookupByLibrary.simpleMessage("Ошибка проверки"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("Проверить обновления"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage(
      "Текущее приложение уже является последней версией",
    ),
    "checking": MessageLookupByLibrary.simpleMessage("Проверка..."),
    "clearData": MessageLookupByLibrary.simpleMessage("Очистить данные"),
    "clearDataTip": MessageLookupByLibrary.simpleMessage(
      "Это удалит все данные приложения и перезапустит его. Вы уверены?",
    ),
    "clipboardExport": MessageLookupByLibrary.simpleMessage(
      "Экспорт в буфер обмена",
    ),
    "clipboardImport": MessageLookupByLibrary.simpleMessage(
      "Импорт из буфера обмена",
    ),
    "collapseAll": MessageLookupByLibrary.simpleMessage("Свернуть всё"),
    "color": MessageLookupByLibrary.simpleMessage("Цвет"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("Цветовые схемы"),
    "columns": MessageLookupByLibrary.simpleMessage("Столбцы"),
    "compatible": MessageLookupByLibrary.simpleMessage("Режим совместимости"),
    "compatibleDesc": MessageLookupByLibrary.simpleMessage(
      "Включение приведет к потере части функциональности, но обеспечит полную совместимость с Clash",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("Подтвердить"),
    "connections": MessageLookupByLibrary.simpleMessage("Подключения"),
    "connectionsActive": MessageLookupByLibrary.simpleMessage("Активные"),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Просмотр текущих данных о соединениях",
    ),
    "connectionsLog": MessageLookupByLibrary.simpleMessage("Журнал"),
    "connectivity": MessageLookupByLibrary.simpleMessage("Связь："),
    "contactMe": MessageLookupByLibrary.simpleMessage("Свяжитесь со мной"),
    "content": MessageLookupByLibrary.simpleMessage("Содержание"),
    "contentScheme": MessageLookupByLibrary.simpleMessage("Контентная тема"),
    "copy": MessageLookupByLibrary.simpleMessage("Копировать"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage(
      "Копирование переменных окружения",
    ),
    "copyLink": MessageLookupByLibrary.simpleMessage("Копировать ссылку"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("Копирование успешно"),
    "core": MessageLookupByLibrary.simpleMessage("Ядро"),
    "coreInfo": MessageLookupByLibrary.simpleMessage("Информация о ядре"),
    "coreStatusRestarting": MessageLookupByLibrary.simpleMessage("Перезапуск"),
    "coreStatusRunning": MessageLookupByLibrary.simpleMessage("Запущено"),
    "coreStatusStopped": MessageLookupByLibrary.simpleMessage("Остановлено"),
    "coreUpdate": MessageLookupByLibrary.simpleMessage("Обновление ядра"),
    "coreUpdateAvailable": MessageLookupByLibrary.simpleMessage(
      "Доступно обновление ядра",
    ),
    "coreUpdateChecking": MessageLookupByLibrary.simpleMessage(
      "Проверка обновлений...",
    ),
    "coreUpdateDownloading": MessageLookupByLibrary.simpleMessage(
      "Загрузка...",
    ),
    "coreUpdateFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось обновить",
    ),
    "coreUpdateSuccess": MessageLookupByLibrary.simpleMessage("Ядро обновлено"),
    "country": MessageLookupByLibrary.simpleMessage("Страна"),
    "crashTest": MessageLookupByLibrary.simpleMessage("Тест на сбои"),
    "crashlytics": MessageLookupByLibrary.simpleMessage("Отчёты о сбоях"),
    "crashlyticsDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически отправлять журналы сбоев через Firebase Crashlytics; конфиденциальные данные не передаются",
    ),
    "create": MessageLookupByLibrary.simpleMessage("Создать"),
    "cut": MessageLookupByLibrary.simpleMessage("Вырезать"),
    "dark": MessageLookupByLibrary.simpleMessage("Темный"),
    "dashboard": MessageLookupByLibrary.simpleMessage("Главная"),
    "dashboardAnnouncementBadge": MessageLookupByLibrary.simpleMessage(
      "Объявление",
    ),
    "dashboardClickUpdateSubscription": MessageLookupByLibrary.simpleMessage(
      "Нажмите для обновления",
    ),
    "dashboardContactSupport": MessageLookupByLibrary.simpleMessage(
      "Поддержка",
    ),
    "dashboardCurrentNodeLabel": m0,
    "dashboardHwidNotSupported": MessageLookupByLibrary.simpleMessage(
      "Привязка HWID не поддерживается сервером",
    ),
    "dashboardNotSyncedYet": MessageLookupByLibrary.simpleMessage(
      "Синхронизация: нет",
    ),
    "dashboardRuleOverrideCount": m1,
    "dashboardTotalNodesCount": m2,
    "day": MessageLookupByLibrary.simpleMessage("день"),
    "days": MessageLookupByLibrary.simpleMessage("дней"),
    "daysGenitive": MessageLookupByLibrary.simpleMessage("дня"),
    "defaultNameserver": MessageLookupByLibrary.simpleMessage(
      "Сервер имен по умолчанию",
    ),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Для разрешения DNS-сервера",
    ),
    "defaultProxyAutoTarget": MessageLookupByLibrary.simpleMessage(
      "Прокси по умолчанию (авто)",
    ),
    "defaultSort": MessageLookupByLibrary.simpleMessage(
      "Сортировка по умолчанию",
    ),
    "defaultText": MessageLookupByLibrary.simpleMessage("По умолчанию"),
    "delay": MessageLookupByLibrary.simpleMessage("Задержка"),
    "delaySort": MessageLookupByLibrary.simpleMessage("Сортировка по задержке"),
    "delete": MessageLookupByLibrary.simpleMessage("Удалить"),
    "deleteMultipTip": m3,
    "deleteTip": m4,
    "desc": MessageLookupByLibrary.simpleMessage(
      "Многоплатформенный прокси-клиент на основе ClashMeta, простой и удобный в использовании, с открытым исходным кодом и без рекламы.",
    ),
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "Использует сторонний API. Только для справки",
    ),
    "determiningIp": MessageLookupByLibrary.simpleMessage("Определяю IP.."),
    "developerMode": MessageLookupByLibrary.simpleMessage("Режим разработчика"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "Режим разработчика активирован.",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("Прямой"),
    "disclaimer": MessageLookupByLibrary.simpleMessage(
      "Отказ от ответственности",
    ),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "Данное программное обеспечение предназначено исключительно для некоммерческого использования в образовательных и исследовательских целях. Коммерческое использование запрещено. Разработчики не несут ответственности за любую коммерческую деятельность с использованием данного ПО.",
    ),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "Обнаружена новая версия",
    ),
    "discovery": MessageLookupByLibrary.simpleMessage(
      "Обнаружена новая версия",
    ),
    "dnsDesc": MessageLookupByLibrary.simpleMessage(
      "Обновление настроек, связанных с DNS",
    ),
    "dnsMode": MessageLookupByLibrary.simpleMessage("Режим DNS"),
    "doYouWantToPass": MessageLookupByLibrary.simpleMessage(
      "Добавляем профиль по адресу",
    ),
    "domain": MessageLookupByLibrary.simpleMessage("Домен"),
    "download": MessageLookupByLibrary.simpleMessage("Загрузка"),
    "downloadingZashboard": MessageLookupByLibrary.simpleMessage(
      "Качаю Zashboard…",
    ),
    "edit": MessageLookupByLibrary.simpleMessage("Редактировать"),
    "emptyTip": m5,
    "en": MessageLookupByLibrary.simpleMessage("Английский"),
    "enableGlobalOverride": MessageLookupByLibrary.simpleMessage(
      "Включить глобальные правила",
    ),
    "enableOverride": MessageLookupByLibrary.simpleMessage(
      "Включить переопределение",
    ),
    "entries": MessageLookupByLibrary.simpleMessage(" записей"),
    "errorTitle": MessageLookupByLibrary.simpleMessage("Ошибка"),
    "exclude": MessageLookupByLibrary.simpleMessage("Скрыть из списка задач"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "Скрывать приложение из списка последних задач в фоновом режиме",
    ),
    "excludeFromVpn": MessageLookupByLibrary.simpleMessage("Исключить из VPN"),
    "existsTip": m6,
    "exit": MessageLookupByLibrary.simpleMessage("Выход"),
    "expand": MessageLookupByLibrary.simpleMessage("Стандартный"),
    "expandAll": MessageLookupByLibrary.simpleMessage("Развернуть всё"),
    "expertMode": MessageLookupByLibrary.simpleMessage("Режим эксперта"),
    "expirationTime": MessageLookupByLibrary.simpleMessage("Время истечения"),
    "expiresOn": MessageLookupByLibrary.simpleMessage("Истекает"),
    "exportFile": MessageLookupByLibrary.simpleMessage("Экспорт файла"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("Экспорт логов"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("Экспорт успешен"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("Экспрессивные"),
    "externalController": MessageLookupByLibrary.simpleMessage(
      "Внешний контроллер",
    ),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "Включить управление ядром через API на порту 9090",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("Внешняя ссылка"),
    "externalResources": MessageLookupByLibrary.simpleMessage(
      "Внешние ресурсы",
    ),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Фильтр Fakeip"),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Диапазон Fakeip"),
    "fallback": MessageLookupByLibrary.simpleMessage("Резервный"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage(
      "Обычно используется оффшорный DNS",
    ),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage(
      "Фильтр резервного DNS",
    ),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("Точная передача"),
    "file": MessageLookupByLibrary.simpleMessage("Файл"),
    "fileDesc": MessageLookupByLibrary.simpleMessage(
      "Загрузить профиль из файла",
    ),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "Файл был изменён. Сохранить изменения?",
    ),
    "fileTooLarge": MessageLookupByLibrary.simpleMessage(
      "Файл слишком большой",
    ),
    "filterSystemApp": MessageLookupByLibrary.simpleMessage(
      "Фильтровать системные приложения",
    ),
    "findProcessMode": MessageLookupByLibrary.simpleMessage(
      "Режим поиска процесса",
    ),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage(
      "Может незначительно снизить производительность",
    ),
    "fontFamily": MessageLookupByLibrary.simpleMessage("Семейство шрифтов"),
    "fourColumns": MessageLookupByLibrary.simpleMessage("Четыре столбца"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("Фруктовый микс"),
    "general": MessageLookupByLibrary.simpleMessage("Общие"),
    "generalDesc": MessageLookupByLibrary.simpleMessage(
      "Изменение общих настроек",
    ),
    "geoData": MessageLookupByLibrary.simpleMessage("Геоданные"),
    "geodataLoader": MessageLookupByLibrary.simpleMessage(
      "Экономия памяти для геоданных",
    ),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage(
      "Использовать режим загрузки геоданных с низким потреблением памяти",
    ),
    "geoipCode": MessageLookupByLibrary.simpleMessage("Код Geoip"),
    "getOriginRules": MessageLookupByLibrary.simpleMessage(
      "Получить оригинальные правила",
    ),
    "global": MessageLookupByLibrary.simpleMessage("Глобальный"),
    "globalOverride": MessageLookupByLibrary.simpleMessage(
      "Глобальные правила",
    ),
    "globalOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "Действует для всех профилей без повторной настройки",
    ),
    "go": MessageLookupByLibrary.simpleMessage("Перейти"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Перейти к загрузке"),
    "goToPurchasePrompt": MessageLookupByLibrary.simpleMessage(
      "Нет подписки? Купить или активировать код",
    ),
    "goToSelected": MessageLookupByLibrary.simpleMessage("К выбранному"),
    "gratitude": MessageLookupByLibrary.simpleMessage("Благодарность"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Сохранить изменения в кэше?",
    ),
    "healthActionOpenDns": MessageLookupByLibrary.simpleMessage(
      "Настройки DNS",
    ),
    "healthActionOpenNetwork": MessageLookupByLibrary.simpleMessage(
      "Настройки сети",
    ),
    "healthActionOpenProfiles": MessageLookupByLibrary.simpleMessage(
      "К профилям",
    ),
    "healthActionOpenProxies": MessageLookupByLibrary.simpleMessage(
      "Сменить узел",
    ),
    "healthActionOpenPurchase": MessageLookupByLibrary.simpleMessage(
      "Продлить",
    ),
    "healthActionOpenTun": MessageLookupByLibrary.simpleMessage(
      "Настройки TUN",
    ),
    "healthActionReapplySystemProxy": MessageLookupByLibrary.simpleMessage(
      "Восстановить прокси",
    ),
    "healthActionRestartCore": MessageLookupByLibrary.simpleMessage(
      "Перезапуск ядра",
    ),
    "healthActionStartProxy": MessageLookupByLibrary.simpleMessage("Запустить"),
    "healthCheckCancel": MessageLookupByLibrary.simpleMessage("Отмена"),
    "healthCheckChecking": MessageLookupByLibrary.simpleMessage("Проверка…"),
    "healthCheckCopied": MessageLookupByLibrary.simpleMessage(
      "Сводка скопирована в буфер обмена",
    ),
    "healthCheckCopySummary": MessageLookupByLibrary.simpleMessage(
      "Копировать",
    ),
    "healthCheckDiagnoseAction": MessageLookupByLibrary.simpleMessage(
      "Диагностика",
    ),
    "healthCheckExport": MessageLookupByLibrary.simpleMessage("Экспорт отчёта"),
    "healthCheckExportDialogTitle": MessageLookupByLibrary.simpleMessage(
      "Экспорт обезличенного отчёта",
    ),
    "healthCheckExportFailed": MessageLookupByLibrary.simpleMessage(
      "Ошибка экспорта отчёта",
    ),
    "healthCheckExportSuccess": MessageLookupByLibrary.simpleMessage(
      "Отчёт экспортирован",
    ),
    "healthCheckLastChecked": m7,
    "healthCheckPrivacyNote": MessageLookupByLibrary.simpleMessage(
      "Отчёт содержит только коды статусов и время — без имён узлов, IP, ссылок и логов.",
    ),
    "healthCheckRecheck": MessageLookupByLibrary.simpleMessage("Проверить"),
    "healthCheckSubtitle": MessageLookupByLibrary.simpleMessage(
      "Диагностика профиля, ядра, перехвата трафика и связи",
    ),
    "healthCheckTitle": MessageLookupByLibrary.simpleMessage("Проверка сети"),
    "healthDetailCancelled": MessageLookupByLibrary.simpleMessage("Отменено"),
    "healthDetailCoreDelayBusy": MessageLookupByLibrary.simpleMessage(
      "Очередь замера занята, повторите позже",
    ),
    "healthDetailCoreFailed": MessageLookupByLibrary.simpleMessage(
      "Сбой или тайм-аут интерфейса ядра",
    ),
    "healthDetailCoreHealthy": m8,
    "healthDetailCoreSlow": MessageLookupByLibrary.simpleMessage(
      "Медленный отклик ядра (> 500 мс)",
    ),
    "healthDetailDirectFailed": MessageLookupByLibrary.simpleMessage(
      "Сбой прямого доступа: проверьте сеть или роутер",
    ),
    "healthDetailDirectMode": MessageLookupByLibrary.simpleMessage(
      "Выбран прямой режим (Direct)",
    ),
    "healthDetailDirectOk": MessageLookupByLibrary.simpleMessage(
      "Прямой доступ работает",
    ),
    "healthDetailDirectSlow": MessageLookupByLibrary.simpleMessage(
      "Высокая задержка прямого канала",
    ),
    "healthDetailDnsFailed": MessageLookupByLibrary.simpleMessage(
      "Ошибка или тайм-аут DNS",
    ),
    "healthDetailDnsFakeIp": MessageLookupByLibrary.simpleMessage(
      "Core DNS (fake-ip)",
    ),
    "healthDetailDnsOk": MessageLookupByLibrary.simpleMessage(
      "Разрешено успешно",
    ),
    "healthDetailDnsPoisoned": MessageLookupByLibrary.simpleMessage(
      "DNS вернул некорректный адрес-заглушку",
    ),
    "healthDetailDnsStaleFakeIp": MessageLookupByLibrary.simpleMessage(
      "Обнаружен устаревший кэш Fake-IP при выключенном TUN",
    ),
    "healthDetailE2eBypassed": MessageLookupByLibrary.simpleMessage(
      "Доступ есть, но соединение обошло ядро",
    ),
    "healthDetailE2eDirectRule": MessageLookupByLibrary.simpleMessage(
      "Вошёл в ядро (правило DIRECT)",
    ),
    "healthDetailE2eFailed": MessageLookupByLibrary.simpleMessage(
      "Сквозные запросы завершились ошибкой",
    ),
    "healthDetailE2eVerified": m9,
    "healthDetailLocalProfile": MessageLookupByLibrary.simpleMessage(
      "Локальный профиль",
    ),
    "healthDetailNoProfile": MessageLookupByLibrary.simpleMessage(
      "Профиль не выбран",
    ),
    "healthDetailOutboundDirectSelected": MessageLookupByLibrary.simpleMessage(
      "В группе выбран DIRECT вместо узла",
    ),
    "healthDetailOutboundFailed": m10,
    "healthDetailOutboundProbeFallbackOk": m11,
    "healthDetailOutboundRejectSelected": MessageLookupByLibrary.simpleMessage(
      "В группе выбран REJECT (блокировка)",
    ),
    "healthDetailOutboundSlow": m12,
    "healthDetailProfileFileMissing": MessageLookupByLibrary.simpleMessage(
      "Файл профиля отсутствует или пуст",
    ),
    "healthDetailProxyRunning": MessageLookupByLibrary.simpleMessage("Запущен"),
    "healthDetailProxyStopped": MessageLookupByLibrary.simpleMessage(
      "Остановлен",
    ),
    "healthDetailRuntimeMismatch": MessageLookupByLibrary.simpleMessage(
      "Профиль ещё не применён к ядру",
    ),
    "healthDetailRuntimeSynced": m13,
    "healthDetailSkipPrerequisite": MessageLookupByLibrary.simpleMessage(
      "Пропущено из-за предыдущей ошибки",
    ),
    "healthDetailSkipProxyStopped": MessageLookupByLibrary.simpleMessage(
      "Пропущено: прокси остановлен",
    ),
    "healthDetailSubDeviceLimit": MessageLookupByLibrary.simpleMessage(
      "Достигнут лимит устройств",
    ),
    "healthDetailSubExhausted": MessageLookupByLibrary.simpleMessage(
      "Трафик исчерпан",
    ),
    "healthDetailSubExpired": MessageLookupByLibrary.simpleMessage(
      "Подписка истекла",
    ),
    "healthDetailSubExpiringSoon": m14,
    "healthDetailSubHealthy": MessageLookupByLibrary.simpleMessage(
      "Подписка активна",
    ),
    "healthDetailSubHealthyEternal": MessageLookupByLibrary.simpleMessage(
      "Бессрочно · Безлимит",
    ),
    "healthDetailSubNeverSynced": MessageLookupByLibrary.simpleMessage(
      "Ещё не синхронизирован, обновите подписку",
    ),
    "healthDetailSubNoMeta": MessageLookupByLibrary.simpleMessage(
      "Сервер не передал данные о лимитах",
    ),
    "healthDetailSubTrafficLow": m15,
    "healthDetailSysProxyDisabled": MessageLookupByLibrary.simpleMessage(
      "Выключен в настройках",
    ),
    "healthDetailSysProxyDisabledExternally":
        MessageLookupByLibrary.simpleMessage("Системный прокси выключен в ОС"),
    "healthDetailSysProxyHijacked": MessageLookupByLibrary.simpleMessage(
      "Системный прокси изменён извне",
    ),
    "healthDetailSysProxyInvalidPort": MessageLookupByLibrary.simpleMessage(
      "Локальный mixed-port отключён (0)",
    ),
    "healthDetailSysProxyNotApplied": MessageLookupByLibrary.simpleMessage(
      "Системный прокси ещё не применён",
    ),
    "healthDetailSysProxyReadFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось прочитать настройки прокси",
    ),
    "healthDetailSysProxyUnexpectedPac": MessageLookupByLibrary.simpleMessage(
      "Обнаружен сторонний PAC-адрес",
    ),
    "healthDetailSysProxyUnsupported": MessageLookupByLibrary.simpleMessage(
      "Неприменимо на этой платформе",
    ),
    "healthDetailTakeoverBoth": MessageLookupByLibrary.simpleMessage(
      "Активны TUN и системный прокси",
    ),
    "healthDetailTakeoverNone": MessageLookupByLibrary.simpleMessage(
      "Ни TUN, ни системный прокси не активны",
    ),
    "healthDetailTakeoverPartial": MessageLookupByLibrary.simpleMessage(
      "Активен только один из включённых режимов",
    ),
    "healthDetailTakeoverSysProxy": MessageLookupByLibrary.simpleMessage(
      "Перехват через системный прокси",
    ),
    "healthDetailTakeoverTun": MessageLookupByLibrary.simpleMessage(
      "Перехват через адаптер TUN",
    ),
    "healthDetailTunBypassedSystemProxyOk":
        MessageLookupByLibrary.simpleMessage(
          "Маршрут TUN не работает; проверено через системный прокси",
        ),
    "healthDetailTunDisabled": MessageLookupByLibrary.simpleMessage(
      "Выключен в настройках",
    ),
    "healthDetailTunReady": MessageLookupByLibrary.simpleMessage(
      "Виртуальный адаптер активен",
    ),
    "healthDetailTunReadyElevated": MessageLookupByLibrary.simpleMessage(
      "Активен · Права админа",
    ),
    "healthExitCountryPart": m16,
    "healthItemCoreResponsive": MessageLookupByLibrary.simpleMessage(
      "Отклик ядра",
    ),
    "healthItemDirect": MessageLookupByLibrary.simpleMessage("Прямой доступ"),
    "healthItemDns": MessageLookupByLibrary.simpleMessage("DNS-разрешение"),
    "healthItemEndToEnd": MessageLookupByLibrary.simpleMessage(
      "Сквозная проверка",
    ),
    "healthItemOutbound": MessageLookupByLibrary.simpleMessage("Узел выхода"),
    "healthItemProfileSelected": MessageLookupByLibrary.simpleMessage(
      "Текущий профиль",
    ),
    "healthItemProxyStarted": MessageLookupByLibrary.simpleMessage(
      "Состояние прокси",
    ),
    "healthItemRuntimeConfig": MessageLookupByLibrary.simpleMessage(
      "Применение конфига",
    ),
    "healthItemSubscription": MessageLookupByLibrary.simpleMessage(
      "Статус подписки",
    ),
    "healthItemSystemProxy": MessageLookupByLibrary.simpleMessage(
      "Системный прокси",
    ),
    "healthItemTrafficTakeover": MessageLookupByLibrary.simpleMessage(
      "Итог перехвата",
    ),
    "healthItemTunTakeover": MessageLookupByLibrary.simpleMessage(
      "Адаптер TUN",
    ),
    "healthLayerConfig": MessageLookupByLibrary.simpleMessage(
      "Профиль и подписка",
    ),
    "healthLayerCore": MessageLookupByLibrary.simpleMessage("Ядро прокси"),
    "healthLayerNetwork": MessageLookupByLibrary.simpleMessage(
      "Сетевой маршрут",
    ),
    "healthLayerTakeover": MessageLookupByLibrary.simpleMessage(
      "Перехват трафика",
    ),
    "healthStatusFailed": MessageLookupByLibrary.simpleMessage("Ошибка"),
    "healthStatusPassed": MessageLookupByLibrary.simpleMessage("Норма"),
    "healthStatusRunning": MessageLookupByLibrary.simpleMessage("Проверка"),
    "healthStatusSkipped": MessageLookupByLibrary.simpleMessage("Пропуск"),
    "healthStatusTimeout": MessageLookupByLibrary.simpleMessage("Тайм-аут"),
    "healthStatusWarning": MessageLookupByLibrary.simpleMessage("Внимание"),
    "healthVerdictCancelledTitle": MessageLookupByLibrary.simpleMessage(
      "Проверка остановлена",
    ),
    "healthVerdictCheckingTitle": MessageLookupByLibrary.simpleMessage(
      "Пошаговая проверка соединения…",
    ),
    "healthVerdictCoreUnresponsive": MessageLookupByLibrary.simpleMessage(
      "Ядро прокси не отвечает",
    ),
    "healthVerdictDnsFailed": MessageLookupByLibrary.simpleMessage(
      "Ошибка разрешения DNS или подмена адреса",
    ),
    "healthVerdictEndToEndFailed": MessageLookupByLibrary.simpleMessage(
      "Сквозная проверка не удалась, смените узел",
    ),
    "healthVerdictHealthyDirectSubtitle": m17,
    "healthVerdictHealthySubtitle": m18,
    "healthVerdictHealthyTitle": MessageLookupByLibrary.simpleMessage(
      "Соединение в норме",
    ),
    "healthVerdictLocalNetworkDown": MessageLookupByLibrary.simpleMessage(
      "Локальная сеть недоступна (не связано с узлом)",
    ),
    "healthVerdictOutboundFailed": MessageLookupByLibrary.simpleMessage(
      "Локальная сеть работает, но узел недоступен",
    ),
    "healthVerdictProfileMissing": MessageLookupByLibrary.simpleMessage(
      "Профиль не выбран или файл отсутствует",
    ),
    "healthVerdictProxyNotStarted": MessageLookupByLibrary.simpleMessage(
      "Прокси остановлен, трафик идёт напрямую",
    ),
    "healthVerdictSubscriptionExhausted": MessageLookupByLibrary.simpleMessage(
      "Трафик подписки исчерпан",
    ),
    "healthVerdictSubscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "Срок действия подписки истёк",
    ),
    "healthVerdictTakeoverFailed": MessageLookupByLibrary.simpleMessage(
      "Трафик не перехватывается: проверьте TUN или прокси",
    ),
    "healthVerdictTrafficBypassed": MessageLookupByLibrary.simpleMessage(
      "Сеть доступна, но трафик обошёл ядро прокси",
    ),
    "healthVerdictTunBypassedTitle": MessageLookupByLibrary.simpleMessage(
      "TUN не перехватывает трафик; работает только системный прокси",
    ),
    "healthVerdictWarningsTitle": MessageLookupByLibrary.simpleMessage(
      "Соединение работает, но есть предупреждения",
    ),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("Добавить Hosts"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage(
      "Конфликт горячих клавиш",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("Горячие клавиши"),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage(
      "Управление приложением с помощью клавиатуры",
    ),
    "hour": MessageLookupByLibrary.simpleMessage("час"),
    "hours": MessageLookupByLibrary.simpleMessage("Часов"),
    "hoursGenitive": MessageLookupByLibrary.simpleMessage("часов"),
    "hoursPlural": MessageLookupByLibrary.simpleMessage("часа"),
    "hwidNotSupported": MessageLookupByLibrary.simpleMessage(
      "Привязка по HWID не поддерживается на этой платформе.",
    ),
    "icon": MessageLookupByLibrary.simpleMessage("Иконка"),
    "iconConfiguration": MessageLookupByLibrary.simpleMessage(
      "Конфигурация иконки",
    ),
    "iconStyle": MessageLookupByLibrary.simpleMessage("Стиль иконки"),
    "import": MessageLookupByLibrary.simpleMessage("Импорт"),
    "importFile": MessageLookupByLibrary.simpleMessage("Импорт из файла"),
    "importFromURL": MessageLookupByLibrary.simpleMessage(
      "Вставьте ссылку подписки и нажмите ОК",
    ),
    "importUrl": MessageLookupByLibrary.simpleMessage("Импорт по URL"),
    "includeInVpn": MessageLookupByLibrary.simpleMessage("Включить в VPN"),
    "infiniteTime": MessageLookupByLibrary.simpleMessage(
      "Долгосрочное действие",
    ),
    "init": MessageLookupByLibrary.simpleMessage("Инициализация"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage(
      "Введите корректную комбинацию клавиш",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage(
      "Интеллектуальный выбор",
    ),
    "internet": MessageLookupByLibrary.simpleMessage("Интернет"),
    "interval": MessageLookupByLibrary.simpleMessage("Интервал"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("Внутренний IP"),
    "invalidQrMessage": MessageLookupByLibrary.simpleMessage("Неверный QR-код"),
    "ipcidr": MessageLookupByLibrary.simpleMessage("IPCIDR"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "При включении будет возможно получать IPv6 трафик",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешить входящий IPv6",
    ),
    "ja": MessageLookupByLibrary.simpleMessage("Японский"),
    "just": MessageLookupByLibrary.simpleMessage("Только что"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "Интервал поддержания TCP-соединения",
    ),
    "key": MessageLookupByLibrary.simpleMessage("Ключ"),
    "language": MessageLookupByLibrary.simpleMessage("Язык"),
    "layout": MessageLookupByLibrary.simpleMessage("Макет"),
    "light": MessageLookupByLibrary.simpleMessage("Светлый"),
    "list": MessageLookupByLibrary.simpleMessage("Список"),
    "listen": MessageLookupByLibrary.simpleMessage("Слушать"),
    "local": MessageLookupByLibrary.simpleMessage("Локальный"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование локальных данных на локальный диск",
    ),
    "localRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "Восстановление данных из файла",
    ),
    "localSplitMode": MessageLookupByLibrary.simpleMessage(
      "Локальное разделение трафика",
    ),
    "localSplitModeDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически направлять локальный трафик напрямую для голых подписок",
    ),
    "localSplitMode_always": MessageLookupByLibrary.simpleMessage(
      "Всегда добавлять прямой маршрут",
    ),
    "localSplitMode_auto": MessageLookupByLibrary.simpleMessage(
      "Автоопределение (Авто)",
    ),
    "localSplitMode_off": MessageLookupByLibrary.simpleMessage("Выкл"),
    "locations": MessageLookupByLibrary.simpleMessage("Локации"),
    "logLevel": MessageLookupByLibrary.simpleMessage("Уровень логов"),
    "logcat": MessageLookupByLibrary.simpleMessage("Журналирование"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage(
      "Вести журнал событий приложения",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("Логи"),
    "logsDesc": MessageLookupByLibrary.simpleMessage("Записи журнала событий"),
    "logsTest": MessageLookupByLibrary.simpleMessage("Тест журналов"),
    "loopback": MessageLookupByLibrary.simpleMessage("Разблокировка Loopback"),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage(
      "Разблокировать Loopback для UWP-приложений",
    ),
    "loose": MessageLookupByLibrary.simpleMessage("Свободный"),
    "managedByProvider": MessageLookupByLibrary.simpleMessage(
      "Заблокированными настройками управляет ваш провайдер",
    ),
    "managedByProviderNetwork": MessageLookupByLibrary.simpleMessage(
      "Этими параметрами управляет ваш провайдер",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("Информация о памяти"),
    "messageTest": MessageLookupByLibrary.simpleMessage(
      "Тестирование сообщения",
    ),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("Это сообщение."),
    "min": MessageLookupByLibrary.simpleMessage("Мин"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage(
      "Сворачивать при выходе",
    ),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage(
      "Сворачивать приложение в трей вместо закрытия",
    ),
    "minutes": MessageLookupByLibrary.simpleMessage("Минут"),
    "mixedPort": MessageLookupByLibrary.simpleMessage("Смешанный порт"),
    "mode": MessageLookupByLibrary.simpleMessage("Режим"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("Монохром"),
    "months": MessageLookupByLibrary.simpleMessage("Месяцев"),
    "more": MessageLookupByLibrary.simpleMessage("Еще"),
    "name": MessageLookupByLibrary.simpleMessage("Имя"),
    "nameSort": MessageLookupByLibrary.simpleMessage("Сортировка по имени"),
    "nameserver": MessageLookupByLibrary.simpleMessage("Сервер имен"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Для разрешения домена",
    ),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage(
      "Политика сервера имен",
    ),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage(
      "Указать соответствующую политику сервера имен",
    ),
    "network": MessageLookupByLibrary.simpleMessage("Сеть"),
    "networkDesc": MessageLookupByLibrary.simpleMessage(
      "Изменение настроек, связанных с сетью",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage("Ваш IP-адрес"),
    "networkSpeed": MessageLookupByLibrary.simpleMessage("Скорость сети"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("Нейтральные"),
    "newDashboard": MessageLookupByLibrary.simpleMessage("Краткий режим"),
    "noData": MessageLookupByLibrary.simpleMessage("Нет данных"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("Нет горячей клавиши"),
    "noIcon": MessageLookupByLibrary.simpleMessage("Нет иконки"),
    "noInfo": MessageLookupByLibrary.simpleMessage("Нет информации"),
    "noMoreInfoDesc": MessageLookupByLibrary.simpleMessage(
      "Дополнительная информация отсутствует",
    ),
    "noNetwork": MessageLookupByLibrary.simpleMessage("Нет сети"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("Приложение без сети"),
    "noProxy": MessageLookupByLibrary.simpleMessage("Нет прокси"),
    "noProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, создайте профиль или добавьте действительный профиль",
    ),
    "noResolve": MessageLookupByLibrary.simpleMessage("Не разрешать IP"),
    "nodeOverviewActive": MessageLookupByLibrary.simpleMessage("Активный"),
    "nodeOverviewAddSubscription": MessageLookupByLibrary.simpleMessage(
      "Добавить подписку",
    ),
    "nodeOverviewAllHealthCounts": m19,
    "nodeOverviewAllProfiles": MessageLookupByLibrary.simpleMessage(
      "Все профили",
    ),
    "nodeOverviewAllProfilesCount": m20,
    "nodeOverviewAmbiguousNode": MessageLookupByLibrary.simpleMessage(
      "Определения узлов повторяются; не удалось подтвердить идентичность",
    ),
    "nodeOverviewAnnouncement": m21,
    "nodeOverviewAutoConnectedBest": m22,
    "nodeOverviewAutoConnectedSmartBest": m23,
    "nodeOverviewAutoSelectedAllFailedWarning": m24,
    "nodeOverviewAutoSelectedExpiredWarning": m25,
    "nodeOverviewAutoSelectedTrafficExhaustedWarning": m26,
    "nodeOverviewAutoUpdateHours": m27,
    "nodeOverviewAutoUpdateMinutes": m28,
    "nodeOverviewAvailableFilterEmpty": MessageLookupByLibrary.simpleMessage(
      "Сейчас нет проверенных доступных узлов (не проверены или недоступны)",
    ),
    "nodeOverviewAvailableOnly": MessageLookupByLibrary.simpleMessage(
      "Только доступные",
    ),
    "nodeOverviewBandFailed": m29,
    "nodeOverviewBandFast": m30,
    "nodeOverviewBandSlow": m31,
    "nodeOverviewBandUntested": m32,
    "nodeOverviewBatchSummary": m33,
    "nodeOverviewChainUnsupported": MessageLookupByLibrary.simpleMessage(
      "Изолированная проверка цепочек прокси не поддерживается",
    ),
    "nodeOverviewCurrentActiveProfile": m34,
    "nodeOverviewCurrentProfile": MessageLookupByLibrary.simpleMessage(
      "Текущий профиль",
    ),
    "nodeOverviewDeviceLimitReached": MessageLookupByLibrary.simpleMessage(
      "Достигнут лимит устройств",
    ),
    "nodeOverviewEmptyStepsHint": MessageLookupByLibrary.simpleMessage(
      "① Подписка  ·  ② Тест задержки  ·  ③ Быстрейший",
    ),
    "nodeOverviewEmptySubtitle": MessageLookupByLibrary.simpleMessage(
      "Вставьте ссылку подписки — приложение автоматически проверит задержку и подключит лучший узел",
    ),
    "nodeOverviewEmptyTitle": MessageLookupByLibrary.simpleMessage(
      "Нет добавленных подписок",
    ),
    "nodeOverviewExpireAt": m35,
    "nodeOverviewExpireDaysLeft": m36,
    "nodeOverviewExpireHoursLeft": m37,
    "nodeOverviewExpireSoon": MessageLookupByLibrary.simpleMessage(
      "менее 1 ч.",
    ),
    "nodeOverviewExpired": MessageLookupByLibrary.simpleMessage(
      "Подписка истекла",
    ),
    "nodeOverviewExpiredCountBadge": m38,
    "nodeOverviewExpiringSoonCountBadge": m39,
    "nodeOverviewFileMissing": MessageLookupByLibrary.simpleMessage(
      "Файл профиля отсутствует",
    ),
    "nodeOverviewFileSource": m40,
    "nodeOverviewGlobalMedian": m41,
    "nodeOverviewGlobalMedianAndBest": m42,
    "nodeOverviewHealthCapacityExceeded": MessageLookupByLibrary.simpleMessage(
      "Хранилище истории заполнено; часть результатов не сохранена",
    ),
    "nodeOverviewHealthCounts": m43,
    "nodeOverviewHealthStoreUnavailable": MessageLookupByLibrary.simpleMessage(
      "Не удалось сохранить часть результатов проверки задержки",
    ),
    "nodeOverviewHistoryNotice": MessageLookupByLibrary.simpleMessage(
      "Результаты проверки задержки сохраняются до следующей завершённой проверки. Время проверки указано под каждым узлом.",
    ),
    "nodeOverviewInUse": MessageLookupByLibrary.simpleMessage("Используется"),
    "nodeOverviewIndependentTest": MessageLookupByLibrary.simpleMessage(
      "Независимая проверка задержки",
    ),
    "nodeOverviewLastActiveTest": m44,
    "nodeOverviewLastSync": m45,
    "nodeOverviewLastTest": m46,
    "nodeOverviewLive": MessageLookupByLibrary.simpleMessage(
      "В реальном времени",
    ),
    "nodeOverviewLocalProfile": MessageLookupByLibrary.simpleMessage(
      "Локальный файл",
    ),
    "nodeOverviewLockedManualNode": m47,
    "nodeOverviewManageProfiles": MessageLookupByLibrary.simpleMessage(
      "Управление профилями / обновление подписки",
    ),
    "nodeOverviewManualSelectCompact": MessageLookupByLibrary.simpleMessage(
      "Фикс. IP",
    ),
    "nodeOverviewManualSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "Фикс. IP",
    ),
    "nodeOverviewManualSelectTitle": MessageLookupByLibrary.simpleMessage(
      "Ручной выбор",
    ),
    "nodeOverviewManualUpdate": MessageLookupByLibrary.simpleMessage("Вручную"),
    "nodeOverviewMedian": m48,
    "nodeOverviewMoreIssues": m49,
    "nodeOverviewNeverExpires": MessageLookupByLibrary.simpleMessage(
      "Истекает: бессрочно",
    ),
    "nodeOverviewNoActiveProfile": MessageLookupByLibrary.simpleMessage(
      "Активный: нет",
    ),
    "nodeOverviewNoNodes": MessageLookupByLibrary.simpleMessage(
      "Нет подходящих узлов",
    ),
    "nodeOverviewNodeUnidentified": MessageLookupByLibrary.simpleMessage(
      "Не удалось распознать узел",
    ),
    "nodeOverviewParseFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось разобрать профиль",
    ),
    "nodeOverviewPartialSummary": MessageLookupByLibrary.simpleMessage(
      "В сводке учтены только загруженные узлы",
    ),
    "nodeOverviewPickerAvailableNodes": m50,
    "nodeOverviewPickerExpireDate": m51,
    "nodeOverviewPickerPerpetual": MessageLookupByLibrary.simpleMessage(
      "Бессрочно",
    ),
    "nodeOverviewPreviewUnsupported": MessageLookupByLibrary.simpleMessage(
      "Локальные узлы провайдера не поддерживаются в этой предварительной версии",
    ),
    "nodeOverviewProfileCountBadge": m52,
    "nodeOverviewProgress": m53,
    "nodeOverviewProviderDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить провайдера",
    ),
    "nodeOverviewProviderNotCached": MessageLookupByLibrary.simpleMessage(
      "Локальный кэш провайдера недоступен",
    ),
    "nodeOverviewProviderOptionsUnsupported":
        MessageLookupByLibrary.simpleMessage(
          "Эти параметры провайдера не поддерживаются",
        ),
    "nodeOverviewProviderPending": m54,
    "nodeOverviewProviderTooLarge": MessageLookupByLibrary.simpleMessage(
      "Превышен лимит размера или числа узлов провайдера",
    ),
    "nodeOverviewProviderUnloaded": MessageLookupByLibrary.simpleMessage(
      "Узлы провайдера ещё не загружены. Проверка задержки всех узлов прочитает их и загрузит отсутствующий кэш.",
    ),
    "nodeOverviewProviderUnsafePath": MessageLookupByLibrary.simpleMessage(
      "Файл провайдера находится вне разрешённого каталога",
    ),
    "nodeOverviewProviderUnsafeUrl": MessageLookupByLibrary.simpleMessage(
      "URL провайдера не соответствует требованиям безопасности",
    ),
    "nodeOverviewProxyConnected": MessageLookupByLibrary.simpleMessage(
      "Прокси включён · Подключено",
    ),
    "nodeOverviewProxyConnectedSmart": m55,
    "nodeOverviewProxyConnectedSmartWithNode": m56,
    "nodeOverviewProxyConnectedWithNode": m57,
    "nodeOverviewProxyDisconnected": MessageLookupByLibrary.simpleMessage(
      "Прокси выключен · Нажмите Включить или Использовать у узла",
    ),
    "nodeOverviewProxyStarting": MessageLookupByLibrary.simpleMessage(
      "Запуск прокси…",
    ),
    "nodeOverviewProxyStopping": MessageLookupByLibrary.simpleMessage(
      "Остановка прокси…",
    ),
    "nodeOverviewQuickUse": MessageLookupByLibrary.simpleMessage("Быстрейший"),
    "nodeOverviewRemainingTraffic": m58,
    "nodeOverviewRuntimeSource": MessageLookupByLibrary.simpleMessage(
      "Активный узел",
    ),
    "nodeOverviewSelectProfileTitle": MessageLookupByLibrary.simpleMessage(
      "Выбор профиля",
    ),
    "nodeOverviewShowAllNodes": MessageLookupByLibrary.simpleMessage(
      "Показать все узлы",
    ),
    "nodeOverviewSmartInUse": MessageLookupByLibrary.simpleMessage("Авто"),
    "nodeOverviewSmartSelectCompact": MessageLookupByLibrary.simpleMessage(
      "Умный",
    ),
    "nodeOverviewSmartSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "Лучший опыт",
    ),
    "nodeOverviewSmartSelectTitle": MessageLookupByLibrary.simpleMessage(
      "Умный выбор",
    ),
    "nodeOverviewStale": MessageLookupByLibrary.simpleMessage(
      "Возможно, устарело",
    ),
    "nodeOverviewStatusExpired": MessageLookupByLibrary.simpleMessage("Истёк"),
    "nodeOverviewStrictUnsupported": MessageLookupByLibrary.simpleMessage(
      "В строгом режиме изолированные проверки недоступны",
    ),
    "nodeOverviewSwitchedToNode": m59,
    "nodeOverviewSwitchedToSmart": m60,
    "nodeOverviewSwitchedToSmartWithNode": m61,
    "nodeOverviewTestAll": MessageLookupByLibrary.simpleMessage(
      "Проверить задержку всех узлов",
    ),
    "nodeOverviewTestCurrent": MessageLookupByLibrary.simpleMessage(
      "Проверить текущий профиль",
    ),
    "nodeOverviewTestFailed": MessageLookupByLibrary.simpleMessage(
      "Ошибка проверки",
    ),
    "nodeOverviewTestInterrupted": MessageLookupByLibrary.simpleMessage(
      "Проверка прервана; предыдущие результаты сохранены",
    ),
    "nodeOverviewTestNode": MessageLookupByLibrary.simpleMessage(
      "Тест задержки",
    ),
    "nodeOverviewTestTimedOut": MessageLookupByLibrary.simpleMessage(
      "Истекло время проверки или чтения провайдера",
    ),
    "nodeOverviewTestUnavailable": MessageLookupByLibrary.simpleMessage(
      "Не удалось начать проверку. Проверьте версию фоновых компонентов.",
    ),
    "nodeOverviewTooManyNodes": MessageLookupByLibrary.simpleMessage(
      "Слишком много узлов для этой предварительной версии",
    ),
    "nodeOverviewTrafficUnlimited": MessageLookupByLibrary.simpleMessage(
      "Трафик: безлимитный",
    ),
    "nodeOverviewTurnOffProxy": MessageLookupByLibrary.simpleMessage(
      "Выключить",
    ),
    "nodeOverviewTurnOnProxy": MessageLookupByLibrary.simpleMessage("Включить"),
    "nodeOverviewTypeUnsupported": MessageLookupByLibrary.simpleMessage(
      "Изолированная проверка этого протокола не поддерживается",
    ),
    "nodeOverviewUntested": MessageLookupByLibrary.simpleMessage(
      "Не проверено",
    ),
    "nodeOverviewUpdateAllSubscriptions": MessageLookupByLibrary.simpleMessage(
      "Обновить все",
    ),
    "nodeOverviewUpdateSubscription": MessageLookupByLibrary.simpleMessage(
      "Обновить",
    ),
    "nodeOverviewUpdating": MessageLookupByLibrary.simpleMessage(
      "Обновление подписки",
    ),
    "nodeOverviewUpdatingShort": MessageLookupByLibrary.simpleMessage(
      "Обновление",
    ),
    "nodeOverviewUseNode": MessageLookupByLibrary.simpleMessage("Использовать"),
    "nodeOverviewUsedOfTotalTraffic": m62,
    "nodeOverviewUsedTrafficOnly": m63,
    "none": MessageLookupByLibrary.simpleMessage("Нет"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "Текущая группа прокси недоступна для выбора",
    ),
    "noviceMode": MessageLookupByLibrary.simpleMessage("Простой режим"),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Профиль отсутствует. Пожалуйста, добавьте профиль",
    ),
    "nullScriptTip": MessageLookupByLibrary.simpleMessage(
      "Скрипты отсутствуют",
    ),
    "nullTip": m64,
    "numberTip": m65,
    "oneColumn": MessageLookupByLibrary.simpleMessage("Один столбец"),
    "oneline": MessageLookupByLibrary.simpleMessage("Линия"),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("Только иконка"),
    "onlyOtherApps": MessageLookupByLibrary.simpleMessage(
      "Только сторонние приложения",
    ),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "Учитывать только прокси-трафик",
    ),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Учитывать в статистике только трафик через прокси",
    ),
    "openLogsFolder": MessageLookupByLibrary.simpleMessage(
      "Открыть папку логов",
    ),
    "openPanel": MessageLookupByLibrary.simpleMessage("Открыть панель"),
    "options": MessageLookupByLibrary.simpleMessage("Опции"),
    "originalRepository": MessageLookupByLibrary.simpleMessage(
      "Оригинальный репозиторий",
    ),
    "other": MessageLookupByLibrary.simpleMessage("Другое"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("Контрибьюторы"),
    "outboundMode": MessageLookupByLibrary.simpleMessage(
      "Режим исходящих подключений",
    ),
    "override": MessageLookupByLibrary.simpleMessage("Переопределение"),
    "overrideAutoSavedHint": MessageLookupByLibrary.simpleMessage(
      "Изменения сохраняются и применяются автоматически",
    ),
    "overrideDesc": MessageLookupByLibrary.simpleMessage(
      "Переопределение конфигурации прокси",
    ),
    "overrideDns": MessageLookupByLibrary.simpleMessage("Переопределить DNS"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage(
      "Переопределить настройки DNS из профиля",
    ),
    "overrideInvalidTip": MessageLookupByLibrary.simpleMessage(
      "В скриптовом режиме не действует",
    ),
    "overrideNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Переопределение сетевых настроек",
    ),
    "overrideNetworkSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "Игнорировать сетевые настройки из конфига провайдера",
    ),
    "overrideOriginRules": MessageLookupByLibrary.simpleMessage(
      "Переопределить оригинальное правило",
    ),
    "overrideProviderSettings": MessageLookupByLibrary.simpleMessage(
      "Переопределение",
    ),
    "overrideProviderSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "Игнорировать настройки от провайдера и управлять вручную",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("Палитра"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "paste": MessageLookupByLibrary.simpleMessage("Вставить"),
    "pasteFromClipboard": MessageLookupByLibrary.simpleMessage("Вставить"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, привяжите WebDAV",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите название скрипта",
    ),
    "pleaseInputAdminPassword": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите пароль администратора",
    ),
    "pleaseUploadFile": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, загрузите файл",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, загрузите действительный QR-код",
    ),
    "port": MessageLookupByLibrary.simpleMessage("Порт"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage(
      "Введите другой порт",
    ),
    "portTip": m66,
    "preferH3Desc": MessageLookupByLibrary.simpleMessage(
      "Использовать HTTP/3 для DOH (если доступно)",
    ),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage("Нажмите клавишу"),
    "preview": MessageLookupByLibrary.simpleMessage("Предпросмотр"),
    "profile": MessageLookupByLibrary.simpleMessage("Профиль"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Пожалуйста, введите действительный формат интервала времени",
        ),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Пожалуйста, введите интервал времени для автообновления",
        ),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "Профиль был изменён. Отключить автообновление?",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите имя профиля",
    ),
    "profileParseErrorDesc": MessageLookupByLibrary.simpleMessage(
      "Ошибка парсинга профиля",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите действительный URL профиля",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите URL профиля",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("Профили"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("Сортировка профилей"),
    "project": MessageLookupByLibrary.simpleMessage("Проект"),
    "providers": MessageLookupByLibrary.simpleMessage("Провайдеры"),
    "proxies": MessageLookupByLibrary.simpleMessage("Прокси"),
    "proxiesSetting": MessageLookupByLibrary.simpleMessage("Настройка прокси"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("Группа прокси"),
    "proxyNameserver": MessageLookupByLibrary.simpleMessage(
      "Прокси-сервер имен",
    ),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Домен для разрешения прокси-узлов",
    ),
    "proxyPort": MessageLookupByLibrary.simpleMessage("Порт прокси"),
    "proxyPortDesc": MessageLookupByLibrary.simpleMessage(
      "Установить порт прослушивания прокси-сервера",
    ),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("Провайдеры прокси"),
    "purchase": MessageLookupByLibrary.simpleMessage("Покупка"),
    "purchaseAccount": MessageLookupByLibrary.simpleMessage(
      "Аккаунт и подписка",
    ),
    "purchaseAcquireOpenSupport": MessageLookupByLibrary.simpleMessage(
      "Написать в поддержку",
    ),
    "purchaseAcquirePlanCode": MessageLookupByLibrary.simpleMessage(
      "Получить код",
    ),
    "purchaseAcquireSheetSubtitle": MessageLookupByLibrary.simpleMessage(
      "Получите код через магазин карт или WeChat ниже, затем активируйте его здесь. Заказ в приложении не создаётся.",
    ),
    "purchaseAuthTabLogin": MessageLookupByLibrary.simpleMessage("Вход"),
    "purchaseAuthTabRegister": MessageLookupByLibrary.simpleMessage(
      "Регистрация +2G",
    ),
    "purchaseAvailablePlans": MessageLookupByLibrary.simpleMessage(
      "Доступные тарифы",
    ),
    "purchaseBackToLogin": MessageLookupByLibrary.simpleMessage(
      "Вернуться ко входу",
    ),
    "purchaseBackupContactsLabel": MessageLookupByLibrary.simpleMessage(
      "Резервная поддержка (WeChat)",
    ),
    "purchaseBalance": MessageLookupByLibrary.simpleMessage("Баланс аккаунта"),
    "purchaseBalanceOnlyHint": MessageLookupByLibrary.simpleMessage(
      "Пополнение баланса не активирует подписку автоматически.",
    ),
    "purchaseBenefitsAfter": MessageLookupByLibrary.simpleMessage(
      "Бонусы отобразятся после активации.",
    ),
    "purchaseCaptchaRequiredNotice": MessageLookupByLibrary.simpleMessage(
      "На сайте включена CAPTCHA. Продолжите на веб-странице.",
    ),
    "purchaseCardStore": MessageLookupByLibrary.simpleMessage(
      "Открыть магазин карт",
    ),
    "purchaseCenterDescription": MessageLookupByLibrary.simpleMessage(
      "Активируйте карту для подключения или продления тарифа, затем синхронизируйте подписку.",
    ),
    "purchaseCenterTitle": MessageLookupByLibrary.simpleMessage(
      "Активация подарочных карт",
    ),
    "purchaseChannelError": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить данные магазина карт. Вы по-прежнему можете обратиться в поддержку ниже.",
    ),
    "purchaseCheck": MessageLookupByLibrary.simpleMessage("Проверить карту"),
    "purchaseChecking": MessageLookupByLibrary.simpleMessage("Проверка…"),
    "purchaseClearCode": MessageLookupByLibrary.simpleMessage("Очистить код"),
    "purchaseClipboardEmpty": MessageLookupByLibrary.simpleMessage(
      "В буфере обмена не найден код активации.",
    ),
    "purchaseCode": MessageLookupByLibrary.simpleMessage(
      "Код подарочной карты",
    ),
    "purchaseCodeFormatError": MessageLookupByLibrary.simpleMessage(
      "Введите код из 8–32 латинских букв и цифр.",
    ),
    "purchaseCodeSentNotice": MessageLookupByLibrary.simpleMessage(
      "Код подтверждения отправлен. Проверьте почту и папку «Спам».",
    ),
    "purchaseConfirmRedeem": MessageLookupByLibrary.simpleMessage(
      "Подтвердить активацию",
    ),
    "purchaseContactDescription": MessageLookupByLibrary.simpleMessage(
      "Онлайн-оплата пока недоступна. Добавьте любой из указанных аккаунтов WeChat для покупки или продления.",
    ),
    "purchaseCooldownWithSecondsError": m67,
    "purchaseCopyInquiry": MessageLookupByLibrary.simpleMessage(
      "Скопировать запрос",
    ),
    "purchaseEmail": MessageLookupByLibrary.simpleMessage("Электронная почта"),
    "purchaseEmailCode": MessageLookupByLibrary.simpleMessage(
      "Код подтверждения email",
    ),
    "purchaseEmailCodeInvalidError": MessageLookupByLibrary.simpleMessage(
      "Недействительный или просроченный код из письма.",
    ),
    "purchaseEmailCodeLockedError": MessageLookupByLibrary.simpleMessage(
      "Слишком много попыток ввода кода. Запросите новый позже.",
    ),
    "purchaseEmailCodeRequired": MessageLookupByLibrary.simpleMessage(
      "Введите 6-значный код подтверждения",
    ),
    "purchaseEmailCooldownError": MessageLookupByLibrary.simpleMessage(
      "Подождите перед повторной отправкой кода.",
    ),
    "purchaseEmailDomainError": MessageLookupByLibrary.simpleMessage(
      "Этот почтовый домен не поддерживается. Используйте другой адрес электронной почты.",
    ),
    "purchaseEmailExistsError": MessageLookupByLibrary.simpleMessage(
      "Этот email уже зарегистрирован. Переключитесь на «Вход».",
    ),
    "purchaseEmailRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "Превышен лимит запросов кода. Попробуйте позже.",
    ),
    "purchaseEmailRequired": MessageLookupByLibrary.simpleMessage(
      "Введите корректный адрес электронной почты.",
    ),
    "purchaseEmailVerifyDisabledError": MessageLookupByLibrary.simpleMessage(
      "Подтверждение по email отключено.",
    ),
    "purchaseExpires": MessageLookupByLibrary.simpleMessage("Истекает"),
    "purchaseExpiryChange": MessageLookupByLibrary.simpleMessage(
      "Срок действия: до → после",
    ),
    "purchaseExtraDays": MessageLookupByLibrary.simpleMessage(
      "Продление срока (дн.)",
    ),
    "purchaseExtraDevices": MessageLookupByLibrary.simpleMessage(
      "Доп. устройства",
    ),
    "purchaseFilterAll": MessageLookupByLibrary.simpleMessage("Все тарифы"),
    "purchaseFilterOnetime": MessageLookupByLibrary.simpleMessage(
      "Пакеты трафика",
    ),
    "purchaseFilterPeriod": MessageLookupByLibrary.simpleMessage("По периоду"),
    "purchaseForgotPassword": MessageLookupByLibrary.simpleMessage(
      "Забыли пароль?",
    ),
    "purchaseGenericError": MessageLookupByLibrary.simpleMessage(
      "Ошибка запроса. Повторите попытку.",
    ),
    "purchaseGetCard": MessageLookupByLibrary.simpleMessage(
      "Получить подарочную карту",
    ),
    "purchaseGetCardDescription": MessageLookupByLibrary.simpleMessage(
      "Приобрести карту или получить помощь можно через магазин карт, онлайн-поддержку или контакты WeChat ниже.",
    ),
    "purchaseGmailAliasError": MessageLookupByLibrary.simpleMessage(
      "Псевдонимы Gmail (со знаком «+») не поддерживаются. Используйте основной адрес.",
    ),
    "purchaseHandoffDescription": MessageLookupByLibrary.simpleMessage(
      "Скопируйте код после покупки и вернитесь в окно — бонусы проверятся автоматически без списания.",
    ),
    "purchaseHandoffPasteAction": MessageLookupByLibrary.simpleMessage(
      "Вставить и проверить",
    ),
    "purchaseHandoffTitle": m68,
    "purchaseHeaderSyncedBadge": MessageLookupByLibrary.simpleMessage(
      "Узлы синхронизированы",
    ),
    "purchaseHeaderTrialBadge": MessageLookupByLibrary.simpleMessage(
      "2 ГиБ бесплатно при регистрации · Бессрочный трафик",
    ),
    "purchaseHidePassword": MessageLookupByLibrary.simpleMessage(
      "Скрыть пароль",
    ),
    "purchaseHistory": MessageLookupByLibrary.simpleMessage(
      "История активаций",
    ),
    "purchaseHistoryEmpty": MessageLookupByLibrary.simpleMessage(
      "Активаций пока нет.",
    ),
    "purchaseHistoryPage": MessageLookupByLibrary.simpleMessage("Стр."),
    "purchaseHistoryRetry": MessageLookupByLibrary.simpleMessage(
      "Обновить историю",
    ),
    "purchaseHistoryTotal": MessageLookupByLibrary.simpleMessage("Всего"),
    "purchaseInquiryTemplate": m69,
    "purchaseInvitationUnavailableError": MessageLookupByLibrary.simpleMessage(
      "Приглашения временно недоступны.",
    ),
    "purchaseInviteCode": MessageLookupByLibrary.simpleMessage(
      "Код приглашения",
    ),
    "purchaseInviteCodeInvalidError": MessageLookupByLibrary.simpleMessage(
      "Недействительный или просроченный код приглашения.",
    ),
    "purchaseInviteCodeOptionalToggle": MessageLookupByLibrary.simpleMessage(
      "Указать код приглашения (необязательно)",
    ),
    "purchaseInviteCodeRequired": MessageLookupByLibrary.simpleMessage(
      "Введите код приглашения",
    ),
    "purchaseInviteCodeRequiredError": MessageLookupByLibrary.simpleMessage(
      "Для регистрации требуется код приглашения.",
    ),
    "purchaseJumpToWorkbench": MessageLookupByLibrary.simpleMessage(
      "Есть код? Перейти к активации",
    ),
    "purchaseLoggingIn": MessageLookupByLibrary.simpleMessage(
      "Выполняется вход…",
    ),
    "purchaseLogin": MessageLookupByLibrary.simpleMessage("Войти"),
    "purchaseLoginDescription": MessageLookupByLibrary.simpleMessage(
      "Войдите в аккаунт для активации кода — тариф и узлы синхронизируются автоматически.",
    ),
    "purchaseLoginTitle": MessageLookupByLibrary.simpleMessage(
      "Войдите для активации",
    ),
    "purchaseLogout": MessageLookupByLibrary.simpleMessage("Выйти"),
    "purchaseLogoutRemoteError": MessageLookupByLibrary.simpleMessage(
      "Выход выполнен на этом устройстве, но подтвердить его на сервере не удалось.",
    ),
    "purchaseMailUnavailableError": MessageLookupByLibrary.simpleMessage(
      "Сервис отправки писем недоступен. Свяжитесь с поддержкой или попробуйте позже.",
    ),
    "purchaseMysteryPreview": MessageLookupByLibrary.simpleMessage(
      "Это карта-сюрприз. Содержимое откроется после активации.",
    ),
    "purchaseNewActivationBadge": MessageLookupByLibrary.simpleMessage(
      "Новая активация",
    ),
    "purchaseNewPassword": MessageLookupByLibrary.simpleMessage("Новый пароль"),
    "purchaseNextPage": MessageLookupByLibrary.simpleMessage("Следующая"),
    "purchaseNoBenefits": MessageLookupByLibrary.simpleMessage(
      "Дополнительных бонусов нет.",
    ),
    "purchaseNoExpiry": MessageLookupByLibrary.simpleMessage("Бессрочно"),
    "purchaseNoPlan": MessageLookupByLibrary.simpleMessage(
      "Нет активного тарифа",
    ),
    "purchaseNoPreviousExpiry": MessageLookupByLibrary.simpleMessage(
      "Не задано",
    ),
    "purchaseNotEligible": MessageLookupByLibrary.simpleMessage(
      "Эту карту нельзя активировать для данного аккаунта.",
    ),
    "purchaseOnlineSupport": MessageLookupByLibrary.simpleMessage(
      "Онлайн-поддержка",
    ),
    "purchaseOpenLinkFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось открыть страницу. Попробуйте ещё раз.",
    ),
    "purchaseOpenNodesAction": MessageLookupByLibrary.simpleMessage(
      "Открыть профили и узлы",
    ),
    "purchaseOpenWebAuth": MessageLookupByLibrary.simpleMessage(
      "Продолжить на сайте",
    ),
    "purchaseOrderNumber": MessageLookupByLibrary.simpleMessage(
      "Номер активации",
    ),
    "purchasePassword": MessageLookupByLibrary.simpleMessage("Пароль"),
    "purchasePasswordMinLength": MessageLookupByLibrary.simpleMessage(
      "Пароль должен содержать минимум 8 символов.",
    ),
    "purchasePasswordRequired": MessageLookupByLibrary.simpleMessage(
      "Введите пароль.",
    ),
    "purchasePeriod": MessageLookupByLibrary.simpleMessage("Период оплаты"),
    "purchasePeriodHalfYearly": MessageLookupByLibrary.simpleMessage("Полгода"),
    "purchasePeriodMonthly": MessageLookupByLibrary.simpleMessage("Месяц"),
    "purchasePeriodOnetime": MessageLookupByLibrary.simpleMessage("По трафику"),
    "purchasePeriodQuarterly": MessageLookupByLibrary.simpleMessage("Квартал"),
    "purchasePeriodThreeYearly": MessageLookupByLibrary.simpleMessage("3 года"),
    "purchasePeriodTwoYearly": MessageLookupByLibrary.simpleMessage("2 года"),
    "purchasePeriodYearly": MessageLookupByLibrary.simpleMessage("Год"),
    "purchasePlan": MessageLookupByLibrary.simpleMessage("Текущий тариф"),
    "purchasePlanBuyNow": MessageLookupByLibrary.simpleMessage("Купить"),
    "purchasePlanCollapseDetails": MessageLookupByLibrary.simpleMessage(
      "Свернуть описание",
    ),
    "purchasePlanDetails": MessageLookupByLibrary.simpleMessage(
      "Описание тарифа",
    ),
    "purchasePlanDevices": MessageLookupByLibrary.simpleMessage(
      "Лимит устройств",
    ),
    "purchasePlanExpandDetails": MessageLookupByLibrary.simpleMessage(
      "Показать полное описание",
    ),
    "purchasePlanFeaturedBadge": MessageLookupByLibrary.simpleMessage(
      "Рекомендуем",
    ),
    "purchasePlanFreeBadge": MessageLookupByLibrary.simpleMessage("Пробный"),
    "purchasePlanFreeHint": MessageLookupByLibrary.simpleMessage("Бесплатно"),
    "purchasePlanImageNotLoaded": MessageLookupByLibrary.simpleMessage(
      "Внешнее изображение не загружено",
    ),
    "purchasePlanLowStock": m70,
    "purchasePlanNotProvided": MessageLookupByLibrary.simpleMessage(
      "Не указано",
    ),
    "purchasePlanResetMonthStart": MessageLookupByLibrary.simpleMessage(
      "Первого числа каждого месяца",
    ),
    "purchasePlanResetMonthlyExpiry": MessageLookupByLibrary.simpleMessage(
      "Ежемесячно в день окончания срока",
    ),
    "purchasePlanResetNever": MessageLookupByLibrary.simpleMessage(
      "Без автоматического сброса",
    ),
    "purchasePlanResetPrice": MessageLookupByLibrary.simpleMessage(
      "Сброс трафика · указанная цена",
    ),
    "purchasePlanResetSystem": MessageLookupByLibrary.simpleMessage(
      "По настройкам системы",
    ),
    "purchasePlanResetUnknown": m71,
    "purchasePlanResetYearStart": MessageLookupByLibrary.simpleMessage(
      "1 января каждого года",
    ),
    "purchasePlanResetYearlyExpiry": MessageLookupByLibrary.simpleMessage(
      "Ежегодно в дату окончания срока",
    ),
    "purchasePlanSalesCapacity": MessageLookupByLibrary.simpleMessage(
      "Оставшиеся места для продажи",
    ),
    "purchasePlanSoldOut": MessageLookupByLibrary.simpleMessage("Распродано"),
    "purchasePlanSpeed": MessageLookupByLibrary.simpleMessage(
      "Ограничение скорости",
    ),
    "purchasePlanTrafficReset": MessageLookupByLibrary.simpleMessage(
      "Сброс трафика",
    ),
    "purchasePlanUnitPriceHint": m72,
    "purchasePlanUnknown": MessageLookupByLibrary.simpleMessage("Подписка"),
    "purchasePlanUnlimited": MessageLookupByLibrary.simpleMessage(
      "Без ограничений",
    ),
    "purchasePlansDescription": MessageLookupByLibrary.simpleMessage(
      "Цены указаны как на сайте. Нажмите «Купить» для перехода в магазин кодов, затем активируйте полученный код здесь.",
    ),
    "purchasePlansEmpty": MessageLookupByLibrary.simpleMessage(
      "Сейчас нет доступных тарифов.",
    ),
    "purchasePlansError": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить тарифы. Повторите попытку.",
    ),
    "purchasePlansErrorHint": MessageLookupByLibrary.simpleMessage(
      "Вход, бесплатная регистрация и активация кода справа остаются доступны.",
    ),
    "purchasePlansLoading": MessageLookupByLibrary.simpleMessage(
      "Загрузка тарифов…",
    ),
    "purchasePlansRetry": MessageLookupByLibrary.simpleMessage(
      "Перезагрузить тарифы",
    ),
    "purchasePreloginCodeHint": MessageLookupByLibrary.simpleMessage(
      "Уже купили код? Вставьте его сюда для автопроверки после входа",
    ),
    "purchasePreview": MessageLookupByLibrary.simpleMessage(
      "Проверьте перед активацией",
    ),
    "purchasePreviousPage": MessageLookupByLibrary.simpleMessage("Предыдущая"),
    "purchaseProfiles": MessageLookupByLibrary.simpleMessage(
      "Управление профилями",
    ),
    "purchaseQuotaChange": MessageLookupByLibrary.simpleMessage(
      "Общий трафик: до → после",
    ),
    "purchaseRecoverPassword": MessageLookupByLibrary.simpleMessage(
      "Восстановить пароль на сайте",
    ),
    "purchaseRecoverResult": MessageLookupByLibrary.simpleMessage(
      "Проверить результат",
    ),
    "purchaseRedeemFor": MessageLookupByLibrary.simpleMessage(
      "Аккаунт для активации",
    ),
    "purchaseRedeemTitle": MessageLookupByLibrary.simpleMessage(
      "Активация подарочной карты",
    ),
    "purchaseRedeeming": MessageLookupByLibrary.simpleMessage("Активация…"),
    "purchaseRefresh": MessageLookupByLibrary.simpleMessage("Обновить аккаунт"),
    "purchaseRegister": MessageLookupByLibrary.simpleMessage(
      "Создать аккаунт на сайте",
    ),
    "purchaseRegisterSubmit": MessageLookupByLibrary.simpleMessage(
      "Создать аккаунт и синхронизировать",
    ),
    "purchaseRegisterTrialBanner": MessageLookupByLibrary.simpleMessage(
      "Получите 2 ГиБ бессрочного пробного трафика сразу после регистрации с автоимпортом узлов.",
    ),
    "purchaseRegisterWebRequiredError": MessageLookupByLibrary.simpleMessage(
      "Требуется подтверждение почты или CAPTCHA. Нажмите «Создать аккаунт на сайте» ниже.",
    ),
    "purchaseRegistering": MessageLookupByLibrary.simpleMessage(
      "Создание аккаунта…",
    ),
    "purchaseRegistrationClosedError": MessageLookupByLibrary.simpleMessage(
      "Регистрация новых аккаунтов временно закрыта.",
    ),
    "purchaseRemaining": MessageLookupByLibrary.simpleMessage(
      "Остаток трафика",
    ),
    "purchaseRenewalBadge": MessageLookupByLibrary.simpleMessage("Продление"),
    "purchaseResetPasswordDescription": MessageLookupByLibrary.simpleMessage(
      "Введите зарегистрированный email и 6-значный код подтверждения, чтобы задать новый пароль.",
    ),
    "purchaseResetPasswordSubmit": MessageLookupByLibrary.simpleMessage(
      "Подтвердить сброс пароля",
    ),
    "purchaseResetPasswordSuccess": MessageLookupByLibrary.simpleMessage(
      "Пароль сброшен. Войдите с новым паролем.",
    ),
    "purchaseResetPasswordTitle": MessageLookupByLibrary.simpleMessage(
      "Сброс пароля",
    ),
    "purchaseResetTraffic": MessageLookupByLibrary.simpleMessage(
      "Сбросить использованный трафик",
    ),
    "purchaseResettingPassword": MessageLookupByLibrary.simpleMessage(
      "Сброс...",
    ),
    "purchaseRestoring": MessageLookupByLibrary.simpleMessage(
      "Восстановление аккаунта…",
    ),
    "purchaseSendCode": MessageLookupByLibrary.simpleMessage("Отправить код"),
    "purchaseSendCodeCooldown": m73,
    "purchaseSendingCode": MessageLookupByLibrary.simpleMessage("Отправка..."),
    "purchaseShowPassword": MessageLookupByLibrary.simpleMessage(
      "Показать пароль",
    ),
    "purchaseSpecAllDevicesSupported": MessageLookupByLibrary.simpleMessage(
      "Поддержка всех типов устройств",
    ),
    "purchaseSpecBillingCycle": m74,
    "purchaseSpecDevicesCount": m75,
    "purchaseSpecDevicesUnlimited": MessageLookupByLibrary.simpleMessage(
      "Устройства: без лимита",
    ),
    "purchaseSpecDurationUnlimited": MessageLookupByLibrary.simpleMessage(
      "Срок действия: бессрочно",
    ),
    "purchaseSpecSpeedLimit": m76,
    "purchaseSpecTrafficUntilUsed": MessageLookupByLibrary.simpleMessage(
      "Трафик действует до исчерпания",
    ),
    "purchaseStepBrowse": MessageLookupByLibrary.simpleMessage(
      "① Выберите тариф или код",
    ),
    "purchaseStepRedeem": MessageLookupByLibrary.simpleMessage(
      "② Войдите и проверьте код",
    ),
    "purchaseStepSync": MessageLookupByLibrary.simpleMessage(
      "③ Автосинхронизация узлов",
    ),
    "purchaseStorageError": MessageLookupByLibrary.simpleMessage(
      "Защищённое хранилище учётных данных недоступно. Проверьте настройки системы и повторите.",
    ),
    "purchaseSuccess": MessageLookupByLibrary.simpleMessage(
      "Подарочная карта активирована",
    ),
    "purchaseSuccessDescription": MessageLookupByLibrary.simpleMessage(
      "Бонусы начислены на аккаунт. Статус синхронизации подписки подтверждается отдельно.",
    ),
    "purchaseSync": MessageLookupByLibrary.simpleMessage(
      "Синхронизировать подписку",
    ),
    "purchaseSyncError": MessageLookupByLibrary.simpleMessage(
      "Не удалось синхронизировать подписку. Вы можете повторить попытку ниже.",
    ),
    "purchaseSyncFailed": MessageLookupByLibrary.simpleMessage(
      "Карта активирована, но не удалось синхронизировать подписку. Повторите синхронизацию ниже.",
    ),
    "purchaseSyncSucceeded": MessageLookupByLibrary.simpleMessage(
      "Подписка успешно синхронизирована.",
    ),
    "purchaseSyncing": MessageLookupByLibrary.simpleMessage(
      "Синхронизация подписки…",
    ),
    "purchaseTitle": MessageLookupByLibrary.simpleMessage(
      "Покупка и продление",
    ),
    "purchaseTosAgreementPrefix": MessageLookupByLibrary.simpleMessage(
      "Регистрируясь, вы принимаете",
    ),
    "purchaseTosLinkLabel": MessageLookupByLibrary.simpleMessage(
      "Условия использования",
    ),
    "purchaseTraffic": MessageLookupByLibrary.simpleMessage("Лимит трафика"),
    "purchaseUnresolved": MessageLookupByLibrary.simpleMessage(
      "Требуется проверка результата",
    ),
    "purchaseUnresolvedDescription": MessageLookupByLibrary.simpleMessage(
      "Запрос был прерван. Проверьте результат перед активацией другой карты.",
    ),
    "purchaseUnsupportedAccount": MessageLookupByLibrary.simpleMessage(
      "Для активации подарочной карты используйте обычный пользовательский аккаунт.",
    ),
    "purchaseUsed": MessageLookupByLibrary.simpleMessage("Использовано"),
    "purchaseUsedPreserved": MessageLookupByLibrary.simpleMessage(
      "Использованный трафик сохраняется",
    ),
    "purchaseValidityDays": MessageLookupByLibrary.simpleMessage(
      "Срок действия (дн.)",
    ),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("Чисто черный режим"),
    "qrNotFound": MessageLookupByLibrary.simpleMessage("QR-код не найден"),
    "qrcode": MessageLookupByLibrary.simpleMessage("QR-код"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "Сканировать QR-код для получения профиля",
    ),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("Радужные"),
    "receiveSubscriptionTitle": MessageLookupByLibrary.simpleMessage(
      "Получение подписки",
    ),
    "recovery": MessageLookupByLibrary.simpleMessage("Восстановление"),
    "recoveryAll": MessageLookupByLibrary.simpleMessage(
      "Восстановить все данные",
    ),
    "recoveryProfiles": MessageLookupByLibrary.simpleMessage(
      "Только восстановление профилей",
    ),
    "recoveryStrategy": MessageLookupByLibrary.simpleMessage(
      "Стратегия восстановления",
    ),
    "recoveryStrategy_compatible": MessageLookupByLibrary.simpleMessage(
      "Совместимый",
    ),
    "recoveryStrategy_override": MessageLookupByLibrary.simpleMessage(
      "Переопределение",
    ),
    "recoverySuccess": MessageLookupByLibrary.simpleMessage(
      "Восстановление успешно",
    ),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir-порт"),
    "redo": MessageLookupByLibrary.simpleMessage("Повторить"),
    "regExp": MessageLookupByLibrary.simpleMessage("Регулярное выражение"),
    "remaining": MessageLookupByLibrary.simpleMessage("Осталось"),
    "remainingPlural": MessageLookupByLibrary.simpleMessage("Осталось"),
    "remainingSingular": MessageLookupByLibrary.simpleMessage("Остался"),
    "remote": MessageLookupByLibrary.simpleMessage("Удаленный"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование локальных данных на WebDAV",
    ),
    "remoteRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "Восстановление данных с WebDAV",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Удалить"),
    "rename": MessageLookupByLibrary.simpleMessage("Переименовать"),
    "renew": MessageLookupByLibrary.simpleMessage("Продлить"),
    "renewSubscription": MessageLookupByLibrary.simpleMessage(
      "Продлить подписку",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("Запросы"),
    "requestsDesc": MessageLookupByLibrary.simpleMessage(
      "Просмотр последних записей запросов",
    ),
    "reset": MessageLookupByLibrary.simpleMessage("Сброс"),
    "resetTip": MessageLookupByLibrary.simpleMessage(
      "Убедитесь, что хотите сбросить",
    ),
    "resources": MessageLookupByLibrary.simpleMessage("Ресурсы"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage(
      "Управление внешними ресурсами",
    ),
    "respectRules": MessageLookupByLibrary.simpleMessage("Соблюдать правила"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS-запросы следуют правилам маршрутизации (требуется настройка proxy-server-nameserver)",
    ),
    "restart": MessageLookupByLibrary.simpleMessage("Перезапустить"),
    "restartCore": MessageLookupByLibrary.simpleMessage("Перезапустить ядро"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("Адрес маршрутизации"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage(
      "Настройка адреса прослушивания маршрутизации",
    ),
    "routeMode": MessageLookupByLibrary.simpleMessage("Режим маршрутизации"),
    "routeMode_bypassPrivate": MessageLookupByLibrary.simpleMessage(
      "Обход частных адресов маршрутизации",
    ),
    "routeMode_config": MessageLookupByLibrary.simpleMessage(
      "Использовать конфигурацию",
    ),
    "ru": MessageLookupByLibrary.simpleMessage("Русский"),
    "rule": MessageLookupByLibrary.simpleMessage("По правилам"),
    "ruleName": MessageLookupByLibrary.simpleMessage("Название правила"),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("Провайдеры правил"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("Цель правила"),
    "running": MessageLookupByLibrary.simpleMessage("Запущено"),
    "runtimeConfig": MessageLookupByLibrary.simpleMessage(
      "Текущая конфигурация",
    ),
    "runtimeConfigNotAvailable": MessageLookupByLibrary.simpleMessage(
      "Конфигурация недоступна",
    ),
    "save": MessageLookupByLibrary.simpleMessage("Сохранить"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("Сохранить изменения?"),
    "saveTip": MessageLookupByLibrary.simpleMessage("Сохранить изменения?"),
    "scan": MessageLookupByLibrary.simpleMessage("Сканировать"),
    "script": MessageLookupByLibrary.simpleMessage("Скрипт"),
    "search": MessageLookupByLibrary.simpleMessage("Поиск"),
    "seconds": MessageLookupByLibrary.simpleMessage("Секунд"),
    "selectAll": MessageLookupByLibrary.simpleMessage("Выбрать все"),
    "selectProfile": MessageLookupByLibrary.simpleMessage("Выбрать профиль"),
    "selected": MessageLookupByLibrary.simpleMessage("Выбрано"),
    "selectedCountTitle": m77,
    "sendToTv": MessageLookupByLibrary.simpleMessage("Отправить на ТВ"),
    "sendToTvTitle": MessageLookupByLibrary.simpleMessage("Отправить на ТВ"),
    "sentSuccessfullyMessage": MessageLookupByLibrary.simpleMessage(
      "Отправлено успешно",
    ),
    "settings": MessageLookupByLibrary.simpleMessage("Настройки"),
    "settingsSendDeviceDataSubtitle": MessageLookupByLibrary.simpleMessage(
      "Отправлять идентификатор устройства, версию приложения и название устройства на сервер прокси-провайдера",
    ),
    "settingsSendDeviceDataTitle": MessageLookupByLibrary.simpleMessage(
      "Отправлять HWID",
    ),
    "show": MessageLookupByLibrary.simpleMessage("Показать"),
    "shrink": MessageLookupByLibrary.simpleMessage("Сжать"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("Скрытый запуск"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Запускать в свернутом виде",
    ),
    "size": MessageLookupByLibrary.simpleMessage("Размер"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socks-порт"),
    "sort": MessageLookupByLibrary.simpleMessage("Сортировка"),
    "source": MessageLookupByLibrary.simpleMessage("Источник"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("Исходный IP"),
    "stackMode": MessageLookupByLibrary.simpleMessage("Режим стека"),
    "standard": MessageLookupByLibrary.simpleMessage("Стандартный"),
    "start": MessageLookupByLibrary.simpleMessage("Старт"),
    "startVpn": MessageLookupByLibrary.simpleMessage("Запуск VPN..."),
    "status": MessageLookupByLibrary.simpleMessage("Статус"),
    "statusDesc": MessageLookupByLibrary.simpleMessage(
      "При выключении будет использоваться системный DNS",
    ),
    "stop": MessageLookupByLibrary.simpleMessage("Стоп"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("Остановка VPN..."),
    "stopped": MessageLookupByLibrary.simpleMessage("Остановлено"),
    "style": MessageLookupByLibrary.simpleMessage("Стиль"),
    "subRule": MessageLookupByLibrary.simpleMessage("Подправило"),
    "submit": MessageLookupByLibrary.simpleMessage("Отправить"),
    "subscriptionClipboardEmptyError": MessageLookupByLibrary.simpleMessage(
      "Буфер обмена пуст. Сначала скопируйте ссылку",
    ),
    "subscriptionEternal": MessageLookupByLibrary.simpleMessage(
      "Бессрочная подписка",
    ),
    "subscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "Ваша подписка истекла",
    ),
    "subscriptionExpiresInDays": m78,
    "subscriptionExpiresSoon": MessageLookupByLibrary.simpleMessage(
      "Подписка скоро истекает",
    ),
    "subscriptionExpiresToday": MessageLookupByLibrary.simpleMessage(
      "Ваша подписка истекает сегодня",
    ),
    "subscriptionImportAuthOrNotFoundError":
        MessageLookupByLibrary.simpleMessage(
          "Ссылка подписки недействительна или устарела",
        ),
    "subscriptionImportGenericError": MessageLookupByLibrary.simpleMessage(
      "Не удалось импортировать подписку. Проверьте ссылку",
    ),
    "subscriptionImportInvalidConfigError":
        MessageLookupByLibrary.simpleMessage(
          "Ссылка не содержит корректной конфигурации подписки",
        ),
    "subscriptionImportTimeoutError": MessageLookupByLibrary.simpleMessage(
      "Превышено время ожидания загрузки подписки. Проверьте сеть",
    ),
    "subscriptionUnlimited": MessageLookupByLibrary.simpleMessage(
      "Бессрочная подписка",
    ),
    "subscriptionUrlEmptyError": MessageLookupByLibrary.simpleMessage(
      "Сначала вставьте ссылку подписки",
    ),
    "subscriptionUrlInvalidError": MessageLookupByLibrary.simpleMessage(
      "Не найдена корректная http(s):// ссылка подписки",
    ),
    "successTitle": MessageLookupByLibrary.simpleMessage("Успешно"),
    "support": MessageLookupByLibrary.simpleMessage("Поддержка"),
    "supportBackupWechatToggle": MessageLookupByLibrary.simpleMessage(
      "Резервный WeChat",
    ),
    "supportComposerHint": MessageLookupByLibrary.simpleMessage(
      "Введите сообщение, Enter — отправить...",
    ),
    "supportConversationLockedNotice": MessageLookupByLibrary.simpleMessage(
      "Этот диалог завершён. Начните новый диалог, чтобы продолжить.",
    ),
    "supportMessageFailed": MessageLookupByLibrary.simpleMessage("Ошибка"),
    "supportMessageSending": MessageLookupByLibrary.simpleMessage("Отправка"),
    "supportNewConversation": MessageLookupByLibrary.simpleMessage(
      "Новый диалог",
    ),
    "supportNotConfiguredNotice": MessageLookupByLibrary.simpleMessage(
      "Онлайн-чат пока не настроен. Используйте резервные контакты WeChat ниже.",
    ),
    "supportOpenExternalFallback": MessageLookupByLibrary.simpleMessage(
      "Открыть в браузере",
    ),
    "supportRefreshTooltip": MessageLookupByLibrary.simpleMessage(
      "Обновить сообщения",
    ),
    "supportRetryAction": MessageLookupByLibrary.simpleMessage("Повторить"),
    "supportSendTooltip": MessageLookupByLibrary.simpleMessage("Отправить"),
    "supportSheetTitle": MessageLookupByLibrary.simpleMessage(
      "Онлайн-поддержка",
    ),
    "supportStatusConnected": MessageLookupByLibrary.simpleMessage(
      "Подключено",
    ),
    "supportStatusConnecting": MessageLookupByLibrary.simpleMessage(
      "Подключение",
    ),
    "supportStatusOffline": MessageLookupByLibrary.simpleMessage("Офлайн"),
    "supportTypingAnonymous": MessageLookupByLibrary.simpleMessage("Оператор"),
    "supportTypingIndicator": m79,
    "supportWelcomeFallbackSubtitle": MessageLookupByLibrary.simpleMessage(
      "Задайте любой вопрос о тарифах, узлах или подарочных картах.",
    ),
    "supportWelcomeFallbackTitle": MessageLookupByLibrary.simpleMessage(
      "Добро пожаловать в поддержку FreedomNet",
    ),
    "sync": MessageLookupByLibrary.simpleMessage("Обновление"),
    "system": MessageLookupByLibrary.simpleMessage("Система"),
    "systemApp": MessageLookupByLibrary.simpleMessage("Системное приложение"),
    "systemFont": MessageLookupByLibrary.simpleMessage("Системный шрифт"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("Системный прокси"),
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Использовать HTTP-прокси через VPN",
    ),
    "tab": MessageLookupByLibrary.simpleMessage("Вкладка"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("Анимация вкладок"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage(
      "Работает только в мобильном режиме",
    ),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("Параллельный TCP"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage(
      "Использовать параллельные TCP-соединения",
    ),
    "testAllDelay": MessageLookupByLibrary.simpleMessage("Проверить задержку"),
    "testUrl": MessageLookupByLibrary.simpleMessage("Тест URL"),
    "textScale": MessageLookupByLibrary.simpleMessage("Масштабирование текста"),
    "thanks": MessageLookupByLibrary.simpleMessage("Спасибо за вклад"),
    "theme": MessageLookupByLibrary.simpleMessage("Тема"),
    "themeAtmosphereSection": MessageLookupByLibrary.simpleMessage(
      "Текстура и анимация",
    ),
    "themeColor": MessageLookupByLibrary.simpleMessage("Цвет темы"),
    "themeCustomBgNotice": MessageLookupByLibrary.simpleMessage(
      "Обнаружены обои подписки",
    ),
    "themeDesc": MessageLookupByLibrary.simpleMessage(
      "Синхронизация неба дня и ночи, прозрачность стекла и цвет",
    ),
    "themeGlassPresetAiry": MessageLookupByLibrary.simpleMessage("Лёгкая"),
    "themeGlassPresetBalanced": MessageLookupByLibrary.simpleMessage("Баланс"),
    "themeGlassPresetLabel": MessageLookupByLibrary.simpleMessage(
      "Прозрачность карточек",
    ),
    "themeGlassPresetSolid": MessageLookupByLibrary.simpleMessage("Плотная"),
    "themeIgnoreCustomBgLabel": MessageLookupByLibrary.simpleMessage(
      "Предпочитать фон неба",
    ),
    "themeMode": MessageLookupByLibrary.simpleMessage("Режим темы"),
    "themeSkyAmbientAnimation": MessageLookupByLibrary.simpleMessage(
      "Движение облаков и звёзд",
    ),
    "themeSkyAmbientAnimationDesc": MessageLookupByLibrary.simpleMessage(
      "Останавливает фоновое движение для экономии энергии, сохраняя рассвет и закат",
    ),
    "themeSkyConsoleSection": MessageLookupByLibrary.simpleMessage(
      "Синхронизация неба",
    ),
    "themeSkyModeDay": MessageLookupByLibrary.simpleMessage(
      "Всегда ясный день",
    ),
    "themeSkyModeDayDesc": MessageLookupByLibrary.simpleMessage(
      "Сохранять светлое ясное небо даже без подключения",
    ),
    "themeSkyModeFollow": MessageLookupByLibrary.simpleMessage(
      "По подключению",
    ),
    "themeSkyModeFollowDesc": MessageLookupByLibrary.simpleMessage(
      "Ясный день при подключении, звёздная ночь без связи",
    ),
    "themeSkyModeNight": MessageLookupByLibrary.simpleMessage(
      "Всегда звёздная ночь",
    ),
    "themeSkyModeNightDesc": MessageLookupByLibrary.simpleMessage(
      "Сохранять тёмное звёздное небо даже при подключении",
    ),
    "themeSkyStatusConnecting": MessageLookupByLibrary.simpleMessage(
      "Рассвет · Подключение",
    ),
    "themeSkyStatusDayConnected": MessageLookupByLibrary.simpleMessage(
      "Ясный день · Подключено",
    ),
    "themeSkyStatusLockedDay": MessageLookupByLibrary.simpleMessage(
      "Ясный день · Закреплено",
    ),
    "themeSkyStatusLockedNight": MessageLookupByLibrary.simpleMessage(
      "Звёздная ночь · Закреплено",
    ),
    "themeSkyStatusNightDisconnected": MessageLookupByLibrary.simpleMessage(
      "Звёздная ночь · Отключено",
    ),
    "themeTextScaleDefaultDesc": MessageLookupByLibrary.simpleMessage(
      "По умолчанию системы (100%)",
    ),
    "threeColumns": MessageLookupByLibrary.simpleMessage("Три столбца"),
    "tight": MessageLookupByLibrary.simpleMessage("Плотный"),
    "time": MessageLookupByLibrary.simpleMessage("Время"),
    "tip": MessageLookupByLibrary.simpleMessage("Подсказка"),
    "toggle": MessageLookupByLibrary.simpleMessage("Переключить"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("Тональный акцент"),
    "tooFrequentOperation": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, подождите 15 секунд перед повторным обновлением",
    ),
    "tools": MessageLookupByLibrary.simpleMessage("Настройки"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxy-порт"),
    "traffic": MessageLookupByLibrary.simpleMessage("Трафик"),
    "trafficUnlimited": MessageLookupByLibrary.simpleMessage(
      "Безлимитный трафик",
    ),
    "trafficUsage": MessageLookupByLibrary.simpleMessage(
      "Использование трафика",
    ),
    "tributeDialogTitle": MessageLookupByLibrary.simpleMessage(
      "Дань уважения Open Source и благодарности",
    ),
    "tributeFlclashxBadge": MessageLookupByLibrary.simpleMessage(
      "OPEN-SOURCE HERITAGE",
    ),
    "tributeFlclashxBody": MessageLookupByLibrary.simpleMessage(
      "FreedomNet официально заявляет, что данное приложение создано на базе открытого проекта FlClashX (pluralplay/FlClashX) и экосистемы FlClash / Mihomo (Clash.Meta). Выражаем глубочайшее уважение и искреннюю благодарность авторам и всем участникам открытого сообщества.",
    ),
    "tributeFlclashxTitle": MessageLookupByLibrary.simpleMessage(
      "Создано на базе открытого проекта FlClashX",
    ),
    "tributeGeminiBadge": MessageLookupByLibrary.simpleMessage(
      "ENGINEERING & DESIGN SUPPORT",
    ),
    "tributeGeminiBody": MessageLookupByLibrary.simpleMessage(
      "Выражаем особую благодарность Gemini 4 за ключевую поддержку в архитектуре, коммерческом UI/UX-дизайне, инженерной разработке и автоматизированном тестировании FreedomNet.",
    ),
    "tributeGeminiTitle": MessageLookupByLibrary.simpleMessage(
      "Особая благодарность Gemini 4",
    ),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage(
      "Доступно только в режиме администратора",
    ),
    "tunDisableAction": MessageLookupByLibrary.simpleMessage(
      "Запросить остановку",
    ),
    "tunErrorAdapterCreate": MessageLookupByLibrary.simpleMessage(
      "Windows не смогла добавить виртуальный адаптер; повторите попытку позже",
    ),
    "tunErrorAuthorization": MessageLookupByLibrary.simpleMessage(
      "Требуются права администратора; включите повторно",
    ),
    "tunErrorComponents": MessageLookupByLibrary.simpleMessage(
      "Версии фоновых компонентов различаются; включите для обновления",
    ),
    "tunErrorConfiguration": MessageLookupByLibrary.simpleMessage(
      "Конфигурация не применена",
    ),
    "tunErrorLegacyAgent": MessageLookupByLibrary.simpleMessage(
      "Завершите старое фоновое приложение и снова откройте эту версию",
    ),
    "tunErrorProfileRequired": MessageLookupByLibrary.simpleMessage(
      "Перед подключением выберите читаемый непустой профиль",
    ),
    "tunErrorStart": MessageLookupByLibrary.simpleMessage(
      "Не удалось запустить интерфейс; включите повторно",
    ),
    "tunErrorStop": MessageLookupByLibrary.simpleMessage(
      "Не удалось остановить; проверьте состояние",
    ),
    "tunErrorUnavailable": MessageLookupByLibrary.simpleMessage(
      "Не удалось проверить состояние; проверьте версию фонового процесса",
    ),
    "tunStatusFailure": m80,
    "tunStatusOff": MessageLookupByLibrary.simpleMessage("Не запущен"),
    "tunStatusOn": MessageLookupByLibrary.simpleMessage("Запущен"),
    "tunStatusStarting": MessageLookupByLibrary.simpleMessage("Запуск…"),
    "tunStatusStopping": MessageLookupByLibrary.simpleMessage("Остановка…"),
    "tunStatusUnknown": MessageLookupByLibrary.simpleMessage(
      "Состояние неизвестно",
    ),
    "tunStatusWaiting": MessageLookupByLibrary.simpleMessage(
      "Включить при запуске прокси",
    ),
    "twoColumns": MessageLookupByLibrary.simpleMessage("Два столбца"),
    "unableToUpdateCurrentProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Невозможно обновить текущий профиль",
    ),
    "undo": MessageLookupByLibrary.simpleMessage("Отменить"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage(
      "Унифицированная задержка",
    ),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage(
      "Не учитывать дополнительные задержки (например, рукопожатие)",
    ),
    "unknown": MessageLookupByLibrary.simpleMessage("Неизвестно"),
    "unnamed": MessageLookupByLibrary.simpleMessage("Без имени"),
    "untilDate": MessageLookupByLibrary.simpleMessage("до"),
    "update": MessageLookupByLibrary.simpleMessage("Обновить"),
    "updateAllGeoData": MessageLookupByLibrary.simpleMessage(
      "Обновить все геофайлы",
    ),
    "updated": MessageLookupByLibrary.simpleMessage("Обновлено"),
    "upload": MessageLookupByLibrary.simpleMessage("Отправка"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage("Загрузить профиль по URL"),
    "urlTip": m81,
    "useHosts": MessageLookupByLibrary.simpleMessage("Использовать hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage(
      "Использовать системные hosts",
    ),
    "value": MessageLookupByLibrary.simpleMessage("Значение"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("Яркие"),
    "view": MessageLookupByLibrary.simpleMessage("Просмотр"),
    "vpnDesc": MessageLookupByLibrary.simpleMessage(
      "Изменение настроек, связанных с VPN",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически направляет весь системный трафик через VpnService",
    ),
    "vpnSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Использовать HTTP-прокси через VPN",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage(
      "Изменения вступят в силу после перезапуска VPN",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage(
      "Конфигурация WebDAV",
    ),
    "wechatId": MessageLookupByLibrary.simpleMessage("WeChat ID"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage(
      "Режим белого списка",
    ),
    "whitelistModeDesc": MessageLookupByLibrary.simpleMessage(
      "Через VPN идут только выбранные приложения; остальные — напрямую.",
    ),
    "years": MessageLookupByLibrary.simpleMessage("Лет"),
    "zashboardInApp": MessageLookupByLibrary.simpleMessage(
      "Открывать zashboard в приложении",
    ),
    "zashboardInAppDesc": MessageLookupByLibrary.simpleMessage(
      "Показывать панель во встроенном браузере, не переключаясь на внешний",
    ),
    "zh_CN": MessageLookupByLibrary.simpleMessage("Упрощенный китайский"),
  };
}
