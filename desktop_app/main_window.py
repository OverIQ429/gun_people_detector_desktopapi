import json
from pathlib import Path

import cv2

from PySide6.QtCore import Qt, QThread, QUrl
from PySide6.QtGui import QPixmap, QImage, QDesktopServices
from PySide6.QtWidgets import (
    QMainWindow,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QGridLayout,
    QPushButton,
    QLabel,
    QFileDialog,
    QTextEdit,
    QDoubleSpinBox,
    QSpinBox,
    QMessageBox,
    QProgressBar,
    QTableWidget,
    QTableWidgetItem,
    QGroupBox,
    QTabWidget,
    QCheckBox,
    QLineEdit,
    QHeaderView,
)

from PySide6.QtMultimedia import QMediaPlayer, QAudioOutput
from PySide6.QtMultimediaWidgets import QVideoWidget

from desktop_app.worker import InferenceWorker
from desktop_app.settings_manager import load_settings, save_settings
from desktop_app.history_manager import load_history
from desktop_app.email_notifier import send_detection_email


def first_frame_to_qimage(video_path: str) -> QImage | None:
    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        return None

    ok, frame = cap.read()
    cap.release()

    if not ok:
        return None

    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    h, w, ch = frame_rgb.shape
    bytes_per_line = ch * w

    return QImage(
        frame_rgb.data,
        w,
        h,
        bytes_per_line,
        QImage.Format_RGB888,
    ).copy()


def format_seconds(value: float) -> str:
    value = float(value)
    minutes = int(value // 60)
    seconds = value - minutes * 60
    return f"{minutes:02d}:{seconds:05.2f}"


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Person With Weapon Detector")
        self.resize(1300, 850)

        self.settings = load_settings()

        self.video_path: str | None = None
        self.last_result: dict | None = None
        self.current_preview_qimage: QImage | None = None

        self.thread: QThread | None = None
        self.worker: InferenceWorker | None = None

        self.history_records: list[dict] = []
        self.selected_history_record: dict | None = None

        self.player = QMediaPlayer()
        self.audio_output = QAudioOutput()
        self.player.setAudioOutput(self.audio_output)

        self._build_ui()
        self._load_settings_to_ui()
        self.refresh_history()

    # ----------------------------------------------------------------------
    # UI
    # ----------------------------------------------------------------------

    def _build_ui(self):
        self.tabs = QTabWidget()

        self.detection_tab = self._build_detection_tab()
        self.history_tab = self._build_history_tab()
        self.player_tab = self._build_player_tab()
        self.settings_tab = self._build_settings_tab()

        self.tabs.addTab(self.detection_tab, "Детекция")
        self.tabs.addTab(self.history_tab, "История")
        self.tabs.addTab(self.player_tab, "Плеер")
        self.tabs.addTab(self.settings_tab, "Настройки")

        self.setCentralWidget(self.tabs)

    def _build_detection_tab(self) -> QWidget:
        tab = QWidget()
        main_layout = QVBoxLayout()

        title = QLabel("Детектор")
        title.setObjectName("MainTitle")
        main_layout.addWidget(title)

        subtitle = QLabel("Desktop-приложение для анализа видео, детекции объектов и сохранения событий")
        subtitle.setObjectName("Subtitle")
        main_layout.addWidget(subtitle)

        info_panel = QLabel(
            "Модель: YOLO11n finetuned | Классы: person_no_weapon / person_with_weapon | "
            "Postprocessing: подтверждение события по последовательным кадрам"
        )
        info_panel.setObjectName("PathLabel")
        info_panel.setWordWrap(True)
        main_layout.addWidget(info_panel)

        content_layout = QHBoxLayout()

        left_layout = QVBoxLayout()

        self.preview_label = QLabel("Preview видео")
        self.preview_label.setObjectName("PreviewLabel")
        self.preview_label.setAlignment(Qt.AlignCenter)
        self.preview_label.setMinimumSize(760, 460)
        left_layout.addWidget(self.preview_label)

        self.progress_bar = QProgressBar()
        self.progress_bar.setValue(0)
        left_layout.addWidget(self.progress_bar)

        self.status_label = QLabel("Статус: ожидание")
        self.status_label.setObjectName("StatusNeutral")
        left_layout.addWidget(self.status_label)

        self.result_label = QLabel("Результат: —")
        self.result_label.setObjectName("ResultNeutral")
        left_layout.addWidget(self.result_label)

        right_layout = QVBoxLayout()

        video_group = QGroupBox("Видео")
        video_layout = QVBoxLayout()

        self.video_label = QLabel("Видео не выбрано")
        self.video_label.setObjectName("PathLabel")
        self.video_label.setWordWrap(True)
        video_layout.addWidget(self.video_label)

        video_buttons = QHBoxLayout()

        self.select_video_button = QPushButton("Выбрать видео")
        self.select_video_button.clicked.connect(self.select_video)
        video_buttons.addWidget(self.select_video_button)

        self.run_button = QPushButton("Запустить детекцию")
        self.run_button.clicked.connect(self.run_inference)
        self.run_button.setEnabled(False)
        video_buttons.addWidget(self.run_button)

        video_layout.addLayout(video_buttons)

        self.play_processed_button = QPushButton("Проиграть обработанное видео")
        self.play_processed_button.clicked.connect(self.play_last_processed_video)
        self.play_processed_button.setEnabled(False)
        video_layout.addWidget(self.play_processed_button)

        self.save_json_button = QPushButton("Сохранить результат JSON")
        self.save_json_button.clicked.connect(self.save_current_json)
        self.save_json_button.setEnabled(False)
        video_layout.addWidget(self.save_json_button)

        video_group.setLayout(video_layout)
        right_layout.addWidget(video_group)

        events_group = QGroupBox("Интервалы событий текущего видео")
        events_layout = QVBoxLayout()

        self.current_events_table = QTableWidget(0, 5)
        self.current_events_table.setHorizontalHeaderLabels(
            ["start_frame", "end_frame", "start_time", "end_time", "duration_sec"]
        )
        self.current_events_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        events_layout.addWidget(self.current_events_table)

        events_group.setLayout(events_layout)
        right_layout.addWidget(events_group)

        summary_group = QGroupBox("Сводка результата")
        summary_layout = QVBoxLayout()

        self.output_text = QTextEdit()
        self.output_text.setReadOnly(True)
        summary_layout.addWidget(self.output_text)

        summary_group.setLayout(summary_layout)
        right_layout.addWidget(summary_group)

        content_layout.addLayout(left_layout, 2)
        content_layout.addLayout(right_layout, 1)

        main_layout.addLayout(content_layout)
        tab.setLayout(main_layout)

        return tab

    def _build_history_tab(self) -> QWidget:
        tab = QWidget()
        main_layout = QVBoxLayout()

        title = QLabel("История сработок")
        title.setObjectName("MainTitle")
        main_layout.addWidget(title)

        buttons_layout = QHBoxLayout()

        self.refresh_history_button = QPushButton("Обновить историю")
        self.refresh_history_button.clicked.connect(self.refresh_history)
        buttons_layout.addWidget(self.refresh_history_button)

        self.open_report_folder_button = QPushButton("Открыть папку отчета")
        self.open_report_folder_button.clicked.connect(self.open_selected_report_folder)
        self.open_report_folder_button.setEnabled(False)
        buttons_layout.addWidget(self.open_report_folder_button)

        self.play_history_video_button = QPushButton("Проиграть обработанное видео")
        self.play_history_video_button.clicked.connect(self.play_selected_history_video)
        self.play_history_video_button.setEnabled(False)
        buttons_layout.addWidget(self.play_history_video_button)

        main_layout.addLayout(buttons_layout)

        self.history_table = QTableWidget(0, 6)
        self.history_table.setHorizontalHeaderLabels(
            ["report_id", "created_at", "events", "source_video", "processed_video", "report_dir"]
        )
        self.history_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.history_table.itemSelectionChanged.connect(self.on_history_selection_changed)
        main_layout.addWidget(self.history_table)

        lower_layout = QHBoxLayout()

        clips_group = QGroupBox("Клипы событий")
        clips_layout = QVBoxLayout()

        self.clips_table = QTableWidget(0, 5)
        self.clips_table.setHorizontalHeaderLabels(
            ["event", "start_time", "end_time", "frames", "clip_path"]
        )
        self.clips_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        clips_layout.addWidget(self.clips_table)

        self.play_clip_button = QPushButton("Проиграть выбранный клип")
        self.play_clip_button.clicked.connect(self.play_selected_clip)
        self.play_clip_button.setEnabled(False)
        clips_layout.addWidget(self.play_clip_button)

        clips_group.setLayout(clips_layout)

        details_group = QGroupBox("Детали отчета")
        details_layout = QVBoxLayout()

        self.history_details_text = QTextEdit()
        self.history_details_text.setReadOnly(True)
        details_layout.addWidget(self.history_details_text)

        details_group.setLayout(details_layout)

        lower_layout.addWidget(clips_group, 1)
        lower_layout.addWidget(details_group, 1)

        main_layout.addLayout(lower_layout)

        tab.setLayout(main_layout)
        return tab

    def _build_player_tab(self) -> QWidget:
        tab = QWidget()
        main_layout = QVBoxLayout()

        title = QLabel("Плеер обработанных видео")
        title.setObjectName("MainTitle")
        main_layout.addWidget(title)

        self.video_widget = QVideoWidget()
        self.video_widget.setMinimumSize(900, 500)
        self.player.setVideoOutput(self.video_widget)
        main_layout.addWidget(self.video_widget)

        controls = QHBoxLayout()

        self.open_player_video_button = QPushButton("Открыть видео")
        self.open_player_video_button.clicked.connect(self.open_video_in_player_dialog)
        controls.addWidget(self.open_player_video_button)

        self.player_play_button = QPushButton("Play")
        self.player_play_button.clicked.connect(self.player.play)
        controls.addWidget(self.player_play_button)

        self.player_pause_button = QPushButton("Pause")
        self.player_pause_button.clicked.connect(self.player.pause)
        controls.addWidget(self.player_pause_button)

        self.player_stop_button = QPushButton("Stop")
        self.player_stop_button.clicked.connect(self.player.stop)
        controls.addWidget(self.player_stop_button)

        main_layout.addLayout(controls)

        self.player_label = QLabel("Файл не выбран")
        self.player_label.setWordWrap(True)
        main_layout.addWidget(self.player_label)

        tab.setLayout(main_layout)
        return tab

    def _build_settings_tab(self) -> QWidget:
        tab = QWidget()
        main_layout = QVBoxLayout()

        title = QLabel("Настройки системы")
        title.setObjectName("MainTitle")
        main_layout.addWidget(title)

        subtitle = QLabel("Параметры модели, временной фильтрации, сохранения истории и email-оповещений")
        subtitle.setObjectName("Subtitle")
        main_layout.addWidget(subtitle)

        inference_group = QGroupBox("Настройки инференса")
        inference_layout = QGridLayout()

        self.conf_spin = QDoubleSpinBox()
        self.conf_spin.setRange(0.01, 0.99)
        self.conf_spin.setSingleStep(0.01)

        self.imgsz_spin = QSpinBox()
        self.imgsz_spin.setRange(320, 1280)
        self.imgsz_spin.setSingleStep(32)

        self.iou_spin = QDoubleSpinBox()
        self.iou_spin.setRange(0.1, 0.95)
        self.iou_spin.setSingleStep(0.05)

        self.min_consecutive_spin = QSpinBox()
        self.min_consecutive_spin.setRange(1, 300)

        self.save_history_checkbox = QCheckBox("Сохранять историю сработок")
        self.export_processed_checkbox = QCheckBox("Экспортировать обработанное видео")

        inference_layout.addWidget(QLabel("Confidence threshold:"), 0, 0)
        inference_layout.addWidget(self.conf_spin, 0, 1)

        inference_layout.addWidget(QLabel("Image size:"), 1, 0)
        inference_layout.addWidget(self.imgsz_spin, 1, 1)

        inference_layout.addWidget(QLabel("IoU:"), 2, 0)
        inference_layout.addWidget(self.iou_spin, 2, 1)

        inference_layout.addWidget(QLabel("Кадров подряд:"), 3, 0)
        inference_layout.addWidget(self.min_consecutive_spin, 3, 1)

        inference_layout.addWidget(self.save_history_checkbox, 4, 0, 1, 2)
        inference_layout.addWidget(self.export_processed_checkbox, 5, 0, 1, 2)

        inference_group.setLayout(inference_layout)
        main_layout.addWidget(inference_group)

        email_group = QGroupBox("Email-оповещения")
        email_layout = QGridLayout()

        self.email_enabled_checkbox = QCheckBox("Включить email-оповещения")

        self.smtp_host_edit = QLineEdit()
        self.smtp_port_spin = QSpinBox()
        self.smtp_port_spin.setRange(1, 65535)

        self.smtp_tls_checkbox = QCheckBox("Использовать TLS")

        self.sender_email_edit = QLineEdit()
        self.sender_password_edit = QLineEdit()
        self.sender_password_edit.setEchoMode(QLineEdit.Password)

        self.recipient_email_edit = QLineEdit()

        email_layout.addWidget(self.email_enabled_checkbox, 0, 0, 1, 2)

        email_layout.addWidget(QLabel("SMTP host:"), 1, 0)
        email_layout.addWidget(self.smtp_host_edit, 1, 1)

        email_layout.addWidget(QLabel("SMTP port:"), 2, 0)
        email_layout.addWidget(self.smtp_port_spin, 2, 1)

        email_layout.addWidget(self.smtp_tls_checkbox, 3, 0, 1, 2)

        email_layout.addWidget(QLabel("Sender email:"), 4, 0)
        email_layout.addWidget(self.sender_email_edit, 4, 1)

        email_layout.addWidget(QLabel("Sender password / app password:"), 5, 0)
        email_layout.addWidget(self.sender_password_edit, 5, 1)

        email_layout.addWidget(QLabel("Recipient email:"), 6, 0)
        email_layout.addWidget(self.recipient_email_edit, 6, 1)

        email_group.setLayout(email_layout)
        main_layout.addWidget(email_group)

        buttons_layout = QHBoxLayout()

        self.save_settings_button = QPushButton("Сохранить настройки")
        self.save_settings_button.clicked.connect(self.save_settings_from_ui)
        buttons_layout.addWidget(self.save_settings_button)

        self.test_email_button = QPushButton("Отправить тестовое письмо")
        self.test_email_button.clicked.connect(self.send_test_email)
        buttons_layout.addWidget(self.test_email_button)

        main_layout.addLayout(buttons_layout)

        hint = QLabel(
            "Для Gmail обычно нужен пароль приложения, а не обычный пароль аккаунта. "
            "В прототипе пароль хранится в app_settings.json открытым текстом."
        )
        hint.setWordWrap(True)
        hint.setStyleSheet("color: #666;")
        main_layout.addWidget(hint)

        main_layout.addStretch()

        tab.setLayout(main_layout)
        return tab

    # ----------------------------------------------------------------------
    # Settings
    # ----------------------------------------------------------------------

    def _load_settings_to_ui(self):
        inference = self.settings.get("inference", {})
        email = self.settings.get("email", {})

        self.conf_spin.setValue(float(inference.get("conf", 0.50)))
        self.imgsz_spin.setValue(int(inference.get("imgsz", 640)))
        self.iou_spin.setValue(float(inference.get("iou", 0.5)))
        self.min_consecutive_spin.setValue(int(inference.get("min_consecutive", 10)))
        self.save_history_checkbox.setChecked(bool(inference.get("save_history", True)))
        self.export_processed_checkbox.setChecked(bool(inference.get("export_processed_video", True)))

        self.email_enabled_checkbox.setChecked(bool(email.get("enabled", False)))
        self.smtp_host_edit.setText(str(email.get("smtp_host", "smtp.gmail.com")))
        self.smtp_port_spin.setValue(int(email.get("smtp_port", 587)))
        self.smtp_tls_checkbox.setChecked(bool(email.get("use_tls", True)))
        self.sender_email_edit.setText(str(email.get("sender_email", "")))
        self.sender_password_edit.setText(str(email.get("sender_password", "")))
        self.recipient_email_edit.setText(str(email.get("recipient_email", "")))

    def collect_settings_from_ui(self) -> dict:
        return {
            "inference": {
                "conf": float(self.conf_spin.value()),
                "imgsz": int(self.imgsz_spin.value()),
                "iou": float(self.iou_spin.value()),
                "min_consecutive": int(self.min_consecutive_spin.value()),
                "save_history": bool(self.save_history_checkbox.isChecked()),
                "export_processed_video": bool(self.export_processed_checkbox.isChecked()),
            },
            "email": {
                "enabled": bool(self.email_enabled_checkbox.isChecked()),
                "smtp_host": self.smtp_host_edit.text().strip(),
                "smtp_port": int(self.smtp_port_spin.value()),
                "use_tls": bool(self.smtp_tls_checkbox.isChecked()),
                "sender_email": self.sender_email_edit.text().strip(),
                "sender_password": self.sender_password_edit.text(),
                "recipient_email": self.recipient_email_edit.text().strip(),
            },
        }

    def save_settings_from_ui(self):
        self.settings = self.collect_settings_from_ui()
        save_settings(self.settings)
        QMessageBox.information(self, "Готово", "Настройки сохранены.")

    def send_test_email(self):
        settings = self.collect_settings_from_ui()
        email_settings = settings["email"].copy()
        email_settings["enabled"] = True

        try:
            send_detection_email(
                email_settings,
                {
                    "report_id": "test_email",
                    "source_video": "test",
                    "report_dir": "",
                    "processed_video_path": "",
                    "events": [
                        {
                            "start_time_sec": 1.0,
                            "end_time_sec": 2.0,
                            "start_frame": 25,
                            "end_frame": 50,
                        }
                    ],
                },
            )
            QMessageBox.information(self, "Готово", "Тестовое письмо отправлено.")
        except Exception as exc:
            QMessageBox.critical(self, "Ошибка email", str(exc))

    # ----------------------------------------------------------------------
    # Detection
    # ----------------------------------------------------------------------

    def select_video(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "Выбрать видео",
            "",
            "Video files (*.mp4 *.avi *.mov *.mkv)",
        )

        if not file_path:
            return

        self.video_path = file_path
        self.video_label.setText(f"Видео: {file_path}")
        self.run_button.setEnabled(True)

        qimage = first_frame_to_qimage(file_path)
        if qimage is not None:
            self.current_preview_qimage = qimage
            self.set_preview(qimage)

    def set_preview(self, qimage: QImage):
        self.current_preview_qimage = qimage

        pixmap = QPixmap.fromImage(qimage)
        scaled = pixmap.scaled(
            self.preview_label.size(),
            Qt.KeepAspectRatio,
            Qt.SmoothTransformation,
        )

        self.preview_label.setPixmap(scaled)

    def resizeEvent(self, event):
        super().resizeEvent(event)

        if self.current_preview_qimage is not None:
            self.set_preview(self.current_preview_qimage)

    def run_inference(self):
        if not self.video_path:
            QMessageBox.warning(self, "Ошибка", "Сначала выбери видео.")
            return

        self.settings = self.collect_settings_from_ui()
        save_settings(self.settings)

        inference = self.settings["inference"]
        email_settings = self.settings["email"]

        export_video_path = None
        if inference.get("export_processed_video", True):
            video = Path(self.video_path)
            export_video_path = str(Path("exports") / f"{video.stem}_processed.mp4")

        self.run_button.setEnabled(False)
        self.select_video_button.setEnabled(False)
        self.save_json_button.setEnabled(False)
        self.play_processed_button.setEnabled(False)

        self.progress_bar.setValue(0)
        self.output_text.clear()
        self.current_events_table.setRowCount(0)

        self.result_label.setText("Результат: обработка...")
        self.result_label.setObjectName("ResultNeutral")
        self.result_label.style().unpolish(self.result_label)
        self.result_label.style().polish(self.result_label)
        self.status_label.setText("Статус: запуск...")

        self.thread = QThread()

        self.worker = InferenceWorker(
            video_path=self.video_path,
            conf=float(inference.get("conf", 0.50)),
            imgsz=int(inference.get("imgsz", 640)),
            iou=float(inference.get("iou", 0.5)),
            min_consecutive=int(inference.get("min_consecutive", 10)),
            export_video_path=export_video_path,
            save_history=bool(inference.get("save_history", True)),
            email_settings=email_settings,
            preview_every_n_frames=2,
        )

        self.worker.moveToThread(self.thread)

        self.thread.started.connect(self.worker.run)

        self.worker.progress_text.connect(self.on_progress_text)
        self.worker.progress_value.connect(self.on_progress_value)
        self.worker.preview_frame.connect(self.on_preview_frame)

        self.worker.finished.connect(self.on_inference_finished)
        self.worker.error.connect(self.on_inference_error)

        self.worker.finished.connect(self.thread.quit)
        self.worker.error.connect(self.thread.quit)

        self.worker.finished.connect(self.worker.deleteLater)
        self.worker.error.connect(self.worker.deleteLater)
        self.thread.finished.connect(self.thread.deleteLater)

        self.thread.start()

    def on_progress_text(self, message: str):
        self.status_label.setText(f"Статус: {message}")

    def on_progress_value(self, value: int):
        self.progress_bar.setValue(value)

    def on_preview_frame(self, qimage: QImage):
        self.set_preview(qimage)

    def on_inference_finished(self, result: dict):
        self.last_result = result

        has_weapon = result["video_result"]["has_person_with_weapon"]

        if has_weapon:
            self.result_label.setText("Результат: ОБНАРУЖЕН человек с оружием")
            self.result_label.setObjectName("ResultDanger")
        else:
            self.result_label.setText("Результат: человек с оружием не обнаружен")
            self.result_label.setObjectName("ResultSafe")

        self.result_label.style().unpolish(self.result_label)
        self.result_label.style().polish(self.result_label)

        self.fill_current_events_table(result["video_result"]["events"])

        performance = result["performance"]
        metadata = result["video_metadata"]
        settings = result["settings"]
        history_report = result.get("history_report")

        summary = {
            "has_person_with_weapon": has_weapon,
            "events_count": len(result["video_result"]["events"]),
            "events": result["video_result"]["events"],
            "source_frame_count": metadata["source_frame_count"],
            "frames_processed": metadata["frames_processed"],
            "elapsed_sec": round(performance["elapsed_sec"], 3),
            "fps_processing": round(performance["fps_processing"], 3),
            "sec_per_frame": round(performance["sec_per_frame"], 4),
            "conf": settings["conf"],
            "imgsz": settings["imgsz"],
            "min_consecutive": settings["min_consecutive"],
            "processed_video_path": result.get("processed_video_path"),
            "history_report_id": history_report.get("report_id") if history_report else None,
        }

        self.output_text.setPlainText(json.dumps(summary, ensure_ascii=False, indent=2))

        self.status_label.setText("Статус: готово")
        self.progress_bar.setValue(100)

        self.run_button.setEnabled(True)
        self.select_video_button.setEnabled(True)
        self.save_json_button.setEnabled(True)

        if result.get("processed_video_path"):
            self.play_processed_button.setEnabled(True)

        self.refresh_history()

    def on_inference_error(self, message: str):
        self.status_label.setText("Статус: ошибка")

        QMessageBox.critical(
            self,
            "Ошибка инференса",
            message,
        )

        self.run_button.setEnabled(True)
        self.select_video_button.setEnabled(True)

    def fill_current_events_table(self, events: list[dict]):
        self.current_events_table.setRowCount(0)

        for event in events:
            row = self.current_events_table.rowCount()
            self.current_events_table.insertRow(row)

            values = [
                event.get("start_frame", ""),
                event.get("end_frame", ""),
                format_seconds(event.get("start_time_sec", 0)),
                format_seconds(event.get("end_time_sec", 0)),
                f"{event.get('duration_sec', 0):.2f}",
            ]

            for col, value in enumerate(values):
                self.current_events_table.setItem(row, col, QTableWidgetItem(str(value)))

        self.current_events_table.resizeColumnsToContents()

    def save_current_json(self):
        if self.last_result is None:
            QMessageBox.warning(self, "Ошибка", "Нет результата для сохранения.")
            return

        file_path, _ = QFileDialog.getSaveFileName(
            self,
            "Сохранить результат",
            "result.json",
            "JSON files (*.json)",
        )

        if not file_path:
            return

        with Path(file_path).open("w", encoding="utf-8") as f:
            json.dump(self.last_result, f, ensure_ascii=False, indent=2)

        QMessageBox.information(self, "Готово", f"Результат сохранен:\n{file_path}")

    def play_last_processed_video(self):
        if not self.last_result:
            return

        path = self.last_result.get("processed_video_path")
        if not path:
            QMessageBox.warning(self, "Ошибка", "Нет обработанного видео.")
            return

        self.play_video(path)

    # ----------------------------------------------------------------------
    # History
    # ----------------------------------------------------------------------

    def refresh_history(self):
        try:
            self.history_records = load_history()
        except Exception:
            self.history_records = []

        self.history_table.setRowCount(0)
        self.clips_table.setRowCount(0)
        self.history_details_text.clear()

        for record in self.history_records:
            row = self.history_table.rowCount()
            self.history_table.insertRow(row)

            values = [
                record.get("report_id", ""),
                record.get("created_at", ""),
                str(len(record.get("events", []))),
                record.get("source_video", ""),
                record.get("processed_video_path", ""),
                record.get("report_dir", ""),
            ]

            for col, value in enumerate(values):
                self.history_table.setItem(row, col, QTableWidgetItem(str(value)))

        self.history_table.resizeColumnsToContents()

        self.open_report_folder_button.setEnabled(False)
        self.play_history_video_button.setEnabled(False)
        self.play_clip_button.setEnabled(False)

    def on_history_selection_changed(self):
        selected = self.history_table.selectedItems()

        if not selected:
            self.selected_history_record = None
            return

        row = selected[0].row()

        if row < 0 or row >= len(self.history_records):
            self.selected_history_record = None
            return

        record = self.history_records[row]
        self.selected_history_record = record

        self.history_details_text.setPlainText(
            json.dumps(record, ensure_ascii=False, indent=2)
        )

        self.fill_clips_table(record.get("clips", []))

        self.open_report_folder_button.setEnabled(bool(record.get("report_dir")))
        self.play_history_video_button.setEnabled(bool(record.get("processed_video_path")))

    def fill_clips_table(self, clips: list[dict]):
        self.clips_table.setRowCount(0)

        for clip in clips:
            row = self.clips_table.rowCount()
            self.clips_table.insertRow(row)

            frames = f"{clip.get('start_frame', '')}-{clip.get('end_frame', '')}"

            values = [
                clip.get("event_index", ""),
                format_seconds(clip.get("start_time_sec", 0)),
                format_seconds(clip.get("end_time_sec", 0)),
                frames,
                clip.get("clip_path", ""),
            ]

            for col, value in enumerate(values):
                self.clips_table.setItem(row, col, QTableWidgetItem(str(value)))

        self.clips_table.resizeColumnsToContents()
        self.play_clip_button.setEnabled(len(clips) > 0)

    def open_selected_report_folder(self):
        if not self.selected_history_record:
            return

        report_dir = self.selected_history_record.get("report_dir", "")

        if not report_dir:
            return

        path = Path(report_dir)

        if not path.exists():
            QMessageBox.warning(self, "Ошибка", f"Папка не найдена:\n{path}")
            return

        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path.resolve())))

    def play_selected_history_video(self):
        if not self.selected_history_record:
            return

        path = self.selected_history_record.get("processed_video_path", "")

        if not path:
            QMessageBox.warning(self, "Ошибка", "У отчета нет обработанного видео.")
            return

        self.play_video(path)

    def play_selected_clip(self):
        selected = self.clips_table.selectedItems()

        if not selected:
            QMessageBox.warning(self, "Ошибка", "Выбери клип в таблице.")
            return

        row = selected[0].row()
        item = self.clips_table.item(row, 4)

        if item is None:
            return

        path = item.text()

        if not path:
            return

        self.play_video(path)

    # ----------------------------------------------------------------------
    # Player
    # ----------------------------------------------------------------------

    def open_video_in_player_dialog(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "Открыть видео",
            "",
            "Video files (*.mp4 *.avi *.mov *.mkv)",
        )

        if not file_path:
            return

        self.play_video(file_path)

    def play_video(self, path: str):
        video_path = Path(path)

        if not video_path.exists():
            QMessageBox.warning(self, "Ошибка", f"Видео не найдено:\n{video_path}")
            return

        self.tabs.setCurrentWidget(self.player_tab)

        self.player.setSource(QUrl.fromLocalFile(str(video_path.resolve())))
        self.player_label.setText(f"Видео: {video_path}")
        self.player.play()

    # ----------------------------------------------------------------------
    # Cleanup
    # ----------------------------------------------------------------------

    def closeEvent(self, event):
        try:
            self.player.stop()
        except Exception:
            pass

        event.accept()