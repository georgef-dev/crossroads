Feature: Settings
  Tagging calendars from the settings view rewrites config.json safely.

  Background:
    Given a config where "me@icloud.com" has these calendars:
      | id     | tag      | name   |
      | home   | personal | George |
      | family | personal | Family |

  @Settings.TagIsApplied
  Scenario: Retagging a calendar
    When I tag "family" as "work"
    Then "me@icloud.com" has these calendars:
      | id     | tag      | name   |
      | home   | personal | George |
      | family | work     | Family |

  @Settings.TagIsApplied
  Scenario: Turning a calendar off removes it
    When I tag "home" as "off"
    Then "me@icloud.com" has these calendars:
      | id     | tag      | name   |
      | family | personal | Family |

  @Settings.TagIsApplied
  Scenario: Turning on a new calendar keeps its name
    When I tag "partner" named "Partner" as "personal"
    Then "me@icloud.com" has these calendars:
      | id        | tag      | name      |
      | home      | personal | George    |
      | family    | personal | Family    |
      | partner | personal | Partner |

  @Settings.TypeOK
  Scenario: A bad tag is rejected and nothing changes
    When I tag "home" as "family"
    Then the change fails with "tag"
    And config.json is unchanged

  @Settings.ConfigIsAlwaysWhole
  Scenario: A write that dies keeps the old file
    Given the disk fails while saving
    When I tag "home" as "work"
    Then the change fails with "disk"
    And config.json is unchanged

  Scenario: An account that isn't configured is rejected
    When I tag "home" on "someone@icloud.com" as "work"
    Then the change fails with "someone@icloud.com"
    And config.json is unchanged
