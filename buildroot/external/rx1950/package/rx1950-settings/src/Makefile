CFLAGS += -Wall -Wextra -Os -ffunction-sections -fdata-sections
LDFLAGS += -Wl,--gc-sections
PKG_CONFIG ?= pkg-config
GTK_CFLAGS := $(shell $(PKG_CONFIG) --cflags gtk+-2.0)
GTK_LIBS := $(shell $(PKG_CONFIG) --libs gtk+-2.0)

all: rx1950-settings

rx1950-settings: rx1950-settings.c
	$(CC) $(CFLAGS) $(GTK_CFLAGS) -o $@ $< $(LDFLAGS) $(GTK_LIBS)

clean:
	rm -f rx1950-settings
