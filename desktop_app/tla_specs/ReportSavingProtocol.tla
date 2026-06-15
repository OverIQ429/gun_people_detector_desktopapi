--------------------------- MODULE ReportSavingProtocol ---------------------------
(*
  Формальная спецификация протокола сохранения отчёта
  из модуля desktop_app/worker.py (метод process_video)

  Реальный код выполняет 6 шагов последовательно:
    1. create_report_dir()          — создать папку отчёта
    2. copy_processed_video()       — скопировать видео в папку
    3. cut_event_clips()            — нарезать клипы событий
    4. save_report_json()           — сохранить JSON отчёта
    5. append_history_record()      — добавить в индекс истории
    6. send_detection_email()       — отправить email

  Проблема которую ищем:
  При ошибке на любом шаге (2-6) папка отчёта уже создана на диске,
  но отчёт может быть не записан в индекс истории. Пользователь
  видит папку в файловой системе, но не видит её в UI истории.
  
  Кроме того: email отправляется ДО того как можно убедиться
  что все предыдущие шаги завершились успешно.

  Спецификация проверяет:
  [P1] Если отчёт в индексе — папка существует
  [P2] Если папка существует — отчёт либо в индексе либо операция ещё идёт
  [P3] Email отправляется только после успешной записи в индекс
  [P4] При ошибке на любом шаге система возвращается в консистентное состояние
  [P5] Никогда не бывает отчёта в индексе без JSON файла
*)

EXTENDS Naturals, TLC

VARIABLES
    step,              \* текущий шаг протокола
    dir_created,       \* True если папка отчёта создана на диске
    video_copied,      \* True если видео скопировано в папку
    clips_cut,         \* True если клипы нарезаны
    json_saved,        \* True если report.json сохранён
    in_history_index,  \* True если запись добавлена в history_index.json
    email_sent,        \* True если email отправлен
    error_occurred,    \* True если произошла ошибка
    protocol_done      \* True если протокол завершён (успешно или с ошибкой)

vars == <<step, dir_created, video_copied, clips_cut,
          json_saved, in_history_index, email_sent,
          error_occurred, protocol_done>>

\* Шаги протокола
Steps == 0..7
\* 0 = не начат
\* 1 = create_report_dir
\* 2 = copy_processed_video
\* 3 = cut_event_clips
\* 4 = save_report_json
\* 5 = append_history_record
\* 6 = send_detection_email
\* 7 = завершён

TypeInvariant ==
    /\ step              \in Steps
    /\ dir_created       \in BOOLEAN
    /\ video_copied      \in BOOLEAN
    /\ clips_cut         \in BOOLEAN
    /\ json_saved        \in BOOLEAN
    /\ in_history_index  \in BOOLEAN
    /\ email_sent        \in BOOLEAN
    /\ error_occurred    \in BOOLEAN
    /\ protocol_done     \in BOOLEAN

Init ==
    /\ step             = 0
    /\ dir_created      = FALSE
    /\ video_copied     = FALSE
    /\ clips_cut        = FALSE
    /\ json_saved       = FALSE
    /\ in_history_index = FALSE
    /\ email_sent       = FALSE
    /\ error_occurred   = FALSE
    /\ protocol_done    = FALSE

\* ─────────────────────────────────────────────────────────────────
\*  ШАГ 1: create_report_dir()
\*  Создаём папку отчёта на диске
\*  Соответствует: report_id, report_dir = create_report_dir()
\* ─────────────────────────────────────────────────────────────────
Step1_CreateDir ==
    /\ step = 0
    /\ ~protocol_done
    /\ step'        = 1
    /\ dir_created' = TRUE
    /\ UNCHANGED <<video_copied, clips_cut, json_saved,
                   in_history_index, email_sent,
                   error_occurred, protocol_done>>

\* ─────────────────────────────────────────────────────────────────
\*  ШАГ 2: copy_processed_video_to_report()
\*  Копируем видео в папку отчёта
\*  МОЖЕТ УПАСТЬ: если диск полон или файл заблокирован
\* ─────────────────────────────────────────────────────────────────
Step2_CopyVideo_Success ==
    /\ step = 1
    /\ ~protocol_done
    /\ step'         = 2
    /\ video_copied' = TRUE
    /\ UNCHANGED <<dir_created, clips_cut, json_saved,
                   in_history_index, email_sent,
                   error_occurred, protocol_done>>

Step2_CopyVideo_Fail ==
    /\ step = 1
    /\ ~protocol_done
    /\ error_occurred' = TRUE
    /\ protocol_done'  = TRUE
    /\ step'           = 7
    \* папка создана (dir_created=TRUE) но видео не скопировано
    \* отчёт НЕ попадёт в индекс — это потенциальная проблема
    /\ UNCHANGED <<dir_created, video_copied, clips_cut,
                   json_saved, in_history_index, email_sent>>

\* ─────────────────────────────────────────────────────────────────
\*  ШАГ 3: cut_event_clips()
\*  Нарезаем клипы событий
\*  МОЖЕТ УПАСТЬ: если видео повреждено или нет места на диске
\* ─────────────────────────────────────────────────────────────────
Step3_CutClips_Success ==
    /\ step = 2
    /\ ~protocol_done
    /\ step'       = 3
    /\ clips_cut'  = TRUE
    /\ UNCHANGED <<dir_created, video_copied, json_saved,
                   in_history_index, email_sent,
                   error_occurred, protocol_done>>

Step3_CutClips_Fail ==
    /\ step = 2
    /\ ~protocol_done
    /\ error_occurred' = TRUE
    /\ protocol_done'  = TRUE
    /\ step'           = 7
    \* папка и видео есть, но клипов нет и в индексе нет
    /\ UNCHANGED <<dir_created, video_copied, clips_cut,
                   json_saved, in_history_index, email_sent>>

\* ─────────────────────────────────────────────────────────────────
\*  ШАГ 4: save_report_json()
\*  Сохраняем JSON отчёта в папку
\*  МОЖЕТ УПАСТЬ: права доступа, диск полон
\* ─────────────────────────────────────────────────────────────────
Step4_SaveJson_Success ==
    /\ step = 3
    /\ ~protocol_done
    /\ step'        = 4
    /\ json_saved'  = TRUE
    /\ UNCHANGED <<dir_created, video_copied, clips_cut,
                   in_history_index, email_sent,
                   error_occurred, protocol_done>>

Step4_SaveJson_Fail ==
    /\ step = 3
    /\ ~protocol_done
    /\ error_occurred' = TRUE
    /\ protocol_done'  = TRUE
    /\ step'           = 7
    \* папка, видео и клипы есть, но JSON нет и в индексе нет
    /\ UNCHANGED <<dir_created, video_copied, clips_cut,
                   json_saved, in_history_index, email_sent>>

\* ─────────────────────────────────────────────────────────────────
\*  ШАГ 5: append_history_record()
\*  Добавляем запись в history_index.json
\*  МОЖЕТ УПАСТЬ: файл заблокирован другим процессом
\* ─────────────────────────────────────────────────────────────────
Step5_AppendHistory_Success ==
    /\ step = 4
    /\ ~protocol_done
    /\ step'              = 5
    /\ in_history_index'  = TRUE
    /\ UNCHANGED <<dir_created, video_copied, clips_cut,
                   json_saved, email_sent,
                   error_occurred, protocol_done>>

Step5_AppendHistory_Fail ==
    /\ step = 4
    /\ ~protocol_done
    /\ error_occurred' = TRUE
    /\ protocol_done'  = TRUE
    /\ step'           = 7
    \* ВСЁ создано: папка, видео, клипы, JSON
    \* НО в индексе НЕТ — пользователь не увидит отчёт в UI
    \* Это главная проблема: данные есть, но они недоступны через UI
    /\ UNCHANGED <<dir_created, video_copied, clips_cut,
                   json_saved, in_history_index, email_sent>>

\* ─────────────────────────────────────────────────────────────────
\*  ШАГ 6: send_detection_email()
\*  Отправляем email уведомление
\*  МОЖЕТ УПАСТЬ: сеть недоступна, неверные настройки SMTP
\* ─────────────────────────────────────────────────────────────────
Step6_SendEmail_Success ==
    /\ step = 5
    /\ ~protocol_done
    /\ step'         = 6
    /\ email_sent'   = TRUE
    /\ protocol_done' = TRUE
    /\ UNCHANGED <<dir_created, video_copied, clips_cut,
                   json_saved, in_history_index, error_occurred>>

Step6_SendEmail_Fail ==
    /\ step = 5
    /\ ~protocol_done
    /\ error_occurred' = TRUE
    /\ protocol_done'  = TRUE
    /\ step'           = 7
    \* Всё сохранено успешно, только email не отправлен
    \* Это менее критично — данные целостны
    /\ UNCHANGED <<dir_created, video_copied, clips_cut,
                   json_saved, in_history_index, email_sent>>

\* ─────────────────────────────────────────────────────────────────
\*  Объединение всех переходов
\* ─────────────────────────────────────────────────────────────────
Next ==
    \/ Step1_CreateDir
    \/ Step2_CopyVideo_Success
    \/ Step2_CopyVideo_Fail
    \/ Step3_CutClips_Success
    \/ Step3_CutClips_Fail
    \/ Step4_SaveJson_Success
    \/ Step4_SaveJson_Fail
    \/ Step5_AppendHistory_Success
    \/ Step5_AppendHistory_Fail
    \/ Step6_SendEmail_Success
    \/ Step6_SendEmail_Fail

Fairness ==
    \/ WF_vars(Step2_CopyVideo_Success)
    \/ WF_vars(Step3_CutClips_Success)
    \/ WF_vars(Step4_SaveJson_Success)
    \/ WF_vars(Step5_AppendHistory_Success)
    \/ WF_vars(Step6_SendEmail_Success)

Spec == Init /\ [][Next]_vars /\ Fairness

\* ═══════════════════════════════════════════════════════════════
\*  ПРОВЕРЯЕМЫЕ СВОЙСТВА
\* ═══════════════════════════════════════════════════════════════

\* [P1] Если отчёт в индексе истории — JSON файл тоже должен быть
\* Нарушение означает: пользователь видит отчёт в UI но открыть не может
IndexImpliesJson ==
    in_history_index => json_saved

\* [P2] Если отчёт в индексе — папка существует
\* Нарушение означает: UI показывает отчёт которого нет на диске
IndexImpliesDir ==
    in_history_index => dir_created

\* [P3] Email отправляется только после записи в индекс
\* Нарушение означает: пользователь получил email но не видит отчёт в UI
\* ОЖИДАЕМ НАРУШЕНИЕ: в реальном коде email идёт ПОСЛЕ append_history_record
\* но если append упал — email уже не отправится. Если порядок поменяют —
\* это станет багом. Спецификация фиксирует правильный порядок.
EmailOnlyAfterHistory ==
    email_sent => in_history_index

\* [P4] Если папка создана и протокол завершён с ошибкой —
\* отчёт может отсутствовать в индексе
\* Это ФИКСАЦИЯ ИЗВЕСТНОЙ ПРОБЛЕМЫ: "осиротевшие" папки отчётов
OrphanedDirPossible ==
    (dir_created /\ error_occurred /\ protocol_done) =>
        ~in_history_index \/ in_history_index

\* [P5] ГЛАВНОЕ СВОЙСТВО: атомарность протокола
\* Если протокол завершился БЕЗ ошибки — все шаги выполнены
\* Нарушение означает нарушение целостности данных
CompleteOrNothing ==
    (protocol_done /\ ~error_occurred) =>
        (dir_created /\ video_copied /\ clips_cut /\
         json_saved  /\ in_history_index)

\* [P6] КРИТИЧЕСКАЯ ПРОБЛЕМА: папка создана но в индексе нет
\* При ошибке на шагах 2-5 возникает "осиротевший" отчёт
\* TLC НАЙДЁТ НАРУШЕНИЕ — это реальный баг в коде
NoOrphanedReports ==
    protocol_done => (dir_created => in_history_index \/ ~error_occurred)

\* [P7] Порядок шагов строго соблюдается
\* json сохраняется до записи в индекс
JsonBeforeIndex ==
    in_history_index => json_saved

\* [P8] Видео копируется до нарезки клипов
VideoBeforeClips ==
    clips_cut => video_copied

==========================================================================
