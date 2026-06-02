APP_STYLE = """
QMainWindow {
    background-color: #f4f6f8;
}

QWidget {
    font-family: "Segoe UI", Arial, sans-serif;
    font-size: 14px;
    color: #1f2933;
}

QTabWidget::pane {
    border: 1px solid #d7dde5;
    background: #ffffff;
    border-radius: 8px;
}

QTabBar::tab {
    background: #e9eef5;
    color: #334155;
    padding: 10px 22px;
    margin-right: 4px;
    border-top-left-radius: 8px;
    border-top-right-radius: 8px;
}

QTabBar::tab:selected {
    background: #2563eb;
    color: #ffffff;
    font-weight: 600;
}

QTabBar::tab:hover {
    background: #dbe7ff;
    color: #1d4ed8;
}

QGroupBox {
    background-color: #ffffff;
    border: 1px solid #d9e2ec;
    border-radius: 10px;
    margin-top: 12px;
    padding: 12px;
    font-weight: 600;
}

QGroupBox::title {
    subcontrol-origin: margin;
    subcontrol-position: top left;
    padding: 0px 8px;
    color: #1e3a8a;
}

QPushButton {
    background-color: #2563eb;
    color: white;
    border: none;
    border-radius: 7px;
    padding: 9px 14px;
    font-weight: 600;
}

QPushButton:hover {
    background-color: #1d4ed8;
}

QPushButton:pressed {
    background-color: #1e40af;
}

QPushButton:disabled {
    background-color: #cbd5e1;
    color: #64748b;
}

QLineEdit, QTextEdit, QSpinBox, QDoubleSpinBox {
    background-color: #ffffff;
    border: 1px solid #cbd5e1;
    border-radius: 6px;
    padding: 6px;
    selection-background-color: #2563eb;
}

QLineEdit:focus, QTextEdit:focus, QSpinBox:focus, QDoubleSpinBox:focus {
    border: 1px solid #2563eb;
}

QTableWidget {
    background-color: #ffffff;
    border: 1px solid #d9e2ec;
    border-radius: 8px;
    gridline-color: #e5e7eb;
    selection-background-color: #dbeafe;
    selection-color: #111827;
}

QHeaderView::section {
    background-color: #eff6ff;
    color: #1e3a8a;
    padding: 7px;
    border: none;
    border-right: 1px solid #dbeafe;
    font-weight: 600;
}

QProgressBar {
    border: 1px solid #cbd5e1;
    border-radius: 8px;
    background: #e5e7eb;
    height: 18px;
    text-align: center;
    color: #111827;
    font-weight: 600;
}

QProgressBar::chunk {
    background-color: #22c55e;
    border-radius: 8px;
}

QCheckBox {
    spacing: 8px;
}

QCheckBox::indicator {
    width: 16px;
    height: 16px;
}

QLabel#MainTitle {
    font-size: 28px;
    font-weight: 800;
    color: #0f172a;
    padding-bottom: 8px;
}

QLabel#Subtitle {
    color: #64748b;
    font-size: 14px;
}

QLabel#PreviewLabel {
    background-color: #0f172a;
    color: #cbd5e1;
    border: 2px solid #1e293b;
    border-radius: 12px;
}

QLabel#StatusNeutral {
    background-color: #eef2ff;
    color: #3730a3;
    border-radius: 8px;
    padding: 8px;
    font-weight: 600;
}

QLabel#ResultNeutral {
    background-color: #f1f5f9;
    color: #334155;
    border-radius: 10px;
    padding: 12px;
    font-size: 17px;
    font-weight: 700;
}

QLabel#ResultDanger {
    background-color: #fee2e2;
    color: #991b1b;
    border: 1px solid #fecaca;
    border-radius: 10px;
    padding: 12px;
    font-size: 17px;
    font-weight: 800;
}

QLabel#ResultSafe {
    background-color: #dcfce7;
    color: #166534;
    border: 1px solid #bbf7d0;
    border-radius: 10px;
    padding: 12px;
    font-size: 17px;
    font-weight: 800;
}

QLabel#PathLabel {
    background-color: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 8px;
    color: #475569;
}
"""