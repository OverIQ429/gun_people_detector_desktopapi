--------------------------- MODULE SettingsRaceCondition ---------------------------
(*
  Формальная спецификация гонки состояний между настройками и воркером
  из модулей desktop_app/main_window.py и desktop_app/settings_manager.py

  Проблема TOCTOU (Time Of Check To Time Of Use):
  1. Пользователь запускает детекцию — настройки читаются и сохраняются
  2. Воркер начинает работать с зафиксированными настройками
  3. Пользователь меняет настройки во время обработки
  4. save_settings() перезаписывает файл
  5. Воркер завершается и сохраняет в отчёт СТАРЫЕ настройки
  6. Но файл настроек содержит УЖЕ НОВЫЕ настройки
  => Отчёт содержит настройки которые не совпадают с текущими в файле

  Вторая проблема — конкурентный доступ к файлу истории:
  - Воркер (фоновый поток) вызывает append_history_record()
  - UI (главный поток) вызывает refresh_history() через load_history()
  - Оба читают и пишут один файл history_index.json без блокировки
  => Возможна потеря записи или чтение частично записанного файла

  Спецификация проверяет:
  [P1] Настройки в отчёте совпадают с настройками на момент запуска
  [P2] Настройки в отчёте не совпадают с текущим файлом если их меняли
  [P3] История не теряет записи при конкурентном доступе
  [P4] UI никогда не читает частично записанный индекс
*)

EXTENDS Naturals, TLC, Sequences

VARIABLES
    \* Настройки
    settings_in_file,    \* версия настроек в файле (1 или 2)
    settings_at_start,   \* настройки с которыми запущен воркер
    settings_in_report,  \* настройки которые воркер записал в отчёт

    \* Состояния потоков
    worker_state,        \* IDLE | RUNNING | SAVING | DONE
    ui_can_change,       \* True если UI может менять настройки

    \* История — конкурентный доступ
    history_records,     \* количество записей в файле
    worker_writing,      \* True если воркер пишет в файл истории
    ui_reading,          \* True если UI читает файл истории
    ui_last_read_count   \* сколько записей прочитал UI последний раз

vars == <<settings_in_file, settings_at_start, settings_in_report,
          worker_state, ui_can_change,
          history_records, worker_writing, ui_reading, ui_last_read_count>>

WorkerStates == {"IDLE", "RUNNING", "SAVING", "DONE"}
SettingsVersions == {1, 2}  \* 1 = начальные, 2 = изменённые пользователем

TypeInvariant ==
    /\ settings_in_file    \in SettingsVersions
    /\ settings_at_start   \in SettingsVersions \union {0}
    /\ settings_in_report  \in SettingsVersions \union {0}
    /\ worker_state        \in WorkerStates
    /\ ui_can_change       \in BOOLEAN
    /\ history_records     \in 0..5
    /\ worker_writing      \in BOOLEAN
    /\ ui_reading          \in BOOLEAN
    /\ ui_last_read_count  \in 0..5

Init ==
    /\ settings_in_file   = 1
    /\ settings_at_start  = 0    \* 0 = воркер ещё не запускался
    /\ settings_in_report = 0    \* 0 = отчёт ещё не сохранён
    /\ worker_state       = "IDLE"
    /\ ui_can_change      = TRUE
    /\ history_records    = 0
    /\ worker_writing     = FALSE
    /\ ui_reading         = FALSE
    /\ ui_last_read_count = 0

\* ─────────────────────────────────────────────────────────────────
\*  БЛОК 1: Гонка настроек (TOCTOU)
\* ─────────────────────────────────────────────────────────────────

\* Запуск детекции — читаем настройки из файла
\* Соответствует: run_inference() строки 575-576
StartInference ==
    /\ worker_state = "IDLE"
    /\ worker_state'      = "RUNNING"
    /\ settings_at_start' = settings_in_file  \* фиксируем текущие настройки
    /\ ui_can_change'     = TRUE  \* UI по-прежнему может менять настройки!
    /\ UNCHANGED <<settings_in_file, settings_in_report,
                   history_records, worker_writing,
                   ui_reading, ui_last_read_count>>

\* Пользователь меняет настройки во время обработки
\* Соответствует: save_settings() вызванный из вкладки Настройки
UserChangesSettings ==
    /\ ui_can_change = TRUE
    /\ worker_state  = "RUNNING"  \* именно во время обработки!
    /\ settings_in_file' = 2      \* новые настройки записаны в файл
    /\ UNCHANGED <<settings_at_start, settings_in_report,
                   worker_state, ui_can_change,
                   history_records, worker_writing,
                   ui_reading, ui_last_read_count>>

\* Воркер завершает обработку и сохраняет отчёт
\* Настройки в отчёте берутся из settings_at_start (зафиксированных при запуске)
\* Соответствует: result["settings"] = {...} в process_video()
WorkerSavesReport ==
    /\ worker_state = "RUNNING"
    /\ worker_state'      = "SAVING"
    /\ settings_in_report' = settings_at_start  \* старые настройки в отчёте
    /\ UNCHANGED <<settings_in_file, settings_at_start,
                   ui_can_change, history_records,
                   worker_writing, ui_reading, ui_last_read_count>>

\* Воркер завершился
WorkerDone ==
    /\ worker_state = "SAVING"
    /\ worker_state'  = "DONE"
    /\ ui_can_change' = TRUE
    /\ UNCHANGED <<settings_in_file, settings_at_start,
                   settings_in_report, history_records,
                   worker_writing, ui_reading, ui_last_read_count>>

\* Сброс для новой задачи
Reset ==
    /\ worker_state = "DONE"
    /\ worker_state'      = "IDLE"
    /\ settings_at_start' = 0
    /\ settings_in_report' = 0
    /\ UNCHANGED <<settings_in_file, ui_can_change,
                   history_records, worker_writing,
                   ui_reading, ui_last_read_count>>

\* ─────────────────────────────────────────────────────────────────
\*  БЛОК 2: Конкурентный доступ к файлу истории
\* ─────────────────────────────────────────────────────────────────

\* Воркер начинает запись в файл истории
\* Соответствует: append_history_record() из фонового потока
WorkerStartsWritingHistory ==
    /\ worker_state   = "SAVING"
    /\ ~worker_writing
    /\ ~ui_reading    \* нет проверки в реальном коде!
    /\ worker_writing' = TRUE
    /\ UNCHANGED <<settings_in_file, settings_at_start,
                   settings_in_report, worker_state,
                   ui_can_change, history_records,
                   ui_reading, ui_last_read_count>>

\* Воркер завершил запись
WorkerFinishesWritingHistory ==
    /\ worker_writing = TRUE
    /\ worker_writing'    = FALSE
    /\ history_records'   = history_records + 1
    /\ UNCHANGED <<settings_in_file, settings_at_start,
                   settings_in_report, worker_state,
                   ui_can_change, ui_reading, ui_last_read_count>>

\* UI читает файл истории (refresh_history из главного потока)
\* В реальном коде нет проверки что воркер не пишет в этот момент
UIStartsReadingHistory ==
    /\ ~ui_reading
    /\ ui_reading'         = TRUE
    /\ ui_last_read_count' = history_records  \* читаем текущее состояние
    /\ UNCHANGED <<settings_in_file, settings_at_start,
                   settings_in_report, worker_state,
                   ui_can_change, history_records, worker_writing>>

\* UI завершил чтение
UIFinishesReadingHistory ==
    /\ ui_reading  = TRUE
    /\ ui_reading' = FALSE
    /\ UNCHANGED <<settings_in_file, settings_at_start,
                   settings_in_report, worker_state,
                   ui_can_change, history_records,
                   worker_writing, ui_last_read_count>>

Next ==
    \/ StartInference
    \/ UserChangesSettings
    \/ WorkerSavesReport
    \/ WorkerDone
    \/ Reset
    \/ WorkerStartsWritingHistory
    \/ WorkerFinishesWritingHistory
    \/ UIStartsReadingHistory
    \/ UIFinishesReadingHistory

Fairness ==
    /\ WF_vars(WorkerSavesReport)
    /\ WF_vars(WorkerDone)

Spec == Init /\ [][Next]_vars /\ Fairness

\* ═══════════════════════════════════════════════════════════════
\*  ПРОВЕРЯЕМЫЕ СВОЙСТВА
\* ═══════════════════════════════════════════════════════════════

\* [P1] Настройки в отчёте совпадают с настройками на момент запуска
\* Это корректное поведение — отчёт должен отражать то с чем работал воркер
ReportMatchesStartSettings ==
    (settings_in_report > 0 /\ settings_at_start > 0) =>
        settings_in_report = settings_at_start

\* [P2] ГЛАВНАЯ ПРОБЛЕМА TOCTOU:
\* Настройки в файле могут НЕ совпадать с настройками в отчёте
\* Пользователь смотрит в файл настроек и не понимает почему
\* результат получился с другими параметрами
\* TLC НАЙДЁТ что это состояние достижимо
SettingsConsistency ==
    settings_in_report > 0 =>
        settings_in_report = settings_in_file

\* [P3] UI никогда не читает файл истории пока воркер пишет
\* В реальном коде эта проверка ОТСУТСТВУЕТ
\* TLC НАЙДЁТ состояние где оба активны одновременно
NoSimultaneousHistoryAccess ==
    ~(worker_writing /\ ui_reading)

\* [P4] UI всегда видит актуальное количество записей
\* Нарушение: UI прочитал файл пока воркер его не дописал
UISeesConsistentHistory ==
    ~ui_reading => ui_last_read_count <= history_records

\* [P5] Воркер завершается корректно
EventuallyDone ==
    worker_state = "RUNNING" ~> worker_state = "DONE"

==========================================================================
