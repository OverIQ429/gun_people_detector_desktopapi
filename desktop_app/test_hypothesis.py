from hypothesis import given, settings
from hypothesis import strategies as st
from desktop_app.worker import build_events_from_flags


flags_strategy = st.lists(st.booleans(), min_size=0, max_size=300)
fps_strategy = st.floats(min_value=1.0, max_value=60.0).filter(lambda x: x == x)


@given(
    flags=flags_strategy,
    fps=fps_strategy,
    min_consecutive=st.integers(min_value=1, max_value=30)
)
@settings(max_examples=1000)
def test_events_do_not_overlap(flags, fps, min_consecutive):
    """События никогда не пересекаются по кадрам."""
    events, _ = build_events_from_flags(flags, fps, min_consecutive)
    for i in range(len(events)):
        for j in range(i + 1, len(events)):
            assert events[i]["end_frame"] < events[j]["start_frame"], (
                f"Событие {i} ({events[i]['start_frame']}–{events[i]['end_frame']}) "
                f"пересекается с событием {j} ({events[j]['start_frame']}–{events[j]['end_frame']})"
            )


@given(
    flags=flags_strategy,
    fps=fps_strategy,
    min_consecutive=st.integers(min_value=1, max_value=30)
)
@settings(max_examples=1000)
def test_event_bounds_correct(flags, fps, min_consecutive):
    """start_frame всегда <= end_frame (событие из 1 кадра допустимо)."""
    events, _ = build_events_from_flags(flags, fps, min_consecutive)
    for e in events:
        assert e["start_frame"] <= e["end_frame"], (
            f"Некорректные границы: start={e['start_frame']}, end={e['end_frame']}"
        )


@given(
    flags=flags_strategy,
    fps=fps_strategy,
    min_consecutive=st.integers(min_value=1, max_value=30)
)
@settings(max_examples=1000)
def test_event_min_length(flags, fps, min_consecutive):
    """Длина каждого события >= min_consecutive кадров."""
    events, _ = build_events_from_flags(flags, fps, min_consecutive)
    for e in events:
        length = e["end_frame"] - e["start_frame"] + 1
        assert length >= min_consecutive, (
            f"Событие короче порога: длина={length}, min_consecutive={min_consecutive}"
        )


@given(
    flags=flags_strategy,
    fps=fps_strategy,
    min_consecutive=st.integers(min_value=1, max_value=30)
)
@settings(max_examples=1000)
def test_no_events_when_no_flags(flags, fps, min_consecutive):
    """Если все флаги False — событий нет."""
    all_false = [False] * len(flags)
    events, confirmed = build_events_from_flags(all_false, fps, min_consecutive)
    assert events == [], f"Ожидался пустой список событий, получено: {events}"
    assert confirmed == [], f"Ожидался пустой список кадров, получено: {confirmed}"


@given(
    flags=flags_strategy,
    fps=fps_strategy,
    min_consecutive=st.integers(min_value=1, max_value=30)
)
@settings(max_examples=1000)
def test_events_within_frame_bounds(flags, fps, min_consecutive):
    """Кадры событий не выходят за пределы длины входного списка."""
    events, _ = build_events_from_flags(flags, fps, min_consecutive)
    n = len(flags)
    for e in events:
        # кадры нумеруются с 1
        assert e["start_frame"] >= 1, "start_frame не может быть меньше 1"
        assert e["end_frame"] <= n, (
            f"end_frame={e['end_frame']} выходит за длину списка={n}"
        )


@given(
    flags=flags_strategy,
    fps=fps_strategy,
    min_consecutive=st.integers(min_value=1, max_value=30)
)
@settings(max_examples=1000)
def test_time_consistent_with_frames(flags, fps, min_consecutive):
    """Временные метки согласованы с номерами кадров — кадры нумеруются с 1."""
    events, _ = build_events_from_flags(flags, fps, min_consecutive)
    for e in events:
        # кадр 1 → 0.0 сек, кадр N → (N-1)/fps сек
        expected_start = (e["start_frame"] - 1) / fps
        expected_end = (e["end_frame"] - 1) / fps
        assert abs(e["start_time_sec"] - expected_start) < 0.001, (
            f"start_time_sec={e['start_time_sec']:.4f} не соответствует "
            f"(start_frame-1)/fps={expected_start:.4f}"
        )
        assert abs(e["end_time_sec"] - expected_end) < 0.001, (
            f"end_time_sec={e['end_time_sec']:.4f} не соответствует "
            f"(end_frame-1)/fps={expected_end:.4f}"
        )