library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

entity tb_savestates is
   generic
   (
      SAVETYPESCOUNT    : integer := 14;
      LOADSTATE         : std_logic := '0';
      FILENAME          : string := "NONE"
   );
   port 
   (
      clk               : in  std_logic;
      reset_in          : in  std_logic;
      reset_out         : out std_logic := '0';
      loading_savestate : out std_logic := '0';
      SS_reset          : out std_logic := '0';
      SS_DataWrite      : out std_logic_vector(63 downto 0) := (others => '0');
      SS_Adr            : out unsigned(18 downto 0) := (others => '0');
      SS_wren           : out std_logic_vector(SAVETYPESCOUNT - 1 downto 0) := (others => '0')
   );
end entity;

architecture arch of tb_savestates is

   type t_data is array(0 to (2**24)-1) of integer;
   type bit_vector_file is file of bit_vector;
   signal initFromFile : std_logic := '1';
   
   signal savetype_counter : integer range 0 to SAVETYPESCOUNT;
   type tsavetype is record
      offset      : integer;
      size        : integer;
   end record;
   type t_savetypes is array(0 to SAVETYPESCOUNT - 1) of tsavetype;
   constant savetypes : t_savetypes := 
   (
      (  2048,     8),    -- AI           0 
      (  3072,     8),    -- MI           1 
      (  4096,     8),    -- PI           2 
      (  5120,     8),    -- PIF          3 
      (  6144,     8),    -- RDP          4 
      (  7168,     8),    -- RDRAMREGS    5 
      (  8192,     8),    -- RI           6 
      (  9216,     8),    -- RSP          7 
      ( 10240,     8),    -- SI           8 
      ( 11264,     8),    -- VI           9 
      ( 16384,     8),    -- CPU          10
      ( 32768,     8),    -- DMEM         11
      ( 65536,     8),    -- IMEM         12   
      (1048576,    8)     -- RAM          13
   );
   
   signal transfered : std_logic := '0';
   
begin

   process
   
      variable data           : t_data := (others => 0);
      file infile             : bit_vector_file;
      variable f_status       : FILE_OPEN_STATUS;
      variable read_byte      : std_logic_vector(7 downto 0);
      variable next_vector    : bit_vector (0 downto 0);
      variable actual_len     : natural;
      variable targetpos      : integer;
      
      -- copy from std_logic_arith, not used here because numeric std is also included
      function CONV_STD_LOGIC_VECTOR(ARG: INTEGER; SIZE: INTEGER) return STD_LOGIC_VECTOR is
        variable result: STD_LOGIC_VECTOR (SIZE-1 downto 0);
        variable temp: integer;
      begin
 
         temp := ARG;
         for i in 0 to SIZE-1 loop
 
         if (temp mod 2) = 1 then
            result(i) := '1';
         else 
            result(i) := '0';
         end if;
 
         if temp > 0 then
            temp := temp / 2;
         elsif (temp > integer'low) then
            temp := (temp - 1) / 2; -- simulate ASR
         else
            temp := temp / 2; -- simulate ASR
         end if;
        end loop;
 
        return result;  
      end;
   
   begin
      wait until rising_edge(clk);
      
      if (reset_in = '0' and transfered = '0') then
      
         SS_reset <= '1';
         wait until rising_edge(clk);
         SS_reset <= '0';
         wait until rising_edge(clk);
         
         loading_savestate <= '1';
      
         if (LOADSTATE = '1') then

            for savetype in 0 to 12 loop
               for i in 0 to (savetypes(savetype).size - 1) loop
                  SS_DataWrite( 7 downto  0) <= std_logic_vector(to_unsigned(data((savetypes(savetype).offset + i) * 8 + 0), 8));
                  SS_DataWrite(15 downto  8) <= std_logic_vector(to_unsigned(data((savetypes(savetype).offset + i) * 8 + 1), 8));
                  SS_DataWrite(23 downto 16) <= std_logic_vector(to_unsigned(data((savetypes(savetype).offset + i) * 8 + 2), 8));
                  SS_DataWrite(31 downto 24) <= std_logic_vector(to_unsigned(data((savetypes(savetype).offset + i) * 8 + 3), 8));
                  SS_DataWrite(39 downto 32) <= std_logic_vector(to_unsigned(data((savetypes(savetype).offset + i) * 8 + 4), 8));
                  SS_DataWrite(47 downto 40) <= std_logic_vector(to_unsigned(data((savetypes(savetype).offset + i) * 8 + 5), 8));
                  SS_DataWrite(55 downto 48) <= std_logic_vector(to_unsigned(data((savetypes(savetype).offset + i) * 8 + 6), 8));
                  SS_DataWrite(63 downto 56) <= std_logic_vector(to_unsigned(data((savetypes(savetype).offset + i) * 8 + 7), 8));
                  SS_wren(savetype) <= '1';
                  SS_Adr            <= to_unsigned(i, 19);
                  wait until rising_edge(clk);
                  SS_wren(savetype) <= '0';
               end loop;
            end loop;
            
         end if;
            
         transfered <= '1';
         reset_out <= '1';
         wait until rising_edge(clk);
         reset_out <= '0';
         loading_savestate <= '0';
         wait until rising_edge(clk);
      end if;

      if (initFromFile = '1' and LOADSTATE = '1') then
         initFromFile <= '0';
         file_open(f_status, infile, FILENAME, read_mode);
         targetpos := 0;
         while (not endfile(infile)) loop
            read(infile, next_vector, actual_len);  
            read_byte := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(0)), 8);
            data(targetpos) := to_integer(unsigned(read_byte));
            targetpos       := targetpos + 1;
         end loop;
         file_close(infile);
      end if;
   
   end process;
   
end architecture;


