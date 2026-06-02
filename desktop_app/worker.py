from pathlib import Path
import time
import sys
import shutil

import cv2
import numpy as np
from ultralytics import YOLO

from PySide6.QtCore import QObject, Signal, Slot
from PySide6.QtGui import QImage

from desktop_app.history_manager import (
    create_report_dir,
    copy_processed_video_to_report,
    cut_event_clips,
    save_report_json,
    append_history_record,
    seconds_from_frame,
)
from desktop_app.email_notifier import send_detection_email


CLASS_NAMES = {
    0: "person_no_weapon",
    1: "person_with_weapon",
}


def get_app_base_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).parent
    return Path.cwd()


def find_model_path() -> Path:
    base_dir = get_app_base_dir()

    candidates = [
        base_dir / r"runs\detect\runs\exp_final_balanced_yolo11n\weights\best.pt",
        base_dir / r"runs\detect\exp_final_balanced_yolo11n\weights\best.pt",
        Path(r"runs\detect\runs\exp_final_balanced_yolo11n\weights\best.pt"),
        Path(r"runs\detect\exp_final_balanced_yolo11n\weights\best.pt"),
    ]

    for path in candidates:
        if path.exists():
            return path

    raise FileNotFoundError(
        "Не найден best.pt. Проверенные пути:\n"
        + "\n".join(str(p) for p in candidates)
    )


def bgr_to_qimage(frame_bgr: np.ndarray) -> QImage:
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    h, w, ch = frame_rgb.shape
    bytes_per_line = ch * w

    return QImage(
        frame_rgb.data,
        w,
        h,
        bytes_per_line,
        QImage.Format_RGB888,
    ).copy()


def draw_detections(frame_bgr: np.ndarray, detections: list[dict]) -> np.ndarray:
    output = frame_bgr.copy()

    for det in detections:
        cls_id = det["class_id"]
        class_name = det["class_name"]
        conf = det["confidence"]
        x1, y1, x2, y2 = det["bbox_xyxy"]

        x1 = int(x1)
        y1 = int(y1)
        x2 = int(x2)
        y2 = int(y2)

        if cls_id == 1:
            color = (0, 0, 255)
        else:
            color = (0, 200, 0)

        label = f"{class_name} {conf:.2f}"

        cv2.rectangle(output, (x1, y1), (x2, y2), color, 2)
        cv2.putText(
            output,
            label,
            (x1, max(y1 - 8, 20)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            color,
            2,
            cv2.LINE_AA,
        )

    return output


def build_events_from_flags(
    flags: list[bool],
    fps: float,
    min_consecutive: int,
) -> tuple[list[dict], list[int]]:
    """
    Находит интервалы, где person_with_weapon держался минимум min_consecutive кадров.
    Возвращает:
    - events
    - confirmed_frames
    """
    if fps <= 0:
        fps = 25.0

    events = []
    confirmed_frames = []

    run_start = None
    run_end = None

    def close_run(start, end):
        if start is None or end is None:
            return

        duration = end - start + 1

        if duration >= min_consecutive:
            for frame_id in range(start, end + 1):
                confirmed_frames.append(frame_id)

            events.append(
                {
                    "start_frame": start,
                    "end_frame": end,
                    "duration_frames": duration,
                    "start_time_sec": seconds_from_frame(start, fps),
                    "end_time_sec": seconds_from_frame(end, fps),
                    "duration_sec": duration / fps,
                }
            )

    for idx, flag in enumerate(flags, start=1):
        if flag:
            if run_start is None:
                run_start = idx
            run_end = idx
        else:
            close_run(run_start, run_end)
            run_start = None
            run_end = None

    close_run(run_start, run_end)

    return events, confirmed_frames


class InferenceWorker(QObject):
    progress_text = Signal(str)
    progress_value = Signal(int)
    preview_frame = Signal(object)
    finished = Signal(dict)
    error = Signal(str)

    def __init__(
        self,
        video_path: str,
        conf: float,
        imgsz: int,
        iou: float,
        min_consecutive: int,
        export_video_path: str | None,
        save_history: bool,
        email_settings: dict,
        preview_every_n_frames: int = 2,
    ):
        super().__init__()

        self.video_path = Path(video_path)
        self.conf = conf
        self.imgsz = imgsz
        self.iou = iou
        self.min_consecutive = min_consecutive
        self.export_video_path = Path(export_video_path) if export_video_path else None
        self.save_history = save_history
        self.email_settings = email_settings
        self.preview_every_n_frames = preview_every_n_frames

    @Slot()
    def run(self):
        try:
            result = self.process_video()
            self.finished.emit(result)
        except Exception as exc:
            self.error.emit(str(exc))

    def process_video(self) -> dict:
        if not self.video_path.exists():
            raise FileNotFoundError(f"Видео не найдено: {self.video_path}")

        self.progress_text.emit("Загрузка модели...")

        model_path = find_model_path()
        model = YOLO(str(model_path))

        self.progress_text.emit("Открытие видео...")

        cap = cv2.VideoCapture(str(self.video_path))

        if not cap.isOpened():
            raise RuntimeError(f"Не удалось открыть видео: {self.video_path}")

        source_fps = cap.get(cv2.CAP_PROP_FPS)
        source_frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

        if source_fps <= 0:
            source_fps = 25.0

        if self.export_video_path is None:
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            self.export_video_path = Path("exports") / f"{self.video_path.stem}_{timestamp}_processed.mp4"

        self.export_video_path.parent.mkdir(parents=True, exist_ok=True)

        writer = cv2.VideoWriter(
            str(self.export_video_path),
            cv2.VideoWriter_fourcc(*"mp4v"),
            source_fps,
            (width, height),
        )

        if not writer.isOpened():
            raise RuntimeError(f"Не удалось создать видео: {self.export_video_path}")

        start_time = time.time()

        frame_index = 0
        processed_frames = 0

        frame_results = []
        weapon_flags = []

        self.progress_text.emit("Обработка видео...")

        while True:
            ok, frame = cap.read()

            if not ok:
                break

            frame_index += 1
            processed_frames += 1

            yolo_results = model.predict(
                source=frame,
                imgsz=self.imgsz,
                conf=self.conf,
                iou=self.iou,
                verbose=False,
            )

            detections = []
            frame_has_weapon = False

            for result in yolo_results:
                if result.boxes is None:
                    continue

                for box in result.boxes:
                    cls_id = int(box.cls[0])
                    confidence = float(box.conf[0])
                    x1, y1, x2, y2 = box.xyxy[0].tolist()

                    class_name = CLASS_NAMES.get(cls_id, str(cls_id))

                    det = {
                        "class_id": cls_id,
                        "class_name": class_name,
                        "confidence": confidence,
                        "bbox_xyxy": [
                            round(float(x1), 2),
                            round(float(y1), 2),
                            round(float(x2), 2),
                            round(float(y2), 2),
                        ],
                    }

                    detections.append(det)

                    if cls_id == 1:
                        frame_has_weapon = True

            weapon_flags.append(frame_has_weapon)

            annotated_frame = draw_detections(frame, detections)
            writer.write(annotated_frame)

            if frame_index % self.preview_every_n_frames == 0:
                self.preview_frame.emit(bgr_to_qimage(annotated_frame))

            if source_frame_count > 0:
                progress = int(frame_index / source_frame_count * 100)
                self.progress_value.emit(min(progress, 100))

            frame_results.append(
                {
                    "frame_index": frame_index,
                    "has_person_with_weapon": frame_has_weapon,
                    "detections": detections,
                }
            )

        cap.release()
        writer.release()

        elapsed_sec = time.time() - start_time
        fps_processing = processed_frames / elapsed_sec if elapsed_sec > 0 else 0.0
        sec_per_frame = elapsed_sec / processed_frames if processed_frames > 0 else 0.0

        events, confirmed_frames = build_events_from_flags(
            flags=weapon_flags,
            fps=source_fps,
            min_consecutive=self.min_consecutive,
        )

        result = {
            "video_path": str(self.video_path),
            "model_path": str(model_path),
            "processed_video_path": str(self.export_video_path),
            "settings": {
                "conf": self.conf,
                "imgsz": self.imgsz,
                "iou": self.iou,
                "min_consecutive": self.min_consecutive,
            },
            "video_metadata": {
                "source_fps": source_fps,
                "source_frame_count": source_frame_count,
                "frames_processed": processed_frames,
                "width": width,
                "height": height,
            },
            "performance": {
                "elapsed_sec": elapsed_sec,
                "fps_processing": fps_processing,
                "sec_per_frame": sec_per_frame,
            },
            "video_result": {
                "has_person_with_weapon": len(events) > 0,
                "confirmed_frames": confirmed_frames,
                "events": events,
                "method": "temporal_consecutive_frames",
                "min_consecutive": self.min_consecutive,
            },
            "frame_results": frame_results,
            "history_report": None,
        }

        if len(events) > 0 and self.save_history:
            self.progress_text.emit("Сохранение истории...")

            report_id, report_dir = create_report_dir()

            processed_video_in_report = copy_processed_video_to_report(
                processed_video_path=self.export_video_path,
                report_dir=report_dir,
            )

            clips = cut_event_clips(
                processed_video_path=processed_video_in_report,
                events=events,
                fps=source_fps,
                report_dir=report_dir,
                pad_sec=1.0,
            )

            report = {
                "report_id": report_id,
                "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "source_video": str(self.video_path),
                "report_dir": str(report_dir),
                "processed_video_path": str(processed_video_in_report),
                "has_person_with_weapon": True,
                "events": events,
                "clips": clips,
                "settings": result["settings"],
                "performance": result["performance"],
            }

            report_json_path = save_report_json(report_dir, report)
            report["report_json_path"] = str(report_json_path)

            append_history_record(report)

            result["history_report"] = report

            if self.email_settings.get("enabled", False):
                self.progress_text.emit("Отправка email...")
                send_detection_email(self.email_settings, report)

        self.progress_value.emit(100)
        self.progress_text.emit("Готово.")

        return result