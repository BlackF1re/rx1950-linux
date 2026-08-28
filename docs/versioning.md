# Versioning

Engineering releases use:

```text
MAJOR.MINOR.PATCH-engineer
```

During hardware bring-up the line remains `0.1.x-engineer`; every published engineering release increments `PATCH`.

## Assignment and publication

The `Plan` job reads existing `*-engineer` tags and computes the next numeric patch automatically. A push to `main` publishes that version only after rootfs, kernel, package-feed and sealed-image validation all succeed. A manual workflow run can use the same publication path.

The release tag targets the exact `main` commit whose artifacts were verified. Publication uploads those artifacts; it never performs a second build.

`-engineer` means hardware bring-up. It does not imply that every peripheral has passed physical acceptance. Promotion to another prerelease channel or a stable version requires an explicit policy change after the gates in [goals.md](goals.md) are met.
