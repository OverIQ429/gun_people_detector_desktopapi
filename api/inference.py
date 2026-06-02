from pathlib import Path
import time
import cv2
from ultralytics import YOLO


CLASS_NAMES = {
    0: "person_no_weapon",
    1: "person_with_weapon",
}


MODEL_CANDIDATES = [
    Path(r"runs\detect\runs\exp2_finetuned_yolo11n\weights\best.pt"),
    Path(r"runs\detect\exp2_finetuned_yolo11n\weights\best.pt"),
]


def find_model_path() -> Path:
    for path in MODEL_CANDIDATES:
        if path.exists():
            return path

    raise FileNotFoundError(
        "Не найден best.pt. Проверь путь к обученной модели. "
        "Ожидался один из путей: "
        + ", ".join(str(p) for p in MODEL_CANDIDATES)
    )


class WeaponPersonDetector:
    def __init__(
        self,
        model_path: str | Path | None = None,
        conf: float = 0.15,
        imgsz: int = 640,
        iou: float = 0.5,
        min_consecutive: int = 3,
        frame_stride: int = 1,
    ):
        if model_path is None:
            model_path = find_model_path()

        self.model_path = Path(model_path)
        self.model = YOLO(str(self.model_path))

        self.conf = conf
        self.imgsz = imgsz
        self.iou = iou
        self.min_consecutive = min_consecutive
        self.frame_stride = frame_stride

    def predict_video(self, video_path: str | Path) -> dict:
        video_path = Path(video_path)

        if not video_path.exists():
            raise FileNotFoundError(f"Видео не найдено: {video_path}")

        start_time = time.time()

        cap = cv2.VideoCapture(str(video_path))

        if not cap.isOpened():
            raise RuntimeError(f"Не удалось открыть видео: {video_path}")

        source_fps = cap.get(cv2.CAP_PROP_FPS)
        source_frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

        frame_index = 0
        processed_frames = 0

        frame_results = []
        weapon_frame_flags = []

        while True:
            ok, frame = cap.read()

            if not ok:
                break

            frame_index += 1

            if self.frame_stride > 1 and frame_index % self.frame_stride != 0:
                continue

            processed_frames += 1

            results = self.model.predict(
                source=frame,
                imgsz=self.imgsz,
                conf=self.conf,
                iou=self.iou,
                verbose=False,
            )

            detections = []
            frame_has_person_with_weapon = False

            for result in results:
                if result.boxes is None:
                    continue

                for box in result.boxes:
                    cls_id = int(box.cls[0])
                    confidence = float(box.conf[0])
                    x1, y1, x2, y2 = box.xyxy[0].tolist()

                    class_name = CLASS_NAMES.get(cls_id, str(cls_id))

                    detection = {
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

                    detections.append(detection)

                    if cls_id == 1:
                        frame_has_person_with_weapon = True

            weapon_frame_flags.append(frame_has_person_with_weapon)

            frame_results.append(
                {
                    "frame_index": frame_index,
                    "processed_index": processed_frames,
                    "has_person_with_weapon": frame_has_person_with_weapon,
                    "detections": detections,
                }
            )

        cap.release()

        video_result = self.temporal_postprocess(
            weapon_frame_flags=weapon_frame_flags,
            frame_results=frame_results,
        )

        elapsed_sec = time.time() - start_time
        fps_processing = processed_frames / elapsed_sec if elapsed_sec > 0 else 0.0
        sec_per_frame = elapsed_sec / processed_frames if processed_frames > 0 else 0.0

        return {
            "video_path": str(video_path),
            "model_path": str(self.model_path),
            "settings": {
                "conf": self.conf,
                "imgsz": self.imgsz,
                "iou": self.iou,
                "min_consecutive": self.min_consecutive,
                "frame_stride": self.frame_stride,
            },
            "video_metadata": {
                "source_fps": source_fps,
                "source_frame_count": source_frame_count,
                "frames_processed": processed_frames,
            },
            "performance": {
                "elapsed_sec": elapsed_sec,
                "fps_processing": fps_processing,
                "sec_per_frame": sec_per_frame,
            },
            "video_result": video_result,
            "frame_results": frame_results,
        }

    def temporal_postprocess(self, weapon_frame_flags: list[bool], frame_results: list[dict]) -> dict:
        consecutive = 0
        confirmed_frames = []

        for idx, has_weapon in enumerate(weapon_frame_flags):
            if has_weapon:
                consecutive += 1
            else:
                consecutive = 0

            if consecutive >= self.min_consecutive:
                confirmed_frames.append(frame_results[idx]["frame_index"])

        return {
            "has_person_with_weapon": len(confirmed_frames) > 0,
            "confirmed_frames": confirmed_frames,
            "min_consecutive": self.min_consecutive,
            "method": "temporal_3_consecutive_frames",
        }