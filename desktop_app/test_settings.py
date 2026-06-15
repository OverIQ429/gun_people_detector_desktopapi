"""
Тесты на основе Hypothesis для модуля settings_manager.py

Проверяемые свойства:
  1. Сохранение и загрузка не искажают данные (roundtrip)
  2. Дефолтные ключи всегда присутствуют после загрузки
  3. Пользовательские значения имеют приоритет над дефолтными
  4. Неизвестные секции не теряются при загрузке
  5. Повторное сохранение перезаписывает предыдущее
  6. Файл всегда является валидным JSON
  7. При отсутствии файла возвращаются дефолтные настройки
"""

import json
import tempfile
import shutil
import os
import pytest
from pathlib import Path
from copy import deepcopy
from hypothesis import given, settings, HealthCheck
from hypothesis import strategies as st

import desktop_app.settings_manager as sm
from desktop_app.settings_manager import load_settings, save_settings, DEFAULT_SETTINGS


# ══════════════════════════════════════════════════════════════════
#  ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ══════════════════════════════════════════════════════════════════

def with_temp_settings(func):
    """
    Декоратор: подменяет SETTINGS_PATH на временный файл,
    выполняет функцию, затем восстанавливает путь.
    Не использует os.chdir — избегаем проблем с Windows.
    """
    def wrapper(*args, **kwargs):
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            return func(*args, **kwargs)
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)
    return wrapper


# ══════════════════════════════════════════════════════════════════
#  СТРАТЕГИИ
# ══════════════════════════════════════════════════════════════════

# Стратегия для inference-секции
inference_strategy = st.fixed_dictionaries({
    "conf":                    st.floats(min_value=0.01, max_value=0.99,
                                         allow_nan=False),
    "imgsz":                   st.sampled_from([320, 416, 512, 640, 1280]),
    "iou":                     st.floats(min_value=0.1, max_value=0.95,
                                         allow_nan=False),
    "min_consecutive":         st.integers(min_value=1, max_value=300),
    "save_history":            st.booleans(),
    "export_processed_video":  st.booleans(),
})

# Стратегия для email-секции
email_strategy = st.fixed_dictionaries({
    "enabled":          st.booleans(),
    "smtp_host":        st.text(min_size=1, max_size=50,
                                alphabet="abcdefghijklmnopqrstuvwxyz.-"),
    "smtp_port":        st.integers(min_value=1, max_value=65535),
    "use_tls":          st.booleans(),
    "sender_email":     st.text(min_size=0, max_size=50),
    "sender_password":  st.text(min_size=0, max_size=30),
    "recipient_email":  st.text(min_size=0, max_size=50),
})

# Полные настройки
full_settings_strategy = st.fixed_dictionaries({
    "inference": inference_strategy,
    "email":     email_strategy,
})


# ══════════════════════════════════════════════════════════════════
#  БЛОК 1 — Roundtrip: сохранение и загрузка
# ══════════════════════════════════════════════════════════════════

class TestRoundtrip:

    @given(user_settings=full_settings_strategy)
    @settings(max_examples=500,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_saved_settings_load_correctly(self, user_settings):
        """Сохранённые настройки загружаются без искажений."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            save_settings(user_settings)
            loaded = load_settings()
            # Проверяем что все сохранённые ключи присутствуют
            for section, values in user_settings.items():
                assert section in loaded, \
                    f"Секция '{section}' не найдена после загрузки"
                for key, value in values.items():
                    assert loaded[section][key] == value, \
                        f"Значение {section}.{key} изменилось: " \
                        f"сохранено {value}, загружено {loaded[section][key]}"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)

    @given(user_settings=full_settings_strategy)
    @settings(max_examples=300,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_file_is_valid_json_after_save(self, user_settings):
        """Файл настроек всегда является валидным JSON после сохранения."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            save_settings(user_settings)
            content = sm.SETTINGS_PATH.read_text(encoding="utf-8")
            parsed = json.loads(content)
            assert isinstance(parsed, dict)
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)

    @given(settings_list=st.lists(full_settings_strategy,
                                   min_size=2, max_size=5))
    @settings(max_examples=200,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_last_save_wins(self, settings_list):
        """При повторном сохранении побеждают последние настройки."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            for s in settings_list:
                save_settings(s)
            loaded = load_settings()
            last = settings_list[-1]
            for section, values in last.items():
                for key, value in values.items():
                    assert loaded[section][key] == value, \
                        f"После повторного сохранения {section}.{key} " \
                        f"должно быть {value}, получено {loaded[section][key]}"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)


# ══════════════════════════════════════════════════════════════════
#  БЛОК 2 — Дефолтные значения
# ══════════════════════════════════════════════════════════════════

class TestDefaults:

    def test_missing_file_returns_defaults(self):
        """Если файл настроек отсутствует — возвращаются дефолтные значения."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "nonexistent.json"
            loaded = load_settings()
            for section, values in DEFAULT_SETTINGS.items():
                assert section in loaded, \
                    f"Дефолтная секция '{section}' отсутствует"
                for key, default_value in values.items():
                    assert loaded[section][key] == default_value, \
                        f"Дефолтное значение {section}.{key} изменилось"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)

    @given(user_settings=full_settings_strategy)
    @settings(max_examples=300,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_all_default_keys_always_present(self, user_settings):
        """После загрузки все дефолтные ключи всегда присутствуют."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            save_settings(user_settings)
            loaded = load_settings()
            for section, values in DEFAULT_SETTINGS.items():
                assert section in loaded, \
                    f"Дефолтная секция '{section}' исчезла после загрузки"
                for key in values:
                    assert key in loaded[section], \
                        f"Дефолтный ключ '{section}.{key}' исчез после загрузки"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)

    @given(partial_inference=st.fixed_dictionaries({
        "conf": st.floats(min_value=0.1, max_value=0.9, allow_nan=False)
    }))
    @settings(max_examples=300,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_missing_keys_filled_with_defaults(self, partial_inference):
        """Отсутствующие ключи заполняются дефолтными значениями."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            # Сохраняем только часть inference-настроек
            partial_settings = {"inference": partial_inference}
            save_settings(partial_settings)
            loaded = load_settings()
            # Все дефолтные ключи inference должны присутствовать
            for key in DEFAULT_SETTINGS["inference"]:
                assert key in loaded["inference"], \
                    f"Ключ 'inference.{key}' не заполнен дефолтным значением"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)


# ══════════════════════════════════════════════════════════════════
#  БЛОК 3 — Приоритет пользовательских значений
# ══════════════════════════════════════════════════════════════════

class TestUserPriority:

    @given(user_settings=full_settings_strategy)
    @settings(max_examples=500,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_user_values_override_defaults(self, user_settings):
        """Пользовательские значения всегда имеют приоритет над дефолтными."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            save_settings(user_settings)
            loaded = load_settings()
            for section, values in user_settings.items():
                if section in DEFAULT_SETTINGS:
                    for key, user_value in values.items():
                        assert loaded[section][key] == user_value, \
                            f"{section}.{key}: ожидалось пользовательское " \
                            f"значение {user_value}, " \
                            f"получено {loaded[section][key]}"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)

    @given(
        conf=st.floats(min_value=0.1, max_value=0.9, allow_nan=False),
        port=st.integers(min_value=1, max_value=65535),
    )
    @settings(max_examples=500,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_specific_values_preserved(self, conf, port):
        """Конкретные значения conf и smtp_port сохраняются точно."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            user_settings = deepcopy(DEFAULT_SETTINGS)
            user_settings["inference"]["conf"] = conf
            user_settings["email"]["smtp_port"] = port
            save_settings(user_settings)
            loaded = load_settings()
            assert abs(loaded["inference"]["conf"] - conf) < 1e-9, \
                f"conf изменился: сохранено {conf}, загружено {loaded['inference']['conf']}"
            assert loaded["email"]["smtp_port"] == port, \
                f"smtp_port изменился: сохранено {port}, загружено {loaded['email']['smtp_port']}"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)


# ══════════════════════════════════════════════════════════════════
#  БЛОК 4 — Граничные случаи
# ══════════════════════════════════════════════════════════════════

class TestEdgeCases:

    def test_empty_file_falls_back_to_defaults(self):
        """Пустой файл настроек не роняет приложение — возвращаются дефолты."""
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            # Записываем пустой JSON-объект
            sm.SETTINGS_PATH.write_text("{}", encoding="utf-8")
            loaded = load_settings()
            # Все дефолтные секции должны присутствовать
            for section in DEFAULT_SETTINGS:
                assert section in loaded, \
                    f"Секция '{section}' отсутствует при пустом файле"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)

    @given(extra_section=st.text(min_size=1, max_size=20,
                                  alphabet="abcdefghijklmnopqrstuvwxyz_"))
    @settings(max_examples=200,
              suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_unknown_sections_preserved(self, extra_section):
        """Неизвестные секции не удаляются при загрузке."""
        from hypothesis import assume
        assume(extra_section not in DEFAULT_SETTINGS)
        tmp_dir = tempfile.mkdtemp()
        original_path = sm.SETTINGS_PATH
        try:
            sm.SETTINGS_PATH = Path(tmp_dir) / "app_settings.json"
            settings_with_extra = deepcopy(DEFAULT_SETTINGS)
            settings_with_extra[extra_section] = {"custom_key": "custom_value"}
            save_settings(settings_with_extra)
            loaded = load_settings()
            assert extra_section in loaded, \
                f"Неизвестная секция '{extra_section}' была удалена при загрузке"
        finally:
            sm.SETTINGS_PATH = original_path
            shutil.rmtree(tmp_dir, ignore_errors=True)

    def test_default_inference_values_are_valid(self):
        """Дефолтные значения inference находятся в допустимых диапазонах."""
        inf = DEFAULT_SETTINGS["inference"]
        assert 0.0 < inf["conf"] < 1.0, "conf должен быть в (0, 1)"
        assert inf["imgsz"] > 0, "imgsz должен быть положительным"
        assert 0.0 < inf["iou"] < 1.0, "iou должен быть в (0, 1)"
        assert inf["min_consecutive"] >= 1, \
            "min_consecutive должен быть >= 1"

    def test_default_email_port_is_valid(self):
        """Дефолтный SMTP-порт находится в допустимом диапазоне."""
        port = DEFAULT_SETTINGS["email"]["smtp_port"]
        assert 1 <= port <= 65535, \
            f"smtp_port={port} выходит за допустимый диапазон"
