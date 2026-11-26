# Glo55 - build helpers. Needs V (https://vlang.io), libx11-dev, libxft-dev, libxinerama-dev, libxi-dev.
V ?= v

# make install: PREFIX picks where it goes (baked into the binary so it finds its
# themes), DESTDIR stages it for packaging:   make PREFIX=/usr && sudo make PREFIX=/usr install
PREFIX ?= /usr/local
DESTDIR ?=
BINDIR = $(DESTDIR)$(PREFIX)/bin
DATADIR = $(DESTDIR)$(PREFIX)/share/glo55
SESSIONDIR = $(DESTDIR)$(PREFIX)/share/xsessions

# the installed binary: the same program with PREFIX built in. build/prefix
# changes when PREFIX does, so a different PREFIX rebuilds it.
build/glo55: main.v x11/*.v glo55/*.v build/prefix
	$(V) -d glo55_prefix=$(PREFIX) -o build/glo55 .

build/prefix: FORCE
	@mkdir -p build
	@echo '$(PREFIX)' | cmp -s - $@ || echo '$(PREFIX)' > $@

# install: binary, the sample config (Blue Steel by name; a copy in
# ~/.config/glo55 keeps working), the bundled themes (default, Blue Steel,
# Fossils of the Machines, CORPO, Fresh Breath with its four palettes,
# geo55 and pinkline), X session entry. The other themes live on in themes/ for the
# installed config to point at by name; the per-theme sample configs the
# functional tests use are in test/.
FRESH = sedona painted-desert chillwave office-print
install: build/glo55
	install -d $(BINDIR) $(DATADIR)/themes/default $(DATADIR)/themes/bluesteel $(DATADIR)/themes/fossils $(DATADIR)/themes/corpo $(DATADIR)/themes/fresh-breath $(DATADIR)/themes/geo55 $(DATADIR)/themes/pinkline $(SESSIONDIR)
	install -m 755 build/glo55 $(BINDIR)/glo55
	sed 's|^theme = .*|theme = "bluesteel/theme.toml"|' config.toml > $(DATADIR)/config.toml
	chmod 644 $(DATADIR)/config.toml
	cp -R themes/default/. $(DATADIR)/themes/default/
	cp -R themes/bluesteel/. $(DATADIR)/themes/bluesteel/
	cp -R themes/fossils/. $(DATADIR)/themes/fossils/
	cp -R themes/corpo/. $(DATADIR)/themes/corpo/
	cp -R themes/fresh-breath/. $(DATADIR)/themes/fresh-breath/
	cp -R themes/geo55/. $(DATADIR)/themes/geo55/
	cp -R themes/pinkline/. $(DATADIR)/themes/pinkline/
	find $(DATADIR) -type d -exec chmod 755 {} + && find $(DATADIR) -type f -exec chmod 644 {} +
	sed 's|^Exec=.*|Exec=$(PREFIX)/bin/glo55|' dist/glo55.desktop > $(SESSIONDIR)/glo55.desktop
	chmod 644 $(SESSIONDIR)/glo55.desktop
	@echo "installed: $(PREFIX)/bin/glo55, $(PREFIX)/share/glo55/ (config.toml, themes/), $(PREFIX)/share/xsessions/glo55.desktop"

uninstall:
	rm -f $(BINDIR)/glo55 $(SESSIONDIR)/glo55.desktop
	rm -rf $(DATADIR)

test:
	$(V) test glo55 x11

functional: build/glo55
	test/functional.sh && test/floating.sh && test/multimonitor.sh && test/stress.sh && test/bluesteel.sh && test/fossils.sh && test/corpo.sh && test/fresh-breath.sh && test/geo55.sh && test/pinkline.sh && test/unicode.sh && test/workspace_buttons.sh && test/multiple_toolbars.sh && test/session.sh && test/install.sh

fmt:
	$(V) fmt -w main.v x11 glo55

run: build/glo55
	test/run-nested.sh

clean:
	rm -rf build

FORCE:

.PHONY: test functional fmt run clean install uninstall FORCE
