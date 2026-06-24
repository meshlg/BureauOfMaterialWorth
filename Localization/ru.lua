-- Russian overrides. Keyed by the string id (already created in en.lua, which
-- loads first), so only the values that differ from English need to appear
-- here; anything omitted keeps its English text.
local strings = {
    -- Settings panel
    [SI_BMW_PANEL_NAME] = "Bureau of Material Worth",
    [SI_BMW_PANEL_DISPLAY_NAME] = "|c6FCB9FBureau|r of Material Worth",
    [SI_BMW_PANEL_INTRO] = "|c6FCB9FСтоимость ремесленной сумки с первого взгляда.|r Bureau of Material Worth суммирует рыночную стоимость всего содержимого ремесленной сумки и показывает её в небольшой панели рядом с сумкой, с необязательной разбивкой по профессиям.",
    [SI_BMW_PANEL_OVERVIEW] = "|c8C8A82• Использует LibPrice (Master Merchant / Tamriel Trade Centre / Arkadius' Trade Tools)\n• Считает лениво, только пока ремесленная сумка открыта\n• Обновляется постепенно при вкладывании и извлечении материалов|r",

    [SI_BMW_HEADER_DISPLAY] = "|cC5C29EОтображение|r",
    [SI_BMW_HEADER_DIAGNOSTICS] = "|cC5C29EДиагностика|r",

    [SI_BMW_SETTING_CATEGORY_BREAKDOWN_NAME] = "Показывать разбивку по категориям",
    [SI_BMW_SETTING_CATEGORY_BREAKDOWN_TOOLTIP] = "Показывать подытоги по профессиям (кузнечное дело, алхимия, провизия и т.д.) под общей суммой. Если выключено, отображается только общая сумма.",
    [SI_BMW_SETTING_CATEGORY_ICONS_NAME] = "Показывать иконки категорий",
    [SI_BMW_SETTING_CATEGORY_ICONS_TOOLTIP] = "Показывать небольшую иконку профессии слева от названия каждой категории, чтобы строки читались быстрее. У «Прочего» нет профессии - иконка не отображается.",
    [SI_BMW_SETTING_COLOR_SCALE_NAME] = "Окрашивать золото по стоимости",
    [SI_BMW_SETTING_COLOR_SCALE_TOOLTIP] = "Подкрашивать сумму золота каждой категории в зависимости от величины - от тусклого для малых сумм до яркого для самых больших - чтобы самые ценные категории были заметны сразу. Если выключено, все суммы используют один золотой оттенок.",
    [SI_BMW_SETTING_SORT_BY_VALUE_NAME] = "Сортировать категории по стоимости",
    [SI_BMW_SETTING_SORT_BY_VALUE_TOOLTIP] = "Упорядочивать строки категорий по убыванию стоимости в золоте, чтобы самые ценные запасы всегда были сверху. Если выключено, используется фиксированный порядок профессий.",
    [SI_BMW_SETTING_DELTA_MODE_NAME] = "База для «с прошлого визита»",
    [SI_BMW_SETTING_DELTA_MODE_TOOLTIP] = "С чем сравнивается строка изменения стоимости в футере. «Каждый визит»: с предыдущим открытием ремесленной сумки (сохраняется между перезапусками). «Каждую сессию»: с первым открытием после входа в игру или перезагрузки интерфейса, так что изменение накапливается до выхода или /reloadui. В обоих режимах чисто ценовое изменение (те же материалы, обновлённые цены) не показывает дельту.",
    [SI_BMW_SETTING_DELTA_MODE_VISIT] = "Каждый визит",
    [SI_BMW_SETTING_DELTA_MODE_SESSION] = "Каждую сессию",
    [SI_BMW_SETTING_BACKGROUND_NAME] = "Показывать фон",
    [SI_BMW_SETTING_BACKGROUND_TOOLTIP] = "Рисовать тёмный фон панели за текстом. Выключите для простого текста поверх ремесленной сумки.",
    [SI_BMW_SETTING_BORDER_NAME] = "Показывать рамку",
    [SI_BMW_SETTING_BORDER_TOOLTIP] = "Рисовать рамку панели. Выключите для более чистого вида без рамки.",
    [SI_BMW_SETTING_VALUE_HISTORY_NAME] = "Показывать историю стоимости",
    [SI_BMW_SETTING_VALUE_HISTORY_TOOLTIP] = "Рисовать внизу панели небольшой график стоимости ремесленной сумки во времени. Одна точка записывается при каждом открытии сумки (не чаще раза в несколько часов), хранятся последние 90 точек. Наведите курсор на график, чтобы увидеть самое старое, самое новое значения и итоговое изменение.",
    [SI_BMW_SETTING_NOTIFY_VISIT_NAME] = "Сообщать стоимость в чат",
    [SI_BMW_SETTING_NOTIFY_VISIT_TOOLTIP] = "Выводить стоимость ремесленной сумки в чат при первом открытии за сессию, вместе с изменением с прошлого визита (когда запас менялся). Выключите, чтобы не выводить ничего в чат.",
    [SI_BMW_SETTING_WIDTH_NAME] = "Ширина окна",
    [SI_BMW_SETTING_WIDTH_TOOLTIP] = "Ширина панели стоимости в пикселях. Увеличьте, если длинные названия категорий или большие суммы золота выглядят тесно.",
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
    -- %d = занятые ячейки (уникальные материалы), %s = классические стаки по 200,
    -- %s = общее число предметов.
    [SI_BMW_WINDOW_SUBTITLE] = "%d ячеек · %s стаков · %s предметов",
    [SI_BMW_WINDOW_EMPTY] = "Ремесленная сумка пуста",

    -- Window: per-category hover tooltip
    [SI_BMW_TOOLTIP_VALUE] = "Стоимость: %s золота",
    [SI_BMW_TOOLTIP_SLOTS] = "Ячеек (уникальных материалов): %d",
    [SI_BMW_TOOLTIP_STACKS] = "Стаков по 200: %s",
    [SI_BMW_TOOLTIP_ITEMS] = "Предметов: %s",
    [SI_BMW_TOOLTIP_UNPRICED] = "Без цены: %d ячеек",
    [SI_BMW_TOOLTIP_CLICK_HINT] = "Нажмите для полного списка материалов",

    -- Detail window: per-category material table (opened by clicking a row)
    [SI_BMW_DETAIL_TITLE] = "%s - материалы",
    [SI_BMW_DETAIL_COL_NAME] = "Материал",
    [SI_BMW_DETAIL_COL_QTY] = "Кол-во",
    [SI_BMW_DETAIL_COL_VALUE] = "Стоимость",
    [SI_BMW_DETAIL_COL_CUM] = "Накоп. %",
    [SI_BMW_DETAIL_CUM] = "%d%%",
    [SI_BMW_DETAIL_CUM_TOOLTIP_TITLE] = "Накопленная доля",
    [SI_BMW_DETAIL_CUM_TOOLTIP_BODY] = "Доля каждого материала в общей стоимости этого списка, считается от самого дорогого вниз - поэтому число не меняется, как бы вы ни сортировали таблицу. Читайте его на виде |cFFF897по стоимости|r (по умолчанию): строки примерно до 80% - это те немногие стопки, что дают основную ценность, их и вези на продажу в первую очередь, остальное можно не трогать. Итоговые 100% всегда приходятся на самый дешёвый материал. Материалы без цены не учитываются и показывают прочерк.",
    [SI_BMW_DETAIL_COL_CHANGE] = "Изменение",
    [SI_BMW_DETAIL_GROWTH] = "%s%%",
    [SI_BMW_DETAIL_GROWTH_NEW] = "-",
    [SI_BMW_DETAIL_EMPTY] = "В этой категории нет материалов.",
    [SI_BMW_DETAIL_SEARCH_HINT] = "Поиск...",
    [SI_BMW_DETAIL_SEARCH_TITLE] = "Результаты поиска",

    -- Snapshot + diff view
    [SI_BMW_DETAIL_BTN_REMEMBER] = "Запомнить",
    [SI_BMW_DETAIL_BTN_REMEMBER_TOOLTIP_TITLE] = "Запомнить состав",
    [SI_BMW_DETAIL_BTN_REMEMBER_TOOLTIP_BODY] = "Вручную сохранить снимок текущего содержимого ремесленной сумки. Позже нажмите «Изменения», чтобы увидеть, что добавилось, убыло или изменилось. Снимок один - повторное нажатие перезаписывает его.",
    [SI_BMW_DETAIL_BTN_CHANGES] = "Изменения",
    [SI_BMW_DETAIL_BTN_CHANGES_TOOLTIP_TITLE] = "Изменения с момента снимка",
    [SI_BMW_DETAIL_BTN_CHANGES_TOOLTIP_BODY] = "Показать, как изменилась ремесленная сумка с момента сохранённого снимка: какие материалы добавились, убыли или изменились в количестве, и стоимость каждого движения в золоте. Сначала нажмите «Запомнить», чтобы сделать снимок.",
    [SI_BMW_DETAIL_BTN_BACK] = "Назад",
    [SI_BMW_DETAIL_BTN_BACK_TOOLTIP_TITLE] = "Назад к материалам",
    [SI_BMW_DETAIL_BTN_BACK_TOOLTIP_BODY] = "Вернуться из вида изменений к списку материалов.",
    [SI_BMW_DETAIL_DIFF_TITLE] = "Изменения с %s",
    [SI_BMW_DETAIL_DIFF_EMPTY] = "С момента снимка ничего не изменилось.",
    [SI_BMW_DETAIL_NO_SNAPSHOT] = "Снимок ещё не сделан. Нажмите «Запомнить».",
    [SI_BMW_DETAIL_COL_QTY_DELTA] = "Кол-во +/-",
    [SI_BMW_DETAIL_COL_VALUE_DELTA] = "Стоим. +/-",
    [SI_BMW_DETAIL_COL_SHARE] = "Доля",
    [SI_BMW_DETAIL_COL_STATUS] = "Статус",
    [SI_BMW_DETAIL_STATUS_NEW] = "новый",
    [SI_BMW_DETAIL_STATUS_GONE] = "убыл",
    [SI_BMW_DETAIL_STATUS_CHANGED] = "изменён",
    [SI_BMW_DETAIL_QTY_DELTA] = "%s%s",

    -- Withdraw dialog
    [SI_BMW_WITHDRAW_TITLE] = "Извлечь: %s",
    [SI_BMW_WITHDRAW_FREE_SLOTS] = "Свободных ячеек в сумке: %d",
    [SI_BMW_WITHDRAW_MAX] = "Максимум к извлечению: %s",
    [SI_BMW_WITHDRAW_TOTAL_VALUE] = "Общая стоимость: %s",
    [SI_BMW_WITHDRAW_QTY_LABEL] = "Количество",
    [SI_BMW_WITHDRAW_PRESET_STACK] = "%d стак",
    [SI_BMW_WITHDRAW_PRESET_STACKS] = "%d стаков",
    [SI_BMW_WITHDRAW_CONFIRM] = "Извлечь",
    [SI_BMW_WITHDRAW_CANCEL] = "Отмена",
    [SI_BMW_WITHDRAW_BACKPACK_FULL] = "Сумка переполнена",
    [SI_BMW_WITHDRAW_PROGRESS] = "Извлечение... %d / %d",
    [SI_BMW_WITHDRAW_HINT] = "ЛКМ: извлечь    ПКМ: в очередь",

    -- Withdraw queue
    [SI_BMW_QUEUE_TITLE] = "Очередь извлечения",
    [SI_BMW_QUEUE_EMPTY] = "Нажмите ПКМ на материалах, чтобы добавить их в очередь.",
    [SI_BMW_QUEUE_SLOTS] = "Нужно ячеек: %d / свободно %d",
    [SI_BMW_QUEUE_TOTAL] = "Стоимость очереди: %s",
    [SI_BMW_QUEUE_WITHDRAW_ALL] = "Извлечь всё",
    [SI_BMW_QUEUE_CLEAR] = "Очистить",

    -- Window: footer (two-column label -> value rows)
    [SI_BMW_FOOTER_UPDATED_LABEL] = "Обновлено",
    [SI_BMW_FOOTER_COVERAGE_LABEL] = "Покрытие",
    [SI_BMW_FOOTER_COVERAGE_VALUE] = "%d/%d с ценой",
    [SI_BMW_FOOTER_LOW_COVERAGE] = "%d/%d без цены!",
    [SI_BMW_FOOTER_DELTA_LABEL] = "За визит",
    [SI_BMW_FOOTER_DELTA_LABEL_SESSION] = "За сессию",
    [SI_BMW_FOOTER_DELTA_VALUE] = "%s золота",
    [SI_BMW_FOOTER_HISTORY_LABEL] = "История стоимости",
    [SI_BMW_HISTORY_TOOLTIP_POINTS] = "Записано точек: %d",
    [SI_BMW_HISTORY_TOOLTIP_OLDEST] = "Самая старая: %s золота",
    [SI_BMW_HISTORY_TOOLTIP_NEWEST] = "Самая новая: %s золота",
    [SI_BMW_HISTORY_TOOLTIP_CHANGE] = "Изменение: %s золота",

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
    [SI_BMW_MSG_STATUS_SLOTS] = "Ячеек с ценой: %d | без цены: %d.",
    [SI_BMW_MSG_VISIT_DELTA] = "Ремесленная сумка стоит %s золота (%s%s с прошлого визита).",
    [SI_BMW_MSG_VISIT_TOTAL] = "Ремесленная сумка стоит %s золота.",
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
