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

  static String m0(label) =>
      "Вы уверены, что хотите удалить выбранные ${label}?";

  static String m1(label) => "Вы уверены, что хотите удалить текущий ${label}?";

  static String m2(label) => "${label} не может быть пустым";

  static String m3(label) => "Текущий ${label} уже существует";

  static String m4(text) => "Объявление: ${text}";

  static String m5(hours) => "Автообновление ${hours} ч.";

  static String m6(minutes) => "Автообновление ${minutes} мин.";

  static String m7(completed, failed, untested, profiles) =>
      "Завершено ${completed} · Ошибок ${failed} · Не проверено ${untested} · Профилей с проблемами ${profiles}";

  static String m8(date) => "Истекает: ${date}";

  static String m9(days) => "осталось ${days} дн.";

  static String m10(hours) => "осталось ${hours} ч.";

  static String m11(provider) => "Файл профиля · ${provider}";

  static String m12(available, tested, total) =>
      "Доступно ${available} / проверено ${tested} / всего ${total}";

  static String m13(time) => "Проверка при последней активации: ${time}";

  static String m14(time) => "Синхронизация: ${time}";

  static String m15(time) => "Последняя проверка: ${time}";

  static String m16(delay) => "Медиана: ${delay}";

  static String m17(count) => "Ещё типов проблем: ${count}";

  static String m18(available, total) => "Доступно ${available} / ${total}";

  static String m19(date) => "До ${date}";

  static String m20(count) => "Профилей: ${count}";

  static String m21(completed, total) => "${completed} / ${total}";

  static String m22(provider) => "${provider}: узлы появятся после активации";

  static String m23(traffic) => "Остаток трафика: ${traffic}";

  static String m24(profile, node) => "Переключено на ${profile} · ${node}";

  static String m25(used, total) => "Использовано ${used} из ${total}";

  static String m26(used) => "Использовано: ${used}";

  static String m27(label) => "Сейчас ${label} нет";

  static String m28(label) => "${label} должно быть числом";

  static String m29(label) => "${label} должен быть числом от 1024 до 49151";

  static String m30(plan, quota, price) =>
      "Здравствуйте! Хочу приобрести код активации для тарифа «${plan} · ${quota} GiB (${price})».";

  static String m31(count) => "Осталось: ${count}";

  static String m32(code) => "Неизвестное правило (${code})";

  static String m33(count) => "Выбрано ${count} элементов";

  static String m34(days) => "Ваша подписка истекает через ${days} дн.";

  static String m35(reason) => "TUN: ${reason}";

  static String m36(label) => "${label} должен быть URL";

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
    "day": MessageLookupByLibrary.simpleMessage("день"),
    "days": MessageLookupByLibrary.simpleMessage("дней"),
    "daysGenitive": MessageLookupByLibrary.simpleMessage("дня"),
    "defaultNameserver": MessageLookupByLibrary.simpleMessage(
      "Сервер имен по умолчанию",
    ),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Для разрешения DNS-сервера",
    ),
    "defaultSort": MessageLookupByLibrary.simpleMessage(
      "Сортировка по умолчанию",
    ),
    "defaultText": MessageLookupByLibrary.simpleMessage("По умолчанию"),
    "delay": MessageLookupByLibrary.simpleMessage("Задержка"),
    "delaySort": MessageLookupByLibrary.simpleMessage("Сортировка по задержке"),
    "delete": MessageLookupByLibrary.simpleMessage("Удалить"),
    "deleteMultipTip": m0,
    "deleteTip": m1,
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
    "emptyTip": m2,
    "en": MessageLookupByLibrary.simpleMessage("Английский"),
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
    "existsTip": m3,
    "exit": MessageLookupByLibrary.simpleMessage("Выход"),
    "expand": MessageLookupByLibrary.simpleMessage("Стандартный"),
    "expandAll": MessageLookupByLibrary.simpleMessage("Развернуть всё"),
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
    "go": MessageLookupByLibrary.simpleMessage("Перейти"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Перейти к загрузке"),
    "goToSelected": MessageLookupByLibrary.simpleMessage("К выбранному"),
    "gratitude": MessageLookupByLibrary.simpleMessage("Благодарность"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Сохранить изменения в кэше?",
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
    "importFromURL": MessageLookupByLibrary.simpleMessage("Импорт из URL"),
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
    "nodeOverviewAllProfiles": MessageLookupByLibrary.simpleMessage(
      "Все профили",
    ),
    "nodeOverviewAmbiguousNode": MessageLookupByLibrary.simpleMessage(
      "Определения узлов повторяются; не удалось подтвердить идентичность",
    ),
    "nodeOverviewAnnouncement": m4,
    "nodeOverviewAutoUpdateHours": m5,
    "nodeOverviewAutoUpdateMinutes": m6,
    "nodeOverviewAvailableOnly": MessageLookupByLibrary.simpleMessage(
      "Только доступные",
    ),
    "nodeOverviewBatchSummary": m7,
    "nodeOverviewChainUnsupported": MessageLookupByLibrary.simpleMessage(
      "Изолированная проверка цепочек прокси не поддерживается",
    ),
    "nodeOverviewCurrentProfile": MessageLookupByLibrary.simpleMessage(
      "Текущий профиль",
    ),
    "nodeOverviewDeviceLimitReached": MessageLookupByLibrary.simpleMessage(
      "Достигнут лимит устройств",
    ),
    "nodeOverviewExpireAt": m8,
    "nodeOverviewExpireDaysLeft": m9,
    "nodeOverviewExpireHoursLeft": m10,
    "nodeOverviewExpireSoon": MessageLookupByLibrary.simpleMessage(
      "менее 1 ч.",
    ),
    "nodeOverviewExpired": MessageLookupByLibrary.simpleMessage(
      "Подписка истекла",
    ),
    "nodeOverviewFileMissing": MessageLookupByLibrary.simpleMessage(
      "Файл профиля отсутствует",
    ),
    "nodeOverviewFileSource": m11,
    "nodeOverviewHealthCapacityExceeded": MessageLookupByLibrary.simpleMessage(
      "Хранилище истории заполнено; часть результатов не сохранена",
    ),
    "nodeOverviewHealthCounts": m12,
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
    "nodeOverviewLastActiveTest": m13,
    "nodeOverviewLastSync": m14,
    "nodeOverviewLastTest": m15,
    "nodeOverviewLive": MessageLookupByLibrary.simpleMessage(
      "В реальном времени",
    ),
    "nodeOverviewLocalProfile": MessageLookupByLibrary.simpleMessage(
      "Локальный файл",
    ),
    "nodeOverviewManageProfiles": MessageLookupByLibrary.simpleMessage(
      "Управление профилями / обновление подписки",
    ),
    "nodeOverviewManualUpdate": MessageLookupByLibrary.simpleMessage("Вручную"),
    "nodeOverviewMedian": m16,
    "nodeOverviewMoreIssues": m17,
    "nodeOverviewNeverExpires": MessageLookupByLibrary.simpleMessage(
      "Истекает: бессрочно",
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
    "nodeOverviewPickerAvailableNodes": m18,
    "nodeOverviewPickerExpireDate": m19,
    "nodeOverviewPickerPerpetual": MessageLookupByLibrary.simpleMessage(
      "Бессрочно",
    ),
    "nodeOverviewPreviewUnsupported": MessageLookupByLibrary.simpleMessage(
      "Локальные узлы провайдера не поддерживаются в этой предварительной версии",
    ),
    "nodeOverviewProfileCountBadge": m20,
    "nodeOverviewProgress": m21,
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
    "nodeOverviewProviderPending": m22,
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
    "nodeOverviewQuickUse": MessageLookupByLibrary.simpleMessage(
      "Использовать",
    ),
    "nodeOverviewRemainingTraffic": m23,
    "nodeOverviewRuntimeSource": MessageLookupByLibrary.simpleMessage(
      "Активный узел",
    ),
    "nodeOverviewSelectProfileTitle": MessageLookupByLibrary.simpleMessage(
      "Выбор профиля",
    ),
    "nodeOverviewStale": MessageLookupByLibrary.simpleMessage(
      "Возможно, устарело",
    ),
    "nodeOverviewStatusExpired": MessageLookupByLibrary.simpleMessage("Истёк"),
    "nodeOverviewStrictUnsupported": MessageLookupByLibrary.simpleMessage(
      "В строгом режиме изолированные проверки недоступны",
    ),
    "nodeOverviewSwitchedToNode": m24,
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
    "nodeOverviewTypeUnsupported": MessageLookupByLibrary.simpleMessage(
      "Изолированная проверка этого протокола не поддерживается",
    ),
    "nodeOverviewUntested": MessageLookupByLibrary.simpleMessage(
      "Не проверено",
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
    "nodeOverviewUsedOfTotalTraffic": m25,
    "nodeOverviewUsedTrafficOnly": m26,
    "none": MessageLookupByLibrary.simpleMessage("Нет"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "Текущая группа прокси недоступна для выбора",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Профиль отсутствует. Пожалуйста, добавьте профиль",
    ),
    "nullScriptTip": MessageLookupByLibrary.simpleMessage(
      "Скрипты отсутствуют",
    ),
    "nullTip": m27,
    "numberTip": m28,
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
    "portTip": m29,
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
    "purchaseAvailablePlans": MessageLookupByLibrary.simpleMessage(
      "Доступные тарифы",
    ),
    "purchaseClearCode": MessageLookupByLibrary.simpleMessage("Очистить код"),
    "purchaseContactDescription": MessageLookupByLibrary.simpleMessage(
      "Онлайн-оплата пока недоступна. Добавьте любой из указанных аккаунтов WeChat для покупки или продления.",
    ),
    "purchaseCopyInquiry": MessageLookupByLibrary.simpleMessage(
      "Скопировать запрос",
    ),
    "purchaseFilterAll": MessageLookupByLibrary.simpleMessage("Все тарифы"),
    "purchaseFilterOnetime": MessageLookupByLibrary.simpleMessage(
      "Пакеты трафика",
    ),
    "purchaseFilterPeriod": MessageLookupByLibrary.simpleMessage("По периоду"),
    "purchaseHidePassword": MessageLookupByLibrary.simpleMessage(
      "Скрыть пароль",
    ),
    "purchaseInquiryTemplate": m30,
    "purchaseJumpToWorkbench": MessageLookupByLibrary.simpleMessage(
      "Есть код? Перейти к активации",
    ),
    "purchaseLoginDescription": MessageLookupByLibrary.simpleMessage(
      "Войдите в аккаунт для активации кода — тариф и узлы синхронизируются автоматически.",
    ),
    "purchaseNewActivationBadge": MessageLookupByLibrary.simpleMessage(
      "Новая активация",
    ),
    "purchaseOpenNodesAction": MessageLookupByLibrary.simpleMessage(
      "Открыть профили и узлы",
    ),
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
    "purchasePlanImageNotLoaded": MessageLookupByLibrary.simpleMessage(
      "Внешнее изображение не загружено",
    ),
    "purchasePlanLowStock": m31,
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
    "purchasePlanResetUnknown": m32,
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
    "purchasePlansLoading": MessageLookupByLibrary.simpleMessage(
      "Загрузка тарифов…",
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
    "selectedCountTitle": m33,
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
    "subscriptionEternal": MessageLookupByLibrary.simpleMessage(
      "Бессрочная подписка",
    ),
    "subscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "Ваша подписка истекла",
    ),
    "subscriptionExpiresInDays": m34,
    "subscriptionExpiresSoon": MessageLookupByLibrary.simpleMessage(
      "Подписка скоро истекает",
    ),
    "subscriptionExpiresToday": MessageLookupByLibrary.simpleMessage(
      "Ваша подписка истекает сегодня",
    ),
    "subscriptionUnlimited": MessageLookupByLibrary.simpleMessage(
      "Бессрочная подписка",
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
    "tunStatusFailure": m35,
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
    "urlTip": m36,
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
