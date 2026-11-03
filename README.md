# zxQ — ZX Spectrum 48K demo

A **ZX Spectrum 48K** demo written in Z80 assembly: ~46 s, 12 scenes of 192 frames each with continuous beeper music.
Effects: plasma, fire, particles, 3D dots, zoom, attribute effects.

![Loading screen](zxQ_256x192.png)

## Build

Requirements: `python3` (Pillow, numpy) and the [pasmo](https://pasmo.speccy.org/) assembler in `PATH`.

```sh
make                         # build/zxQ_demo.tap
make PASMO=/path/to/pasmo    # if pasmo is not in PATH
```

The `tools/` scripts generate effect data and graphics; `tools/zxsim.py` is a simple simulator used for testing.

## License

MIT — see [LICENSE](LICENSE).
