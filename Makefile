APP := MergeQ.app
INSTALL_DIR := $(HOME)/Applications
AGENT := $(HOME)/Library/LaunchAgents/local.mergeq.plist

.PHONY: build app test install uninstall run clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf build/$(APP)
	mkdir -p build/$(APP)/Contents/MacOS
	cp .build/release/MergeQ build/$(APP)/Contents/MacOS/MergeQ
	cp Info.plist build/$(APP)/Contents/Info.plist
	codesign --force --sign - build/$(APP)

run: app
	open build/$(APP)

# Copies the app to ~/Applications and starts it at login via a LaunchAgent.
install: app
	-pkill -x MergeQ
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(APP)
	cp -R build/$(APP) $(INSTALL_DIR)/$(APP)
	sed "s#__APP__#$(INSTALL_DIR)/$(APP)#" local.mergeq.plist > $(AGENT)
	-launchctl bootout gui/$$(id -u) $(AGENT) 2>/dev/null
	launchctl bootstrap gui/$$(id -u) $(AGENT)

uninstall:
	-launchctl bootout gui/$$(id -u) $(AGENT)
	rm -f $(AGENT)
	rm -rf $(INSTALL_DIR)/$(APP)

clean:
	rm -rf .build build
