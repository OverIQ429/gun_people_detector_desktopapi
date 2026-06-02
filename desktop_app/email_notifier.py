import smtplib
from email.message import EmailMessage


def send_detection_email(email_settings: dict, report: dict) -> None:
    if not email_settings.get("enabled", False):
        return

    sender = email_settings.get("sender_email", "")
    password = email_settings.get("sender_password", "")
    recipient = email_settings.get("recipient_email", "")

    if not sender or not password or not recipient:
        raise ValueError("Email включен, но sender/password/recipient не заполнены.")

    smtp_host = email_settings.get("smtp_host", "smtp.gmail.com")
    smtp_port = int(email_settings.get("smtp_port", 587))
    use_tls = bool(email_settings.get("use_tls", True))

    events = report.get("events", [])

    subject = "Обнаружен человек с оружием"

    lines = [
        "Система детекции обнаружила событие: человек с оружием.",
        "",
        f"Видео: {report.get('source_video', '')}",
        f"Report ID: {report.get('report_id', '')}",
        f"Количество событий: {len(events)}",
        "",
        "Интервалы:",
    ]

    for idx, event in enumerate(events, start=1):
        lines.append(
            f"{idx}) "
            f"{event.get('start_time_sec', 0):.2f}s - "
            f"{event.get('end_time_sec', 0):.2f}s "
            f"(frames {event.get('start_frame')} - {event.get('end_frame')})"
        )

    lines.extend(
        [
            "",
            f"Обработанное видео: {report.get('processed_video_path', '')}",
            f"Папка отчета: {report.get('report_dir', '')}",
        ]
    )

    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = recipient
    msg["Subject"] = subject
    msg.set_content("\n".join(lines))

    with smtplib.SMTP(smtp_host, smtp_port, timeout=30) as server:
        if use_tls:
            server.starttls()

        server.login(sender, password)
        server.send_message(msg)