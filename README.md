# zxQ — ZX Spectrum 48K demo

Demo na **ZX Spectrum 48K** w asemblerze Z80: ~46 s, 12 scen z ciągłą muzyką na beeperze.
Efekty: plazma, ogień, cząsteczki, kropki 3D, zoom, efekty na atrybutach.

![Ekran ładowania](zxQ_256x192.png)

## Build

Wymagania: `python3` (Pillow, numpy) i asembler [pasmo](https://pasmo.speccy.org/) w `PATH`.

```sh
make                         # build/zxQ_demo.tap
make PASMO=/path/to/pasmo    # jeśli pasmo nie jest w PATH
```

Narzędzia w `tools/` generują dane efektów i grafikę, `tools/zxsim.py` to prosty symulator do testów.
