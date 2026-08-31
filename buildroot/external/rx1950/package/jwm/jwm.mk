################################################################################
#
# jwm
#
################################################################################

JWM_VERSION = 2.4.6
JWM_SOURCE = jwm-$(JWM_VERSION).tar.xz
JWM_SITE = https://github.com/joewing/jwm/releases/download/v$(JWM_VERSION)
JWM_LICENSE = MIT
JWM_LICENSE_FILES = LICENSE
JWM_DEPENDENCIES = host-pkgconf xlib_libX11 xlib_libXft xlib_libXrender
JWM_CONF_OPTS = \
	--enable-confirm \
	--enable-icons \
	--disable-png \
	--disable-jpeg \
	--disable-cairo \
	--disable-rsvg \
	--enable-xft \
	--enable-xrender \
	--disable-pango \
	--disable-xpm \
	--enable-xbm \
	--disable-shape \
	--disable-xmu \
	--disable-xinerama \
	--disable-debug

$(eval $(autotools-package))
