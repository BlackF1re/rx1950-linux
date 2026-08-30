################################################################################
# rx1950-shell
################################################################################

RX1950_SHELL_VERSION = 1.0
RX1950_SHELL_SITE = $(BR2_EXTERNAL_RX1950_PATH)/package/rx1950-shell/src
RX1950_SHELL_SITE_METHOD = local
RX1950_SHELL_DEPENDENCIES = xlib_libX11
RX1950_SHELL_LICENSE = MIT
RX1950_SHELL_LICENSE_FILES = COPYING

define RX1950_SHELL_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)
endef

define RX1950_SHELL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/rx1950-shell $(TARGET_DIR)/usr/bin/rx1950-shell
endef

$(eval $(generic-package))
