---------------------------- MODULE ConflictFlags ----------------------------
\* How Crossroads flags overlapping calendar events, which kind of overlap each
\* event shows (none, same tag, or personal + work), and the overlap cards
\* it shows for each colliding pair of events.
EXTENDS Naturals, FiniteSets

CONSTANTS
    Ids,           \* event identities; copies of one event share an id
    PersonalCals,  \* calendars tagged personal
    WorkCals,      \* calendars tagged work
    MaxTime,       \* last time slot of the modeled day
    MaxEvents,     \* bound on events visible at once
    ModelStatuses  \* statuses the model explores, a subset of Statuses

Cals     == PersonalCals \cup WorkCals
Statuses == {"accepted", "tentative", "declined", "cancelled"}

ASSUME PersonalCals \cap WorkCals = {}
ASSUME ModelStatuses \subseteq Statuses
Kinds    == {"none", "same", "mixed"}

TimedShapes ==
    {sh \in [start : 0..MaxTime, end : 0..MaxTime, allDay : {FALSE}] :
        sh.start < sh.end}
AllDayShape == [start |-> 0, end |-> MaxTime, allDay |-> TRUE]

\* One event as it appears on one calendar.
Occurrences ==
    {[id |-> i, cal |-> c, start |-> sh.start, end |-> sh.end,
      allDay |-> sh.allDay, status |-> st] :
        i \in Ids, c \in Cals, sh \in TimedShapes \cup {AllDayShape},
        st \in ModelStatuses}

\* Copies of one event share their time, and appear once per calendar.
Consistent(S) ==
    \A a, b \in S : a.id = b.id =>
        /\ a.start = b.start /\ a.end = b.end /\ a.allDay = b.allDay
        /\ (a.cal = b.cal => a = b)

Tag(o) == IF o.cal \in PersonalCals THEN "personal" ELSE "work"

VARIABLES
    events,    \* events currently fetched from all calendars
    flags,     \* kind shown for each event in the view
    cards,     \* overlap cards shown in the view
    rendered   \* the view reflects the current events

vars == <<events, flags, cards, rendered>>

Max(a, b) == IF a > b THEN a ELSE b
Min(a, b) == IF a < b THEN a ELSE b

-----------------------------------------------------------------------------
\* Design: how the view computes each event's kind.

Flaggable(o) == ~o.allDay /\ o.status \in {"accepted", "tentative"}

Conflict(a, b) ==
    /\ Flaggable(a) /\ Flaggable(b)
    /\ a.id # b.id
    /\ a.start < b.end /\ b.start < a.end

KindOf(o) ==
    IF \E p \in events : Conflict(o, p) /\ Tag(p) # Tag(o) THEN "mixed"
    ELSE IF \E p \in events : Conflict(o, p) THEN "same"
    ELSE "none"

\* One card per pair of event ids; copies of an event share its id and time.
CardsOf(S) ==
    {[ids |-> {p[1].id, p[2].id},
      start |-> Max(p[1].start, p[2].start),
      end |-> Min(p[1].end, p[2].end)] :
        p \in {q \in S \X S : Conflict(q[1], q[2])}}

-----------------------------------------------------------------------------

\* Stale kinds and cards shown before a render are not modeled: no property
\* reads them, so a change clears them.
NoFlags == [o \in {} |-> "none"]

Init ==
    /\ events = {}
    /\ flags = NoFlags
    /\ cards = {}
    /\ rendered = TRUE

\* A calendar gains an event.
Add(o) ==
    /\ o \notin events
    /\ Cardinality(events) < MaxEvents
    /\ Consistent(events \cup {o})
    /\ events' = events \cup {o}
    /\ flags' = NoFlags
    /\ cards' = {}
    /\ rendered' = FALSE

\* A calendar loses an event.
Remove(o) ==
    /\ o \in events
    /\ events' = events \ {o}
    /\ flags' = NoFlags
    /\ cards' = {}
    /\ rendered' = FALSE

\* The view recomputes every event's kind and the overlap cards.
Render ==
    /\ ~rendered
    /\ flags' = [o \in events |-> KindOf(o)]
    /\ cards' = CardsOf(events)
    /\ rendered' = TRUE
    /\ UNCHANGED events

Next == (\E o \in Occurrences : Add(o) \/ Remove(o)) \/ Render

\* Fairness: the view always renders a pending change; nothing in the
\* system can block a recompute indefinitely.
Spec == Init /\ [][Next]_vars /\ WF_vars(Render)

-----------------------------------------------------------------------------
\* Properties, stated from the user's rules rather than the design above.

Timed(o)       == ~o.allDay
Active(o)      == o.status \in {"accepted", "tentative"}
Overlap(a, b)  == a.start < b.end /\ b.start < a.end
RealOverlap(a, b) ==
    a.id # b.id /\ Timed(a) /\ Timed(b) /\ Active(a) /\ Active(b) /\ Overlap(a, b)

\* Every event in the view has one of the three kinds.
TypeOK ==
    /\ events \subseteq Occurrences
    /\ rendered \in BOOLEAN
    /\ \A o \in DOMAIN flags : flags[o] \in Kinds
    /\ rendered => DOMAIN flags = events
    /\ cards \subseteq [ids : SUBSET Ids, start : 0..MaxTime, end : 0..MaxTime]

\* All-day events are never flagged.
AllDayNeverFlagged ==
    rendered => \A o \in events : o.allDay => flags[o] = "none"

\* Declined and cancelled events are never flagged; tentative ones can be.
InactiveNeverFlagged ==
    rendered => \A o \in events : ~Active(o) => flags[o] = "none"

\* Any two timed events that overlap are both flagged, whatever their calendars.
OverlapsAreFlagged ==
    rendered => \A a, b \in events :
        RealOverlap(a, b) => flags[a] # "none" /\ flags[b] # "none"

\* An event is flagged only for a real overlap: touching ends and its own copies don't count.
FlagsNeedRealOverlap ==
    rendered => \A o \in events :
        flags[o] # "none" => \E p \in events : RealOverlap(o, p)

\* An event that overlaps one with the other tag shows as personal + work.
CrossTagShowsMixed ==
    rendered => \A a, b \in events :
        RealOverlap(a, b) /\ Tag(a) # Tag(b) => flags[a] = "mixed"

\* An event shows as personal + work only when it overlaps one with the other tag.
MixedNeedsCrossTag ==
    rendered => \A o \in events :
        flags[o] = "mixed" => \E p \in events : RealOverlap(o, p) /\ Tag(p) # Tag(o)

\* Every overlap card shows two different events that really overlap.
CardsAreRealOverlaps ==
    rendered => \A c \in cards :
        \E a, b \in events : c.ids = {a.id, b.id} /\ RealOverlap(a, b)

\* Every real overlap between two events gets exactly one card, even when one of them sits on two calendars.
OneCardPerOverlap ==
    rendered => \A a, b \in events :
        RealOverlap(a, b) => Cardinality({c \in cards : c.ids = {a.id, b.id}}) = 1

\* A card's window is the time when both events are happening.
CardWindowIsTheOverlap ==
    rendered => \A c \in cards : \A a, b \in events :
        c.ids = {a.id, b.id} /\ RealOverlap(a, b) =>
            /\ c.start = IF a.start > b.start THEN a.start ELSE b.start
            /\ c.end = IF a.end < b.end THEN a.end ELSE b.end

\* After any calendar change, the view eventually catches up.
ViewCatchesUp == ~rendered ~> rendered

=============================================================================
