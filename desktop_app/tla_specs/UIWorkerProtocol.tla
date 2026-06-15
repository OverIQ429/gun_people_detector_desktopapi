--------------------------- MODULE UIWorkerProtocol ---------------------------
(*
  Р¤РѕСЂРјР°Р»СЊРЅР°СЏ СЃРїРµС†РёС„РёРєР°С†РёСЏ РїСЂРѕС‚РѕРєРѕР»Р° РІР·Р°РёРјРѕРґРµР№СЃС‚РІРёСЏ
  РјРµР¶РґСѓ РіР»Р°РІРЅС‹Рј РѕРєРЅРѕРј (MainWindow) Рё РІРѕСЂРєРµСЂРѕРј (InferenceWorker)
  РёР· РјРѕРґСѓР»РµР№ desktop_app/main_window.py Рё desktop_app/worker.py

  РњРѕРґРµР»РёСЂСѓРµРј РґРІР° РїР°СЂР°Р»Р»РµР»СЊРЅС‹С… РїСЂРѕС†РµСЃСЃР°:
    UI    вЂ” РіР»Р°РІРЅРѕРµ РѕРєРЅРѕ, СЂРµР°РіРёСЂСѓРµС‚ РЅР° РґРµР№СЃС‚РІРёСЏ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ
    Worker вЂ” РїРѕС‚РѕРє РѕР±СЂР°Р±РѕС‚РєРё РІРёРґРµРѕ, РёСЃРїСѓСЃРєР°РµС‚ СЃРёРіРЅР°Р»С‹

  РџСЂРѕРІРµСЂСЏРµРјС‹Рµ СЃРІРѕР№СЃС‚РІР°:
    1. NoDoubleStart       вЂ” РЅРµР»СЊР·СЏ Р·Р°РїСѓСЃС‚РёС‚СЊ РґРІР° РІРѕСЂРєРµСЂР° РѕРґРЅРѕРІСЂРµРјРµРЅРЅРѕ
    2. ResultConsistency   вЂ” UI РїРѕРєР°Р·С‹РІР°РµС‚ СЂРµР·СѓР»СЊС‚Р°С‚ С‚РѕР»СЊРєРѕ РєРѕРіРґР° РѕРЅ РіРѕС‚РѕРІ
    3. NoLostSignals       вЂ” РєР°Р¶РґС‹Р№ СЃРёРіРЅР°Р» РІРѕСЂРєРµСЂР° РѕР±СЂР°Р±Р°С‚С‹РІР°РµС‚СЃСЏ UI
    4. UIAlwaysResponsive  вЂ” UI РЅРµ Р±Р»РѕРєРёСЂСѓРµС‚СЃСЏ РЅР°РІСЃРµРіРґР°
    5. SafeAbort           вЂ” РїСЂРµСЂС‹РІР°РЅРёРµ РѕР±СЂР°Р±РѕС‚РєРё РЅРµ РѕСЃС‚Р°РІР»СЏРµС‚ СЃРёСЃС‚РµРјСѓ
                             РІ РЅРµРєРѕСЂСЂРµРєС‚РЅРѕРј СЃРѕСЃС‚РѕСЏРЅРёРё
    6. SignalHandledOnce   вЂ” РєР°Р¶РґС‹Р№ СЃРёРіРЅР°Р» РѕР±СЂР°Р±Р°С‚С‹РІР°РµС‚СЃСЏ СЂРѕРІРЅРѕ РѕРґРёРЅ СЂР°Р·
*)

EXTENDS Naturals, TLC, Sequences

VARIABLES
    ui_state,       \* СЃРѕСЃС‚РѕСЏРЅРёРµ РіР»Р°РІРЅРѕРіРѕ РѕРєРЅР°
    worker_state,   \* СЃРѕСЃС‚РѕСЏРЅРёРµ РІРѕСЂРєРµСЂР°
    signal_queue,   \* РѕС‡РµСЂРµРґСЊ СЃРёРіРЅР°Р»РѕРІ РѕС‚ РІРѕСЂРєРµСЂР° Рє UI
    result_stored,  \* True РµСЃР»Рё СЂРµР·СѓР»СЊС‚Р°С‚ СЃРѕС…СЂР°РЅС‘РЅ РІ UI
    abort_requested \* True РµСЃР»Рё РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ Р·Р°РїСЂРѕСЃРёР» РїСЂРµСЂС‹РІР°РЅРёРµ

\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\*  РњРќРћР–Р•РЎРўР’Рђ Р”РћРџРЈРЎРўР�РњР«РҐ Р—РќРђР§Р•РќР�Р™
\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

UIStates     == {"IDLE", "RUNNING", "SHOWING_RESULT", "SHOWING_ERROR"}
WorkerStates == {"IDLE", "PROCESSING", "DONE", "FAILED", "ABORTED"}
Signals      == {"finished", "error", "aborted", "none"}

vars == <<ui_state, worker_state, signal_queue,
          result_stored, abort_requested>>

\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\*  Р�РќР’РђР Р�РђРќРў РўР�РџРћР’
\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

TypeInvariant ==
    /\ ui_state        \in UIStates
    /\ worker_state    \in WorkerStates
    /\ signal_queue    \in Seq(Signals)
    /\ result_stored   \in BOOLEAN
    /\ abort_requested \in BOOLEAN

\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\*  РќРђР§РђР›Р¬РќРћР• РЎРћРЎРўРћРЇРќР�Р•
\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

Init ==
    /\ ui_state        = "IDLE"
    /\ worker_state    = "IDLE"
    /\ signal_queue    = <<>>
    /\ result_stored   = FALSE
    /\ abort_requested = FALSE

\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\*  Р”Р•Р™РЎРўР’Р�РЇ UI
\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

\* РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ РЅР°Р¶Р°Р» "Р—Р°РїСѓСЃС‚РёС‚СЊ РґРµС‚РµРєС†РёСЋ"
\* UI РїРµСЂРµС…РѕРґРёС‚ РІ RUNNING Рё Р·Р°РїСѓСЃРєР°РµС‚ РІРѕСЂРєРµСЂ
UserStartsDetection ==
    /\ ui_state     = "IDLE"
    /\ worker_state = "IDLE"
    /\ ui_state'        = "RUNNING"
    /\ worker_state'    = "PROCESSING"
    /\ abort_requested' = FALSE
    /\ UNCHANGED <<signal_queue, result_stored>>

\* РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ Р·Р°РїСЂРѕСЃРёР» РїСЂРµСЂС‹РІР°РЅРёРµ РІРѕ РІСЂРµРјСЏ РѕР±СЂР°Р±РѕС‚РєРё
UserRequestsAbort ==
    /\ ui_state        = "RUNNING"
    /\ worker_state    = "PROCESSING"
    /\ abort_requested' = TRUE
    /\ UNCHANGED <<ui_state, worker_state, signal_queue, result_stored>>

\* UI РѕР±СЂР°Р±РѕС‚Р°Р» СЃРёРіРЅР°Р» finished вЂ” РїРѕРєР°Р·С‹РІР°РµС‚ СЂРµР·СѓР»СЊС‚Р°С‚
UIHandlesFinished ==
    /\ ui_state     = "RUNNING"
    /\ Len(signal_queue) > 0
    /\ Head(signal_queue) = "finished"
    /\ ui_state'      = "SHOWING_RESULT"
    /\ result_stored' = TRUE
    /\ signal_queue'  = Tail(signal_queue)
    /\ UNCHANGED <<worker_state, abort_requested>>

\* UI РѕР±СЂР°Р±РѕС‚Р°Р» СЃРёРіРЅР°Р» error вЂ” РїРѕРєР°Р·С‹РІР°РµС‚ РѕС€РёР±РєСѓ
UIHandlesError ==
    /\ ui_state     = "RUNNING"
    /\ Len(signal_queue) > 0
    /\ Head(signal_queue) = "error"
    /\ ui_state'      = "SHOWING_ERROR"
    /\ result_stored' = FALSE
    /\ signal_queue'  = Tail(signal_queue)
    /\ UNCHANGED <<worker_state, abort_requested>>

\* UI РѕР±СЂР°Р±РѕС‚Р°Р» СЃРёРіРЅР°Р» aborted вЂ” РІРѕР·РІСЂР°С‚ РІ IDLE
UIHandlesAborted ==
    /\ ui_state     = "RUNNING"
    /\ Len(signal_queue) > 0
    /\ Head(signal_queue) = "aborted"
    /\ ui_state'      = "IDLE"
    /\ result_stored' = FALSE
    /\ signal_queue'  = Tail(signal_queue)
    /\ UNCHANGED <<worker_state, abort_requested>>

\* РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ Р·Р°РєСЂС‹Р» СЂРµР·СѓР»СЊС‚Р°С‚ вЂ” РІРѕР·РІСЂР°С‚ РІ IDLE
UserDismissesResult ==
    /\ ui_state \in {"SHOWING_RESULT", "SHOWING_ERROR"}
    /\ ui_state'      = "IDLE"
    /\ result_stored' = FALSE
    /\ UNCHANGED <<worker_state, signal_queue, abort_requested>>

\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\*  Р”Р•Р™РЎРўР’Р�РЇ Р’РћР РљР•Р Рђ
\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

\* Р’РѕСЂРєРµСЂ СѓСЃРїРµС€РЅРѕ Р·Р°РІРµСЂС€РёР» РѕР±СЂР°Р±РѕС‚РєСѓ вЂ” РёСЃРїСѓСЃРєР°РµС‚ finished
WorkerFinishes ==
    /\ worker_state    = "PROCESSING"
    /\ abort_requested = FALSE
    /\ worker_state' = "DONE"
    /\ signal_queue' = Append(signal_queue, "finished")
    /\ UNCHANGED <<ui_state, result_stored, abort_requested>>

\* Р’РѕСЂРєРµСЂ Р·Р°РІРµСЂС€РёР»СЃСЏ СЃ РѕС€РёР±РєРѕР№ вЂ” РёСЃРїСѓСЃРєР°РµС‚ error
WorkerFails ==
    /\ worker_state = "PROCESSING"
    /\ worker_state' = "FAILED"
    /\ signal_queue' = Append(signal_queue, "error")
    /\ UNCHANGED <<ui_state, result_stored, abort_requested>>

\* Р’РѕСЂРєРµСЂ РѕР±СЂР°Р±РѕС‚Р°Р» Р·Р°РїСЂРѕСЃ РїСЂРµСЂС‹РІР°РЅРёСЏ вЂ” РёСЃРїСѓСЃРєР°РµС‚ aborted
WorkerAborts ==
    /\ worker_state    = "PROCESSING"
    /\ abort_requested = TRUE
    /\ worker_state' = "ABORTED"
    /\ signal_queue' = Append(signal_queue, "aborted")
    /\ UNCHANGED <<ui_state, result_stored, abort_requested>>

\* Р’РѕСЂРєРµСЂ СЃР±СЂР°СЃС‹РІР°РµС‚СЃСЏ РІ IDLE (РіРѕС‚РѕРІ Рє РЅРѕРІРѕР№ Р·Р°РґР°С‡Рµ)
WorkerResets ==
    /\ worker_state \in {"DONE", "FAILED", "ABORTED"}
    /\ ui_state     \in {"IDLE", "SHOWING_RESULT", "SHOWING_ERROR"}
    /\ worker_state' = "IDLE"
    /\ UNCHANGED <<ui_state, signal_queue, result_stored, abort_requested>>

\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\*  РћР‘РЄР•Р”Р�РќР•РќР�Р• Р’РЎР•РҐ РџР•Р Р•РҐРћР”РћР’
\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

Next ==
    \/ UserStartsDetection
    \/ UserRequestsAbort
    \/ UIHandlesFinished
    \/ UIHandlesError
    \/ UIHandlesAborted
    \/ UserDismissesResult
    \/ WorkerFinishes
    \/ WorkerFails
    \/ WorkerAborts
    \/ WorkerResets

\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\*  FAIRNESS
\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

Fairness ==
    /\ WF_vars(WorkerFinishes)
    /\ WF_vars(WorkerFails)
    /\ WF_vars(WorkerAborts)
    /\ WF_vars(UIHandlesFinished)
    /\ WF_vars(UIHandlesError)
    /\ WF_vars(UIHandlesAborted)

Spec == Init /\ [][Next]_vars /\ Fairness

\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\*  РџР РћР’Р•Р РЇР•РњР«Р• РЎР’РћР™РЎРўР’Рђ
\* в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

\* Safety 1: РЅРµР»СЊР·СЏ Р·Р°РїСѓСЃС‚РёС‚СЊ РґРІР° РІРѕСЂРєРµСЂР° РѕРґРЅРѕРІСЂРµРјРµРЅРЅРѕ
\* Р•СЃР»Рё UI РІ RUNNING вЂ” РІРѕСЂРєРµСЂ РѕР±СЏР·Р°РЅ Р±С‹С‚СЊ РІ РѕРґРЅРѕРј РёР· СЂР°Р±РѕС‡РёС… СЃРѕСЃС‚РѕСЏРЅРёР№
NoDoubleStart ==
    ui_state = "RUNNING" =>
        worker_state \in {"PROCESSING", "DONE", "FAILED", "ABORTED"}

\* Safety 2: СЂРµР·СѓР»СЊС‚Р°С‚ РїРѕРєР°Р·С‹РІР°РµС‚СЃСЏ С‚РѕР»СЊРєРѕ РєРѕРіРґР° РѕРЅ РґРµР№СЃС‚РІРёС‚РµР»СЊРЅРѕ РіРѕС‚РѕРІ
\* result_stored=TRUE С‚РѕР»СЊРєРѕ РµСЃР»Рё РІРѕСЂРєРµСЂ Р·Р°РІРµСЂС€РёР»СЃСЏ СѓСЃРїРµС€РЅРѕ
ResultConsistency ==
    result_stored => ui_state = "SHOWING_RESULT"

\* Safety 3: РѕС‡РµСЂРµРґСЊ СЃРёРіРЅР°Р»РѕРІ РЅРµ СЂР°СЃС‚С‘С‚ Р±РµСЃРєРѕРЅРµС‡РЅРѕ
\* (РЅРµ Р±РѕР»РµРµ РѕРґРЅРѕРіРѕ РЅРµРѕР±СЂР°Р±РѕС‚Р°РЅРЅРѕРіРѕ СЃРёРіРЅР°Р»Р° РѕРґРЅРѕРІСЂРµРјРµРЅРЅРѕ)
QueueBoundedByOne ==
    Len(signal_queue) <= 1

\* Safety 4: UI РЅРёРєРѕРіРґР° РЅРµ РїРѕРєР°Р·С‹РІР°РµС‚ СЂРµР·СѓР»СЊС‚Р°С‚ Рё РѕС€РёР±РєСѓ РѕРґРЅРѕРІСЂРµРјРµРЅРЅРѕ
NoResultAndError ==
    ~(ui_state = "SHOWING_RESULT" /\ worker_state = "FAILED")

\* Safety 5: РїСЂРµСЂС‹РІР°РЅРёРµ РЅРµ РїСЂРёРІРѕРґРёС‚ Рє РїРѕРєР°Р·Сѓ СЂРµР·СѓР»СЊС‚Р°С‚Р°
AbortNeverShowsResult ==
    abort_requested => ui_state # "SHOWING_RESULT"

\* Liveness 1: UI СЂР°РЅРѕ РёР»Рё РїРѕР·РґРЅРѕ РїРѕРєРёРґР°РµС‚ СЃРѕСЃС‚РѕСЏРЅРёРµ RUNNING
UIEventuallyNotRunning ==
    [](ui_state = "RUNNING" => <>(ui_state # "RUNNING"))

SignalHandledOnlyWhenRunning ==
    [][Len(signal_queue) > 0 => ui_state = "RUNNING"]_vars

SignalsEventuallyHandled ==
    \A s \in {1} : <>(Len(signal_queue) = 0)

==========================================================================
