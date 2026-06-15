/**
 * Formal Dafny Specification for build_events_from_flags
 * desktop_app/worker.py
 *
 * Verified postconditions:
 *   [P1] Events are strictly non-overlapping
 *   [P2] Each event meets minimum duration requirement
 *   [P3] All event frame numbers are in valid range [1, |flags|]
 *   [P4] Each event duration_frames field is correctly computed
 *   [P5] All confirmed_frames are in valid range [1, |flags|]
 *   [P7] Events are sorted by start_frame
 *
 * Notes:
 *   - fps <= 0.0 is normalized to 25.0, matching Python code.
 *   - Empty flags sequence is allowed.
 *   - ConfirmedFramesMatchEvents is kept as a ghost predicate for documentation.
 */

module BuildEventsFromFlags {

  // ── Data structure ───────────────────────────────────────────────

  datatype Event = Event(
    start_frame:     int,
    end_frame:       int,
    duration_frames: int,
    start_time_sec:  real,
    end_time_sec:    real,
    duration_sec:    real
  )

  // ── Helper functions ─────────────────────────────────────────────

  function SecondsFromFrame(frame: int, fps: real): real
    requires frame >= 1
    requires fps > 0.0
    decreases frame
  {
    if frame == 1 then 0.0
    else SecondsFromFrame(frame - 1, fps) + 1.0 / fps
  }

  function EffectiveFps(fps: real): real {
    if fps <= 0.0 then 25.0 else fps
  }

  // ── Predicates ───────────────────────────────────────────────────

  predicate IsValidEvent(e: Event, num_frames: int, min_consecutive: int) {
    e.start_frame <= e.end_frame &&
    1 <= e.start_frame &&
    e.end_frame <= num_frames &&
    e.duration_frames == e.end_frame - e.start_frame + 1 &&
    e.duration_frames >= min_consecutive &&
    0.0 <= e.start_time_sec &&
    e.end_time_sec >= e.start_time_sec &&
    e.duration_sec > 0.0
  }

  predicate AreNonOverlapping(events: seq<Event>) {
    forall i, j :: 0 <= i < j < |events| ==>
      events[i].end_frame < events[j].start_frame
  }

  predicate AllEventsValid(
      events: seq<Event>,
      num_frames: int,
      min_consecutive: int)
  {
    forall e :: e in events ==>
      IsValidEvent(e, num_frames, min_consecutive)
  }

  predicate AllFramesInBounds(frames: seq<int>, num_frames: int) {
    forall f :: f in frames ==> 1 <= f <= num_frames
  }

  predicate IsSortedByStart(events: seq<Event>) {
    forall i, j :: 0 <= i < j < |events| ==>
      events[i].start_frame < events[j].start_frame
  }

  // ghost — только для документации, не в постусловиях метода
  ghost predicate ConfirmedFramesMatchEvents(
      events: seq<Event>,
      confirmed_frames: seq<int>)
  {
    forall frame :: frame in confirmed_frames <==>
      (exists e :: e in events &&
        e.start_frame <= frame <= e.end_frame)
  }

  // ── Lemmas ───────────────────────────────────────────────────────

  lemma Lemma_EffectiveFpsPositive(fps: real)
    ensures EffectiveFps(fps) > 0.0
  {
  }

  lemma Lemma_NonOverlappingImpliesSorted(events: seq<Event>)
    requires AreNonOverlapping(events)
    requires forall e :: e in events ==> e.start_frame <= e.end_frame
    ensures IsSortedByStart(events)
  {
    forall i, j | 0 <= i < j < |events|
      ensures events[i].start_frame < events[j].start_frame
    {
      assert events[i].end_frame < events[j].start_frame;
      assert events[i] in events;
      assert events[i].start_frame <= events[i].end_frame;
    }
  }

  lemma Lemma_SecondsFromFrameNonNegative(frame: int, fps: real)
    requires frame >= 1
    requires fps > 0.0
    ensures SecondsFromFrame(frame, fps) >= 0.0
    decreases frame
  {
    if frame == 1 {
    } else {
      Lemma_SecondsFromFrameNonNegative(frame - 1, fps);
      assert 1.0 / fps > 0.0;
    }
  }

  lemma Lemma_SecondsFromFrameMonotonic(start_frame: int, end_frame: int, fps: real)
    requires 1 <= start_frame <= end_frame
    requires fps > 0.0
    ensures SecondsFromFrame(end_frame, fps) >= SecondsFromFrame(start_frame, fps)
    decreases end_frame - start_frame
  {
    if start_frame == end_frame {
    } else {
      assert 1 <= start_frame <= end_frame - 1;
      Lemma_SecondsFromFrameMonotonic(start_frame, end_frame - 1, fps);

      assert SecondsFromFrame(end_frame, fps) ==
        SecondsFromFrame(end_frame - 1, fps) + 1.0 / fps;

      assert 1.0 / fps > 0.0;
    }
  }

  lemma Lemma_AppendPreservesNonOverlapping(
      events: seq<Event>,
      new_event: Event,
      num_frames: int,
      min_consecutive: int)
    requires AreNonOverlapping(events)
    requires AllEventsValid(events, num_frames, min_consecutive)
    requires IsValidEvent(new_event, num_frames, min_consecutive)
    requires |events| == 0 ||
      events[|events|-1].end_frame < new_event.start_frame
    ensures AreNonOverlapping(events + [new_event])
    ensures AllEventsValid(events + [new_event], num_frames, min_consecutive)
  {
    forall i | 0 <= i < |events|
      ensures events[i].end_frame < new_event.start_frame
    {
      var last := |events| - 1;

      if i == last {
        assert events[i].end_frame < new_event.start_frame;
      } else {
        assert 0 <= i < last < |events|;
        assert events[i].end_frame < events[last].start_frame;

        assert events[last] in events;
        assert IsValidEvent(events[last], num_frames, min_consecutive);
        assert events[last].start_frame <= events[last].end_frame;

        assert events[i].end_frame < events[last].end_frame;
        assert events[last].end_frame < new_event.start_frame;
      }
    }

    forall i, j | 0 <= i < j < |events + [new_event]|
      ensures (events + [new_event])[i].end_frame <
              (events + [new_event])[j].start_frame
    {
      var extended := events + [new_event];

      if j < |events| {
        assert extended[i] == events[i];
        assert extended[j] == events[j];
        assert events[i].end_frame < events[j].start_frame;
      } else {
        assert j == |events|;
        assert i < |events|;
        assert extended[i] == events[i];
        assert extended[j] == new_event;
        assert events[i].end_frame < new_event.start_frame;
      }
    }

    forall e | e in events + [new_event]
      ensures IsValidEvent(e, num_frames, min_consecutive)
    {
      if e in events {
        assert AllEventsValid(events, num_frames, min_consecutive);
        assert IsValidEvent(e, num_frames, min_consecutive);
      } else {
        assert e == new_event;
        assert IsValidEvent(new_event, num_frames, min_consecutive);
      }
    }
  }

  lemma Lemma_RunCreatesValidEvent(
      start_frame: int,
      end_frame:   int,
      fps:         real,
      min_consecutive: int,
      num_flags:   int)
    requires 1 <= start_frame <= end_frame <= num_flags
    requires end_frame - start_frame + 1 >= min_consecutive
    requires fps > 0.0
    ensures IsValidEvent(
      Event(
        start_frame     := start_frame,
        end_frame       := end_frame,
        duration_frames := end_frame - start_frame + 1,
        start_time_sec  := SecondsFromFrame(start_frame, fps),
        end_time_sec    := SecondsFromFrame(end_frame, fps),
        duration_sec    := ((end_frame - start_frame + 1) as real) / fps
      ),
      num_flags,
      min_consecutive)
  {
    assert start_frame >= 1;
    assert end_frame >= start_frame;
    assert end_frame <= num_flags;

    assert end_frame - start_frame + 1 >= 1;
    assert ((end_frame - start_frame + 1) as real) > 0.0;
    assert fps > 0.0;

    assert SecondsFromFrame(start_frame, fps) >= 0.0;
    assert SecondsFromFrame(end_frame, fps) >= SecondsFromFrame(start_frame, fps);
  }

  // ── Main Method ──────────────────────────────────────────────────

  method BuildEventsFromFlags(
      flags: seq<bool>,
      fps: real,
      min_consecutive: int)
    returns (events: seq<Event>, confirmed_frames: seq<int>)

    requires min_consecutive > 0

    ensures AreNonOverlapping(events)                             // [P1]
    ensures AllEventsValid(events, |flags|, min_consecutive)      // [P2,P3,P4]
    ensures AllFramesInBounds(confirmed_frames, |flags|)          // [P5]
    ensures IsSortedByStart(events)                               // [P7]
  {
    var effective_fps := EffectiveFps(fps);
    Lemma_EffectiveFpsPositive(fps);
    assert effective_fps > 0.0;

    events := [];
    confirmed_frames := [];

    var run_start: int := -1;
    var run_end:   int := -1;

    for idx := 0 to |flags|
      invariant 0 <= idx <= |flags|
      invariant effective_fps > 0.0
      invariant (run_start == -1) <==> (run_end == -1)
      invariant run_start == -1 ||
        (1 <= run_start <= run_end && run_end == idx)
      invariant AreNonOverlapping(events)
      invariant AllEventsValid(events, |flags|, min_consecutive)
      invariant AllFramesInBounds(confirmed_frames, |flags|)
      invariant IsSortedByStart(events)
      invariant |events| > 0 ==>
        events[|events|-1].end_frame <
        (if run_start == -1 then idx + 1 else run_start)
    {
      var flag := flags[idx];
      var frame_num := idx + 1;

      if flag {
        if run_start == -1 {
          run_start := frame_num;
          run_end   := frame_num;
        } else {
          run_end := frame_num;
        }
      } else {
        if run_start != -1 {
          var duration := run_end - run_start + 1;

          if duration >= min_consecutive {
            // Добавляем подтверждённые кадры
            var f := run_start;

            while f <= run_end
              invariant run_start <= f <= run_end + 1
              invariant run_start >= 1
              invariant run_end <= |flags|
              invariant AllFramesInBounds(confirmed_frames, |flags|)
              decreases run_end + 1 - f
            {
              assert 1 <= f <= |flags|;
              confirmed_frames := confirmed_frames + [f];
              f := f + 1;
            }

            // Создаём событие
            assert run_start != -1;
            assert run_end != -1;
            assert 1 <= run_start;
            assert run_start <= run_end;
            assert run_end == idx;
            assert idx <= |flags|;
            assert run_end <= |flags|;
            assert effective_fps > 0.0;

            Lemma_SecondsFromFrameNonNegative(run_start, effective_fps);
            Lemma_SecondsFromFrameMonotonic(run_start, run_end, effective_fps);

            var event := Event(
              start_frame     := run_start,
              end_frame       := run_end,
              duration_frames := duration,
              start_time_sec  := SecondsFromFrame(run_start, effective_fps),
              end_time_sec    := SecondsFromFrame(run_end, effective_fps),
              duration_sec    := (duration as real) / effective_fps
            );

            Lemma_RunCreatesValidEvent(
              run_start,
              run_end,
              effective_fps,
              min_consecutive,
              |flags|);

            assert IsValidEvent(event, |flags|, min_consecutive);

            Lemma_AppendPreservesNonOverlapping(
              events,
              event,
              |flags|,
              min_consecutive);

            events := events + [event];

            assert forall e :: e in events ==> e.start_frame <= e.end_frame by {
              assert AllEventsValid(events, |flags|, min_consecutive);
            }

            Lemma_NonOverlappingImpliesSorted(events);
          }
        }

        run_start := -1;
        run_end   := -1;
      }
    }

    // Закрываем серию, если видео закончилось в активной серии
    if run_start != -1 {
      var duration := run_end - run_start + 1;

      if duration >= min_consecutive {
        var f := run_start;

        while f <= run_end
          invariant run_start <= f <= run_end + 1
          invariant run_start >= 1
          invariant run_end <= |flags|
          invariant AllFramesInBounds(confirmed_frames, |flags|)
          decreases run_end + 1 - f
        {
          assert 1 <= f <= |flags|;
          confirmed_frames := confirmed_frames + [f];
          f := f + 1;
        }

        assert run_start != -1;
        assert run_end != -1;
        assert 1 <= run_start;
        assert run_start <= run_end;
        assert run_end <= |flags|;
        assert effective_fps > 0.0;

        Lemma_SecondsFromFrameNonNegative(run_start, effective_fps);
        Lemma_SecondsFromFrameMonotonic(run_start, run_end, effective_fps);

        var event := Event(
          start_frame     := run_start,
          end_frame       := run_end,
          duration_frames := duration,
          start_time_sec  := SecondsFromFrame(run_start, effective_fps),
          end_time_sec    := SecondsFromFrame(run_end, effective_fps),
          duration_sec    := (duration as real) / effective_fps
        );

        Lemma_RunCreatesValidEvent(
          run_start,
          run_end,
          effective_fps,
          min_consecutive,
          |flags|);

        assert IsValidEvent(event, |flags|, min_consecutive);

        Lemma_AppendPreservesNonOverlapping(
          events,
          event,
          |flags|,
          min_consecutive);

        events := events + [event];

        assert forall e :: e in events ==> e.start_frame <= e.end_frame by {
          assert AllEventsValid(events, |flags|, min_consecutive);
        }

        Lemma_NonOverlappingImpliesSorted(events);
      }
    }
  }
}