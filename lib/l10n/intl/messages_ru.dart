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

  static String m11(node) => "Повышенная задержка узла ${node}";

  static String m12(count) => "Загружено (групп: ${count})";

  static String m13(days) => "Осталось ${days} дн.";

  static String m14(percent) => "Использовано ${percent}% трафика";

  static String m15(flag) => " · Выход ${flag}";

  static String m16(delay) => "Прямой режим · ${delay} мс";

  static String m17(node, delay, exitPart) =>
      "Узел ${node} · ${delay} мс${exitPart}";

  static String m18(available, tested, total) =>
      "Узлы: дост. ${available} / пров. ${tested} / всего ${total}";

  static String m19(count) => "Профилей: ${count}";

  static String m20(text) => "Объявление: ${text}";

  static String m21(profile, node, delay) =>
      "Автоподключение к лучшему узлу: ${profile} · ${node} (${delay} мс)";

  static String m22(profile, node, delay) =>
      "Умный выбор включён: ${profile} (лучший: ${node} · ${delay} мс)";

  static String m23(node) =>
      "Выбран узел ${node} (все узлы не прошли проверку задержки; обновите подписку или смените узел)";

  static String m24(node) =>
      "Выбран узел ${node}, но срок подписки истёк. Продлите или замените подписку";

  static String m25(node) => "Выбран узел ${node}, но трафик подписки исчерпан";

  static String m26(hours) => "Автообновление ${hours} ч.";

  static String m27(minutes) => "Автообновление ${minutes} мин.";

  static String m28(count) => "Ошибка ${count}";

  static String m29(count) => "Быстр. ${count}";

  static String m30(count) => "Медл. ${count}";

  static String m31(count) => "Не пров. ${count}";

  static String m32(completed, failed, untested, profiles) =>
      "Завершено ${completed} · Ошибок ${failed} · Не проверено ${untested} · Профилей с проблемами ${profiles}";

  static String m33(name) => "Активный: ${name}";

  static String m34(date) => "Истекает: ${date}";

  static String m35(days) => "осталось ${days} дн.";

  static String m36(hours) => "осталось ${hours} ч.";

  static String m37(count) => "Истекло: ${count}";

  static String m38(count) => "Скоро истечёт: ${count}";

  static String m39(provider) => "Файл профиля · ${provider}";

  static String m40(median) => "Медиана: ${median}";

  static String m41(median, best) => "Медиана: ${median} · Лучший: ${best}";

  static String m42(available, tested, total) =>
      "Доступно ${available} / проверено ${tested} / всего ${total}";

  static String m43(time) => "Проверка при последней активации: ${time}";

  static String m44(time) => "Синхронизация: ${time}";

  static String m45(time) => "Последняя проверка: ${time}";

  static String m46(profile, node) =>
      "Закреплён фиксированный узел: ${profile} · ${node}";

  static String m47(delay) => "Медиана: ${delay}";

  static String m48(count) => "Ещё типов проблем: ${count}";

  static String m49(available, total) => "Доступно ${available} / ${total}";

  static String m50(date) => "До ${date}";

  static String m51(count) => "Профилей: ${count}";

  static String m52(completed, total) => "${completed} / ${total}";

  static String m53(provider) => "${provider}: узлы появятся после активации";

  static String m54(profile) => "Прокси вкл · Умный: ${profile} (автоподбор)";

  static String m55(profile, node) =>
      "Прокси вкл · Умный: ${profile} · ${node}";

  static String m56(profile, node) => "Прокси включён · ${profile} · ${node}";

  static String m57(traffic) => "Остаток трафика: ${traffic}";

  static String m58(profile, node) => "Переключено на ${profile} · ${node}";

  static String m59(profile) => "Включён умный выбор: ${profile}";

  static String m60(profile, node) =>
      "Включён умный выбор: ${profile} (${node})";

  static String m61(used, total) => "Использовано ${used} из ${total}";

  static String m62(used) => "Использовано: ${used}";

  static String m63(label) => "Сейчас ${label} нет";

  static String m64(label) => "${label} должно быть числом";

  static String m65(label) => "${label} должен быть числом от 1024 до 49151";

  static String m66(plan) => "Открыт магазин для «${plan}»";

  static String m67(plan, quota, price) =>
      "Здравствуйте! Хочу приобрести код активации для тарифа «${plan} · ${quota} GiB (${price})».";

  static String m68(count) => "Осталось: ${count}";

  static String m69(code) => "Неизвестное правило (${code})";

  static String m70(count) => "Выбрано ${count} элементов";

  static String m71(days) => "Ваша подписка истекает через ${days} дн.";

  static String m72(reason) => "TUN: ${reason}";

  static String m73(label) => "${label} должен быть URL";

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
    "healthDetailOutboundRejectSelected": MessageLookupByLibrary.simpleMessage(
      "В группе выбран REJECT (блокировка)",
    ),
    "healthDetailOutboundSlow": m11,
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
    "healthDetailRuntimeSynced": m12,
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
    "healthDetailSubExpiringSoon": m13,
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
    "healthDetailSubTrafficLow": m14,
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
    "healthExitCountryPart": m15,
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
    "healthVerdictHealthyDirectSubtitle": m16,
    "healthVerdictHealthySubtitle": m17,
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
    "newDashboard": MessageLookupByLibrary.simpleMessage("Новый вид"),
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
    "nodeOverviewAllHealthCounts": m18,
    "nodeOverviewAllProfiles": MessageLookupByLibrary.simpleMessage(
      "Все профили",
    ),
    "nodeOverviewAllProfilesCount": m19,
    "nodeOverviewAmbiguousNode": MessageLookupByLibrary.simpleMessage(
      "Определения узлов повторяются; не удалось подтвердить идентичность",
    ),
    "nodeOverviewAnnouncement": m20,
    "nodeOverviewAutoConnectedBest": m21,
    "nodeOverviewAutoConnectedSmartBest": m22,
    "nodeOverviewAutoSelectedAllFailedWarning": m23,
    "nodeOverviewAutoSelectedExpiredWarning": m24,
    "nodeOverviewAutoSelectedTrafficExhaustedWarning": m25,
    "nodeOverviewAutoUpdateHours": m26,
    "nodeOverviewAutoUpdateMinutes": m27,
    "nodeOverviewAvailableFilterEmpty": MessageLookupByLibrary.simpleMessage(
      "Сейчас нет проверенных доступных узлов (не проверены или недоступны)",
    ),
    "nodeOverviewAvailableOnly": MessageLookupByLibrary.simpleMessage(
      "Только доступные",
    ),
    "nodeOverviewBandFailed": m28,
    "nodeOverviewBandFast": m29,
    "nodeOverviewBandSlow": m30,
    "nodeOverviewBandUntested": m31,
    "nodeOverviewBatchSummary": m32,
    "nodeOverviewChainUnsupported": MessageLookupByLibrary.simpleMessage(
      "Изолированная проверка цепочек прокси не поддерживается",
    ),
    "nodeOverviewCurrentActiveProfile": m33,
    "nodeOverviewCurrentProfile": MessageLookupByLibrary.simpleMessage(
      "Текущий профиль",
    ),
    "nodeOverviewDeviceLimitReached": MessageLookupByLibrary.simpleMessage(
      "Достигнут лимит устройств",
    ),
    "nodeOverviewEmptySubtitle": MessageLookupByLibrary.simpleMessage(
      "Вставьте ссылку подписки — приложение автоматически проверит задержку и подключит лучший узел",
    ),
    "nodeOverviewEmptyTitle": MessageLookupByLibrary.simpleMessage(
      "Нет добавленных подписок",
    ),
    "nodeOverviewExpireAt": m34,
    "nodeOverviewExpireDaysLeft": m35,
    "nodeOverviewExpireHoursLeft": m36,
    "nodeOverviewExpireSoon": MessageLookupByLibrary.simpleMessage(
      "менее 1 ч.",
    ),
    "nodeOverviewExpired": MessageLookupByLibrary.simpleMessage(
      "Подписка истекла",
    ),
    "nodeOverviewExpiredCountBadge": m37,
    "nodeOverviewExpiringSoonCountBadge": m38,
    "nodeOverviewFileMissing": MessageLookupByLibrary.simpleMessage(
      "Файл профиля отсутствует",
    ),
    "nodeOverviewFileSource": m39,
    "nodeOverviewGlobalMedian": m40,
    "nodeOverviewGlobalMedianAndBest": m41,
    "nodeOverviewHealthCapacityExceeded": MessageLookupByLibrary.simpleMessage(
      "Хранилище истории заполнено; часть результатов не сохранена",
    ),
    "nodeOverviewHealthCounts": m42,
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
    "nodeOverviewLastActiveTest": m43,
    "nodeOverviewLastSync": m44,
    "nodeOverviewLastTest": m45,
    "nodeOverviewLive": MessageLookupByLibrary.simpleMessage(
      "В реальном времени",
    ),
    "nodeOverviewLocalProfile": MessageLookupByLibrary.simpleMessage(
      "Локальный файл",
    ),
    "nodeOverviewLockedManualNode": m46,
    "nodeOverviewManageProfiles": MessageLookupByLibrary.simpleMessage(
      "Управление профилями / обновление подписки",
    ),
    "nodeOverviewManualSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "Фикс. IP",
    ),
    "nodeOverviewManualSelectTitle": MessageLookupByLibrary.simpleMessage(
      "Ручной выбор",
    ),
    "nodeOverviewManualUpdate": MessageLookupByLibrary.simpleMessage("Вручную"),
    "nodeOverviewMedian": m47,
    "nodeOverviewMoreIssues": m48,
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
    "nodeOverviewPickerAvailableNodes": m49,
    "nodeOverviewPickerExpireDate": m50,
    "nodeOverviewPickerPerpetual": MessageLookupByLibrary.simpleMessage(
      "Бессрочно",
    ),
    "nodeOverviewPreviewUnsupported": MessageLookupByLibrary.simpleMessage(
      "Локальные узлы провайдера не поддерживаются в этой предварительной версии",
    ),
    "nodeOverviewProfileCountBadge": m51,
    "nodeOverviewProgress": m52,
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
    "nodeOverviewProviderPending": m53,
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
    "nodeOverviewProxyConnectedSmart": m54,
    "nodeOverviewProxyConnectedSmartWithNode": m55,
    "nodeOverviewProxyConnectedWithNode": m56,
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
    "nodeOverviewRemainingTraffic": m57,
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
    "nodeOverviewSwitchedToNode": m58,
    "nodeOverviewSwitchedToSmart": m59,
    "nodeOverviewSwitchedToSmartWithNode": m60,
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
    "nodeOverviewUsedOfTotalTraffic": m61,
    "nodeOverviewUsedTrafficOnly": m62,
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
    "nullTip": m63,
    "numberTip": m64,
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
    "portTip": m65,
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
    "purchaseAcquirePlanCode": MessageLookupByLibrary.simpleMessage(
      "Получить код тарифа",
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
    "purchaseBackupContactsLabel": MessageLookupByLibrary.simpleMessage(
      "Резервная поддержка (WeChat)",
    ),
    "purchaseClearCode": MessageLookupByLibrary.simpleMessage("Очистить код"),
    "purchaseContactDescription": MessageLookupByLibrary.simpleMessage(
      "Онлайн-оплата пока недоступна. Добавьте любой из указанных аккаунтов WeChat для покупки или продления.",
    ),
    "purchaseCopyInquiry": MessageLookupByLibrary.simpleMessage(
      "Скопировать запрос",
    ),
    "purchaseEmailExistsError": MessageLookupByLibrary.simpleMessage(
      "Этот email уже зарегистрирован. Переключитесь на «Вход».",
    ),
    "purchaseFilterAll": MessageLookupByLibrary.simpleMessage("Все тарифы"),
    "purchaseFilterOnetime": MessageLookupByLibrary.simpleMessage(
      "Пакеты трафика",
    ),
    "purchaseFilterPeriod": MessageLookupByLibrary.simpleMessage("По периоду"),
    "purchaseHandoffDescription": MessageLookupByLibrary.simpleMessage(
      "Скопируйте код после покупки и вернитесь в окно — бонусы проверятся автоматически без списания.",
    ),
    "purchaseHandoffPasteAction": MessageLookupByLibrary.simpleMessage(
      "Вставить и проверить",
    ),
    "purchaseHandoffTitle": m66,
    "purchaseHeaderSyncedBadge": MessageLookupByLibrary.simpleMessage(
      "Узлы синхронизированы",
    ),
    "purchaseHeaderTrialBadge": MessageLookupByLibrary.simpleMessage(
      "2 ГиБ бесплатно при регистрации · Бессрочный трафик",
    ),
    "purchaseHidePassword": MessageLookupByLibrary.simpleMessage(
      "Скрыть пароль",
    ),
    "purchaseInquiryTemplate": m67,
    "purchaseJumpToWorkbench": MessageLookupByLibrary.simpleMessage(
      "Есть код? Перейти к активации",
    ),
    "purchaseLoginDescription": MessageLookupByLibrary.simpleMessage(
      "Войдите в аккаунт для активации кода — тариф и узлы синхронизируются автоматически.",
    ),
    "purchaseNewActivationBadge": MessageLookupByLibrary.simpleMessage(
      "Новая активация",
    ),
    "purchaseOnlineSupport": MessageLookupByLibrary.simpleMessage(
      "Онлайн-поддержка",
    ),
    "purchaseOpenNodesAction": MessageLookupByLibrary.simpleMessage(
      "Открыть профили и узлы",
    ),
    "purchasePasswordMinLength": MessageLookupByLibrary.simpleMessage(
      "Пароль должен содержать минимум 8 символов.",
    ),
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
    "purchasePlanImageNotLoaded": MessageLookupByLibrary.simpleMessage(
      "Внешнее изображение не загружено",
    ),
    "purchasePlanLowStock": m68,
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
    "purchasePlanResetUnknown": m69,
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
    "purchasePlanUnlimited": MessageLookupByLibrary.simpleMessage(
      "Без ограничений",
    ),
    "purchasePlansDescription": MessageLookupByLibrary.simpleMessage(
      "Цены указаны как на сайте. Уточните валюту и купите подарочную карту через контакты WeChat ниже, затем активируйте её здесь.",
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
    "purchaseRenewalBadge": MessageLookupByLibrary.simpleMessage("Продление"),
    "purchaseShowPassword": MessageLookupByLibrary.simpleMessage(
      "Показать пароль",
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
    "purchaseTitle": MessageLookupByLibrary.simpleMessage(
      "Покупка и продление",
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
    "selectedCountTitle": m70,
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
    "subscriptionExpiresInDays": m71,
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
    "themeColor": MessageLookupByLibrary.simpleMessage("Цвет темы"),
    "themeDesc": MessageLookupByLibrary.simpleMessage(
      "Установить темный режим, настроить цвет",
    ),
    "themeMode": MessageLookupByLibrary.simpleMessage("Режим темы"),
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
    "tunStatusFailure": m72,
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
    "urlTip": m73,
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
