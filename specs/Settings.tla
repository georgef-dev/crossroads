------------------------------ MODULE Settings ------------------------------
\* How Crossroads saves its settings: the widget's shell.json entry, which the
\* shell replaces whole on every change, and the calendar tags in
\* config.json, which are rewritten through a temp file and a rename.
EXTENDS Naturals, FiniteSets

CONSTANTS
    Keys,        \* settings in the shell.json entry (refresh, keys, range)
    Values,      \* values a setting can take
    Cals,        \* calendars that can be tagged
    MaxChanges,  \* bound on changes, so every run settles
    NONE,
    CORRUPT      \* a config file cut off partway through a write

Tags    == {"personal", "work"}
Choices == Tags \cup {"off"}

VARIABLES
    entry,         \* the widget's shell.json entry
    entryBefore,   \* the entry before the last setting change
    changedKey,    \* the setting the last change was for, or NONE
    disk,          \* config.json: a set of <<calendar, tag>> pairs, or CORRUPT
    diskBefore,    \* config.json before the last committed tag change
    temp,          \* the temp file being written, or NONE
    pending,       \* the tag change being written: <<calendar, choice>>, or NONE
    committed,     \* the last tag change that reached config.json, or NONE
    changes        \* changes made so far

vars == <<entry, entryBefore, changedKey, disk, diskBefore, temp, pending, committed, changes>>

-----------------------------------------------------------------------------
\* Design.

\* updateEntryInline replaces the entry, so the new entry is the whole old
\* entry with one value changed.
WithSetting(e, k, v) == [x \in Keys |-> IF x = k THEN v ELSE e[x]]

\* A tag change keeps every other calendar and gives this one its new tag,
\* or removes it for "off".
Retag(d, c, choice) ==
    {p \in d : p[1] # c} \cup (IF choice = "off" THEN {} ELSE {<<c, choice>>})

Init ==
    /\ entry \in [Keys -> Values]
    /\ entryBefore = entry
    /\ changedKey = NONE
    /\ disk = {}
    /\ diskBefore = {}
    /\ temp = NONE
    /\ pending = NONE
    /\ committed = NONE
    /\ changes = 0

\* The user changes one setting in the settings view.
ChangeSetting(k, v) ==
    /\ changes < MaxChanges
    /\ entryBefore' = entry
    /\ entry' = WithSetting(entry, k, v)
    /\ changedKey' = k
    /\ changes' = changes + 1
    /\ UNCHANGED <<disk, diskBefore, temp, pending, committed>>

\* The user picks a tag; crossroads writes the new config to a temp file.
StartTag(c, choice) ==
    /\ changes < MaxChanges
    /\ pending = NONE
    /\ disk # CORRUPT
    /\ temp' = Retag(disk, c, choice)
    /\ pending' = <<c, choice>>
    /\ changes' = changes + 1
    /\ UNCHANGED <<entry, entryBefore, changedKey, disk, diskBefore, committed>>

\* The rename replaces config.json in one step.
Commit ==
    /\ pending # NONE
    /\ diskBefore' = disk
    /\ disk' = temp
    /\ committed' = pending
    /\ temp' = NONE
    /\ pending' = NONE
    /\ UNCHANGED <<entry, entryBefore, changedKey, changes>>

\* crossroads dies before the rename: the temp file is abandoned.
Crash ==
    /\ pending # NONE
    /\ temp' = NONE
    /\ pending' = NONE
    /\ UNCHANGED <<entry, entryBefore, changedKey, disk, diskBefore, committed, changes>>

Done == changes = MaxChanges /\ pending = NONE

Next ==
    \/ \E k \in Keys, v \in Values : ChangeSetting(k, v)
    \/ \E c \in Cals, choice \in Choices : StartTag(c, choice)
    \/ Commit
    \/ Crash
    \/ (Done /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
\* Properties.

\* Every setting has a value, and config.json holds calendar tags.
TypeOK ==
    /\ entry \in [Keys -> Values]
    /\ disk = CORRUPT \/ disk \subseteq Cals \X Tags
    /\ changes \in 0..MaxChanges

\* Changing one setting leaves every other setting as it was.
OtherSettingsSurvive ==
    changedKey # NONE => \A k \in Keys \ {changedKey} : entry[k] = entryBefore[k]

\* config.json is never left cut off: a write that dies keeps the old file.
ConfigIsAlwaysWhole == disk # CORRUPT

\* Each calendar has at most one tag.
OneTagPerCalendar ==
    disk # CORRUPT => \A c \in Cals : Cardinality({p \in disk : p[1] = c}) <= 1

\* A saved tag change gives the calendar exactly that tag, and "off" removes it.
TagIsApplied ==
    committed # NONE /\ disk # CORRUPT =>
        LET c == committed[1]
            choice == committed[2]
        IN IF choice = "off"
           THEN \A p \in disk : p[1] # c
           ELSE <<c, choice>> \in disk

\* A saved tag change leaves every other calendar as it was.
OtherCalendarsSurvive ==
    committed # NONE /\ disk # CORRUPT /\ diskBefore # CORRUPT =>
        {p \in disk : p[1] # committed[1]} = {p \in diskBefore : p[1] # committed[1]}

=============================================================================
