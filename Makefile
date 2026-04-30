APP=matrix-metal
SRC=src/MatrixMetal.mm src/MatrixRenderer.mm
SAVER_BUNDLE=MatrixMetal.saver
SAVER_CONTENTS=$(SAVER_BUNDLE)/Contents
SAVER_BIN=$(SAVER_CONTENTS)/MacOS/MatrixMetal
SAVER_PLIST=$(SAVER_CONTENTS)/Info.plist
SAVER_ASSET_PLIST=assets/Info.plist
SAVER_ASSET_RESOURCES=assets/thumbnail.png assets/thumbnail@2x.png
SAVER_SRC=src/MatrixMetalScreenSaverView.mm src/MatrixRenderer.mm

standalone:
	clang++ -std=c++17 -fobjc-arc -O2 $(SRC) -o $(APP) \
	  -framework Cocoa -framework Metal -framework MetalKit -framework QuartzCore

run: standalone
	./$(APP)

saver-bundle:
	mkdir -p $(SAVER_CONTENTS)/MacOS $(SAVER_CONTENTS)/Resources
	clang++ -std=c++17 -fobjc-arc -O2 $(SAVER_SRC) \
	  -bundle -o $(SAVER_BIN) \
	  -framework Cocoa -framework ScreenSaver -framework Metal -framework MetalKit -framework QuartzCore
	cp $(SAVER_ASSET_PLIST) $(SAVER_PLIST)
	cp $(SAVER_ASSET_RESOURCES) $(SAVER_CONTENTS)/Resources/

install-saver: saver-bundle
	mkdir -p "$$HOME/Library/Screen Savers"
	rm -rf "$$HOME/Library/Screen Savers/$(SAVER_BUNDLE)"
	cp -R $(SAVER_BUNDLE) "$$HOME/Library/Screen Savers/$(SAVER_BUNDLE)"

clean:
	rm -f $(APP)
	rm -rf $(SAVER_BUNDLE)

reset-screensaver:
	killall "System Settings" 2>/dev/null || true
	killall ScreenSaverEngine 2>/dev/null || true
	killall legacyScreenSaver 2>/dev/null || true
	killall cfprefsd 2>/dev/null || true
