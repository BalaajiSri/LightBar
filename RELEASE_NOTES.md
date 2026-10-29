## Animation Studio · Experimental

New separate section for built-in lamp animations driven by computer audio. Existing colour-based music sync and Experimental BPM remain available.

- Pattern selector, initially 7-Color Wave.
- Optional animation layer, off by default.
- Reference-speed adjustment and estimated BPM display.
- Tempo-influenced animation speed and audio/bass brightness accents.
- Switch the layer off to return to music palettes.
- Original static-animation controls remain available in the Studio.

Built-in patterns use the controller's own colours; custom palettes cannot be superimposed on them with the verified protocol. Speed scaling is a heuristic, not calibrated BPM or phase lock. This feature needs testing on the physical light to verify brightness/speed changes preserve the selected animation.

The audio-capture implementation is unchanged. Existing protocol/audio/tempo checks plus animation-speed and brightness bounds pass; both Mac architectures build and the panel was rendered and visually checked. Intel runtime remains untested.

Download LightBar-macOS-universal.zip, unzip and move LightBar.app to Applications. Requires macOS 13+. The app is ad-hoc signed and not notarized. Updated builds may need renewed Bluetooth or Screen & System Audio Recording permission. Use the installed copy in Applications.
