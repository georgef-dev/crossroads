# Conformance cases

Crossroads has two implementations of the same rules: Python on Omarchy, and
Swift on macOS. The specs in [`specs/`](../specs) say what must be true. The
cases here are concrete examples that **both** implementations must pass, so
the two cannot drift apart.

The Python tests read them in
[`omarchy/tests/test_conflict_flags_conformance.py`](../omarchy/tests/test_conflict_flags_conformance.py).
The Swift tests read the same files.

A case that one implementation fails is a bug in that implementation, or a
property the spec does not yet have. Property tests stay per platform:
Hypothesis in Python, and generated inputs in Swift.

## Format

One JSON file per case:

```json
{
  "property": "ConflictFlags.CrossTagShowsMixed",
  "name": "Kids pickup overlaps a work busy block",
  "events": [
    { "id": "pickup", "calendar": "family", "tag": "personal", "start": "15:00", "end": "15:30", "allDay": false, "status": "accepted" },
    { "id": "busy", "calendar": "work", "tag": "work", "start": "15:15", "end": "16:00", "allDay": false, "status": "accepted" }
  ],
  "kinds": { "pickup@family": "mixed", "busy@work": "mixed" },
  "overlaps": [{ "ids": ["busy", "pickup"], "start": "15:15", "end": "15:30" }]
}
```

| Field | Meaning |
| --- | --- |
| `property` | The spec property the case exercises, as `Spec.PropertyName`. |
| `name` | What the case shows, in words. |
| `events` | The events the view holds. Copies of one event on different calendars share an `id`. |
| `kinds` | The expected kind of each event, keyed `id@calendar`. One of `none`, `same`, or `mixed`. |
| `overlaps` | The expected overlap cards, each with the two event `ids` and the time both events are happening. An empty list means no cards. |

Times are `HH:MM` on one modeled day. Which day it is never matters to the
rules, so each implementation picks its own reference date.

A case asserts `kinds`, `overlaps`, or both. It must assert at least one.
