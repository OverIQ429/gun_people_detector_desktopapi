"""
Тесты на основе Hypothesis для модулей:
  - email_notifier.py  (формирование и валидация письма)
  - history_manager.py (создание отчётов, индекс истории, seconds_from_frame)
"""

import json
import tempfile
import os
import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock
from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st

from desktop_app.email_notifier import send_detection_email
from desktop_app.history_manager import (
    append_history_record,
    load_history,
    save_history_index,
    save_report_json,
    seconds_from_frame,
)


# ══════════════════════════════════════════════════════════════════
#  СТРАТЕГИИ
# ══════════════════════════════════════════════════════════════════

valid_email = st.from_regex(
    r"[a-z]{3,8}@[a-z]{3,6}\.(com|ru|org)", fullmatch=True
)
nonempty_str = st.text(
    min_size=1, max_size=80,
    alphabet=st.characters(
        whitelist_categories=("Lu", "Ll", "Nd"),
        whitelist_characters="@._- "
    )
)

event_strategy = st.fixed_dictionaries({
    "start_frame":    st.integers(min_value=1,   max_value=10000),
    "end_frame":      st.integers(min_value=1,   max_value=10000),
    "start_time_sec": st.floats(min_value=0.0,   max_value=3600.0, allow_nan=False),
    "end_time_sec":   st.floats(min_value=0.0,   max_value=3600.0, allow_nan=False),
    "duration_frames": st.integers(min_value=1,  max_value=10000),
    "duration_sec":   st.floats(min_value=0.0,   max_value=3600.0, allow_nan=False),
})

report_strategy = st.fixed_dictionaries({
    "report_id":            nonempty_str,
    "source_video":         nonempty_str,
    "processed_video_path": nonempty_str,
    "report_dir":           nonempty_str,
    "events":               st.lists(event_strategy, min_size=0, max_size=20),
})

email_settings_strategy = st.fixed_dictionaries({
    "enabled":         st.just(True),
    "sender_email":    valid_email,
    "sender_password": st.text(min_size=1, max_size=30),
    "recipient_email": valid_email,
    "smtp_host":       st.just("smtp.mail.ru"),
    "smtp_port":       st.just(587),
    "use_tls":         st.booleans(),
})

record_strategy = st.fixed_dictionaries({
    "report_id":    nonempty_str,
    "created_at":   nonempty_str,
    "events":       st.integers(min_value=0, max_value=100),
    "source_video": nonempty_str,
})


# ══════════════════════════════════════════════════════════════════
#  БЛОК 1 — EMAIL: валидация входных данных
# ══════════════════════════════════════════════════════════════════

class TestEmailValidation:

    def test_disabled_email_never_sends(self):
        """Если enabled=False — SMTP не вызывается ни при каких данных."""
        cfg = {"enabled": False}
        report = {"events": [], "source_video": "test.mp4", "report_id": "001"}
        with patch("smtplib.SMTP") as mock_smtp:
            send_detection_email(cfg, report)
            mock_smtp.assert_not_called()

    @given(field=st.sampled_from(
        ["sender_email", "sender_password", "recipient_email"]
    ))
    @settings(max_examples=50)
    def test_missing_required_field_raises(self, field):
        """Если любое из трёх обязательных полей пустое — ValueError."""
        cfg = {
            "enabled": True,
            "sender_email": "a@b.com",
            "sender_password": "secret",
            "recipient_email": "c@d.com",
        }
        cfg[field] = ""
        with pytest.raises(ValueError):
            send_detection_email(cfg, {"events": []})

    @given(port=st.integers(min_value=1, max_value=65535))
    @settings(max_examples=100)
    def test_smtp_port_passed_correctly(self, port):
        """SMTP-клиент всегда получает именно тот порт, что задан в настройках."""
        cfg = {
            "enabled": True,
            "sender_email": "sender@mail.ru",
            "sender_password": "pass",
            "recipient_email": "recv@mail.ru",
            "smtp_host": "smtp.mail.ru",
            "smtp_port": port,
            "use_tls": False,
        }
        report = {
            "events": [], "source_video": "v.mp4",
            "report_id": "r1", "processed_video_path": "", "report_dir": ""
        }
        mock_server = MagicMock()
        mock_server.__enter__ = lambda s: mock_server
        mock_server.__exit__ = MagicMock(return_value=False)

        with patch("smtplib.SMTP", return_value=mock_server) as mock_smtp:
            send_detection_email(cfg, report)
            mock_smtp.assert_called_once_with("smtp.mail.ru", port, timeout=30)


# ══════════════════════════════════════════════════════════════════
#  БЛОК 2 — EMAIL: содержимое письма
# ══════════════════════════════════════════════════════════════════

def _make_mock_server():
    """Вспомогательная функция: мок SMTP-сервера с перехватом send_message."""
    sent = []
    mock_server = MagicMock()
    mock_server.__enter__ = lambda s: mock_server
    mock_server.__exit__ = MagicMock(return_value=False)
    mock_server.send_message.side_effect = lambda msg: sent.append(msg)
    return mock_server, sent


class TestEmailContent:

    @given(report=report_strategy, cfg=email_settings_strategy)
    @settings(max_examples=500)
    def test_subject_always_present(self, report, cfg):
        """Тема письма всегда непустая."""
        mock_server, sent = _make_mock_server()
        with patch("smtplib.SMTP", return_value=mock_server):
            send_detection_email(cfg, report)
        assert len(sent) == 1
        assert sent[0]["Subject"] != ""

    @given(report=report_strategy, cfg=email_settings_strategy)
    @settings(max_examples=500)
    def test_sender_and_recipient_in_message(self, report, cfg):
        """Поля From и To всегда совпадают с настройками."""
        mock_server, sent = _make_mock_server()
        with patch("smtplib.SMTP", return_value=mock_server):
            send_detection_email(cfg, report)
        msg = sent[0]
        assert msg["From"] == cfg["sender_email"]
        assert msg["To"] == cfg["recipient_email"]

    @given(report=report_strategy, cfg=email_settings_strategy)
    @settings(max_examples=500)
    def test_all_events_mentioned_in_body(self, report, cfg):
        """Каждое событие из отчёта упомянуто в теле письма."""
        mock_server, sent = _make_mock_server()
        with patch("smtplib.SMTP", return_value=mock_server):
            send_detection_email(cfg, report)
        body = sent[0].get_content()
        for idx in range(1, len(report["events"]) + 1):
            assert f"{idx})" in body

    @given(cfg=email_settings_strategy)
    @settings(max_examples=200)
    def test_empty_events_no_crash(self, cfg):
        """Письмо с пустым списком событий отправляется без ошибок."""
        report = {
            "events": [], "source_video": "test.mp4",
            "report_id": "empty_001",
            "processed_video_path": "/out/video.mp4",
            "report_dir": "/out/",
        }
        mock_server, _ = _make_mock_server()
        with patch("smtplib.SMTP", return_value=mock_server):
            send_detection_email(cfg, report)

    @given(cfg=email_settings_strategy)
    @settings(max_examples=200)
    def test_tls_flag_respected(self, cfg):
        """starttls() вызывается только если use_tls=True."""
        report = {
            "events": [], "source_video": "v.mp4",
            "report_id": "r", "processed_video_path": "", "report_dir": ""
        }
        mock_server, _ = _make_mock_server()
        with patch("smtplib.SMTP", return_value=mock_server):
            send_detection_email(cfg, report)
        if cfg["use_tls"]:
            mock_server.starttls.assert_called_once()
        else:
            mock_server.starttls.assert_not_called()


# ══════════════════════════════════════════════════════════════════
#  БЛОК 3 — seconds_from_frame
# ══════════════════════════════════════════════════════════════════

class TestSecondsFromFrame:

    @given(
        frame=st.integers(min_value=1, max_value=100000),
        fps=st.floats(min_value=0.1, max_value=120.0, allow_nan=False)
    )
    @settings(max_examples=1000)
    def test_result_non_negative(self, frame, fps):
        """Результат всегда >= 0."""
        assert seconds_from_frame(frame, fps) >= 0.0

    @given(fps=st.floats(max_value=0.0, allow_nan=False))
    @settings(max_examples=200)
    def test_invalid_fps_falls_back_to_25(self, fps):
        """При fps <= 0 используется 25 FPS: кадр 1 → 0.0 сек."""
        assert seconds_from_frame(1, fps) == 0.0

    def test_frame_1_is_zero_seconds(self):
        """Первый кадр всегда соответствует 0.0 секунд."""
        assert seconds_from_frame(1, 25.0) == 0.0

    @given(
        frame=st.integers(min_value=2, max_value=100000),
        fps=st.floats(min_value=1.0, max_value=120.0, allow_nan=False)
    )
    @settings(max_examples=1000)
    def test_monotonically_increasing(self, frame, fps):
        """Время строго возрастает с каждым кадром."""
        t1 = seconds_from_frame(frame, fps)
        t2 = seconds_from_frame(frame + 1, fps)
        assert t2 > t1


# ══════════════════════════════════════════════════════════════════
#  БЛОК 4 — индекс истории
#  tmp_path заменён на tempfile.TemporaryDirectory внутри теста
# ══════════════════════════════════════════════════════════════════

class TestHistoryIndex:

    @given(records=st.lists(record_strategy, min_size=0, max_size=50))
    @settings(max_examples=300,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_save_and_load_roundtrip(self, records):
        """Сохранённый индекс полностью совпадает с загруженным."""
        import desktop_app.history_manager as hm
        tmp = tempfile.mkdtemp()
        orig_root = hm.HISTORY_ROOT
        orig_reports = hm.REPORTS_DIR
        orig_index = hm.INDEX_PATH
        try:
            hm.HISTORY_ROOT = Path(tmp) / "history"
            hm.REPORTS_DIR = hm.HISTORY_ROOT / "reports"
            hm.INDEX_PATH = hm.HISTORY_ROOT / "history_index.json"
            save_history_index(records)
            loaded = load_history()
        finally:
            hm.HISTORY_ROOT = orig_root
            hm.REPORTS_DIR = orig_reports
            hm.INDEX_PATH = orig_index
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)
        assert loaded == records

    @given(
        existing=st.lists(record_strategy, min_size=0, max_size=20),
        new_record=record_strategy,
    )
    @settings(max_examples=300,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_new_record_goes_to_front(self, existing, new_record):
        """Новая запись всегда оказывается первой в индексе."""
        import desktop_app.history_manager as hm
        tmp = tempfile.mkdtemp()
        orig_root, orig_reports, orig_index = hm.HISTORY_ROOT, hm.REPORTS_DIR, hm.INDEX_PATH
        try:
            hm.HISTORY_ROOT = Path(tmp) / "history"
            hm.REPORTS_DIR = hm.HISTORY_ROOT / "reports"
            hm.INDEX_PATH = hm.HISTORY_ROOT / "history_index.json"
            save_history_index(existing)
            append_history_record(new_record)
            loaded = load_history()
        finally:
            hm.HISTORY_ROOT = orig_root
            hm.REPORTS_DIR = orig_reports
            hm.INDEX_PATH = orig_index
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)
        assert loaded[0] == new_record

    @given(records=st.lists(record_strategy, min_size=1, max_size=30))
    @settings(max_examples=300,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_count_preserved_after_append(self, records):
        """После добавления записи количество увеличивается ровно на 1."""
        import desktop_app.history_manager as hm
        tmp = tempfile.mkdtemp()
        orig_root, orig_reports, orig_index = hm.HISTORY_ROOT, hm.REPORTS_DIR, hm.INDEX_PATH
        new_rec = {"report_id": "new", "created_at": "2025",
                   "events": 1, "source_video": "v.mp4"}
        try:
            hm.HISTORY_ROOT = Path(tmp) / "history"
            hm.REPORTS_DIR = hm.HISTORY_ROOT / "reports"
            hm.INDEX_PATH = hm.HISTORY_ROOT / "history_index.json"
            save_history_index(records)
            append_history_record(new_rec)
            loaded = load_history()
        finally:
            hm.HISTORY_ROOT = orig_root
            hm.REPORTS_DIR = orig_reports
            hm.INDEX_PATH = orig_index
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)
        assert len(loaded) == len(records) + 1

    @given(records=st.lists(record_strategy, min_size=0, max_size=20))
    @settings(max_examples=200,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_index_is_valid_json(self, records):
        """Файл индекса всегда является валидным JSON."""
        import desktop_app.history_manager as hm
        tmp = tempfile.mkdtemp()
        orig_root, orig_reports, orig_index = hm.HISTORY_ROOT, hm.REPORTS_DIR, hm.INDEX_PATH
        try:
            hm.HISTORY_ROOT = Path(tmp) / "history"
            hm.REPORTS_DIR = hm.HISTORY_ROOT / "reports"
            hm.INDEX_PATH = hm.HISTORY_ROOT / "history_index.json"
            save_history_index(records)
            content = hm.INDEX_PATH.read_text(encoding="utf-8")
            parsed = json.loads(content)
        finally:
            hm.HISTORY_ROOT = orig_root
            hm.REPORTS_DIR = orig_reports
            hm.INDEX_PATH = orig_index
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)
        assert isinstance(parsed, list)


# ══════════════════════════════════════════════════════════════════
#  БЛОК 5 — save_report_json
# ══════════════════════════════════════════════════════════════════

class TestSaveReportJson:

    @given(report=report_strategy)
    @settings(max_examples=300,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_report_file_created(self, report):
        """Файл report.json создаётся после вызова save_report_json."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            save_report_json(tmp_path, report)
            assert (tmp_path / "report.json").exists()

    @given(report=report_strategy)
    @settings(max_examples=300,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_report_roundtrip(self, report):
        """Содержимое report.json точно совпадает с переданным словарём."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            save_report_json(tmp_path, report)
            loaded = json.loads(
                (tmp_path / "report.json").read_text(encoding="utf-8")
            )
        assert loaded == report

    @given(reports=st.lists(report_strategy, min_size=2, max_size=5))
    @settings(max_examples=100,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_last_save_wins(self, reports):
        """При повторном сохранении в ту же папку остаётся последний отчёт."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            for r in reports:
                save_report_json(tmp_path, r)
            loaded = json.loads(
                (tmp_path / "report.json").read_text(encoding="utf-8")
            )
        assert loaded == reports[-1]

    @given(report=report_strategy)
    @settings(max_examples=200,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_report_json_is_valid(self, report):
        """Файл всегда является валидным JSON независимо от содержимого."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            save_report_json(tmp_path, report)
            content = (tmp_path / "report.json").read_text(encoding="utf-8")
            parsed = json.loads(content)
        assert isinstance(parsed, dict)
