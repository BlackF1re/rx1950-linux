# SPDX-License-Identifier: GPL-2.0
obj-m += rx1950_acx.o

# RX1950 still uses the legacy non-DT S3C24xx board support.  The pinmux
# definitions required to reproduce the proven historical WLAN bus setup are
# private to arch/arm/mach-s3c in Linux 6.2.
ccflags-y += -I$(srctree)/arch/arm/mach-s3c
