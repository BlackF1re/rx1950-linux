################################################################################
# rx1950 Buildroot external tree
################################################################################

include $(sort $(wildcard $(BR2_EXTERNAL_RX1950_PATH)/package/*/*.mk))

# The rx1950 uses one fixed fbdev screen and explicit input sections. Build
# only protocol features required by JWM, GTK2/Xaw applications and the
# on-screen keyboard. These overrides are deliberately later than the
# upstream package defaults.
#
# OpenSSL remains in the image for HTTPS, but Xorg only needs SHA1 for cookies.
# Force the tiny libsha1 implementation so Xorg does not map libcrypto solely
# for that purpose.
XSERVER_XORG_SERVER_DEPENDENCIES += libsha1
XSERVER_XORG_SERVER_CONF_OPTS += \
	--disable-config-udev \
	--disable-config-udev-kms \
	--disable-config-dbus \
	--disable-dbe \
	--disable-dga \
	--disable-dmx \
	--disable-dpms \
	--disable-dri2 \
	--disable-dri3 \
	--disable-glamor \
	--disable-libdrm \
	--disable-record \
	--disable-xace \
	--disable-xdm-auth-1 \
	--disable-xdmcp \
	--disable-xf86bigfont \
	--disable-xfree86-utils \
	--disable-xf86vidmode \
	--disable-xinerama \
	--disable-xres \
	--disable-xv \
	--with-sha1=libsha1
