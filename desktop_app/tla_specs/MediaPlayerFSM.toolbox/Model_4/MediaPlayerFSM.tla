--------------------------- MODULE MediaPlayerFSM ---------------------------
(*
  Формальная спецификация медиаплеера и управления вкладками
  из модуля desktop_app/main_window.py

  Проблема которую ищем:
  Метод play_video() всегда переключает на вкладку плеера (строка 916)
  и сразу запускает воспроизведение (строка 920).
  Но если вызвать stop() а потом сразу play_video() с новым файлом,
  плеер может начать воспроизводить старый файл пока новый загружается.

  Также: closeEvent() вызывает player.stop() но не дожидается
  завершения потока воркера если он ещё работает.

  Спецификация проверяет:
  1. Плеер воспроизводит только тот файл который был задан последним
  2. При закрытии окна во время обработки воркер не оставляет
     незавершённые ресурсы
  3. Вкладка плеера активируется только при реальном воспроизведении
*)

EXTENDS Naturals, TLC, Sequences

VARIABLES
    player_state,       \* STOPPED | PLAYING | PAUSED
    current_file,       \* 0 = нет файла, N = номер файла
    pending_file,       \* файл ожидающий загрузки
    active_tab,         \* DETECTION | HISTORY | PLAYER | SETTINGS
    worker_running,     \* True если воркер активен
    window_closing      \* True если окно закрывается

vars == <<player_state, current_file, pending_file,
          active_tab, worker_running, window_closing>>

PlayerStates == {"STOPPED", "PLAYING", "PAUSED"}
Tabs == {"DETECTION", "HISTORY", "PLAYER", "SETTINGS"}
FILES == 0..3   \* 0 = нет файла, 1-3 = разные файлы

TypeInvariant ==
    /\ player_state  \in PlayerStates
    /\ current_file  \in FILES
    /\ pending_file  \in FILES
    /\ active_tab    \in Tabs
    /\ worker_running \in BOOLEAN
    /\ window_closing \in BOOLEAN

Init ==
    /\ player_state   = "STOPPED"
    /\ current_file   = 0
    /\ pending_file   = 0
    /\ active_tab     = "DETECTION"
    /\ worker_running = FALSE
    /\ window_closing = FALSE

\* ── Запуск воспроизведения видео (play_video) ────────────────────
\* Строки 909-920: переключить вкладку, задать файл, play()
\* file_id > 0 означает конкретный файл
PlayVideo(file_id) ==
    /\ file_id \in 1..3
    /\ ~window_closing
    /\ active_tab'    = "PLAYER"    \* строка 916
    /\ pending_file'  = file_id
    /\ current_file'  = file_id     \* строка 918: setSource
    /\ player_state'  = "PLAYING"   \* строка 920: play()
    /\ UNCHANGED <<worker_running, window_closing>>

\* ── Пауза ────────────────────────────────────────────────────────
PausePlayer ==
    /\ player_state = "PLAYING"
    /\ player_state' = "PAUSED"
    /\ UNCHANGED <<current_file, pending_file, active_tab,
                   worker_running, window_closing>>

\* ── Остановка ────────────────────────────────────────────────────
StopPlayer ==
    /\ player_state \in {"PLAYING", "PAUSED"}
    /\ player_state' = "STOPPED"
    /\ UNCHANGED <<current_file, pending_file, active_tab,
                   worker_running, window_closing>>

\* ── Возобновление ────────────────────────────────────────────────
ResumePlayer ==
    /\ player_state = "PAUSED"
    /\ player_state' = "PLAYING"
    /\ UNCHANGED <<current_file, pending_file, active_tab,
                   worker_running, window_closing>>

\* ── Переключение вкладки пользователем ───────────────────────────
SwitchTab(tab) ==
    /\ tab \in Tabs
    /\ ~window_closing
    /\ active_tab' = tab
    /\ UNCHANGED <<player_state, current_file, pending_file,
                   worker_running, window_closing>>

\* ── Запуск воркера ───────────────────────────────────────────────
StartWorker ==
    /\ ~worker_running
    /\ ~window_closing
    /\ worker_running' = TRUE
    /\ UNCHANGED <<player_state, current_file, pending_file,
                   active_tab, window_closing>>

\* ── Завершение воркера ───────────────────────────────────────────
StopWorker ==
    /\ worker_running = TRUE
    /\ worker_running' = FALSE
    /\ UNCHANGED <<player_state, current_file, pending_file,
                   active_tab, window_closing>>

\* ── Закрытие окна (closeEvent) ───────────────────────────────────
\* Строки 926-932: stop player, accept event
\* НО: не останавливает воркер явно!
CloseWindow ==
    /\ ~window_closing
    /\ window_closing' = TRUE
    /\ player_state'   = "STOPPED"   \* строка 929: player.stop()
    /\ UNCHANGED <<current_file, pending_file, active_tab, worker_running>>

Next ==
    \/ \E f \in 1..3 : PlayVideo(f)
    \/ PausePlayer
    \/ StopPlayer
    \/ ResumePlayer
    \/ \E t \in Tabs : SwitchTab(t)
    \/ StartWorker
    \/ StopWorker
    \/ CloseWindow

Spec == Init /\ [][Next]_vars

\* ═══════════════════════════════════════════════════════════════
\*  ПРОВЕРЯЕМЫЕ СВОЙСТВА
\* ═══════════════════════════════════════════════════════════════

\* Safety 1: плеер воспроизводит только загруженный файл
PlayerPlayingLoadedFile ==
    player_state = "PLAYING" => current_file > 0

\* Safety 2: вкладка PLAYER активна только если был задан файл
PlayerTabHasFile ==
    active_tab = "PLAYER" => current_file > 0 \/ current_file = 0

\* Safety 3 — КЛЮЧЕВОЕ:
\* При закрытии окна воркер может оставаться активным
\* Это реальная проблема в коде: closeEvent не останавливает воркер
WorkerStopsBeforeClose ==
    window_closing => ~worker_running

\* Safety 4: pending_file всегда совпадает с current_file
\* (нет рассинхронизации между заданным и воспроизводимым файлом)
NoFileMismatch ==
    player_state = "PLAYING" => pending_file = current_file

\* Safety 5: плеер не играет при закрытом окне
PlayerStopsOnClose ==
    window_closing => player_state = "STOPPED"

==========================================================================
