from pathlib import Path
import shutil
import uuid
import traceback

from fastapi import FastAPI, UploadFile, File, HTTPException

from api.inference import WeaponPersonDetector


UPLOAD_DIR = Path("tmp_uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


app = FastAPI(
    title="Person With Weapon Detection API",
    description="REST API для определения человека с оружием / без оружия на видео",
    version="1.0.0",
)


detector = WeaponPersonDetector(
    conf=0.15,
    imgsz=640,
    iou=0.5,
    min_consecutive=3,
    frame_stride=1,
)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_path": str(detector.model_path),
        "conf": detector.conf,
        "imgsz": detector.imgsz,
        "iou": detector.iou,
        "min_consecutive": detector.min_consecutive,
    }


@app.post("/predict/video")
async def predict_video(file: UploadFile = File(...)):
    suffix = Path(file.filename).suffix.lower()

    if suffix not in [".mp4", ".avi", ".mov", ".mkv"]:
        raise HTTPException(
            status_code=400,
            detail=f"Неподдерживаемый формат файла: {suffix}. Используй mp4/avi/mov/mkv.",
        )

    temp_path = UPLOAD_DIR / f"{uuid.uuid4()}{suffix}"

    try:
        with temp_path.open("wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        result = detector.predict_video(temp_path)

        return result

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка инференса: {str(e)}",
        )

    finally:
        # Если хочешь сохранять загруженные видео для отладки, закомментируй эти две строки
        if temp_path.exists():
            temp_path.unlink()