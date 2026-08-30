CFLAGS += -Wall -Wextra -Werror -Os -ffunction-sections -fdata-sections
LDFLAGS += -Wl,--gc-sections
PKG_CONFIG ?= pkg-config
X11_CFLAGS := $(shell $(PKG_CONFIG) --cflags x11)
X11_LIBS := $(shell $(PKG_CONFIG) --libs x11)

all: rx1950-shell

rx1950-shell: rx1950-shell.c
	$(CC) $(CFLAGS) $(X11_CFLAGS) -o $@ $< $(LDFLAGS) $(X11_LIBS)

clean:
	rm -f rx1950-shell
