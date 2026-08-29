# Documentation

Start with [Quick start](QUICKSTART.md) to write, boot and access the current engineering image.

| Document | Purpose |
| --- | --- |
| [Quick start](QUICKSTART.md) | Install, boot, USB/SSH, packages and first WLAN test. |
| [Hardware support](hardware.md) | Release-facing status and required on-device acceptance tests. |
| [Hardware inventory](hardware-inventory.md) | Component-level map: supported, known/incomplete and unresolved hardware. |
| [Architecture](architecture.md) | Boot, storage, runtime and kernel safety boundaries. |
| [Build](build.md) | Pinned inputs, reproducibility contract and CI/release flow. |
| [Storage](storage.md) | SD layout and first-boot root expansion. |
| [Versioning](versioning.md) | Engineering release numbering and publication policy. |
| [Release gates](goals.md) | What must pass before a feature or release is called supported. |
| [Boot diagnostics](boot-probe.md) | HaRET/early-userspace evidence for failed boot investigation. |

Procedures have one owning document. Hardware is promoted to supported only after a repeatable physical-device result is recorded; CI validates software and artifact contracts, not electrical behaviour.
