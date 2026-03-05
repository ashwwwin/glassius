<p align="center">
  <img src="./logo.png" alt="Glassius logo" width="180" />
</p>

<h1 align="center">GlassiusCam</h1>

<p align="center">
  Menu bar video for two Macs on the same local network.
</p>

<p align="center">
  <a href="https://github.com/ashwwwin/glassius/actions/workflows/ci.yml">
    <img src="https://github.com/ashwwwin/glassius/actions/workflows/ci.yml/badge.svg" alt="CI status" />
  </a>
</p>

GlassiusCam is a macOS menu bar app for low-friction, local-only video between two trusted Macs on the same Wi-Fi.

## Features

- Menu bar app (no Dock icon)
- Local network peer discovery (Bonjour / MultipeerConnectivity)
- Auto camera start when the Glassius panel is opened
- Auto video stop when the panel is closed
- Local/remote panel open-close sync
- Local/remote fullscreen toggle sync
- Right-click menu bar item for quick quit
- Launch at login enabled by default
- Custom app icon from `logo.png`

## Requirements

- macOS 13+
- Camera permission
- Local Network permission
- Two trusted Macs on the same Wi-Fi

## Quick Start

```bash
./scripts/build_app_bundle.sh
open dist/GlassiusCam.app
```

Build output:

- `dist/GlassiusCam.app`

## Run on Two Macs

1. Copy this project (or `dist/GlassiusCam.app`) to both Macs.
2. Launch the app on both Macs.
3. Grant camera and local network permissions when prompted.
4. Open Glassius from the menu bar on either Mac.
5. The other side should auto-open/sync once connected.

## Usage

- Open/close from menu bar to start/stop video session.
- Click `Toggle Fullscreen` to mirror fullscreen state on both Macs.
- Right-click the menu bar item and choose `Quit Glassius` to exit.

## Architecture

- `Sources/GlassiusCamApp.swift`: app lifecycle + menu bar + popover orchestration
- `Sources/AppModel.swift`: state machine and coordination
- `Sources/PeerVideoService.swift`: Multipeer connectivity + control/data messaging
- `Sources/VideoCaptureService.swift`: camera capture + frame encoding
- `Sources/FullscreenWindowController.swift`: fullscreen window behavior
- `scripts/build_app_bundle.sh`: builds `.app`, icon generation, signing

## Privacy & Security

- No cloud backend.
- No external signaling server.
- Traffic is local peer-to-peer over your LAN.
- Intended for **two trusted Macs** only.

## Known Limitations

- Not hardened for hostile/untrusted networks.
- Ad-hoc signing is default; Gatekeeper warnings can appear on copied builds.
- Performance depends on Wi-Fi quality and Mac hardware.

## Contributing

Issues and PRs are welcome.

Suggested workflow:

1. Fork the repo.
2. Create a feature branch.
3. Make your changes.
4. Open a PR with a clear test note.

## License

MIT License. See [LICENSE](./LICENSE).
