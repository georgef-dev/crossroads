Feature: Keyboard shortcut
  The shortcut that opens Crossroads can be changed from settings and reset.

  Background:
    Given Hyprland loads crossroads.lua
    And "SUPER + ALT + T" is bound to "Terminal"
    And the shortcut is "SUPER + ALT + C"

  @Settings.ShortcutIsApplied
  Scenario: Changing the shortcut
    When I change the shortcut to "SUPER + ALT + X"
    Then the shortcut is "SUPER + ALT + X"
    And Hyprland was reloaded

  @Settings.ShortcutIsApplied
  Scenario: Resetting brings back Super+Alt+C
    Given the shortcut is "CTRL + ALT + J"
    When I reset the shortcut
    Then the shortcut is "SUPER + ALT + C"

  @Settings.ShortcutNeverConflicts
  Scenario: A combination another binding uses is refused
    When I change the shortcut to "SUPER + ALT + T"
    Then the change fails with "Terminal"
    And the shortcut is "SUPER + ALT + C"
    And Hyprland was not reloaded

  @Settings.ShortcutFileIsAlwaysWhole
  Scenario: A write that dies keeps the old shortcut
    Given the disk fails while saving
    When I change the shortcut to "SUPER + ALT + X"
    Then the change fails with "disk"
    And the shortcut is "SUPER + ALT + C"
