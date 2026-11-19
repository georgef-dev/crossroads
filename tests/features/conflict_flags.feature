Feature: Conflict flags
  Crossroads flags overlapping events and shows which kind of overlap each one is.

  @ConflictFlags.CrossTagShowsMixed
  Scenario: Kids pickup overlaps a work busy block
    Given these events:
      | id     | calendar | tag      | start | end   | all_day | status   |
      | pickup | family   | personal | 15:00 | 15:30 | no      | accepted |
      | busy   | work     | work     | 15:15 | 16:00 | no      | accepted |
    When Crossroads classifies them
    Then the kinds are:
      | id     | calendar | kind  |
      | pickup | family   | mixed |
      | busy   | work     | mixed |

  @ConflictFlags.OverlapsAreFlagged
  Scenario: Two personal events overlap
    Given these events:
      | id      | calendar | tag      | start | end   | all_day | status   |
      | dentist | family   | personal | 10:00 | 11:00 | no      | accepted |
      | gym     | family   | personal | 10:30 | 11:30 | no      | accepted |
    When Crossroads classifies them
    Then the kinds are:
      | id      | calendar | kind |
      | dentist | family   | same |
      | gym     | family   | same |

  @ConflictFlags.MixedNeedsCrossTag
  Scenario: An event overlapping only its own tag is not mixed
    Given these events:
      | id      | calendar | tag      | start | end   | all_day | status   |
      | dentist | family   | personal | 10:00 | 11:00 | no      | accepted |
      | gym     | family   | personal | 10:30 | 11:30 | no      | accepted |
      | busy    | work     | work     | 11:00 | 12:00 | no      | accepted |
    When Crossroads classifies them
    Then the kinds are:
      | id      | calendar | kind  |
      | dentist | family   | same  |
      | gym     | family   | mixed |
      | busy    | work     | mixed |

  @ConflictFlags.FlagsNeedRealOverlap
  Scenario: Events that only touch are not flagged
    Given these events:
      | id     | calendar | tag      | start | end   | all_day | status   |
      | busy   | work     | work     | 14:00 | 15:00 | no      | accepted |
      | pickup | family   | personal | 15:00 | 15:30 | no      | accepted |
    When Crossroads classifies them
    Then the kinds are:
      | id     | calendar | kind |
      | busy   | work     | none |
      | pickup | family   | none |

  @ConflictFlags.FlagsNeedRealOverlap
  Scenario: One event on two calendars does not conflict with itself
    Given these events:
      | id    | calendar | tag      | start | end   | all_day | status   |
      | party | family   | personal | 18:00 | 20:00 | no      | accepted |
      | party | kids     | personal | 18:00 | 20:00 | no      | accepted |
    When Crossroads classifies them
    Then the kinds are:
      | id    | calendar | kind |
      | party | family   | none |
      | party | kids     | none |

  @ConflictFlags.InactiveNeverFlagged
  Scenario: Declined events are not flagged, tentative ones are
    Given these events:
      | id      | calendar | tag      | start | end   | all_day | status    |
      | pickup  | family   | personal | 15:00 | 15:30 | no      | accepted  |
      | review  | work     | work     | 15:00 | 16:00 | no      | declined  |
      | standup | work     | work     | 15:15 | 15:45 | no      | tentative |
    When Crossroads classifies them
    Then the kinds are:
      | id      | calendar | kind  |
      | pickup  | family   | mixed |
      | review  | work     | none  |
      | standup | work     | mixed |

  @ConflictFlags.AllDayNeverFlagged
  Scenario: All-day events are not flagged
    Given these events:
      | id       | calendar | tag      | start | end   | all_day | status   |
      | birthday | family   | personal | 00:00 | 23:59 | yes     | accepted |
      | busy     | work     | work     | 09:00 | 10:00 | no      | accepted |
    When Crossroads classifies them
    Then the kinds are:
      | id       | calendar | kind |
      | birthday | family   | none |
      | busy     | work     | none |

  @ConflictFlags.CardWindowIsTheOverlap
  Scenario: Kids pickup and a work busy block get one card for the time they share
    Given these events:
      | id     | calendar | tag      | start | end   | all_day | status   |
      | pickup | family   | personal | 15:00 | 15:30 | no      | accepted |
      | busy   | work     | work     | 15:15 | 16:00 | no      | accepted |
    When Crossroads builds the overlap cards
    Then the overlap cards are:
      | ids         | start | end   |
      | busy+pickup | 15:15 | 15:30 |

  @ConflictFlags.OneCardPerOverlap
  Scenario: An event on two calendars gets one card per collision, not one per calendar
    Given these events:
      | id    | calendar | tag      | start | end   | all_day | status   |
      | party | family   | personal | 18:00 | 20:00 | no      | accepted |
      | party | kids     | personal | 18:00 | 20:00 | no      | accepted |
      | busy  | work     | work     | 19:00 | 21:00 | no      | accepted |
    When Crossroads builds the overlap cards
    Then the overlap cards are:
      | ids        | start | end   |
      | busy+party | 19:00 | 20:00 |

  @ConflictFlags.CardsAreRealOverlaps
  Scenario: Touching, declined, and all-day events get no cards
    Given these events:
      | id       | calendar | tag      | start | end   | all_day | status   |
      | busy     | work     | work     | 14:00 | 15:00 | no      | accepted |
      | pickup   | family   | personal | 15:00 | 15:30 | no      | accepted |
      | review   | work     | work     | 15:00 | 16:00 | no      | declined |
      | birthday | family   | personal | 00:00 | 23:59 | yes     | accepted |
    When Crossroads builds the overlap cards
    Then there are no overlap cards
