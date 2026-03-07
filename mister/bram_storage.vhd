---------------------------------------------------------------------------
--    IBM2030 MiSTer On-Chip Block RAM Storage
--    File: bram_storage.vhd
--
--    Copyright 2024 – derived from LJW2030 by Lawrence Wilkinson
--    Licensed under the GNU General Public License v3 or later.
--
--    Purpose
--    -------
--    Implements IBM2030 main and local storage entirely in on-chip FPGA
--    block RAM (M10K on Cyclone V), with the same active-low SRAM
--    interface as sdram_adapter.vhd.  This is a drop-in replacement for
--    sdram_adapter.vhd; no external SDRAM is required.
--
--    Interface (identical polarity to sdram_adapter.vhd)
--    ---------------------------------------------------
--      sram_addr[17:0]  18-bit byte address
--      sram_data[8:0]   9-bit bidirectional data (8 data + 1 parity bit)
--      sram_ce_n        chip enable, active-low
--      sram_we_n        write enable, active-low
--      sram_oe_n        output enable, active-low
--      sram_ub_n        upper byte select, active-low (unused; always '0'
--                       in ibm2030-storage.vhd)
--      sram_lb_n        lower byte select, active-low (unused; always '0'
--                       in ibm2030-storage.vhd)
--
--    Read timing
--    -----------
--    The IBM 360/30 loads its MSAR (address) register several machine
--    cycles before asserting ReadPulse.  This module uses a standard
--    synchronous BRAM: on every rising clock edge the current address
--    is used to look up the RAM, and the result is registered into
--    dout_reg.  Because of the pipeline spacing guaranteed by the 360/30
--    microcode, dout_reg is always settled when ReadPulse is asserted.
--
--    sram_data is driven combinationally from dout_reg while
--    sram_ce_n='0', sram_oe_n='0', and sram_we_n='1', matching the
--    zero-wait-state behaviour expected by ibm2030-storage.vhd.
--
--    Write timing
--    ------------
--    When sram_ce_n='0' and sram_we_n='0', sram_data is written to the
--    BRAM on the rising clock edge.  dout_reg is updated simultaneously
--    (write-through), so a read of the same address in the very next
--    clock cycle returns the freshly written data.
--
--    Resource usage (Cyclone V, Quartus Prime 18.1+)
--    ------------------------------------------------
--    2^18 x 9-bit array = 2.25 Mbit.  Inferred as M10K blocks.
--    Estimated usage: ~230 M10K blocks (out of 553 on 5CSEBA6U23I7).
--    Only the lower 128 KB is addressed by the IBM2030 core because
--    ibm2030.vhd drives sram_addr[17]='0', so synthesis may reduce
--    this to ~115 M10K blocks after optimisation.
---------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bram_storage is
    port (
        -- System clock (50 MHz)
        clk       : in    std_logic;

        -- SRAM-style interface (same polarity as sdram_adapter.vhd)
        sram_addr : in    std_logic_vector(17 downto 0);
        sram_data : inout std_logic_vector(8 downto 0);
        sram_ce_n : in    std_logic;   -- chip enable, active-low
        sram_we_n : in    std_logic;   -- write enable, active-low
        sram_oe_n : in    std_logic;   -- output enable, active-low
        sram_ub_n : in    std_logic;   -- unused; kept for drop-in compatibility
        sram_lb_n : in    std_logic    -- unused; kept for drop-in compatibility
    );
end entity bram_storage;

architecture rtl of bram_storage is

    -- ---------------------------------------------------------------
    -- RAM array: 2^18 locations x 9 bits = 256 KB x 9 bits.
    -- Initialised to all zeros at power-on; ibm2030-storage.vhd also
    -- clears storage to zeros before handing control to the CPU, so
    -- the initial content is always consistent regardless of which
    -- path is taken.
    -- ---------------------------------------------------------------
    type ram_t is array(0 to 2**18 - 1) of std_logic_vector(8 downto 0);
    signal ram : ram_t := (others => (others => '0'));

    -- Registered read output (1-cycle read latency from address to data).
    signal dout_reg : std_logic_vector(8 downto 0) := (others => '0');

begin

    -- ---------------------------------------------------------------
    -- Synchronous read / write process
    --
    -- Write path (sram_ce_n='0', sram_we_n='0'):
    --   Writes sram_data into ram() and captures the written value
    --   into dout_reg in the same cycle (write-through), so that an
    --   immediate read of the same address in the next cycle returns
    --   the new data.
    --
    -- Read / idle path (all other cases):
    --   Registers ram(addr) into dout_reg, making it available in the
    --   following cycle when ReadPulse arrives.
    -- ---------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if sram_ce_n = '0' and sram_we_n = '0' then
                -- Write: update backing store and output register simultaneously
                ram(to_integer(unsigned(sram_addr))) <= sram_data;
                dout_reg <= sram_data;
            else
                -- Read / idle: pipeline BRAM output for next cycle
                dout_reg <= ram(to_integer(unsigned(sram_addr)));
            end if;
        end if;
    end process;

    -- ---------------------------------------------------------------
    -- Combinational read-data output
    --
    -- Drive sram_data from the registered BRAM output while the CPU
    -- asserts a read cycle (CE='0', OE='0', WE='1').  At all other
    -- times tri-state the bus so the ibm2030-storage.vhd write driver
    -- can take control.
    -- ---------------------------------------------------------------
    sram_data <= dout_reg when (sram_ce_n = '0' and sram_oe_n = '0' and sram_we_n = '1')
                 else (others => 'Z');

end architecture rtl;
