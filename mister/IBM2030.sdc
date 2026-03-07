# IBM2030 MiSTer Core – Timing Constraints
# Target device: Intel Cyclone V 5CSEBA6U23I7 (DE10-Nano)

# -----------------------------------------------------------------------
# Primary clock: 50 MHz from DE10-Nano oscillator
# -----------------------------------------------------------------------
create_clock -name {CLK_50M} -period 20.000 -waveform { 0.000 10.000 } [get_ports {CLK_50M}]

# -----------------------------------------------------------------------
# Generated clocks from MiSTer sys/pll.v
# The framework PLL derives several clocks from CLK_50M.
# Exact values depend on the pll.v version; adjust if needed.
# -----------------------------------------------------------------------
# 50 MHz system clock (1:1 from input)
derive_pll_clocks

# -----------------------------------------------------------------------
# Clock groups: all internally-generated clocks are synchronous
# to each other except the HDMI PLL output (treated as async).
# -----------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {*pll_hdmi*}] \
    -group [get_clocks {*pll_audio*}]

# -----------------------------------------------------------------------
# Input / output delays (conservative estimates for USER_IO serial)
# Adjust if timing fails after actual UART bit-rate analysis.
# -----------------------------------------------------------------------
set_input_delay  -clock {CLK_50M} -max 5.0 [get_ports {USER_IO[1]}]
set_input_delay  -clock {CLK_50M} -min 0.0 [get_ports {USER_IO[1]}]
set_output_delay -clock {CLK_50M} -max 5.0 [get_ports {USER_IO[0]}]
set_output_delay -clock {CLK_50M} -min 0.0 [get_ports {USER_IO[0]}]

# -----------------------------------------------------------------------
# False paths for asynchronous inputs (buttons)
# -----------------------------------------------------------------------
set_false_path -from [get_ports {BUTTONS[*]}] -to [all_clocks]

# -----------------------------------------------------------------------
# SDRAM timing (when sdram.sv is connected)
# The MiSTer sdram.sv module expects a 90-degree phase-shifted clock.
# Uncomment and adjust after connecting the SDRAM adapter.
# -----------------------------------------------------------------------
#set_output_delay -clock {SDRAM_CLK} -max  1.5 [get_ports SDRAM_*]
#set_output_delay -clock {SDRAM_CLK} -min -0.8 [get_ports SDRAM_*]
#set_input_delay  -clock {SDRAM_CLK} -max  3.5 [get_ports {SDRAM_DQ[*]}]
#set_input_delay  -clock {SDRAM_CLK} -min  1.0 [get_ports {SDRAM_DQ[*]}]

# -----------------------------------------------------------------------
# Derive default clock uncertainties
# -----------------------------------------------------------------------
derive_clock_uncertainty
