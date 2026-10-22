.PHONY: help deps cert icons test build install update uninstall process reset-permissions clean

ENV_FILE := $(HOME)/.config/murmur/.env

help:
	@echo "make deps        install ffmpeg and create ~/.config/murmur/.env"
	@echo "make cert        create the local signing identity (once)"
	@echo "make install     build and install to /Applications (also: make update)"
	@echo "make process FILE=path   transcribe + summarize an audio file or a leftover .recording-* folder"
	@echo "make test        run the unit tests"
	@echo "make icons       regenerate brand SVGs, AppIcon.icns and menu bar icons"
	@echo "make uninstall   remove the app (notes and settings are kept)"

deps:
	brew install ffmpeg
	mkdir -p $(dir $(ENV_FILE))
	@test -f $(ENV_FILE) || cp .env.example $(ENV_FILE)
	@echo "deps ready; settings live in $(ENV_FILE)"

cert:
	./scripts/create-cert.sh

icons:
	./scripts/make-icons.sh

test:
	swift test

build:
	./scripts/build-app.sh

install: build
	./scripts/install-app.sh

update: install

uninstall:
	-osascript -e 'tell application id "local.murmur.app" to quit'
	rm -rf /Applications/Murmur.app

process:
	@test -n "$(FILE)" || { echo "usage: make process FILE=path/to/audio.m4a (or a .recording-* folder)"; exit 1; }
	/Applications/Murmur.app/Contents/MacOS/Murmur --process "$(FILE)"

reset-permissions:
	tccutil reset Microphone local.murmur.app
	tccutil reset ScreenCapture local.murmur.app
	tccutil reset SpeechRecognition local.murmur.app

clean:
	rm -rf .build build
