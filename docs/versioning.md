# Versioning

## Engineering releases

Engineering builds use three-part semantic versions with a pre-release suffix:

```
MAJOR.MINOR.PATCH-engineer
```

The sequence starts at `0.1.0-engineer`. Until the project has a hardware-
validated usable release, `MAJOR` and `MINOR` remain `0` and `1`; every
published engineering image increases `PATCH` by one:

```
0.1.0-engineer
0.1.1-engineer
0.1.2-engineer
```

The suffix makes the engineering status visible in the release page, package
provenance and support discussions. It is not a claim that all hardware is
supported on a physical iPAQ.

## Automated tag assignment

To publish, run **Build & Release** from `main` and set **Publish a GitHub
release after verification** to true. No version field is entered manually.
The plan job reads every existing tag matching
`MAJOR.MINOR.PATCH-engineer`, selects the highest numeric version and assigns
the next patch version. The first published release is therefore
`0.1.0-engineer`.

The release job runs only after the same workflow has built and verified the
kernel, root filesystem and SD image. It creates the computed Git tag on the
exact commit that was built, then attaches the compressed image, checksums,
provenance, kernel and HaRET startup script. Push-triggered builds never
create a release.

## Promotion policy

`0.1.x-engineer` releases are hardware bring-up images. A future change to a
different pre-release channel or a stable version requires a deliberate
release-policy update after the hardware acceptance gates in `goals.md` are
met. That transition is not performed automatically.
