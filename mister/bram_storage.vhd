---------------------------------------------------------------------------
--    IBM2030 MiSTer – On-chip BRAM Storage
--    File: bram_storage.vhd
--
--    Copyright 2024 – derived from LJW2030 by Lawrence Wilkinson
--    Licensed under the GNU General Public License v3 or later.
--
--    Purpose
--    -------
--    Replaces the SDRAM adapter with a simple synchronous on-chip Block
--    RAM so that the IBM 360/30 storage interface has fully deterministic,
--    single-cycle timing.  The SDRAM adapter is still available for builds
--    that need external storage or wish to scale beyond on-chip capacity
--    (set USE_BRAM => false in IBM2030_MiSTer.vhd).
--
--    Why BRAM instead of SDRAM?
--    --------------------------
--    * Deterministic timing: BRAM reads complete in exactly one 50 MHz
--      clock cycle; no refresh, no row-activate latency, no CAS latency.
--    * No prefetch state machine: the sdram_adapter.vhd read-ahead FSM is
--      unnecessary because BRAM output is always valid the cycle after the
--      address is presented.
--    * Simpler: fewer states, no SDRAM controller dependency.
--    * Capacity: 128 KB × 9 bits = ~1.1 Mbit.  The DE10-Nano Cyclone V
--      has 5.5 Mbit of M10K BRAM – the IBM2030 storage uses ~20% of it,
--      leaving the rest available for display buffers, future expansions,
--      etc.
--    * SDRAM is still the right choice if disk/tape images need to be
--      resident in memory (tens of MB) or if a future port targets an
--      FPGA with less on-chip BRAM.
--
--    Address / data mapping (identical to sdram_adapter)
--    ----------------------------------------------------
--    sram_addr[17:0]  as driven by ibm2030.vhd:
--      bit 17   = always '0' (tied off in ibm2030.vhd)
--      bit 16   = 1 → main storage (64 KB), 0 → local/bump storage (64 KB)
--      bits 15:0 = byte address within the selected 64 KB bank
--    sram_data[8:0]   = 8 data bits + 1 parity bit
--
--    Timing guarantees
--    -----------------
--    The IBM 360/30 loads the MSAR (memory address) register at least one
--    full machine cycle before asserting the ReadPulse strobe.  One IBM
--    machine cycle is ~400 ns; the FPGA clock period is 20 ns (50 MHz).
--    That gives ≥ 20 FPGA clock cycles between address setup and the read
--    strobe – far more than the one-cycle BRAM read latency.
--
--    Write pulses are likewise held for an entire machine cycle, so the
--    synchronous write (sampled on the rising edge) is always safe.
---------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bram_storage is
    port (
        -- 50 MHz system clock
        clk        : in    std_logic;

        -- SRAM-style interface (same polarity as sdram_adapter ports)
        -- Active-low chip-enable, write-enable and output-enable mirror the
        -- original Spartan-3 SRAM convention used by ibm2030-storage.vhd.
        sram_addr  : in    std_logic_vector(17 downto 0);
        sram_data  : inout std_logic_vector(8 downto 0);
        sram_ce_n  : in    std_logic;   -- Chip Enable,   active low
        sram_we_n  : in    std_logic;   -- Write Enable,  active low
        sram_oe_n  : in    std_logic    -- Output Enable, active low
    );
end entity bram_storage;

architecture rtl of bram_storage is

    -- 2^17 = 131 072 locations × 9 bits.
    -- sram_addr[16:0] carries the full effective address; bit 17 is
    -- permanently '0' in the current ibm2030.vhd design.
    constant ADDR_BITS : integer := 17;
    constant MEM_DEPTH : integer := 2 ** ADDR_BITS;   -- 131 072

    type mem_t is array (0 to MEM_DEPTH - 1) of std_logic_vector(8 downto 0);

    -- Quartus infers M10K blocks from this pattern (registered read,
    -- registered write, single-port style).  Initialise to all zeros so
    -- the FPGA comes up in a known state even before the ibm2030-storage
    -- init FSM has finished its clear pass.
    signal mem     : mem_t := (others => (others => '0'));
    signal rd_data : std_logic_vector(8 downto 0) := (others => '0');

begin

    -- -----------------------------------------------------------------------
    -- Synchronous BRAM process
    --
    -- Write path: when CE=0 and WE=0 the data on sram_data (driven by the
    --   ibm2030 core) is written to mem on the rising clock edge.
    --
    -- Read path: mem[addr] is registered into rd_data every rising edge
    --   regardless of CE/OE.  rd_data is stable by the next rising edge and
    --   remains stable until the address changes.  Because the IBM 360/30
    --   always presents the address 20+ FPGA cycles before ReadPulse, the
    --   one-cycle latency is invisible to the CPU.
    -- -----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if sram_ce_n = '0' and sram_we_n = '0' then
                mem(to_integer(unsigned(sram_addr(ADDR_BITS - 1 downto 0))))
                    <= sram_data;
            end if;
            rd_data <=
                mem(to_integer(unsigned(sram_addr(ADDR_BITS - 1 downto 0))));
        end if;
    end process;

    -- -----------------------------------------------------------------------
    -- Output driver
    --
    -- Drive sram_data from the registered BRAM output only during a read
    -- (CE=0, OE=0, WE=1).  In all other conditions tri-state the bus so
    -- the ibm2030 core can drive it for writes.
    -- -----------------------------------------------------------------------
    sram_data <= rd_data
                    when (sram_ce_n = '0' and sram_oe_n = '0' and sram_we_n = '1')
                    else (others => 'Z');

end architecture rtl;
