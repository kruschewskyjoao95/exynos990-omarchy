#!/bin/sh
# Chrome/Chromium only talk to the Wayland text-input protocol (what makes squeekboard open by itself on a
# focused text field) with these flags. Idempotent; run as the desktop user.
for f in "$HOME/.config/chrome-flags.conf" "$HOME/.config/chromium-flags.conf"; do
	touch "$f"
	for flag in --enable-wayland-ime --wayland-text-input-version=3; do
		grep -qxF -- "$flag" "$f" || echo "$flag" >> "$f"
	done
done
