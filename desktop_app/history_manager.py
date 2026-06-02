from pathlib import Path
import json
import shutil
from datetime import datetime

import cv2


HISTORY_ROOT = Path("history")
REPORTS_DIR = HISTORY_ROOT / "reports"
INDEX_PATH = HISTORY_ROOT / "history_index.json"


def ensure_history_dirs() -> None:
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    HISTORY_ROOT.mkdir(parents=True, exist_ok=True)

    if not INDEX_PATH.exists():
        with INDEX_PATH.open("w", encoding="utf-8") as f:
            json.dump([], f, ensure_ascii=False, indent=2)


def load_history() -> list[dict]:
    ensure_history_dirs()

    with INDEX_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_history_index(records: list[dict]) -> None:
    ensure_history_dirs()

    with INDEX_PATH.open("w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, indent=2)


def append_history_record(record: dict) -> None:
    records = load_history()
    records.insert(0, record)
    save_history_index(records)


def create_report_dir() -> tuple[str, Path]:
    ensure_history_dirs()

    report_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_dir = REPORTS_DIR / report_id
    report_dir.mkdir(parents=True, exist_ok=True)

    return report_id, report_dir


def seconds_from_frame(frame_number: int, fps: float) -> float:
    if fps <= 0:
        fps = 25.0

    return max(frame_number - 1, 0) / fps


def copy_processed_video_to_report(processed_video_path: Path, report_dir: Path) -> Path:
    out_path = report_dir / "processed_video.mp4"
    shutil.copy2(processed_video_path, out_path)
    return out_path


def cut_event_clips(
    processed_video_path: Path,
    events: list[dict],
    fps: float,
    report_dir: Path,
    pad_sec: float = 1.0,
) -> list[dict]:
    clips_dir = report_dir / "clips"
    clips_dir.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(str(processed_video_path))

    if not cap.isOpened():
        raise RuntimeError(f"Не удалось открыть обработанное видео: {processed_video_path}")

    source_fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    if source_fps <= 0:
        source_fps = fps if fps > 0 else 25.0

    pad_frames = int(pad_sec * source_fps)

    clip_records = []

    for idx, event in enumerate(events, start=1):
        start_frame = max(1, int(event["start_frame"]) - pad_frames)
        end_frame = min(total_frames, int(event["end_frame"]) + pad_frames)

        clip_path = clips_dir / f"event_{idx:03d}_{start_frame}_{end_frame}.mp4"

        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        writer = cv2.VideoWriter(str(clip_path), fourcc, source_fps, (width, height))

        if not writer.isOpened():
            continue

        cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame - 1)

        current_frame = start_frame

        while current_frame <= end_frame:
            ok, frame = cap.read()

            if not ok:
                break

            writer.write(frame)
            current_frame += 1

        writer.release()

        clip_records.append(
            {
                "event_index": idx,
                "clip_path": str(clip_path),
                "start_frame": start_frame,
                "end_frame": end_frame,
                "start_time_sec": seconds_from_frame(start_frame, source_fps),
                "end_time_sec": seconds_from_frame(end_frame, source_fps),
            }
        )

    cap.release()

    return clip_records


def save_report_json(report_dir: Path, report: dict) -> Path:
    path = report_dir / "report.json"

    with path.open("w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    return path
