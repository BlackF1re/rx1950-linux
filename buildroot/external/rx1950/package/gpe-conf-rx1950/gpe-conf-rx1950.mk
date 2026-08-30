################################################################################
# gpe-conf-rx1950
################################################################################

GPE_CONF_RX1950_VERSION = 1.0
GPE_CONF_RX1950_SITE = $(BR2_EXTERNAL_RX1950_PATH)/package/gpe-conf-rx1950/src
GPE_CONF_RX1950_SITE_METHOD = local
GPE_CONF_RX1950_DEPENDENCIES = host-pkgconf libgtk2
GPE_CONF_RX1950_LICENSE = GPL-2.0-or-later
GPE_CONF_RX1950_LICENSE_FILES = COPYING

define GPE_CONF_RX1950_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)
endef

define GPE_CONF_RX1950_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/gpe-conf $(TARGET_DIR)/usr/bin/gpe-conf
endef

$(eval $(generic-package))
