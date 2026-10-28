## Music colour palettes

Choose Neon, Sunset, Aurora, Ember or Ocean, keep a single chosen colour, or create your own three-colour music palette. Edit colours for bass, mids and treble separately; changes blend live during both classic music sync and Experimental BPM. Palette and custom colours are saved locally.

The audio-capture implementation is unchanged from 0.4.0. The existing and experimental music reactions remain available. This update passed existing audio, tempo and protocol checks and the controls were visually inspected. Preset appearance on the physical light still needs user testing.

## Experimental BPM + spectrum lab

An optional addition to the existing music sync. The experimental switch starts off; enabling it opens the music lab.

- Estimated BPM with a heuristic rhythm-confidence indicator.
- Bass-weighted beat accents and energy-dependent pulse strength.
- Smooth spectral colour diffusion during quiet passages.
- Stereo-biased colour and brighter accents as the music builds.
- A scrolling, 16-band frequency history in the app.
- The existing music reaction remains available with the switch off.

Download **LightBar-macOS-universal.zip**, unzip, and install LightBar.app in Applications. Supports macOS 13+ on Apple Silicon and Intel. Runtime checks ran on Apple Silicon; Intel runtime is untested.

Start music sync and turn on **Experimental BPM**. Give it several seconds of steady rhythm. Tempo estimates can be half/double the song's beat; the search range is approximately 60–180 BPM. Uncertain rhythm uses spectrum/onset response instead. This prerelease needs real-song testing.

The physical bar is still controlled as one colour; the frequency history is displayed in the app. No per-region control or isolated-vocal detection is claimed. Audio is processed locally without saving or uploading it.

Synthetic tempo, missing-beat, frequency, stereo, silence, bounded-output, and protocol checks passed. Both Mac architectures were built, the signature was verified, and both panels were visually checked.

The app is ad-hoc signed and not Apple-notarized. As with previous builds, macOS can require Open Anyway and renewed Bluetooth/recording permission for an updated app. Use the installed copy in Applications.
