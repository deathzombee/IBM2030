--*****************************************************************************************
--**
--**  Disclaimer: LIMITED WARRANTY AND DISCLAMER. These designs are 
--**              provided to you "as is". Xilinx and its licensors make and you 
--**              receive no warranties or conditions, express, implied, statutory 
--**              or otherwise, and Xilinx specifically disclaims any implied 
--**              warranties of merchantability, non-infringement, or fitness for a 
--**              particular purpose. Xilinx does not warrant that the functions 
--**              contained in these designs will meet your requirements, or that the
--**              operation of these designs will be uninterrupted or error free, or 
--**              that defects in the Designs will be corrected. Furthermore, Xilinx 
--**              does not warrant or make any representations regarding use or the 
--**              results of the use of the designs in terms of correctness, accuracy, 
--**              reliability, or otherwise. 
--**
--**              LIMITATION OF LIABILITY. In no event will Xilinx or its licensors be 
--**              liable for any loss of data, lost profits, cost or procurement of 
--**              substitute goods or services, or for any special, incidental, 
--**              consequential, or indirect damages arising from the use or operation 
--**              of the designs or accompanying documentation, however caused and on 
--**              any theory of liability. This limitation will apply even if Xilinx 
--**              has been advised of the possibility of such damage. This limitation 
--**              shall apply not-withstanding the failure of the essential purpose of 
--**              any limited remedies herein. 
--**
--*****************************************************************************************
--	MODULE  : shift_compare_serial.vhd
--	AUTHOR  : Stephan Neuhold
--	VERSION : v1.00
--
--
--	REVISION HISTORY:
--	-----------------
--	No revisions
--
--
--	FUNCTION DESCRIPTION:
--	---------------------
--	This module provides the shifting in of data
--	and comparing that data to the synchronisation
--	pattern. Once the synchronisation pattern has
--	been found, the last eight bits of data
--	shifted in are presented.
--	
--	The shift register and comparator are
--	automatically scaled to the correct length
--	using the "length" generic.


--***************************
--*	Library declarations
--***************************
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- Note: library UNISIM removed for MiSTer/Altera portability.
-- Xilinx FDRE, LUT2 and MUXCY primitives replaced with behavioral VHDL.


--***********************
--*	Entity declaration
--***********************
entity shift_compare_serial is
	generic(
		length : integer := 5
		);
	port(
		clock : in std_logic;
		reset : in std_logic;
		enable : in std_logic;
		din : in std_logic;
		b : in std_logic_vector((2**length) - 1 downto 0);
		eq : out std_logic;
		din_shifted : out std_logic_vector(7 downto 0)
		);
end shift_compare_serial;


architecture Behavioral of shift_compare_serial is


signal a : std_logic_vector((2**length) - 1 downto 0);
signal b_swapped : std_logic_vector((2**length) - 1 downto 0);


begin


--***************************************************
--*	This process swaps the bits in the data byte.
--*	This is done to present the data in the format
--*	that it is entered in the PROM file.
--***************************************************
process (clock, a)
begin
	for i in 0 to 7 loop
		din_shifted(i) <= a(((2**length) - 1) - i);
	end loop;
end process;


--*******************************************************
--*	This process swaps the bits of every byte of the
--*	synchronisation pattern. This is done so that
--*	data read in from the PROM can be directly
--*	compared. Data from the PROM is read with all
--*	bits of every byte swapped.
--*	e.g.
--*	If the data in the PROM is 28h then this is read in
--*	the following way:
--*	00010100
--*******************************************************
process (clock, b)
begin
	for i in 0 to (((2**length) / 8) - 1) loop
		for j in 0 to 7 loop
			b_swapped((8 * i) + j) <= b(7 + (8 * i) - j);
		end loop;
	end loop;
end process;


--***********************************************
--*	Shift register and XNOR comparator.
--*	Replaces Xilinx FDRE / LUT2 / MUXCY primitives
--*	with portable behavioral VHDL.
--*
--*	Shift register: serial data enters at a(0) and
--*	shifts toward a(2**length - 1) each clock cycle
--*	when enable is asserted; reset drives all to '0'.
--*
--*	Comparator: eq is '1' only when every bit of the
--*	shift register matches the (byte-swapped) sync
--*	pattern b_swapped.
--***********************************************

process(clock)
begin
	if rising_edge(clock) then
		if reset = '1' then
			a <= (others => '0');
		elsif enable = '1' then
			a(0) <= din;
			for i in 1 to (2**length) - 1 loop
				a(i) <= a(i - 1);
			end loop;
		end if;
	end if;
end process;

process(a, b_swapped)
	variable match : std_logic;
begin
	match := '1';
	for i in 0 to (2**length) - 1 loop
		if a(i) /= b_swapped(i) then
			match := '0';
		end if;
	end loop;
	eq <= match;
end process;

end Behavioral;
