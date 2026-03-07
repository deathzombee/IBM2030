---------------------------------------------------------------------------
--    IBM2030 MiSTer SDRAM Storage Adapter
--    File: sdram_adapter.vhd
--
--    Copyright 2024 – derived from LJW2030 by Lawrence Wilkinson
--    Licensed under the GNU General Public License v3 or later.
--
--    Purpose
--    -------
--    Bridges the synchronous-SRAM-style interface exported by ibm2030.vhd
--    (sramaddr, srama, sramace, sramoe, sramwe …) to the MiSTer
--    sys/sdram.sv SDRAM controller and to the DE10-Nano's physical
--    SDRAM pins.
--
--    The IBM 2030 storage module was designed for a zero-wait-state,
--    asynchronous SRAM.  The adapter makes the SDRAM appear as a fast
--    SRAM by:
--      1. Running a read-ahead prefetch: any time the address bus
--         changes the adapter immediately issues an SDRAM read and
--         caches the result in a one-word buffer.  Because the IBM
--         360/30's MSAR (address) register is loaded many machine
--         cycles before the read pulse arrives, the prefetch always
--         completes before the data is needed.
--      2. Serving reads combinationally from the cache: when
--         sramace/sramoe are asserted the cached data is placed on
--         the srama bus in the same clock cycle, matching the
--         behaviour expected by ibm2030-storage.vhd.
--      3. Capturing single-cycle write pulses: when sramace/sramwe
--         are asserted together the adapter captures address and data,
--         then issues an SDRAM write and invalidates the cache entry
--         for that address.
--
--    Address / Data mapping
--    ----------------------
--    IBM2030 phys_address[17:0] → SDRAM byte address[17:0] (zero-pad
--      to 25 bits; only the lowest 256 KB of the 32 MB SDRAM is used).
--    IBM2030 phys_data[8:0] (8 data + 1 parity) → SDRAM 16-bit word:
--      SDRAM bits[7:0]  = phys_data[7:0]  (data)
--      SDRAM bit[8]     = phys_data[8]    (parity, stored in bit 8)
--      SDRAM bits[15:9] = 0               (unused)
--    ds (byte select) = "11" to access the full 16-bit word.
--
--    sdram.sv interface targeted
--    ---------------------------
--    The component declaration below matches the standard MiSTer
--    sys/sdram.sv flat-address variant (25-bit addr port).  The
--    interface has been stable since mid-2021; verify against the
--    actual sys/ commit in your build environment.  If your
--    sys/sdram.sv uses a row/bank/col decomposed address, replace:
--      addr : in std_logic_vector(24 downto 0)
--    with:
--      bank : in std_logic_vector(1 downto 0);
--      row  : in std_logic_vector(12 downto 0);
--      col  : in std_logic_vector(9 downto 0);
--    and map the 18-bit IBM2030 address accordingly.
--
--    Build notes
--    -----------
--    This file is VHDL-2008; Quartus Prime 18.1+ supports mixed VHDL /
--    SystemVerilog elaboration, so the `sdram` component (SystemVerilog)
--    is resolved at link time.
---------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sdram_adapter is
    port (
        -- ---------------------------------------------------------------
        -- Clocking / reset
        -- ---------------------------------------------------------------
        clk        : in  std_logic;  -- 50 MHz system clock
        reset      : in  std_logic;  -- Active-high; hold high until SDRAM init done

        -- ---------------------------------------------------------------
        -- SRAM-style interface (connects to ibm2030.vhd sram* ports)
        -- Signals follow the original Spartan-3 SRAM polarity convention:
        --   *_n = active-low (ce_n, we_n, oe_n)
        -- ---------------------------------------------------------------
        sram_addr  : in    std_logic_vector(17 downto 0);  -- 18-bit byte address
        sram_data  : inout std_logic_vector(8 downto 0);   -- 9-bit data (inout)
        sram_ce_n  : in    std_logic;  -- Chip Enable, active low
        sram_we_n  : in    std_logic;  -- Write Enable, active low
        sram_oe_n  : in    std_logic;  -- Output Enable, active low
        sram_ub_n  : in    std_logic;  -- Upper Byte select, active low (unused)
        sram_lb_n  : in    std_logic;  -- Lower Byte select, active low (unused)

        -- ---------------------------------------------------------------
        -- Physical DE10-Nano SDRAM pins
        -- ---------------------------------------------------------------
        SDRAM_CLK  : out   std_logic;
        SDRAM_CKE  : out   std_logic;
        SDRAM_A    : out   std_logic_vector(12 downto 0);
        SDRAM_BA   : out   std_logic_vector(1 downto 0);
        SDRAM_DQ   : inout std_logic_vector(15 downto 0);
        SDRAM_DQML : out   std_logic;
        SDRAM_DQMH : out   std_logic;
        SDRAM_nCS  : out   std_logic;
        SDRAM_nCAS : out   std_logic;
        SDRAM_nRAS : out   std_logic;
        SDRAM_nWE  : out   std_logic
    );
end entity sdram_adapter;

architecture rtl of sdram_adapter is

    -- ---------------------------------------------------------------
    -- sdram component declaration
    -- Matches sys/sdram.sv (flat 25-bit address version).
    -- If using the row/bank/col version, replace with:
    --   bank  : in  std_logic_vector(1 downto 0);
    --   row   : in  std_logic_vector(12 downto 0);
    --   col   : in  std_logic_vector(9 downto 0);
    -- and map below accordingly.
    -- ---------------------------------------------------------------
    component sdram
        port (
            init       : in    std_logic;
            clk        : in    std_logic;

            addr       : in    std_logic_vector(24 downto 0);
            we         : in    std_logic;
            rd         : in    std_logic;
            ds         : in    std_logic_vector(1 downto 0);
            din        : in    std_logic_vector(15 downto 0);
            dout       : out   std_logic_vector(15 downto 0);
            ready      : out   std_logic;

            SDRAM_CLK  : out   std_logic;
            SDRAM_CKE  : out   std_logic;
            SDRAM_A    : out   std_logic_vector(12 downto 0);
            SDRAM_BA   : out   std_logic_vector(1 downto 0);
            SDRAM_DQ   : inout std_logic_vector(15 downto 0);
            SDRAM_DQML : out   std_logic;
            SDRAM_DQMH : out   std_logic;
            SDRAM_nCS  : out   std_logic;
            SDRAM_nCAS : out   std_logic;
            SDRAM_nRAS : out   std_logic;
            SDRAM_nWE  : out   std_logic
        );
    end component;

    -- ---------------------------------------------------------------
    -- SDRAM controller interface signals
    -- ---------------------------------------------------------------
    signal sdram_addr_s  : std_logic_vector(24 downto 0) := (others => '0');
    signal sdram_we_s    : std_logic := '0';
    signal sdram_rd_s    : std_logic := '0';
    signal sdram_ds_s    : std_logic_vector(1 downto 0) := "11";
    signal sdram_din_s   : std_logic_vector(15 downto 0) := (others => '0');
    signal sdram_dout_s  : std_logic_vector(15 downto 0);
    signal sdram_ready_s : std_logic;

    -- ---------------------------------------------------------------
    -- Read-ahead cache: one-word deep
    -- ---------------------------------------------------------------
    signal cache_data    : std_logic_vector(8 downto 0) := (others => '0');
    signal cache_addr    : std_logic_vector(17 downto 0) := (others => '1');
    signal cache_valid   : std_logic := '0';

    -- ---------------------------------------------------------------
    -- State machine
    -- ---------------------------------------------------------------
    type state_t is (
        ST_IDLE,          -- Monitor address bus; dispatch reads/writes
        ST_PREFETCH,      -- Assert sdram_rd for one cycle
        ST_PREFETCH_WAIT, -- Wait for sdram_ready after prefetch
        ST_WRITE,         -- Assert sdram_we for one cycle
        ST_WRITE_WAIT     -- Wait for sdram_ready after write
    );
    signal state       : state_t := ST_IDLE;

    -- Registered copies of the bus at the moment a transaction starts
    signal txn_addr    : std_logic_vector(17 downto 0) := (others => '0');
    signal txn_data    : std_logic_vector(8 downto 0)  := (others => '0');

    -- Registered copy of sram_addr to detect changes
    signal last_addr   : std_logic_vector(17 downto 0) := (others => '1');

    -- Edge-detect for CE assertion
    signal ce_prev     : std_logic := '1';

begin

    -- ---------------------------------------------------------------
    -- Instantiate MiSTer SDRAM controller
    -- ---------------------------------------------------------------
    u_sdram : sdram
        port map (
            init       => reset,
            clk        => clk,
            addr       => sdram_addr_s,
            we         => sdram_we_s,
            rd         => sdram_rd_s,
            ds         => sdram_ds_s,
            din        => sdram_din_s,
            dout       => sdram_dout_s,
            ready      => sdram_ready_s,
            SDRAM_CLK  => SDRAM_CLK,
            SDRAM_CKE  => SDRAM_CKE,
            SDRAM_A    => SDRAM_A,
            SDRAM_BA   => SDRAM_BA,
            SDRAM_DQ   => SDRAM_DQ,
            SDRAM_DQML => SDRAM_DQML,
            SDRAM_DQMH => SDRAM_DQMH,
            SDRAM_nCS  => SDRAM_nCS,
            SDRAM_nCAS => SDRAM_nCAS,
            SDRAM_nRAS => SDRAM_nRAS,
            SDRAM_nWE  => SDRAM_nWE
        );

    -- ---------------------------------------------------------------
    -- Combinational: drive sram_data from cache when the CPU reads
    --
    -- The ibm2030-storage.vhd latch:
    --   StorageIn.ReadData <= phys_data when StorageOut.ReadPulse='1';
    -- is transparent, so phys_data must be valid while sram_ce_n and
    -- sram_oe_n are both low.  We serve it combinationally from the
    -- read-ahead cache.
    --
    -- On a cache miss (cache_valid=0 or address mismatch) sram_data
    -- is tri-stated; the CPU will read '0's or old data.  This should
    -- not occur in normal operation because the prefetch is issued as
    -- soon as the address bus changes, and the IBM 360/30 MSAR register
    -- is loaded several machine cycles before the read pulse.
    -- ---------------------------------------------------------------
    sram_data <=
        cache_data when (sram_ce_n = '0' and sram_oe_n = '0' and sram_we_n = '1'
                         and cache_valid = '1'
                         and cache_addr = sram_addr)
        else (others => 'Z');

    -- ---------------------------------------------------------------
    -- Registered state machine
    -- ---------------------------------------------------------------
    fsm: process(clk)
    begin
        if rising_edge(clk) then

            -- Default: deassert SDRAM strobes after one cycle
            sdram_we_s <= '0';
            sdram_rd_s <= '0';

            -- Track previous CE for edge detection
            ce_prev <= sram_ce_n;

            if reset = '1' then
                -- Hold everything deasserted while SDRAM initialises
                state       <= ST_IDLE;
                cache_valid <= '0';
                last_addr   <= (others => '1');
                sdram_we_s  <= '0';
                sdram_rd_s  <= '0';

            else
                case state is

                    -- ---------------------------------------------------
                    -- IDLE: watch for address changes (prefetch trigger)
                    --       or a write assertion.
                    -- ---------------------------------------------------
                    when ST_IDLE =>

                        -- ---- WRITE: CE and WE both asserted ----
                        -- Capture on the falling edge of CE when WE is
                        -- already low, or when WE goes low while CE is low.
                        --
                        -- TIMING ASSUMPTION: ibm2030-storage.vhd drives
                        -- sram_data (phys_data) combinationally from the
                        -- write-data source (WriteData or init_data) for
                        -- the entire clock cycle in which sramwe='0'.
                        -- The inout is therefore guaranteed to be driven by
                        -- the core for at least one full 50 MHz period, so
                        -- sampling it on the same rising edge is safe.
                        if sram_ce_n = '0' and sram_we_n = '0' then
                            txn_addr    <= sram_addr;
                            txn_data    <= sram_data; -- sample inout while driven by core
                            -- Invalidate cache if we wrote to the cached location
                            if cache_addr = sram_addr then
                                cache_valid <= '0';
                            end if;
                            state <= ST_WRITE;

                        -- ---- PREFETCH: address has changed ----
                        -- Issue a speculative SDRAM read so that data is
                        -- ready in the cache before the CPU's ReadPulse.
                        elsif sram_addr /= last_addr then
                            last_addr   <= sram_addr;
                            txn_addr    <= sram_addr;
                            cache_valid <= '0';  -- invalidate stale cache
                            state       <= ST_PREFETCH;
                        end if;

                    -- ---------------------------------------------------
                    -- PREFETCH: assert sdram_rd for one cycle
                    -- ---------------------------------------------------
                    when ST_PREFETCH =>
                        sdram_addr_s <= "0000000" & txn_addr;
                        sdram_rd_s   <= '1';
                        sdram_ds_s   <= "11";  -- read full 16-bit word
                        state        <= ST_PREFETCH_WAIT;

                    -- ---------------------------------------------------
                    -- PREFETCH_WAIT: wait for sdram_ready
                    -- ---------------------------------------------------
                    when ST_PREFETCH_WAIT =>
                        if sdram_ready_s = '1' then
                            -- Store lower 9 bits of SDRAM word in cache
                            cache_data  <= sdram_dout_s(8 downto 0);
                            cache_addr  <= txn_addr;
                            cache_valid <= '1';
                            state       <= ST_IDLE;
                        end if;

                    -- ---------------------------------------------------
                    -- WRITE: assert sdram_we for one cycle
                    -- ---------------------------------------------------
                    when ST_WRITE =>
                        sdram_addr_s <= "0000000" & txn_addr;
                        sdram_din_s  <= "0000000" & txn_data;
                        sdram_we_s   <= '1';
                        sdram_ds_s   <= "11";  -- write full 16-bit word
                        state        <= ST_WRITE_WAIT;

                    -- ---------------------------------------------------
                    -- WRITE_WAIT: wait for sdram_ready
                    -- After the write completes, re-issue a prefetch for
                    -- the same address so the cache stays coherent.
                    -- ---------------------------------------------------
                    when ST_WRITE_WAIT =>
                        if sdram_ready_s = '1' then
                            -- Update cache with written data (write-through)
                            cache_data  <= txn_data;
                            cache_addr  <= txn_addr;
                            cache_valid <= '1';
                            state       <= ST_IDLE;
                        end if;

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process fsm;

end architecture rtl;
