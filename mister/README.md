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
| HDMI out (via `sys_top`) | VGA 640×480 @ 60 Hz |

The serial port runs at the same baud rate as the original RS-232
interface (connected to the IBM 1050 console terminal emulator).

---

## Known limitations / future work

### Storage / SDRAM

The IBM2030 core uses an external SRAM interface for its 64 KB main
storage and 8 KB local storage.  The DE10-Nano does not have SRAM
chips; instead, it has 32 MB of SDRAM.

**Current status:** the SRAM signals in `IBM2030_MiSTer.vhd` are
left unconnected (tied to '0' / high-impedance).  The CPU will not
run correctly without real storage attached.

**Required work for a future PR:**
1. Instantiate the MiSTer `sys/sdram.sv` module.
2. Write a VHDL adapter that bridges the synchronous-SRAM interface
   used by `ibm2030-storage.vhd` to the SDRAM burst interface.
3. Alternatively, replace the SRAM with on-chip Block RAM (the
   Cyclone V has sufficient BRAM for 64 KB + 8 KB).

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
