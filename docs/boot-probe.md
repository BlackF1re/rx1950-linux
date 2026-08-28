# Boot diagnostics

Use this only when the image does not reach a usable Linux console/SSH session. Normal installation is in [QUICKSTART.md](QUICKSTART.md).

## Evidence chain

HaRET on the FAT partition identifies RX1950/S3C2442, uses the 32 MiB RAM window at `0x30000000`, passes machine type `952` and loads the kernel at the project-tested relocation offset. `earlyharetlog.txt` requests a persistent `haretlog.txt`, which is flushed before Linux takes control.

After BusyBox starts, `S10boot-probe` writes `probe.log` on the Windows-readable FAT partition. Useful milestones include:

```text
early-userspace-reached
rootfs-ready
usb-network-ready
```

`usb0-unavailable` means userspace/root was reached but the USB recovery network was not.

## Reading a failed boot

After reset, read `haretlog.txt` and `probe.log` from FAT:

- no/failed HaRET identity, kernel CRC or final hand-off → loader/image problem;
- successful HaRET hand-off but no `probe.log` → Linux failed before userspace;
- `rootfs-ready` without `usb-network-ready` → Linux/root is alive; investigate USB separately.

Preserve the exact release checksum, SD-card model/capacity and visible screen behaviour with the logs.

The kernel build itself is rejected unless it contains the ARM920T/S3C2442/RX1950 machine configuration and linked `__mach_desc_RX1950`. Experimental GPIO instrumentation is not inserted into the early boot path.

Never probe a boot failure by writing internal NAND or by poking unknown GPIO/MMIO addresses. The supported recovery path is reset → Windows Mobile → FAT logs.
