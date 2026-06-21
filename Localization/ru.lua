-- Russian overrides. Keyed by the string id (already created in en.lua, which
-- loads first), so only the values that differ from English need to appear
-- here; anything omitted keeps its English text.
local strings = {
    -- Settings panel
    [SI_BMW_PANEL_NAME] = "Bureau of Material Worth",
    [SI_BMW_PANEL_DISPLAY_NAME] = "Bureau of Material Worth",
    [SI_BMW_PANEL_INTRO] = "|c6FCB9FСтоимость ремесленной сумки с первого взгляда.|r Bureau of Material Worth суммирует рыночную стоимость всего содержимого ремесленной сумки и показывает её в небольшой панели рядом с сумкой, с необязательной разбивкой по профессиям.",
    [SI_BMW_PANEL_OVERVIEW] = "|c8C8A82• Использует LibPrice (Master Merchant / Tamriel Trade Centre / Arkadius' Trade Tools)\n• Считает лениво, только пока ремесленная сумка открыта\n• Обновляется постепенно при вкладывании и извлечении материалов|r",

    [SI_BMW_HEADER_DISPLAY] = "|cC5C29EОтображение|r",
    [SI_BMW_HEADER_DIAGNOSTICS] = "|cC5C29EДиагностика|r",

    [SI_BMW_SETTING_CATEGORY_BREAKDOWN_NAME] = "Показывать разбивку по категориям",
    [SI_BMW_SETTING_CATEGORY_BREAKDOWN_TOOLTIP] = "Показывать подытоги по профессиям (кузнечное дело, алхимия, провизия и т.д.) под общей суммой. Если выключено, отображается только общая сумма.",
    [SI_BMW_SETTING_OFFSET_X_NAME] = "Смещение по горизонтали",
    [SI_BMW_SETTING_OFFSET_X_TOOLTIP] = "Точная подстройка положения окна по горизонтали относительно панели ремесленной сумки.",
    [SI_BMW_SETTING_OFFSET_Y_NAME] = "Смещение по вертикали",
    [SI_BMW_SETTING_OFFSET_Y_TOOLTIP] = "Точная подстройка положения окна по вертикали относительно панели ремесленной сумки.",
    [SI_BMW_SETTING_DEBUG_MODE_NAME] = "Режим отладки",
    [SI_BMW_SETTING_DEBUG_MODE_TOOLTIP] = "Определяет, сколько диагностических сообщений аддон выводит в чат.",
    [SI_BMW_SETTING_REFRESH_NAME] = "Обновить цены сейчас",
    [SI_BMW_SETTING_REFRESH_TOOLTIP] = "Сбросить кэш цен и пересчитать стоимость ремесленной сумки. Полезно после того, как Master Merchant или Tamriel Trade Centre завершит загрузку свежих данных.",

    -- Window
    [SI_BMW_WINDOW_TITLE] = "Стоимость сумки",
    [SI_BMW_WINDOW_SUBTITLE] = "%d стаков · %s предметов",
    [SI_BMW_WINDOW_EMPTY] = "Ремесленная сумка пуста",

    -- Window: per-category hover tooltip
    [SI_BMW_TOOLTIP_VALUE] = "Стоимость: %s золота",
    [SI_BMW_TOOLTIP_STACKS] = "Стаков: %d",
    [SI_BMW_TOOLTIP_ITEMS] = "Предметов: %s",
    [SI_BMW_TOOLTIP_UNPRICED] = "Без цены: %d стаков",

    -- Window: footer
    [SI_BMW_FOOTER_UPDATED] = "Обновлено %s",
    [SI_BMW_FOOTER_ALL_PRICED] = "Все стаки оценены",
    [SI_BMW_FOOTER_SOME_UNPRICED] = "%d из %d стаков без данных о цене",

    -- Window: relative time
    [SI_BMW_TIME_NEVER] = "никогда",
    [SI_BMW_TIME_JUST_NOW] = "только что",
    [SI_BMW_TIME_SECONDS] = "%d с назад",
    [SI_BMW_TIME_MINUTES] = "%d мин назад",
    [SI_BMW_TIME_HOURS] = "%d ч назад",

    -- Material categories
    [SI_BMW_CATEGORY_BLACKSMITHING] = "Кузнечное дело",
    [SI_BMW_CATEGORY_CLOTHIER] = "Портняжное дело",
    [SI_BMW_CATEGORY_WOODWORKING] = "Столярное дело",
    [SI_BMW_CATEGORY_JEWELRY] = "Ювелирное дело",
    [SI_BMW_CATEGORY_ALCHEMY] = "Алхимия",
    [SI_BMW_CATEGORY_ENCHANTING] = "Зачарование",
    [SI_BMW_CATEGORY_PROVISIONING] = "Провизия",
    [SI_BMW_CATEGORY_OTHER] = "Прочее",

    -- Booleans
    [SI_BMW_BOOL_TRUE] = "да",
    [SI_BMW_BOOL_FALSE] = "нет",

    -- Debug level names
    [SI_BMW_DEBUG_LEVEL_OFF] = "Выкл",
    [SI_BMW_DEBUG_LEVEL_ERRORS] = "Ошибки",
    [SI_BMW_DEBUG_LEVEL_WARNINGS] = "Предупреждения",
    [SI_BMW_DEBUG_LEVEL_INFO] = "Инфо",
    [SI_BMW_DEBUG_LEVEL_VERBOSE] = "Подробно",

    -- Log messages
    [SI_BMW_LOG_ONADDONLOADED_LOADING] = "Загрузка версии %s...",
    [SI_BMW_LOG_ADDON_LOADED] = "Аддон загружен.",
    [SI_BMW_LOG_CRAFTBAG_SHOWN] = "Ремесленная сумка открыта.",
    [SI_BMW_LOG_CRAFTBAG_HIDDEN] = "Ремесленная сумка закрыта.",
    [SI_BMW_LOG_RESCAN_DONE] = "Полный пересчёт завершён: %d ячеек, всего %s золота.",
    [SI_BMW_LOG_SLOT_UPDATED] = "Ячейка %d обновлена (вклад %s золота).",
    [SI_BMW_LOG_LAM_MISSING] = "LibAddonMenu-2.0 не найден; панель настроек недоступна.",

    -- Chat messages
    [SI_BMW_MSG_LIBPRICE_MISSING] = "LibPrice не установлен. Bureau of Material Worth требует LibPrice (и источник цен, например Master Merchant или Tamriel Trade Centre) для работы.",
    [SI_BMW_MSG_VERSION_DEBUG] = "Версия %s | Отладка: %s (%d)",
    [SI_BMW_MSG_STATUS_TOTAL] = "Стоимость ремесленной сумки: %s золота.",
    [SI_BMW_MSG_STATUS_SLOTS] = "Стаков с ценой: %d | без цены: %d.",
    [SI_BMW_MSG_REFRESH_DONE] = "Цены обновлены.",
    [SI_BMW_MSG_DEBUG_MODE_SET] = "Режим отладки: %s (%d).",
    [SI_BMW_MSG_INVALID_DEBUG_LEVEL] = "Неверный уровень отладки. Используйте число от 0 до 4.",
    [SI_BMW_MSG_SETTINGS_UNAVAILABLE] = "Панель настроек недоступна (LibAddonMenu-2.0 не найден).",
    [SI_BMW_MSG_UNKNOWN_COMMAND] = "Неизвестная команда. Введите /bmw help для списка команд.",

    -- Slash command help
    [SI_BMW_MSG_HELP_TITLE] = "|cC5C29EКоманды Bureau of Material Worth:|r",
    [SI_BMW_MSG_HELP_STATUS] = "|cFFFFFF/bmw status|r - показать текущую стоимость ремесленной сумки.",
    [SI_BMW_MSG_HELP_REFRESH] = "|cFFFFFF/bmw refresh|r - сбросить кэш цен и пересчитать.",
    [SI_BMW_MSG_HELP_SETTINGS] = "|cFFFFFF/bmw settings|r - открыть панель настроек.",
    [SI_BMW_MSG_HELP_DEBUG] = "|cFFFFFF/bmw debug <0-4>|r - задать уровень отладки в чате.",
    [SI_BMW_MSG_HELP_HELP] = "|cFFFFFF/bmw help|r - показать этот список команд.",
}

for stringId, value in pairs(strings) do
    SafeAddString(stringId, value, 1)
end
