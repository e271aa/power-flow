# PowerFlow

A menu bar app for Apple Silicon Macs (macOS 13+) that shows where your Mac's
power goes, in watts: adapter, battery and system. It only reads sensors.

This README is a placeholder; the full one comes with the first release.

## Build

```bash
swift test          # unit tests
./build.sh          # builds PowerFlow.app (needs `brew install librsvg`)
./build.sh --dmg    # also builds power-flow.dmg
```

## License

MIT, see [LICENSE](LICENSE).
