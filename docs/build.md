# Build and release

The build is pinned and non-interactive. It produces the same ARMv4T userspace, Linux kernel, optional WLAN modules, package feed and SD image locally or in GitHub Actions.

## Pinned inputs

| Input | Version / policy |
| --- | --- |
| Buildroot | `2025.02.2`, archive SHA-256 verified |
| Linux | `6.2`, archive SHA-256 verified; last upstream RX1950 machine baseline |
| ACX WLAN | pinned `acx-mac80211` commit; memory transport only; RX1950 MEM IRQ fix applied from `kernel/acx-patches/` |
| ACX100 firmware | OpenBSD `acx-firmware-1.4p6`; `WLANGEN.BIN`, `RADIO0d.BIN` and `RADIO11.BIN` accepted only when their pinned SHA-256 digests match |
| HaRET | RX1950-proven binary; SHA-256 verified |
| Target ABI | ARM920T / ARMv4T, EABI, soft-float, musl |

Downloaded build inputs are rejected before use when a pinned payload checksum does not match. The historical OpenBSD firmware vhost is fetched over HTTP because its legacy TLS endpoint is unreliable; integrity comes from the three pinned firmware SHA-256 digests, not from transport security.

## Local build

Required host tools are the same classes installed by `.github/workflows/build-release.yml`.

```sh
bash scripts/build.sh rootfs
bash scripts/build.sh kernel
bash scripts/build.sh image
```

or:

```sh
bash scripts/build.sh all
```

Optional `opkg` packages are built with:

```sh
bash scripts/build-opkg-feed.sh
bash scripts/validate-opkg-feed.sh feed output/packages
```

## Reproducibility contract

Identical source/configuration and release version must produce identical payload bits. The pipeline therefore fixes or normalizes:

- `SOURCE_DATE_EPOCH=1767225600`, UTC locale/timezone and Linux `KBUILD_BUILD_*` identity;
- Buildroot `BR2_REPRODUCIBLE` mode;
- ext4 UUID and directory hash seed, with lazy inode/journal initialization disabled;
- `/etc/os-release` from the release version rather than Git checkout description;
- FAT creation metadata (`mkfs.vfat --invariant`);
- DOS MBR disk signature;
- WLAN module tar ordering, ownership and timestamps;
- bundled ACX100 firmware filenames, payload digests and mtimes;
- single-threaded XZ output;
- non-mutating filesystem verification.

The Git commit belongs in `provenance.txt`, not in binaries whose source tree is otherwise identical. `scripts/validate-reproducible.sh` rejects loss of these invariants.

## CI graph

```text
Plan
├── Root filesystem + package feed
└── Kernel
      │
Root filesystem + Kernel
      └── Assemble and verify
              │
Verified feed + image ── Publish release (main only)
```

Rootfs and kernel build independently. Their SHA-256 hand-off manifests are checked before assembly. The package feed is built in the rootfs job from the same live, verified Buildroot state; it never depends on a cache entry becoming visible to another job. A package is rejected if it would overwrite the sealed base image, has an incomplete dependency closure or carries the wrong ELF ABI.

The first Buildroot build after a real configuration change is intentionally expensive because it builds the ARM/musl toolchain. Exact reusable state is keyed by normalized Kconfig content and the pinned Buildroot version; comments, documentation, workflow logic, rootfs overlays and post-build scripts do not invalidate it. An inexact Buildroot output is never restored. Builds sharing a key are serialized so two runs cannot race to reserve the same cache entry. Compiler objects have a separate ABI-scoped ccache to reduce the cost of genuine configuration changes.

Verified source-download caches depend only on `scripts/sources.lock.sh`. Every downloaded payload is still checksum-verified before use, so an older compatible download cache is safe while ordinary edits to `scripts/build.sh` no longer create duplicate caches. `scripts/validate-cache.sh` enforces these rules in Plan before expensive jobs begin.

## Release assets

A published engineering release contains:

- `rx1950-linux-<version>.img.xz` and `SHA256SUMS`;
- `provenance.txt`;
- `zImage` and `kernel-modules.tar`;
- `startup.txt`;
- `Packages`, `Packages.gz`, `PACKAGES-SHA256SUMS`, `feed.json` and the `.ipk` files.

A push to `main` runs the full pipeline and publishes only after Plan, rootfs, kernel, feed and sealed-image validation succeed. Publication consumes the already verified artifacts; it does not rebuild them.

Build success is not hardware acceptance. Physical support status lives in [hardware.md](hardware.md).
