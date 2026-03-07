---------------------------------------------------------------------------
--    IBM System/360 Model 30 – MiSTer FPGA Port
--    Top-level wrapper targeting the DE10-Nano (Cyclone V) via the
--    MiSTer framework.
--
--    Copyright 2024 – derived from LJW2030 by Lawrence Wilkinson
--    Licensed under the GNU General Public License v3 or later.
--
--    This file is the MiSTer "emu" module that sits between the MiSTer
--    sys/ framework and the IBM2030 core.  It:
--      * Forwards the 50 MHz board clock to the core unchanged.
--      * Maps the 3-bit VGA output of the core to 8-bit-per-channel
--        RGB suitable for MiSTer's video_mixer.
--      * Stubs the Spartan-3-specific hardware (SRAM, platform flash,
--        MAX7219/7318/6951 panel drivers, and expansion-port panel
--        switches) that has no direct DE10-Nano equivalent.
--      * Exposes serial I/O through the USER_IO header.
--
--    ---------------------------------------------------------------
--    IMPORTANT NOTES FOR FUTURE WORK
--    ---------------------------------------------------------------
--    Storage / SDRAM
--      The ibm2030 core uses an external SRAM interface to hold the
--      CPU's 64 KB main storage and 8 KB local storage.  On the
--      DE10-Nano this should be mapped to the on-board 32 MB SDRAM
--      via the MiSTer sdram.sv module (sys/sdram.sv).  Until that
--      adapter is written the SRAM signals below are left
--      unconnected / tied off; the core will not run correctly
--      without real storage.
--
--    Microcode / PROM loading
--      The original design loads an OS image from a Xilinx platform
--      flash after FPGA configuration.  On MiSTer the image should
--      be supplied via the HPS (Linux) side, e.g. as a .ROM file
--      selected from the OSD.  The din / reset_prom / rclk PROM
--      interface is currently tied off.
--
--    Panel switches
--      The IBM 2030 front-panel switches are scanned via a set of
--      GPIO expansion pins on the Spartan-3 board.  On MiSTer these
--      should be mapped to virtual switches in the OSD (via hps_io).
--      They are currently tied to '0' (all switches off / inactive).
--
--    Panel LEDs
--      The MAX7219/MAX7318/MAX6951 serial LED drivers used on the
--      Spartan-3 board are not present on the DE10-Nano.  The front-
--      panel indicator state is already visible on the VGA display
--      rendered by ibm2030-vga.vhd, so these drivers are not
--      required for basic operation.
--
--    OSD / HPS integration
--      This wrapper does not yet instantiate the MiSTer hps_io
--      module.  A future PR should add OSD support (reset, ROM
--      loading, switch configuration) via sys/hps_io.sv.
---------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- -----------------------------------------------------------------------
-- MiSTer emu entity
--
-- The MiSTer framework instantiates this entity from sys/sys_top.v.
-- Port names and widths must match those expected by sys_top.v exactly.
-- -----------------------------------------------------------------------
entity emu is
    port (
        -- Clock
        CLK_50M         : in  std_logic;

        -- MiSTer HPS communication bus (47 downto 0 per framework)
        HPS_BUS         : inout std_logic_vector(47 downto 0);

        -- Video output (8 bits per channel, pixel clock + enable)
        CLK_VIDEO       : out std_logic;
        CE_PIXEL        : out std_logic;
        VIDEO_ARX       : out std_logic_vector(12 downto 0);
        VIDEO_ARY       : out std_logic_vector(12 downto 0);
        VGA_R           : out std_logic_vector(7 downto 0);
        VGA_G           : out std_logic_vector(7 downto 0);
        VGA_B           : out std_logic_vector(7 downto 0);
        VGA_HS          : out std_logic;
        VGA_VS          : out std_logic;
        VGA_DE          : out std_logic;
        VGA_F1          : out std_logic;
        VGA_SL          : out std_logic_vector(1 downto 0);
        VGA_SCALER      : out std_logic;
        VGA_DISABLE     : out std_logic;
        HDMI_WIDTH      : in  std_logic_vector(11 downto 0);
        HDMI_HEIGHT     : in  std_logic_vector(11 downto 0);
        HDMI_FREEZE     : out std_logic;

        -- Audio (16-bit, signed PCM)
        AUDIO_L         : out std_logic_vector(15 downto 0);
        AUDIO_R         : out std_logic_vector(15 downto 0);
        AUDIO_S         : out std_logic;
        AUDIO_MIX       : out std_logic_vector(1 downto 0);

        -- ADC
        ADC_BUS         : inout std_logic_vector(3 downto 0);

        -- SD card passthrough
        SD_SCK          : out std_logic;
        SD_MOSI         : out std_logic;
        SD_MISO         : in  std_logic;
        SD_CS           : out std_logic;
        SD_CD           : in  std_logic;

        -- Indicators
        LED_USER        : out std_logic;
        LED_POWER       : out std_logic_vector(1 downto 0);
        LED_DISK        : out std_logic_vector(1 downto 0);

        -- Buttons
        BUTTONS         : in  std_logic_vector(1 downto 0);

        -- SDRAM (32 MB, 16-bit wide, on DE10-Nano)
        SDRAM_CLK       : out std_logic;
        SDRAM_CKE       : out std_logic;
        SDRAM_A         : out std_logic_vector(12 downto 0);
        SDRAM_BA        : out std_logic_vector(1 downto 0);
        SDRAM_DQ        : inout std_logic_vector(15 downto 0);
        SDRAM_DQML      : out std_logic;
        SDRAM_DQMH      : out std_logic;
        SDRAM_nCS       : out std_logic;
        SDRAM_nCAS      : out std_logic;
        SDRAM_nRAS      : out std_logic;
        SDRAM_nWE       : out std_logic;

        -- USER IO header (GPIO-1) – used here for serial I/O
        -- USER_IO(0) = TxD (out), USER_IO(1) = RxD (in)
        USER_IO         : inout std_logic_vector(6 downto 0);

        -- OSD status word (set by hps_io; not yet connected)
        STATUS          : in  std_logic_vector(31 downto 0);
        STATUS_IN       : out std_logic_vector(31 downto 0);
        STATUS_SET      : out std_logic;
        STATUS_MENUMASK : out std_logic_vector(15 downto 0)
    );
end emu;

architecture rtl of emu is

    -- ---------------------------------------------------------------
    -- IBM2030 component (existing top-level entity)
    -- ---------------------------------------------------------------
    component ibm2030
        port (
            -- Seven-segment displays
            ssd    : out std_logic_vector(7 downto 0);
            ssdan  : out std_logic_vector(3 downto 0);
            -- Discrete LEDs
            led    : out std_logic_vector(7 downto 0);
            -- Pushbuttons and switches
            pb     : in  std_logic_vector(3 downto 0);
            sw     : in  std_logic_vector(7 downto 0);
            -- Front panel switch scan (expansion port)
            pa_io1, pa_io2, pa_io3, pa_io4 : in  std_logic;
            pa_io5, pa_io6, pa_io7, pa_io8, pa_io9,
            pa_io10, pa_io11, pa_io12, pa_io13, pa_io14 : out std_logic;
            pa_io15, pa_io16, pa_io17, pa_io18,
            ma2_db0, ma2_db1, ma2_db2, ma2_db3,
            ma2_db4, ma2_db5 : in std_logic;
            -- VGA
            vga_r, vga_g, vga_b, vga_hs, vga_vs : out std_logic;
            -- MAX7318 I2C (panel switches)
            MAX7318_SCL : out std_logic;
            MAX7318_SDA : inout std_logic;
            -- MAX7219 SPI (panel LEDs)
            MAX7219_CLK, MAX7219_LOAD, MAX7219_DIN : out std_logic;
            -- MAX6951 (miniature panel LEDs)
            MAX6951_CLK, MAX6951_CS0, MAX6951_CS1,
            MAX6951_CS2, MAX6951_CS3, MAX6951_DIN : out std_logic;
            -- Static RAM
            sramaddr : out std_logic_vector(17 downto 0);
            srama    : inout std_logic_vector(8 downto 0);
            sramace  : out std_logic;
            sramwe   : out std_logic;
            sramoe   : out std_logic;
            sramaub  : out std_logic;
            sramalb  : out std_logic;
            -- Serial I/O (RS-232 logic levels)
            serialRx : in  std_logic;
            serialTx : out std_logic;
            -- 50 MHz clock
            clk      : in  std_logic;
            -- Configuration PROM interface
            din         : in  std_logic;
            reset_prom  : out std_logic;
            rclk        : out std_logic
        );
    end component;

    -- ---------------------------------------------------------------
    -- Internal signals
    -- ---------------------------------------------------------------

    -- 1-bit VGA signals from the core
    signal core_vga_r, core_vga_g, core_vga_b : std_logic;
    signal core_vga_hs, core_vga_vs            : std_logic;
    -- VGA_DE reconstruction: the core's vga_panel does not expose its
    -- internal blank signal through the ibm2030 entity ports.  Track
    -- the pixel position locally from the sync signals.
    signal h_count : unsigned(10 downto 0) := (others => '0');
    signal v_count : unsigned(10 downto 0) := (others => '0');
    signal hs_prev, vs_prev : std_logic := '1';
    signal vga_de_int : std_logic;

    -- Serial wires
    signal core_tx, core_rx : std_logic;

    -- Tie-off signals for unused expansion ports
    signal max7318_sda_int : std_logic;

    -- SRAM tie-offs (storage not yet connected to SDRAM)
    signal sram_addr_nc : std_logic_vector(17 downto 0);
    signal sram_data_nc : std_logic_vector(8 downto 0);
    signal sram_ce_nc, sram_we_nc, sram_oe_nc : std_logic;
    signal sram_ub_nc, sram_lb_nc             : std_logic;

    -- PROM tie-offs
    signal prom_reset_nc, prom_rclk_nc : std_logic;

    -- Misc tie-offs
    signal ssd_nc  : std_logic_vector(7 downto 0);
    signal ssdan_nc: std_logic_vector(3 downto 0);
    signal led_nc  : std_logic_vector(7 downto 0);
    signal max_nc  : std_logic;

begin

    -- ---------------------------------------------------------------
    -- Instantiate the IBM2030 core
    -- ---------------------------------------------------------------
    core : ibm2030
        port map (
            -- 7-segment and LED outputs (not connected to DE10-Nano)
            ssd    => ssd_nc,
            ssdan  => ssdan_nc,
            led    => led_nc,

            -- DE10-Nano KEY[1:0] → pushbuttons; SW[7:0] → slide switches
            -- KEY is active-low; invert so '1' = pressed matches original
            pb     => not BUTTONS & "00",
            sw     => STATUS(7 downto 0),

            -- Panel switch scan inputs / outputs – all deasserted
            pa_io1  => '0', pa_io2  => '0',
            pa_io3  => '0', pa_io4  => '0',
            pa_io15 => '0', pa_io16 => '0',
            pa_io17 => '0', pa_io18 => '0',
            ma2_db0 => '0', ma2_db1 => '0',
            ma2_db2 => '0', ma2_db3 => '0',
            ma2_db4 => '0', ma2_db5 => '0',
            -- Scan outputs are ignored
            pa_io5  => open, pa_io6  => open,
            pa_io7  => open, pa_io8  => open,
            pa_io9  => open, pa_io10 => open,
            pa_io11 => open, pa_io12 => open,
            pa_io13 => open, pa_io14 => open,

            -- VGA → captured internally, then expanded to 8-bit
            vga_r  => core_vga_r,
            vga_g  => core_vga_g,
            vga_b  => core_vga_b,
            vga_hs => core_vga_hs,
            vga_vs => core_vga_vs,

            -- MAX7318 I2C (panel switches) – not used
            MAX7318_SCL => open,
            MAX7318_SDA => max7318_sda_int,

            -- MAX7219 SPI (panel LEDs) – not used
            MAX7219_CLK  => open,
            MAX7219_LOAD => open,
            MAX7219_DIN  => open,

            -- MAX6951 (miniature panel) – not used
            MAX6951_CLK => open, MAX6951_CS0 => open,
            MAX6951_CS1 => open, MAX6951_CS2 => open,
            MAX6951_CS3 => open, MAX6951_DIN => open,

            -- SRAM – not yet connected; tie data bus to '0'
            -- TODO: replace with SDRAM adapter (see header notes)
            sramaddr => sram_addr_nc,
            srama    => sram_data_nc,
            sramace  => sram_ce_nc,
            sramwe   => sram_we_nc,
            sramoe   => sram_oe_nc,
            sramaub  => sram_ub_nc,
            sramalb  => sram_lb_nc,

            -- Serial I/O via USER_IO header pin 0 (TX) and pin 1 (RX)
            serialRx => core_rx,
            serialTx => core_tx,

            -- 50 MHz clock from DE10-Nano
            clk => CLK_50M,

            -- PROM – not connected; microcode loading is a future TODO
            din        => '1',
            reset_prom => prom_reset_nc,
            rclk       => prom_rclk_nc
        );

    -- ---------------------------------------------------------------
    -- USER_IO serial passthrough
    -- USER_IO(0) = TxD output to host; USER_IO(1) = RxD input from host
    -- ---------------------------------------------------------------
    USER_IO(0) <= core_tx;
    core_rx    <= USER_IO(1);
    USER_IO(6 downto 2) <= (others => 'Z');

    -- ---------------------------------------------------------------
    -- SDRAM: safe defaults (not actively used yet)
    -- ---------------------------------------------------------------
    SDRAM_CLK  <= '0';
    SDRAM_CKE  <= '0';
    SDRAM_A    <= (others => '0');
    SDRAM_BA   <= (others => '0');
    SDRAM_DQ   <= (others => 'Z');
    SDRAM_DQML <= '1';
    SDRAM_DQMH <= '1';
    SDRAM_nCS  <= '1';
    SDRAM_nCAS <= '1';
    SDRAM_nRAS <= '1';
    SDRAM_nWE  <= '1';

    -- ---------------------------------------------------------------
    -- Video
    --
    -- The IBM2030 core generates standard 640×480 @ 60 Hz VGA with
    -- 1-bit per colour channel.  Expand each bit to fill all 8
    -- output bits (0xFF when asserted, 0x00 when not) so the MiSTer
    -- framework receives full-range RGB.
    --
    -- CLK_VIDEO and CE_PIXEL: the core uses 25 MHz for pixel output
    -- (50 MHz input divided by 2 inside vga_controller_640_60).
    -- We expose the 50 MHz master clock and assert CE_PIXEL every
    -- other cycle to approximate a 25 MHz pixel clock.
    -- ---------------------------------------------------------------
    CLK_VIDEO <= CLK_50M;

    ce_pixel_proc: process(CLK_50M)
        variable toggle : std_logic := '0';
    begin
        if rising_edge(CLK_50M) then
            toggle   := not toggle;
            CE_PIXEL <= toggle;
        end if;
    end process;

    -- Expand 1-bit colour to 8-bit: '1' → 0xFF, '0' → 0x00
    VGA_R  <= (others => core_vga_r);
    VGA_G  <= (others => core_vga_g);
    VGA_B  <= (others => core_vga_b);
    VGA_HS <= core_vga_hs;
    VGA_VS <= core_vga_vs;
    -- Reconstruct VGA_DE from sync edges.
    -- 640×480 @ 60 Hz timing (25 MHz pixel clock):
    --   Horizontal: 640 visible, front porch 16, sync 96, back porch 48 → total 800
    --   Vertical:   480 visible, front porch 10, sync 2,  back porch 33 → total 525
    -- We count pixels using CE_PIXEL (25 MHz) and detect sync falling edges.
    -- Visible window: h_count in [0, 639] and v_count in [0, 479].
    de_gen: process(CLK_50M)
    begin
        if rising_edge(CLK_50M) then
            hs_prev <= core_vga_hs;
            vs_prev <= core_vga_vs;
            if CE_PIXEL = '1' then
                -- Detect falling edge of HS (end of visible / start of blanking)
                if hs_prev = '1' and core_vga_hs = '0' then
                    h_count <= to_unsigned(640 + 16, 11); -- start of sync
                elsif h_count = to_unsigned(799, 11) then
                    h_count <= (others => '0');
                else
                    h_count <= h_count + 1;
                end if;
                -- Detect falling edge of VS
                if vs_prev = '1' and core_vga_vs = '0' then
                    v_count <= to_unsigned(480 + 10, 11); -- start of sync
                elsif h_count = to_unsigned(799, 11) then
                    if v_count = to_unsigned(524, 11) then
                        v_count <= (others => '0');
                    else
                        v_count <= v_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    vga_de_int <= '1' when (h_count < to_unsigned(640, 11)) and
                            (v_count < to_unsigned(480, 11)) else '0';
    VGA_DE      <= vga_de_int;
    VGA_F1      <= '0';
    VGA_SL      <= "00";
    VGA_SCALER  <= '0';
    VGA_DISABLE <= '0';
    HDMI_FREEZE <= '0';

    -- 4:3 aspect ratio (640×480)
    VIDEO_ARX <= std_logic_vector(to_unsigned(4, 13));
    VIDEO_ARY <= std_logic_vector(to_unsigned(3, 13));

    -- ---------------------------------------------------------------
    -- Audio – no audio output in IBM2030 core
    -- ---------------------------------------------------------------
    AUDIO_L   <= (others => '0');
    AUDIO_R   <= (others => '0');
    AUDIO_S   <= '0';
    AUDIO_MIX <= "00";

    -- ---------------------------------------------------------------
    -- LEDs
    -- ---------------------------------------------------------------
    LED_USER    <= '0';
    LED_POWER   <= "00";
    LED_DISK    <= "00";

    -- ---------------------------------------------------------------
    -- SD card – not used
    -- ---------------------------------------------------------------
    SD_SCK  <= '0';
    SD_MOSI <= '0';
    SD_CS   <= '1';

    -- ---------------------------------------------------------------
    -- ADC
    -- ---------------------------------------------------------------
    ADC_BUS <= (others => 'Z');

    -- ---------------------------------------------------------------
    -- HPS status bus defaults
    -- ---------------------------------------------------------------
    STATUS_IN       <= (others => '0');
    STATUS_SET      <= '0';
    STATUS_MENUMASK <= (others => '0');
    HPS_BUS         <= (others => 'Z');

end rtl;
