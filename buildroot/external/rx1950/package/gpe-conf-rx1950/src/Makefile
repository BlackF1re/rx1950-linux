CFLAGS += -Wall -Wextra -Os
PKG_CONFIG ?= pkg-config
GTK_CFLAGS := $(shell $(PKG_CONFIG) --cflags gtk+-2.0)
GTK_LIBS := $(shell $(PKG_CONFIG) --libs gtk+-2.0)

all: gpe-conf

gpe-conf: gpe-conf.c
	$(CC) $(CFLAGS) $(GTK_CFLAGS) -o $@ $< $(LDFLAGS) $(GTK_LIBS)

clean:
	rm -f gpe-conf
