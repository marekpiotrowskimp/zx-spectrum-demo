# zxQ - ZX Spectrum 48K demo (Quake tribute)
# Requirements: python3 with Pillow + numpy; pasmo must be in PATH (or: make PASMO=/path/to/pasmo).

PASMO   ?= pasmo
PYTHON  = python3
FUSE_APP ?= $(HOME)/Downloads/zx/Fuse for macOS/Fuse.app

BUILD   = build
TARGET  = $(BUILD)/zxQ_demo.tap
BIN     = $(BUILD)/zxQ_demo.bin
SYM     = $(BUILD)/zxQ_demo.sym
SCR     = gfx/loading.scr
GEN     = src/gen/tables.asm src/gen/music.asm
GENFX   = src/gen/fx_loops.asm
SRCS    = $(wildcard src/*.asm) $(GEN) $(GENFX)

START_ADDR = 32768
NAME       = zxQ

# headless harness (needs: pip install z80 pillow numpy)
SIMPY  ?= python3

.PHONY: all clean run sim help

all: $(TARGET)

$(GEN) $(SCR) &: tools/gen_data.py tools/zxgfx.py zxQ_256x192.png
	@mkdir -p $(BUILD)
	$(PYTHON) tools/gen_data.py

$(GENFX): tools/gen_fx.py tools/slotgen.py
	cd tools && $(PYTHON) gen_fx.py

$(BIN): $(SRCS)
	@mkdir -p $(BUILD)
	$(PASMO) --bin src/main.asm $(BIN) $(SYM)
	@echo "Binary size: $$(wc -c < $(BIN)) bytes (code_end $$(grep '^code_end' $(SYM) | awk '{print $$3}'))"

$(TARGET): $(BIN) $(SCR) tools/bin2tap.py
	$(PYTHON) tools/bin2tap.py $(BIN) $(TARGET) $(START_ADDR) $(NAME) $(SCR)

run: $(TARGET)
	@if command -v fuse >/dev/null 2>&1; then fuse --machine 48 $(TARGET); \
	elif [ -d "$(FUSE_APP)" ]; then open -a "$(FUSE_APP)" $(TARGET); \
	elif [ -d /Applications/Fuse.app ]; then open -a Fuse $(TARGET); \
	else echo "Fuse not found - open $(TARGET) in an emulator (48K model)."; fi

# run the whole demo headless: screenshots every 48 frames + WAV + CPU stats
sim: $(BIN) $(SCR)
	$(SIMPY) tools/zxsim.py $(BIN) --scr $(SCR) --frames 2520 --every 48 \
	  --out $(BUILD)/sim --wav $(BUILD)/sim/demo.wav --window 192 --offset 28 \
	  --idle 0x$$(grep '^idle_halt' $(SYM) | awk '{print $$3}' | sed 's/H$$//')

clean:
	rm -rf $(BUILD) $(GEN) $(GENFX) $(SCR)

help:
	@echo "make        - build $(TARGET) (BASIC loader + loading screen + code)"
	@echo "make run    - build and open in Fuse (select Spectrum 48K)"
	@echo "make sim    - headless run: screenshots, WAV and CPU stats in build/sim"
	@echo "make clean  - remove generated files"
