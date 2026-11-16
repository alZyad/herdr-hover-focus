NAME := herdr-hover-focus
LABEL := local.$(NAME)
APP := build/HerdrHoverFocus.app
BIN := $(APP)/Contents/MacOS/$(NAME)
INSTALL_APP := $(HOME)/Applications/HerdrHoverFocus.app
AGENT := $(HOME)/Library/LaunchAgents/$(LABEL).plist
IDENTITY ?= $(shell security find-identity -v -p codesigning | grep -q 'Apple Development' && echo 'Apple Development' || echo '-')
DOMAIN := gui/$(shell id -u)

.PHONY: build run install uninstall restart log

build: $(BIN)

$(BIN): Sources/*.swift Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	swiftc -O Sources/*.swift -o $(BIN)
	codesign --force --sign "$(IDENTITY)" $(APP)

run: build
	$(BIN) --verbose

install: build
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	mkdir -p $(HOME)/Applications $(HOME)/Library/LaunchAgents
	rm -rf $(INSTALL_APP)
	cp -R $(APP) $(INSTALL_APP)
	sed 's|@BIN@|$(INSTALL_APP)/Contents/MacOS/$(NAME)|' launchagent.plist > $(AGENT)
	launchctl bootstrap $(DOMAIN) $(AGENT)

restart:
	launchctl kickstart -k $(DOMAIN)/$(LABEL)

uninstall:
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	rm -rf $(INSTALL_APP) $(AGENT)

log:
	tail -f /tmp/$(NAME).log
