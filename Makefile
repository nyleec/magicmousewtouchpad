APP_NAME = MagicMouseApp
SRC = src/main.m src/TouchManager.m
FRAMEWORKS = -framework Cocoa -framework Foundation -framework CoreGraphics -F/System/Library/PrivateFrameworks -framework MultitouchSupport


all: $(APP_NAME).app

$(APP_NAME).app: $(SRC) Info.plist
	mkdir -p $(APP_NAME).app/Contents/MacOS
	mkdir -p $(APP_NAME).app/Contents/Resources
	cp Info.plist $(APP_NAME).app/Contents/Info.plist
	clang -fobjc-arc -o $(APP_NAME).app/Contents/MacOS/$(APP_NAME) $(SRC) $(FRAMEWORKS)

clean:
	rm -rf $(APP_NAME).app
