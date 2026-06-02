from pathlib import Path
import json


SETTINGS_PATH = Path("app_settings.json")


DEFAULT_SETTINGS = {
    "inference": {
        "conf": 0.50,
        "imgsz": 640,
        "iou": 0.5,
        "min_consecutive": 10,
        "save_history": True,
        "export_processed_video": True,
    },
    "email": {
        "enabled": False,
        "smtp_host": "smtp.gmail.com",
        "smtp_port": 587,
        "use_tls": True,
        "sender_email": "",
        "sender_password": "",
        "recipient_email": "",
    }
}


def load_settings() -> dict:
    if not SETTINGS_PATH.exists():
        save_settings(DEFAULT_SETTINGS)
        return DEFAULT_SETTINGS.copy()

    with SETTINGS_PATH.open("r", encoding="utf-8") as f:
        user_settings = json.load(f)

    settings = DEFAULT_SETTINGS.copy()

    for section, values in user_settings.items():
        if section not in settings:
            settings[section] = values
            continue

        settings[section].update(values)

    return settings


def save_settings(settings: dict) -> None:
    with SETTINGS_PATH.open("w", encoding="utf-8") as f:
        json.dump(settings, f, ensure_ascii=False, indent=2)