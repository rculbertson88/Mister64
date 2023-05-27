library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity pif is
   port 
   (
      clk1x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      pifrom_wraddress     : in std_logic_vector(8 downto 0);
      pifrom_wrdata        : in std_logic_vector(31 downto 0);
      pifrom_wren          : in std_logic;
      
      bus_addr             : in  unsigned(10 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0) := (others => '0');
      bus_done             : out std_logic := '0'
   );
end entity;

architecture arch of pif is

   signal bus_read_rom     : std_logic := '0';
   signal bus_read_ram     : std_logic := '0';
   
   signal pifrom_data      : std_logic_vector(31 downto 0) := (others => '0');
   signal pifrom_locked    : std_logic := '0';

   -- pif state machine
   type tState is
   (
      IDLE,
      WRITESTARTUP1,
      WRITESTARTUP2,
      WRITESTARTUP3,
      READCOMMAND,
      EVALWRITE,
      WRITEBACKCOMMAND,
      
      CLEARRAM,
      CLEARREADCOMMAND,
      CLEARCOMPLETE
   );
   signal state                  : tState := IDLE;
   signal startup_complete       : std_logic := '0';
   
   -- PIFRAM
   signal pifram_wren      : std_logic;
   signal pifram_busdata   : std_logic_vector(31 downto 0) := (others => '0');
   
   signal ram_address_b            : std_logic_vector(5 downto 0) := (others => '0');
   signal ram_data_b               : std_logic_vector(7 downto 0) := (others => '0');
   signal ram_wren_b               : std_logic := '0';   
   signal ram_q_b                  : std_logic_vector(7 downto 0); 
   
begin 

   ipifrom : entity work.pifrom
   port map
   (
      clk       => clk1x,
      address   => std_logic_vector(bus_addr(10 downto 2)),
      data      => pifrom_data,

      wraddress => pifrom_wraddress,
      wrdata    => pifrom_wrdata,   
      wren      => pifrom_wren     
   );
   
   pifram_wren <= '1' when (bus_write = '1' and bus_addr > 16#7C0#) else '0';
   
   iPIFRAM: entity work.dpram_dif
   generic map 
   ( 
      addr_width_a  => 4,
      data_width_a  => 32,
      addr_width_b  => 6,
      data_width_b  => 8
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => std_logic_vector(bus_addr(5 downto 2)),
      data_a      => bus_dataWrite,
      wren_a      => pifram_wren,
      q_a         => pifram_busdata,
      
      clock_b     => clk1x,
      address_b   => ram_address_b,
      data_b      => ram_data_b,
      wren_b      => ram_wren_b,
      q_b         => ram_q_b
   );
   

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (reset = '1') then
            
            bus_done          <= '0';
            bus_read_rom      <= '0';
            bus_read_ram      <= '0';
                 
            pifrom_locked     <= '0';
            
            state             <= CLEARRAM;
            startup_complete  <= '0';
            ram_address_b     <= (others => '0');
            ram_data_b        <= (others => '0');
            ram_wren_b        <= '1';
            
         elsif (ce = '1') then
         
            bus_done     <= '0';
            bus_read_rom <= '0';
            bus_read_ram <= '0';
            bus_dataRead <= (others => '0');

            if (bus_read_rom = '1') then
               bus_done <= '1';
               if (pifrom_locked = '0') then
                  bus_dataRead <= pifrom_data;
               end if;
            elsif (bus_read_ram = '1') then
               bus_done     <= '1';
               bus_dataRead <= pifram_busdata(7 downto 0) & pifram_busdata(15 downto 8) & pifram_busdata(23 downto 16) & pifram_busdata(31 downto 24);
            end if;

            -- bus read
            if (bus_read = '1') then
               if (bus_addr <= 16#7C0#) then
                  bus_read_rom <= '1';
               else
                  bus_read_ram <= '1';
               end if;
            end if;

            -- bus write
            if (bus_write = '1') then
               bus_done <= '1';
            end if;
            
            
            -- pif state machine
            ram_wren_b <= '0';
            
            case (state) is
            
               when IDLE =>
                  if (bus_write = '1') then
                     state         <= READCOMMAND;
                     ram_address_b <= 6x"3F";
                  end if;
            
               when WRITESTARTUP1 =>
                  state          <= WRITESTARTUP2;
                  ram_address_b  <= 6x"27";
                  ram_data_b     <= x"3F";
                  ram_wren_b     <= '1';               
                  
               when WRITESTARTUP2 =>
                  state          <= WRITESTARTUP3;
                  ram_address_b  <= 6x"26";
                  ram_data_b     <= x"3F"; -- seed, depends on CIC
                  ram_wren_b     <= '1';
               
               when WRITESTARTUP3 =>
                  state            <= IDLE;  
                  ram_address_b    <= 6x"25";
                  ram_data_b       <= x"00"; -- version and type, depends on CIC
                  ram_wren_b       <= '1';   
                  startup_complete <= '1';
            
               when READCOMMAND =>
                  state <= EVALWRITE;
            
               when EVALWRITE =>
                  state <= IDLE;
                  
                  if (ram_q_b(1) = '1') then -- CIC-NUS-6105 challenge/response
                     report "unimplemented PIF CIC challenge" severity failure;
                     
                  elsif (ram_q_b(2) = '1') then -- unknown
                     report "unimplemented PIF unknown command 2" severity failure;
                     
                  elsif (ram_q_b(3) = '1') then -- will lock up if not done
                     state         <= WRITEBACKCOMMAND;
                     ram_wren_b    <= '1';
                     ram_data_b    <= ram_q_b;
                     ram_data_b(3) <= '0';
                     
                  elsif (ram_q_b(4) = '1') then -- PIFROM locked
                     state         <= WRITEBACKCOMMAND;
                     ram_wren_b    <= '1';
                     ram_data_b    <= ram_q_b;
                     ram_data_b(4) <= '0';
                     pifrom_locked <= '1';
                     
                  elsif (ram_q_b(5) = '1') then -- init
                     state         <= WRITEBACKCOMMAND;
                     ram_wren_b    <= '1';
                     ram_data_b    <= ram_q_b;
                     ram_data_b(5) <= '0';
                     ram_data_b(7) <= '1';
                     
                  elsif (ram_q_b(6) = '1') then -- clear pif ram
                     state         <= CLEARRAM;
                     ram_address_b <= (others => '0');
                     ram_data_b    <= (others => '0');
                     ram_wren_b    <= '1';
                  end if;
                  
               when WRITEBACKCOMMAND =>
                  state         <= READCOMMAND;
            
               when CLEARRAM =>
                  ram_address_b <= std_logic_vector(unsigned(ram_address_b) + 1);
                  ram_wren_b    <= '1';
                  if (ram_address_b = 6x"3E") then
                     if (startup_complete = '1') then
                        state      <= CLEARREADCOMMAND;
                        ram_wren_b <= '0';
                     else
                        state <= WRITESTARTUP1;
                     end if;
                  end if;
                  
               when CLEARREADCOMMAND =>
                  state <= CLEARCOMPLETE;
               
               when CLEARCOMPLETE =>
                  state <= WRITEBACKCOMMAND;
                  ram_wren_b    <= '1';
                  ram_data_b    <= ram_q_b;
                  ram_data_b(6) <= '0';
                  
                  
            
            end case;
            

         end if;
      end if;
   end process;

end architecture;





