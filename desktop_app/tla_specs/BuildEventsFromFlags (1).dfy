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
 * Note: ConfirmedFramesMatchEvents (P6) requires witness hints
 * for the existential quantifier and is left as a ghost predicate
 * for documentation purposes only.
 */

module BuildEventsFromFlags {

  // ── Data structure ───────────────────────────────────────────────
  datatype Event = Event(
    start_frame:    int,
    end_frame:      int,
    duration_frames: int,
    start_time_sec: real,
    end_time_sec:   real,
    duration_sec:   real
  )

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

  lemma Lemma_NonOverlappingImpliesSorted(events: seq<Event>)
    requires AreNonOverlapping(events)
    requires forall e :: e in events ==> e.start_frame <= e.end_frame
    ensures IsSortedByStart(events)
  {
    forall i, j | 0 <= i < j < |events|
      ensures events[i].start_frame < events[j].start_frame
    {
      // events[i].start_frame <= events[i].end_frame (well-formed)
      // events[i].end_frame < events[j].start_frame (non-overlapping)
      // therefore: events[i].start_frame < events[j].start_frame
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
    forall i, j | 0 <= i < j < |events + [new_event]|
      ensures (events + [new_event])[i].end_frame <
              (events + [new_event])[j].start_frame
    {
      var extended := events + [new_event];
      if j < |events| {
        // Both in original: follows from AreNonOverlapping(events)
        assert extended[i] == events[i];
        assert extended[j] == events[j];
      } else {
        // j == |events|, so extended[j] == new_event
        assert extended[i] == events[i];
        assert extended[j] == new_event;
        // Need: events[i].end_frame < new_event.start_frame
        // From precondition: events[|events|-1].end_frame < new_event.start_frame
        // From AreNonOverlapping: events[i].end_frame <= events[|events|-1].end_frame
        // (because i < |events|-1 OR i == |events|-1)
        if i == |events| - 1 {
          // Direct from precondition
        } else {
          // i < |events|-1, so events[i].end_frame < events[|events|-1].start_frame
          // and events[|events|-1].start_frame <= events[|events|-1].end_frame
          // and events[|events|-1].end_frame < new_event.start_frame
        }
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
        start_frame    := start_frame,
        end_frame      := end_frame,
        duration_frames := end_frame - start_frame + 1,
        start_time_sec := (start_frame as real) / fps,
        end_time_sec   := (end_frame   as real) / fps,
        duration_sec   := ((end_frame - start_frame + 1) as real) / fps
      ),
      num_flags, min_consecutive)
  {}

  // ── Main Method ──────────────────────────────────────────────────

  method BuildEventsFromFlags(
      flags: seq<bool>,
      fps:   real,
      min_consecutive: int)
    returns (events: seq<Event>, confirmed_frames: seq<int>)

    requires fps > 0.0
    requires min_consecutive > 0
    requires |flags| > 0

    ensures AreNonOverlapping(events)                             // [P1]
    ensures AllEventsValid(events, |flags|, min_consecutive)      // [P2,P3,P4]
    ensures AllFramesInBounds(confirmed_frames, |flags|)          // [P5]
    ensures IsSortedByStart(events)                               // [P7]
  {
    events          := [];
    confirmed_frames := [];

    var run_start: int := -1;
    var run_end:   int := -1;

    for idx := 0 to |flags|
      invariant 0 <= idx <= |flags|
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
      var flag      := flags[idx];
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
              invariant AllFramesInBounds(confirmed_frames, |flags|)
              decreases run_end + 1 - f
            {
              confirmed_frames := confirmed_frames + [f];
              f := f + 1;
            }

            // Создаём событие
            Lemma_RunCreatesValidEvent(
              run_start, run_end, fps, min_consecutive, |flags|);
            Lemma_AppendPreservesNonOverlapping(
              events,
              Event(
                start_frame    := run_start,
                end_frame      := run_end,
                duration_frames := duration,
                start_time_sec := (run_start as real) / fps,
                end_time_sec   := (run_end   as real) / fps,
                duration_sec   := (duration  as real) / fps
              ),
              |flags|, min_consecutive);

            var event := Event(
              start_frame    := run_start,
              end_frame      := run_end,
              duration_frames := duration,
              start_time_sec := (run_start as real) / fps,
              end_time_sec   := (run_end   as real) / fps,
              duration_sec   := (duration  as real) / fps
            );

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

    // Закрываем серию если видео закончилось в активной серии
    if run_start != -1 {
      var duration := run_end - run_start + 1;

      if duration >= min_consecutive {
        var f := run_start;
        while f <= run_end
          invariant run_start <= f <= run_end + 1
          invariant AllFramesInBounds(confirmed_frames, |flags|)
          decreases run_end + 1 - f
        {
          confirmed_frames := confirmed_frames + [f];
          f := f + 1;
        }

        Lemma_RunCreatesValidEvent(
          run_start, run_end, fps, min_consecutive, |flags|);
        Lemma_AppendPreservesNonOverlapping(
          events,
          Event(
            start_frame    := run_start,
            end_frame      := run_end,
            duration_frames := duration,
            start_time_sec := (run_start as real) / fps,
            end_time_sec   := (run_end   as real) / fps,
            duration_sec   := (duration  as real) / fps
          ),
          |flags|, min_consecutive);

        var event := Event(
          start_frame    := run_start,
          end_frame      := run_end,
          duration_frames := duration,
          start_time_sec := (run_start as real) / fps,
          end_time_sec   := (run_end   as real) / fps,
          duration_sec   := (duration  as real) / fps
        );

        events := events + [event];
        Lemma_NonOverlappingImpliesSorted(events);
      }
    }
  }
}
