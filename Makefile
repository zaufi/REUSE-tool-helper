#
# SPDX-FileCopyrightText: 2024 Alex Turbov <i.zaufi@gmail.com>
# SPDX-License-Identifier: CC0-1.0
#

PREFIX=/usr/local
BINDIR=$(PREFIX)/bin

all:
	:

install: add-copyright-header.sh
	install -D -m 755 '$<' '$(DESTDIR)$(BINDIR)/$(basename $<)'
