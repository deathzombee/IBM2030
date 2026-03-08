# IBM2030 – MiSTer FPGA Port

This directory contains the files required to build and deploy the
IBM System/360 Model 30 FPGA core on the
[MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) platform
(DE10-Nano, Cyclone V FPGA).

---

## Directory structure

```
mister/
  IBM2030_MiSTer.vhd   MiSTer top-level "emu" wrapper
  bram_storage.vhd     On-chip BRAM storage (default, deterministic timing)
  sdram_adapter.vhd    SRAM→SDRAM bridge (optional, for large external memory)
  IBM2030.qsf          Quartus project settings
  IBM2030.sdc          Timing constraints
  IBM2030.ini          MiSTer OSD configuration
  README.md            This file
```

The core VHDL source files remain in the repository root.

---

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Quartus Prime (Lite or Standard) | 18.1 |
| Intel Cyclone V device support | installed |
| MiSTer framework `sys/` | current main branch |

---

## Build instructions

### 1. Obtain the MiSTer framework files

The `sys/` directory is shared across all MiSTer cores and is **not**
included in this repository.  Obtain it from the MiSTer main repository:

```bash
# From the repository root (one level above mister/)
git clone --depth 1 https://github.com/MiSTer-devel/Main_MiSTer sys
```

Alternatively, copy the `sys/` folder from any other MiSTer core
release.  The folder must be at the **repository root** (i.e. a sibling
of the `mister/` directory) so that the relative path `../sys/` in the
`.qsf` file resolves correctly.

### 2. Open the project in Quartus

```
File → Open Project → IBM2030/mister/IBM2030.qsf
```

### 3. Compile

```
Processing → Start Compilation
```

A successful build produces:

```
mister/output/IBM2030_MiSTer.rbf
```

### 4. Deploy to the MiSTer SD card

Copy the `.rbf` to the games folder on the SD card:

```
/media/fat/games/IBM2030/IBM2030_MiSTer.rbf
```

Copy the OSD settings file (optional):

```
/media/fat/games/IBM2030/IBM2030_MiSTer.ini
```

Restart the MiSTer menu and select the IBM2030 core.

---

## Pin mapping

| DE10-Nano signal | IBM2030 function |
|-----------------|-----------------|
| `CLK_50M` (PIN_V11) | 50 MHz system clock |
| `BUTTONS[0]` (KEY0, PIN_AH17) | Pushbutton pb[1] |
| `BUTTONS[1]` (KEY1, PIN_AH16) | Pushbutton pb[0] |
| `USER_IO[0]` (GPIO-1 pin 1, PIN_Y15) | RS-232 TxD (to host) |
| `USER_IO[1]` (GPIO-1 pin 2, PIN_AA15) | RS-232 RxD (from host) |
| SDRAM (32 MB on-board) | IBM2030 main & local storage |
| HDMI out (via `sys_top`) | VGA 640×480 @ 60 Hz |

The serial port runs at the same baud rate as the original RS-232
interface (connected to the IBM 1050 console terminal emulator).

---

## Storage

### Back-end selection

The storage back-end is chosen by the `USE_BRAM` constant near the top of
`IBM2030_MiSTer.vhd`:

```vhdl
constant USE_BRAM : boolean := true;   -- on-chip BRAM (default)
-- constant USE_BRAM : boolean := false;  -- DE10-Nano SDRAM
```

### On-chip BRAM (default, `USE_BRAM = true`)

The IBM 360/30 needs 128 KB of 9-bit-wide storage (64 KB main storage +
64 KB local/bump storage).  The DE10-Nano Cyclone V contains 5.5 Mbit of
M10K block RAM; the IBM2030 storage uses ~1.1 Mbit (~20%), leaving the
rest available for display buffers, future peripherals, etc.

`bram_storage.vhd` implements a single synchronous-read BRAM array:

1. **Deterministic timing**: reads complete in exactly one 50 MHz clock
   cycle — no refresh, no row-activate or CAS latency, no prefetch FSM.
2. **Zero-wait-state operation**: the IBM 360/30 loads its MSAR (address)
   register at least one full machine cycle (~400 ns, ≥ 20 FPGA clocks)
   before the ReadPulse strobe, so the one-cycle BRAM latency is never
   visible to the CPU.
3. **Simpler**: replaces the multi-state SDRAM prefetch machine with a
   single registered-read process.
4. **SKIP_PROM**: because there is no serial configuration PROM on the
   MiSTer board, `SKIP_PROM` is automatically set to `true` when
   `USE_BRAM = true`.  This causes the `ibm2030-storage.vhd` init FSM
   to jump straight to `finished` after zeroing both storage banks,
   rather than hanging indefinitely waiting for a PROM sync pattern.
5. **SDRAM deasserted**: all DE10-Nano SDRAM pins are driven to a safe
   idle state (`CKE=0`, `nCS=1`) when BRAM is active.

### SDRAM adapter (optional, `USE_BRAM = false`)

`sdram_adapter.vhd` bridges the IBM2030 SRAM interface to the DE10-Nano
32 MB SDRAM via the MiSTer `sys/sdram.sv` controller.  This path is
appropriate when disk or tape images need to be resident in memory
(tens of MB) or when a future port targets an FPGA with insufficient
on-chip BRAM.

The adapter uses a **read-ahead prefetch** state machine to hide the
multi-cycle SDRAM latency:

1. Whenever the CPU address bus (MSAR register) changes the adapter
   immediately issues an SDRAM read and buffers the result.
2. When the CPU asserts its read strobe the cached data is placed on the
   bus combinationally, matching zero-wait-state SRAM behaviour.
3. Single-cycle write pulses are captured and written to SDRAM; the
   cache is updated write-through.

### Address / data mapping (common to both back-ends)

| IBM2030 signal | Meaning |
|---|---|
| `sramaddr[17]` | Always `0` (tied off in `ibm2030.vhd`) |
| `sramaddr[16]` | `1` = main storage (64 KB), `0` = local/bump storage (64 KB) |
| `sramaddr[15:0]` | Byte address within the selected 64 KB bank |
| `srama[7:0]` (`sram_data[7:0]`) | 8-bit data byte |
| `srama[8]` (`sram_data[8]`) | Parity bit |

---

## Known limitations / future work

### Microcode / PROM loading

The original design reads an OS image from a Xilinx platform flash
device after FPGA configuration.  On MiSTer there is no equivalent
serial flash accessible from the FPGA fabric.

**Required work for a future PR:**
1. Pre-load the microcode (from `ccros.vhd`) and the OS image into
   SDRAM via the HPS (Linux) side using a `.rom` file passed through
   the OSD.
2. Implement HPS I/O integration in `IBM2030_MiSTer.vhd` using
   `sys/hps_io.sv` to receive the ROM file and trigger initialisation.

### Panel switches and LEDs

The IBM 2030 front-panel has many switches (hex rotary, toggle, and
push-button) and hundreds of indicator lamps.  The original board uses:
- MAX7318 I²C GPIO expander (switch scanning)
- MAX7219 LED driver (panel lamps)
- MAX6951 LED driver (miniature panel)

On MiSTer these are replaced by:
- The VGA front-panel emulation (`ibm2030-vga.vhd`) which already
  renders all indicators on screen.
- Future OSD menus (via `sys/hps_io.sv`) to expose virtual switches.

### OSD / HPS integration

`IBM2030_MiSTer.vhd` does not yet instantiate `sys/hps_io.sv`.
Until this is added:
- The OSD cannot be used to change settings at runtime.
- `STATUS[7:0]` (wired to the `sw` slide-switch input) defaults to
  all-zero (from the Quartus default for undriven inputs).

### Keyboard / disk image handling

Full IBM 1050 console keyboard emulation and disk/tape image handling
via the MiSTer file-system are planned for a future PR.

---

## Changes to core VHDL for portability

The following Xilinx-specific constructs have been replaced with
standard VHDL in the repository-root source files:

| File | Change |
|------|--------|
| `clock_management.vhd` | Replaced Xilinx `SRL16` primitive with a generic integer counter |
| `shift_compare_serial.vhd` | Replaced Xilinx `FDRE`, `LUT2`, `MUXCY` primitives with behavioral VHDL processes |
| `FMD2030_5-08A1.vhd` | Replaced Xilinx `FDCE` primitives with a single clocked process |
| `FMD2030_5-10A.vhd` | Replaced Xilinx `FDRSE` primitives with behavioral SR flip-flop processes |
| `ibm2030.vhd`, `ibm2030-cpu.vhd`, `cpu.vhd`, `ibm1050.vhd`, `vga_controller_640_60.vhd`, `PROM_reader_serial.vhd` | Removed unused `library UNISIM / use UNISIM.vcomponents.all` declarations |

The original Spartan-3 target (Xilinx ISE) is unaffected by these
changes because all replacements are functionally equivalent.

---

## License

This port is derived from LJW2030 by Lawrence Wilkinson.  
Licensed under the GNU General Public License v3 or later.  
See [COPYING](../COPYING) for the full license text.
