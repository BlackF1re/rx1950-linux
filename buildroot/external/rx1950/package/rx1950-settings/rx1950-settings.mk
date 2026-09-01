################################################################################
# rx1950-settings
################################################################################

RX1950_SETTINGS_VERSION = 1.0
RX1950_SETTINGS_SITE = $(BR2_EXTERNAL_RX1950_PATH)/package/rx1950-settings/src
RX1950_SETTINGS_SITE_METHOD = local
RX1950_SETTINGS_DEPENDENCIES = libgtk2

RX1950_SETTINGS_LICENSE = GPL-2.0-or-later
RX1950_SETTINGS_LICENSE_FILES = COPYING

define RX1950_SETTINGS_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)
endef

define RX1950_SETTINGS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/rx1950-settings \
		$(TARGET_DIR)/usr/bin/rx1950-settings
endef

$(eval $(generic-package))
