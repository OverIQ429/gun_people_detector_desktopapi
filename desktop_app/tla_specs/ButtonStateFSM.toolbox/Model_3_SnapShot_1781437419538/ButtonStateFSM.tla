--------------------------- MODULE ButtonStateFSM ---------------------------
(*
  Формальная спецификация управления состоянием кнопок интерфейса
  из модуля desktop_app/main_window.py

  Проблема которую ищем:
  В коде кнопки блокируются в run_inference() и разблокируются
  в on_inference_finished() и on_inference_error().
  Но on_inference_error() НЕ разблокирует play_processed_button
  и save_json_button — они остаются заблокированными после ошибки.
  Также: если пользователь вызывает select_video во время обработки
  (кнопка заблокирована), video_path может быть None когда придёт
  сигнал finished.

  Спецификация проверяет:
  1. После завершения (успех или ошибка) run_button всегда разблокирован
  2. save_json_button разблокирован тогда и только тогда когда есть результат
  3. play_processed_button разблокирован тогда и только тогда
     когда есть обработанное видео
  4. Система не зависает в состоянии обработки
*)

EXTENDS Naturals, TLC

VARIABLES
    worker_state,       \* IDLE | RUNNING | DONE | ERROR
    video_path_set,     \* True если видео выбрано
    last_result_set,    \* True если last_result != None
    processed_video,    \* True если есть путь к обработанному видео
    run_btn,            \* True если кнопка активна
    select_btn,         \* True если кнопка активна
    save_json_btn,      \* True если кнопка активна
    play_processed_btn  \* True если кнопка активна

vars == <<worker_state, video_path_set, last_result_set,
          processed_video, run_btn, select_btn,
          save_json_btn, play_processed_btn>>

States == {"IDLE", "RUNNING", "DONE", "ERROR"}

TypeInvariant ==
    /\ worker_state     \in States
    /\ video_path_set   \in BOOLEAN
    /\ last_result_set  \in BOOLEAN
    /\ processed_video  \in BOOLEAN
    /\ run_btn          \in BOOLEAN
    /\ select_btn       \in BOOLEAN
    /\ save_json_btn    \in BOOLEAN
    /\ play_processed_btn \in BOOLEAN

Init ==
    /\ worker_state       = "IDLE"
    /\ video_path_set     = FALSE
    /\ last_result_set    = FALSE
    /\ processed_video    = FALSE
    /\ run_btn            = FALSE   \* отключена пока нет видео
    /\ select_btn         = TRUE
    /\ save_json_btn      = FALSE
    /\ play_processed_btn = FALSE

\* ── Пользователь выбрал видео ────────────────────────────────────
SelectVideo ==
    /\ worker_state = "IDLE"
    /\ select_btn = TRUE
    /\ video_path_set'     = TRUE
    /\ run_btn'            = TRUE   \* кнопка Run становится активной
    /\ UNCHANGED <<worker_state, last_result_set, processed_video,
                   select_btn, save_json_btn, play_processed_btn>>

\* ── Запуск детекции (run_inference) ──────────────────────────────
\* Соответствует строкам 586-633 main_window.py
StartInference ==
    /\ worker_state = "IDLE"
    /\ video_path_set = TRUE
    /\ run_btn = TRUE
    /\ worker_state'      = "RUNNING"
    /\ run_btn'           = FALSE   \* строка 586
    /\ select_btn'        = FALSE   \* строка 587
    /\ save_json_btn'     = FALSE   \* строка 588
    /\ play_processed_btn' = FALSE  \* строка 589
    /\ UNCHANGED <<video_path_set, last_result_set, processed_video>>

\* ── Успешное завершение (on_inference_finished) ──────────────────
\* Соответствует строкам 644-694 main_window.py
\* С обработанным видео
FinishWithVideo ==
    /\ worker_state = "RUNNING"
    /\ worker_state'      = "DONE"
    /\ last_result_set'   = TRUE    \* строка 645
    /\ processed_video'   = TRUE
    /\ run_btn'           = TRUE    \* строка 687
    /\ select_btn'        = TRUE    \* строка 688
    /\ save_json_btn'     = TRUE    \* строка 689
    /\ play_processed_btn' = TRUE   \* строки 691-692
    /\ UNCHANGED <<video_path_set>>

\* ── Успешное завершение без обработанного видео ──────────────────
FinishWithoutVideo ==
    /\ worker_state = "RUNNING"
    /\ worker_state'      = "DONE"
    /\ last_result_set'   = TRUE
    /\ processed_video'   = FALSE
    /\ run_btn'           = TRUE
    /\ select_btn'        = TRUE
    /\ save_json_btn'     = TRUE
    /\ play_processed_btn' = FALSE  \* не разблокируется без видео
    /\ UNCHANGED <<video_path_set>>

\* ── Завершение с ошибкой (on_inference_error) ────────────────────
\* Соответствует строкам 696-706 main_window.py
\* ВНИМАНИЕ: в реальном коде save_json_btn и play_processed_btn
\* НЕ разблокируются при ошибке — это потенциальная проблема
InferenceError ==
    /\ worker_state = "RUNNING"
    /\ worker_state'      = "ERROR"
    /\ run_btn'           = TRUE    \* строка 705
    /\ select_btn'        = TRUE    \* строка 706
    \* save_json_btn и play_processed_btn остаются FALSE
    \* last_result_set остаётся FALSE
    /\ UNCHANGED <<video_path_set, last_result_set, processed_video,
                   save_json_btn, play_processed_btn>>

\* ── Сброс для новой задачи ───────────────────────────────────────
Reset ==
    /\ worker_state \in {"DONE", "ERROR"}
    /\ worker_state'      = "IDLE"
    /\ UNCHANGED <<video_path_set, last_result_set, processed_video,
                   run_btn, select_btn, save_json_btn, play_processed_btn>>

Next ==
    \/ SelectVideo
    \/ StartInference
    \/ FinishWithVideo
    \/ FinishWithoutVideo
    \/ InferenceError
    \/ Reset

Fairness ==
    /\ WF_vars(FinishWithVideo)
    /\ WF_vars(FinishWithoutVideo)
    /\ WF_vars(InferenceError)

Spec == Init /\ [][Next]_vars /\ Fairness

\* ═══════════════════════════════════════════════════════════════
\*  ПРОВЕРЯЕМЫЕ СВОЙСТВА
\* ═══════════════════════════════════════════════════════════════

\* Safety 1: run_button активна только в IDLE и только если видео выбрано
RunButtonOnlyWhenIdle ==
    run_btn => (worker_state = "IDLE" /\ video_path_set = TRUE)

\* Safety 2: select_button заблокирована только во время обработки
SelectButtonBlockedOnlyDuringRun ==
    ~select_btn => worker_state = "RUNNING"

\* Safety 3: save_json_button активна только если есть результат
\* ОЖИДАЕМ НАРУШЕНИЕ: после ошибки save_json_btn=FALSE но last_result=FALSE
\* — это консистентно. Но если был предыдущий успех, save_json_btn
\* не должна быть активна без результата
SaveJsonConsistency ==
    save_json_btn => last_result_set

\* Safety 4: play_processed_button активна только если есть видео
PlayButtonConsistency ==
    play_processed_btn => processed_video

\* Safety 5: во время обработки кнопки заблокированы
ButtonsBlockedDuringRun ==
    worker_state = "RUNNING" =>
        (~run_btn /\ ~select_btn /\ ~save_json_btn /\ ~play_processed_btn)

\* Safety 6 — КЛЮЧЕВОЕ СВОЙСТВО:
\* После завершения (успех или ошибка) run_button ВСЕГДА активна
\* Это позволяет запустить новую задачу
RunButtonActiveAfterCompletion ==
    worker_state \in {"DONE", "ERROR"} => run_btn

\* Liveness: система не зависает в RUNNING
EventuallyNotRunning ==
    <>(worker_state # "RUNNING")

==========================================================================
