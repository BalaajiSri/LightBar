# LightBar

A native macOS menu bar app for Bluetooth LED lights using duoCo StripX-compatible controllers. Includes power, colour, brightness, built-in animations, and reactions to computer audio.

## Download and install

Download **LightBar-macOS-universal.zip** from [Releases](https://github.com/BalaajiSri/LightBar/releases/latest). Unzip it, move **LightBar.app** to **Applications**, and open it. Click the 💡 menu bar icon to open the controls.

Requires **macOS 13 or newer**, on Apple Silicon or Intel. This release is for Macs, not iPhone, iPad, Android, Windows, or Linux. Private repository downloads require signing in to a GitHub account with repository access.

The app is locally ad-hoc signed and is not Apple-notarized. macOS may require approval under **System Settings → Privacy & Security → Open Anyway** after your first attempt to open it.

## Connect your light

1. Power on the light near the Mac.
2. Fully close the phone app: many controllers accept one Bluetooth connection at a time.
3. Allow Bluetooth access when prompted.
4. Choose the light and click **Connect**. Use **Scan** to retry.

The last selected device is remembered. Reopening scans for 12 seconds; unexpected disconnection triggers another scan. Controls represent requested settings, not live device state.

If the menu bar is crowded, macOS may hide the icon near the notch. Reopen LightBar from Applications to bring up the control panel.

## React to computer audio

Connect the light, choose a music style, and click **React to Mac audio**. Play audio and adjust sensitivity and brightness. The current release includes Beat pulse, Smooth glow, Colour flow, Bass pulse, Voice-range glow, Spectrum colour, and Stereo colour.

Allow LightBar under **System Settings → Privacy & Security → Screen & System Audio Recording** (called Screen Recording on some versions), then quit and reopen if requested. Replacing an ad-hoc signed build can invalidate the previous permission entry. If capture is denied despite an enabled switch, remove the LightBar entry, add the installed copy from Applications, and enable it again.

Audio is processed locally using Apple's ScreenCaptureKit; no audio is saved or uploaded. Only audio output is processed, with microphone capture disabled. macOS may show a recording indicator because the framework uses a display filter. Some protected audio may be unavailable.

Bass, middle-frequency energy, treble, and stereo balance come from audio analysis. Voice-range glow is not isolated-vocal detection. Onsets are not exact tempo tracking. Known Bluetooth streaming commands affect the **whole bar**; independent region control has not been verified. The single combined music experience discussed during development is not implemented in this release.

Stop restores the selected colour or animation. Capture also stops on disconnect, quit, or a capture error. Closing the panel leaves the app running; use **Quit LightBar** to exit.

## Build from source

Install Apple's Xcode Command Line Tools, then run:

```sh
zsh build.sh
```

This produces a universal Apple Silicon / Intel app at `build/LightBar.app` and a distributable `LightBar.zip`. No third-party runtime dependencies are required. The build compiles both architectures, ad-hoc signs the app, verifies the signature, and runs protocol/audio tests on the host architecture. Intel runtime behaviour still needs testing on an Intel Mac.

To run the checks independently:

```sh
build/LightBar.app/Contents/MacOS/LightBar --test
```

GitHub Actions builds the app and uploads the ZIP as a workflow artifact. Release downloads are published separately.

## Compatibility and credits

Developed with a **MELK-OA21** controller. Other duoCo StripX devices may differ. Discovery recognises MELK / duoCo names or service FFF0, and verifies characteristic FFF3 supports writes without response. The app sends basic lighting commands, not pixel-count, wiring-order, or persistent controller-configuration commands.

Protocol research and effect names are based on [Corner-Floor-Lamp-Controller](https://github.com/wxx9248/Corner-Floor-Lamp-Controller). Third-party material retains its original rights; this repository does not grant a separate license to that material.

Diagnostic connection and command events are written locally to `LightBar.log` in the macOS user temporary directory. Captured audio and audio-level streams are not logged. Live music effects require testing with each physical controller; automated signal and protocol checks cannot verify visible LED response.
