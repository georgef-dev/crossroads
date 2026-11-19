def pytest_bdd_apply_tag(tag, function):
    # Tags like @ConflictFlags.OverlapsAreFlagged trace a scenario to its spec
    # property. They are not pytest marks, so claim them before pytest-bdd does.
    return "." in tag or None
