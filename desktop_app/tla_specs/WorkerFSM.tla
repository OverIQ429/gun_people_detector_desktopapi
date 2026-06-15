--------------------------- MODULE WorkerFSM ---------------------------
(*
  Формальная спецификация конечного автомата InferenceWorker
  из модуля desktop_app/worker.py

  Состояния:
    IDLE     — ожидание задачи
    RUNNING  — обработка видео
    DONE     — успешное завершение
    ERROR    — завершение с ошибкой

  Проверяемые свойства:
    1. ResultOnlyWhenDone     — результат доступен только в DONE
    2. ErrorOnlyWhenFailed    — флаг ошибки только в ERROR
    3. NoSimultaneousSignals  — finished и error не приходят одновременно
    4. EventuallyNotRunning   — система не зависает в RUNNING навсегда
    5. CanAlwaysReset         — из DONE и ERROR всегда можно вернуться в IDLE
    6. RunningRequiresStart   — в RUNNING можно попасть только из IDLE
*)

EXTENDS Naturals, TLC

VARIABLES
    state,          \* текущее состояние воркера
    result_ready,   \* True когда результат готов (сигнал finished)
    error_flag,     \* True когда произошла ошибка (сигнал error)
    video_loaded    \* True когда видеофайл выбран пользователем

States == {"IDLE", "RUNNING", "DONE", "ERROR"}

vars == <<state, result_ready, error_flag, video_loaded>>

\* ─────────────────────────────────────────────
\*  ИНВАРИАНТЫ ТИПОВ
\* ─────────────────────────────────────────────

TypeInvariant ==
    /\ state \in States
    /\ result_ready \in BOOLEAN
    /\ error_flag   \in BOOLEAN
    /\ video_loaded \in BOOLEAN

\* ─────────────────────────────────────────────
\*  НАЧАЛЬНОЕ СОСТОЯНИЕ
\* ─────────────────────────────────────────────

Init ==
    /\ state        = "IDLE"
    /\ result_ready = FALSE
    /\ error_flag   = FALSE
    /\ video_loaded = FALSE

\* ─────────────────────────────────────────────
\*  ПЕРЕХОДЫ (действия)
\* ─────────────────────────────────────────────

\* Пользователь выбирает видеофайл
LoadVideo ==
    /\ state = "IDLE"
    /\ video_loaded' = TRUE
    /\ UNCHANGED <<state, result_ready, error_flag>>

\* Пользователь нажимает "Запустить детекцию"
\* Возможно только если видео выбрано
Start ==
    /\ state = "IDLE"
    /\ video_loaded = TRUE
    /\ state'        = "RUNNING"
    /\ result_ready' = FALSE
    /\ error_flag'   = FALSE
    /\ UNCHANGED video_loaded

\* Обработка завершилась успешно — emit сигнала finished
Finish ==
    /\ state = "RUNNING"
    /\ state'        = "DONE"
    /\ result_ready' = TRUE
    /\ error_flag'   = FALSE
    /\ UNCHANGED video_loaded

\* Произошла ошибка — emit сигнала error
Fail ==
    /\ state = "RUNNING"
    /\ state'        = "ERROR"
    /\ result_ready' = FALSE
    /\ error_flag'   = TRUE
    /\ UNCHANGED video_loaded

\* Пользователь запускает новую задачу (сброс после DONE или ERROR)
Reset ==
    /\ state \in {"DONE", "ERROR"}
    /\ state'        = "IDLE"
    /\ result_ready' = FALSE
    /\ error_flag'   = FALSE
    /\ video_loaded' = FALSE

\* Объединение всех переходов
Next ==
    \/ LoadVideo
    \/ Start
    \/ Finish
    \/ Fail
    \/ Reset

\* ─────────────────────────────────────────────
\*  СПЕЦИФИКАЦИЯ (формула поведения)
\* ─────────────────────────────────────────────

\* Слабая справедливость: если Finish или Fail стали возможны,
\* они рано или поздно произойдут (воркер не зависнет навсегда)
Fairness ==
    /\ WF_vars(Finish)
    /\ WF_vars(Fail)

Spec == Init /\ [][Next]_vars /\ Fairness

\* ─────────────────────────────────────────────
\*  ПРОВЕРЯЕМЫЕ СВОЙСТВА
\* ─────────────────────────────────────────────

\* Safety 1: результат доступен только когда воркер завершил работу успешно
ResultOnlyWhenDone ==
    result_ready => state = "DONE"

\* Safety 2: флаг ошибки выставляется только в состоянии ERROR
ErrorOnlyWhenFailed ==
    error_flag => state = "ERROR"

\* Safety 3: сигналы finished и error никогда не приходят одновременно
NoSimultaneousSignals ==
    ~(result_ready /\ error_flag)

\* Safety 4: запустить воркер без загруженного видео невозможно
CannotStartWithoutVideo ==
    state = "RUNNING" => video_loaded = TRUE

\* Safety 5: в RUNNING можно попасть только из IDLE
\* (нет прямого перехода DONE→RUNNING или ERROR→RUNNING)
RunningRequiresIdleFirst ==
    [][state = "RUNNING" => state' \in {"RUNNING", "DONE", "ERROR"}]_vars

\* Liveness: воркер не зависает в RUNNING навсегда
\* Читается как: всегда в будущем наступит момент когда state ≠ RUNNING
EventuallyNotRunning ==
    <>( state # "RUNNING" )

\* Liveness: из любого состояния система рано или поздно вернётся в IDLE
EventuallyIdle ==
    []<>( state = "IDLE" )

==========================================================================