--------------------------- MODULE ButtonStateFSM ---------------------------
(*
  Р¤РѕСЂРјР°Р»СЊРЅР°СЏ СЃРїРµС†РёС„РёРєР°С†РёСЏ СѓРїСЂР°РІР»РµРЅРёСЏ СЃРѕСЃС‚РѕСЏРЅРёРµРј РєРЅРѕРїРѕРє РёРЅС‚РµСЂС„РµР№СЃР°
  РёР· РјРѕРґСѓР»СЏ desktop_app/main_window.py

  РџСЂРѕР±Р»РµРјР° РєРѕС‚РѕСЂСѓСЋ РёС‰РµРј:
  Р’ РєРѕРґРµ РєРЅРѕРїРєРё Р±Р»РѕРєРёСЂСѓСЋС‚СЃСЏ РІ run_inference() Рё СЂР°Р·Р±Р»РѕРєРёСЂСѓСЋС‚СЃСЏ
  РІ on_inference_finished() Рё on_inference_error().
  РќРѕ on_inference_error() РќР• СЂР°Р·Р±Р»РѕРєРёСЂСѓРµС‚ play_processed_button
  Рё save_json_button вЂ” РѕРЅРё РѕСЃС‚Р°СЋС‚СЃСЏ Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅРЅС‹РјРё РїРѕСЃР»Рµ РѕС€РёР±РєРё.
  РўР°РєР¶Рµ: РµСЃР»Рё РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ РІС‹Р·С‹РІР°РµС‚ select_video РІРѕ РІСЂРµРјСЏ РѕР±СЂР°Р±РѕС‚РєРё
  (РєРЅРѕРїРєР° Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅР°), video_path РјРѕР¶РµС‚ Р±С‹С‚СЊ None РєРѕРіРґР° РїСЂРёРґС‘С‚
  СЃРёРіРЅР°Р» finished.

  РЎРїРµС†РёС„РёРєР°С†РёСЏ РїСЂРѕРІРµСЂСЏРµС‚:
  1. РџРѕСЃР»Рµ Р·Р°РІРµСЂС€РµРЅРёСЏ (СѓСЃРїРµС… РёР»Рё РѕС€РёР±РєР°) run_button РІСЃРµРіРґР° СЂР°Р·Р±Р»РѕРєРёСЂРѕРІР°РЅ
  2. save_json_button СЂР°Р·Р±Р»РѕРєРёСЂРѕРІР°РЅ С‚РѕРіРґР° Рё С‚РѕР»СЊРєРѕ С‚РѕРіРґР° РєРѕРіРґР° РµСЃС‚СЊ СЂРµР·СѓР»СЊС‚Р°С‚
  3. play_processed_button СЂР°Р·Р±Р»РѕРєРёСЂРѕРІР°РЅ С‚РѕРіРґР° Рё С‚РѕР»СЊРєРѕ С‚РѕРіРґР°
     РєРѕРіРґР° РµСЃС‚СЊ РѕР±СЂР°Р±РѕС‚Р°РЅРЅРѕРµ РІРёРґРµРѕ
  4. РЎРёСЃС‚РµРјР° РЅРµ Р·Р°РІРёСЃР°РµС‚ РІ СЃРѕСЃС‚РѕСЏРЅРёРё РѕР±СЂР°Р±РѕС‚РєРё
*)

EXTENDS Naturals, TLC

VARIABLES
    worker_state,       \* IDLE | RUNNING | DONE | ERROR
    video_path_set,     \* True РµСЃР»Рё РІРёРґРµРѕ РІС‹Р±СЂР°РЅРѕ
    last_result_set,    \* True РµСЃР»Рё last_result != None
    processed_video,    \* True РµСЃР»Рё РµСЃС‚СЊ РїСѓС‚СЊ Рє РѕР±СЂР°Р±РѕС‚Р°РЅРЅРѕРјСѓ РІРёРґРµРѕ
    run_btn,            \* True РµСЃР»Рё РєРЅРѕРїРєР° Р°РєС‚РёРІРЅР°
    select_btn,         \* True РµСЃР»Рё РєРЅРѕРїРєР° Р°РєС‚РёРІРЅР°
    save_json_btn,      \* True РµСЃР»Рё РєРЅРѕРїРєР° Р°РєС‚РёРІРЅР°
    play_processed_btn  \* True РµСЃР»Рё РєРЅРѕРїРєР° Р°РєС‚РёРІРЅР°

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
    /\ run_btn            = FALSE   \* РѕС‚РєР»СЋС‡РµРЅР° РїРѕРєР° РЅРµС‚ РІРёРґРµРѕ
    /\ select_btn         = TRUE
    /\ save_json_btn      = FALSE
    /\ play_processed_btn = FALSE

\* в”Ђв”Ђ РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ РІС‹Р±СЂР°Р» РІРёРґРµРѕ в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
SelectVideo ==
    /\ worker_state = "IDLE"
    /\ select_btn = TRUE
    /\ video_path_set'     = TRUE
    /\ run_btn'            = TRUE   \* РєРЅРѕРїРєР° Run СЃС‚Р°РЅРѕРІРёС‚СЃСЏ Р°РєС‚РёРІРЅРѕР№
    /\ UNCHANGED <<worker_state, last_result_set, processed_video,
                   select_btn, save_json_btn, play_processed_btn>>

\* в”Ђв”Ђ Р—Р°РїСѓСЃРє РґРµС‚РµРєС†РёРё (run_inference) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\* РЎРѕРѕС‚РІРµС‚СЃС‚РІСѓРµС‚ СЃС‚СЂРѕРєР°Рј 586-633 main_window.py
StartInference ==
    /\ worker_state = "IDLE"
    /\ video_path_set = TRUE
    /\ run_btn = TRUE
    /\ worker_state'      = "RUNNING"
    /\ run_btn'           = FALSE   \* СЃС‚СЂРѕРєР° 586
    /\ select_btn'        = FALSE   \* СЃС‚СЂРѕРєР° 587
    /\ save_json_btn'     = FALSE   \* СЃС‚СЂРѕРєР° 588
    /\ play_processed_btn' = FALSE  \* СЃС‚СЂРѕРєР° 589
    /\ UNCHANGED <<video_path_set, last_result_set, processed_video>>

\* в”Ђв”Ђ РЈСЃРїРµС€РЅРѕРµ Р·Р°РІРµСЂС€РµРЅРёРµ (on_inference_finished) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\* РЎРѕРѕС‚РІРµС‚СЃС‚РІСѓРµС‚ СЃС‚СЂРѕРєР°Рј 644-694 main_window.py
\* РЎ РѕР±СЂР°Р±РѕС‚Р°РЅРЅС‹Рј РІРёРґРµРѕ
FinishWithVideo ==
    /\ worker_state = "RUNNING"
    /\ worker_state'      = "DONE"
    /\ last_result_set'   = TRUE    \* СЃС‚СЂРѕРєР° 645
    /\ processed_video'   = TRUE
    /\ run_btn'           = TRUE    \* СЃС‚СЂРѕРєР° 687
    /\ select_btn'        = TRUE    \* СЃС‚СЂРѕРєР° 688
    /\ save_json_btn'     = TRUE    \* СЃС‚СЂРѕРєР° 689
    /\ play_processed_btn' = TRUE   \* СЃС‚СЂРѕРєРё 691-692
    /\ UNCHANGED <<video_path_set>>

\* в”Ђв”Ђ РЈСЃРїРµС€РЅРѕРµ Р·Р°РІРµСЂС€РµРЅРёРµ Р±РµР· РѕР±СЂР°Р±РѕС‚Р°РЅРЅРѕРіРѕ РІРёРґРµРѕ в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
FinishWithoutVideo ==
    /\ worker_state = "RUNNING"
    /\ worker_state'      = "DONE"
    /\ last_result_set'   = TRUE
    /\ processed_video'   = FALSE
    /\ run_btn'           = TRUE
    /\ select_btn'        = TRUE
    /\ save_json_btn'     = TRUE
    /\ play_processed_btn' = FALSE  \* РЅРµ СЂР°Р·Р±Р»РѕРєРёСЂСѓРµС‚СЃСЏ Р±РµР· РІРёРґРµРѕ
    /\ UNCHANGED <<video_path_set>>

\* в”Ђв”Ђ Р—Р°РІРµСЂС€РµРЅРёРµ СЃ РѕС€РёР±РєРѕР№ (on_inference_error) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
\* РЎРѕРѕС‚РІРµС‚СЃС‚РІСѓРµС‚ СЃС‚СЂРѕРєР°Рј 696-706 main_window.py
\* Р’РќР�РњРђРќР�Р•: РІ СЂРµР°Р»СЊРЅРѕРј РєРѕРґРµ save_json_btn Рё play_processed_btn
\* РќР• СЂР°Р·Р±Р»РѕРєРёСЂСѓСЋС‚СЃСЏ РїСЂРё РѕС€РёР±РєРµ вЂ” СЌС‚Рѕ РїРѕС‚РµРЅС†РёР°Р»СЊРЅР°СЏ РїСЂРѕР±Р»РµРјР°
InferenceError ==
    /\ worker_state = "RUNNING"
    /\ worker_state'      = "ERROR"
    /\ run_btn'           = TRUE    \* СЃС‚СЂРѕРєР° 705
    /\ select_btn'        = TRUE    \* СЃС‚СЂРѕРєР° 706
    \* save_json_btn Рё play_processed_btn РѕСЃС‚Р°СЋС‚СЃСЏ FALSE
    \* last_result_set РѕСЃС‚Р°С‘С‚СЃСЏ FALSE
    /\ UNCHANGED <<video_path_set, last_result_set, processed_video,
                   save_json_btn, play_processed_btn>>

\* в”Ђв”Ђ РЎР±СЂРѕСЃ РґР»СЏ РЅРѕРІРѕР№ Р·Р°РґР°С‡Рё в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
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

\* в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ
\*  РџР РћР’Р•Р РЇР•РњР«Р• РЎР’РћР™РЎРўР’Рђ
\* в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ

\* Safety 1: run_button Р°РєС‚РёРІРЅР° С‚РѕР»СЊРєРѕ РІ IDLE Рё С‚РѕР»СЊРєРѕ РµСЃР»Рё РІРёРґРµРѕ РІС‹Р±СЂР°РЅРѕ
RunButtonOnlyWhenIdle ==
    run_btn => worker_state \in {"IDLE", "DONE", "ERROR"}

\* Safety 2: select_button Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅР° С‚РѕР»СЊРєРѕ РІРѕ РІСЂРµРјСЏ РѕР±СЂР°Р±РѕС‚РєРё
SelectButtonBlockedOnlyDuringRun ==
    ~select_btn => worker_state = "RUNNING"

\* Safety 3: save_json_button Р°РєС‚РёРІРЅР° С‚РѕР»СЊРєРѕ РµСЃР»Рё РµСЃС‚СЊ СЂРµР·СѓР»СЊС‚Р°С‚
\* РћР–Р�Р”РђР•Рњ РќРђР РЈРЁР•РќР�Р•: РїРѕСЃР»Рµ РѕС€РёР±РєРё save_json_btn=FALSE РЅРѕ last_result=FALSE
\* вЂ” СЌС‚Рѕ РєРѕРЅСЃРёСЃС‚РµРЅС‚РЅРѕ. РќРѕ РµСЃР»Рё Р±С‹Р» РїСЂРµРґС‹РґСѓС‰РёР№ СѓСЃРїРµС…, save_json_btn
\* РЅРµ РґРѕР»Р¶РЅР° Р±С‹С‚СЊ Р°РєС‚РёРІРЅР° Р±РµР· СЂРµР·СѓР»СЊС‚Р°С‚Р°
SaveJsonConsistency ==
    save_json_btn => last_result_set

\* Safety 4: play_processed_button Р°РєС‚РёРІРЅР° С‚РѕР»СЊРєРѕ РµСЃР»Рё РµСЃС‚СЊ РІРёРґРµРѕ
PlayButtonConsistency ==
    play_processed_btn => processed_video

\* Safety 5: РІРѕ РІСЂРµРјСЏ РѕР±СЂР°Р±РѕС‚РєРё РєРЅРѕРїРєРё Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅС‹
ButtonsBlockedDuringRun ==
    worker_state = "RUNNING" =>
        (~run_btn /\ ~select_btn /\ ~save_json_btn /\ ~play_processed_btn)

\* Safety 6 вЂ” РљР›Р®Р§Р•Р’РћР• РЎР’РћР™РЎРўР’Рћ:
\* РџРѕСЃР»Рµ Р·Р°РІРµСЂС€РµРЅРёСЏ (СѓСЃРїРµС… РёР»Рё РѕС€РёР±РєР°) run_button Р’РЎР•Р“Р”Рђ Р°РєС‚РёРІРЅР°
\* Р­С‚Рѕ РїРѕР·РІРѕР»СЏРµС‚ Р·Р°РїСѓСЃС‚РёС‚СЊ РЅРѕРІСѓСЋ Р·Р°РґР°С‡Сѓ
RunButtonActiveAfterCompletion ==
    worker_state \in {"DONE", "ERROR"} => run_btn

\* Liveness: СЃРёСЃС‚РµРјР° РЅРµ Р·Р°РІРёСЃР°РµС‚ РІ RUNNING
EventuallyNotRunning ==
    <>(worker_state # "RUNNING")

==========================================================================
