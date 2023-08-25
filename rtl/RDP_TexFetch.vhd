library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;

entity RDP_TexFetch is
   port 
   (
      clk1x                : in  std_logic;
      trigger              : in  std_logic;
         
      error_texMode        : out std_logic;       
         
      settings_otherModes  : in  tsettings_otherModes;
      settings_tile        : in  tsettings_tile;
      index_S              : in  unsigned(9 downto 0);
      index_S1             : in  unsigned(9 downto 0);
      index_S2             : in  unsigned(9 downto 0);
      index_S3             : in  unsigned(9 downto 0);
      index_T              : in  unsigned(9 downto 0);
            
      tex_addr             : out tTextureRamAddr;
      tex_data             : in  tTextureRamData;
      
      -- synthesis translate_off
      export_TextureAddr   : out unsigned(11 downto 0);
      export_TexFt_addr    : out unsigned(31 downto 0);
      export_TexFt_data    : out unsigned(31 downto 0);
      export_TexFt_db1     : out unsigned(31 downto 0);
      export_TexFt_db3     : out unsigned(31 downto 0);
      -- synthesis translate_on
      
      tex_color            : out tcolor3_u8;
      tex_alpha            : out unsigned(7 downto 0);
      tex_copy             : out unsigned(63 downto 0)
   );
end entity;

architecture arch of RDP_TexFetch is

   -- first cycle
   signal addr_base              : unsigned(11 downto 0);
      
   signal dataSelect_next4HL     : unsigned(1 downto 0);
   signal dataSelect_next8HL     : std_logic;
   signal dataSelect_next16      : integer range 0 to 7;
   signal dataSelect_next32      : integer range 0 to 3;
   signal dataSelect4HL          : unsigned(1 downto 0) := (others => '0');
   signal dataSelect8HL          : std_logic := '0';
   signal dataSelect16           : integer range 0 to 7 := 0;
   signal dataSelect32           : integer range 0 to 3 := 0;
      
   signal dataMuxed16            : unsigned(15 downto 0);
   signal dataMuxed32            : unsigned(31 downto 0);
   signal dataMuxed4             : unsigned(3 downto 0);
   signal dataMuxed8             : unsigned(7 downto 0);
   
   signal copySelect0next        : unsigned(2 downto 0);
   signal copySelect1next        : unsigned(2 downto 0);
   signal copySelect2next        : unsigned(2 downto 0);
   signal copySelect3next        : unsigned(2 downto 0);
   signal copySelect0            : integer range 0 to 7 := 0;
   signal copySelect1            : integer range 0 to 7 := 0;
   signal copySelect2            : integer range 0 to 7 := 0;
   signal copySelect3            : integer range 0 to 7 := 0;
   
   signal copyPal4Index0Next     : unsigned(1 downto 0);
   signal copyPal4Index1Next     : unsigned(1 downto 0);
   signal copyPal4Index2Next     : unsigned(1 downto 0);
   signal copyPal4Index3Next     : unsigned(1 downto 0);
   signal copyPal8Index0Next     : std_logic;
   signal copyPal8Index1Next     : std_logic;
   signal copyPal8Index2Next     : std_logic;
   signal copyPal8Index3Next     : std_logic;
   
   signal copyPal4Index0         : unsigned(1 downto 0) := (others => '0');
   signal copyPal4Index1         : unsigned(1 downto 0) := (others => '0');
   signal copyPal4Index2         : unsigned(1 downto 0) := (others => '0');
   signal copyPal4Index3         : unsigned(1 downto 0) := (others => '0');
   signal copyPal8Index0         : std_logic := '0';
   signal copyPal8Index1         : std_logic := '0';
   signal copyPal8Index2         : std_logic := '0';
   signal copyPal8Index3         : std_logic := '0';
   
   signal tex_copy_in0           : unsigned(15 downto 0);
   signal tex_copy_in1           : unsigned(15 downto 0);
   signal tex_copy_in2           : unsigned(15 downto 0);
   signal tex_copy_in3           : unsigned(15 downto 0);
   
   signal tex_copy_4mux0         : unsigned(3 downto 0);
   signal tex_copy_4mux1         : unsigned(3 downto 0);
   signal tex_copy_4mux2         : unsigned(3 downto 0);
   signal tex_copy_4mux3         : unsigned(3 downto 0);
   signal tex_copy_8mux0         : unsigned(7 downto 0);
   signal tex_copy_8mux1         : unsigned(7 downto 0);
   signal tex_copy_8mux2         : unsigned(7 downto 0);
   signal tex_copy_8mux3         : unsigned(7 downto 0);
  
   -- synthesis translate_off
   signal addr_base_1            : unsigned(11 downto 0) := (others => '0');
   -- synthesis translate_on
  
   -- second cycle
   signal tex_color_read         : tcolor3_u8 := (others => (others => '0'));
   signal tex_alpha_read         : unsigned(7 downto 0) := (others => '0');
   
   signal tex_copy_read          : unsigned(63 downto 0) := (others => '0');
   
   -- synthesis translate_off
   signal exportNext_TexFt_addr  : unsigned(31 downto 0) := (others => '0');
   signal exportNext_TexFt_data  : unsigned(31 downto 0) := (others => '0');
   signal exportNext_TexFt_db1   : unsigned(31 downto 0) := (others => '0');
   signal exportNext_TexFt_db3   : unsigned(31 downto 0) := (others => '0');
   -- synthesis translate_on
  
   -- third cycle
   signal paletteMuxed16         : unsigned(15 downto 0);
  
begin 

   addr_base <= to_unsigned(to_integer(settings_tile.Tile_TmemAddr) + (to_integer(index_T) * to_integer(settings_tile.Tile_line)), 12);

   -- address select
   process (all)
      variable addr_calc  : unsigned(11 downto 0);
      variable addr_calc0 : unsigned(12 downto 0);
      variable addr_calc1 : unsigned(12 downto 0);
      variable addr_calc2 : unsigned(12 downto 0);
      variable addr_calc3 : unsigned(12 downto 0);
   begin
   
      addr_calc            := (others => '0');
      addr_calc0           := (others => '0');
      addr_calc1           := (others => '0');
      addr_calc2           := (others => '0');
      addr_calc3           := (others => '0');
            
      tex_addr             <= (others => (others => '0'));
      copySelect0next      <= (others => '0');
      copySelect1next      <= (others => '0');
      copySelect2next      <= (others => '0');
      copySelect3next      <= (others => '0');
      
      if (settings_otherModes.cycleType = "10") then
   
         if (settings_tile.Tile_size = SIZE_8BIT or settings_tile.Tile_format = FORMAT_YUV) then
            addr_calc0 := "00" & index_S  & '0';
            addr_calc1 := "00" & index_S1 & '0';
            addr_calc2 := "00" & index_S2 & '0';
            addr_calc3 := "00" & index_S3 & '0';
         elsif (settings_tile.Tile_size = SIZE_16BIT or settings_tile.Tile_size = SIZE_32BIT) then
            addr_calc0 := "0" & index_S  & "00";
            addr_calc1 := "0" & index_S1 & "00";
            addr_calc2 := "0" & index_S2 & "00";
            addr_calc3 := "0" & index_S3 & "00";
         else
            addr_calc0 := "000" & index_S;
            addr_calc1 := "000" & index_S1;
            addr_calc2 := "000" & index_S2;
            addr_calc3 := "000" & index_S3;
         end if;
         
         addr_calc0 := addr_calc0 + (addr_base(8 downto 0) & "0000");
         addr_calc1 := addr_calc1 + (addr_base(8 downto 0) & "0000");
         addr_calc2 := addr_calc2 + (addr_base(8 downto 0) & "0000");
         addr_calc3 := addr_calc3 + (addr_base(8 downto 0) & "0000");
         
         -- todo: special handling for YUV
         
         if (index_T(0) = '1') then
            addr_calc0(3) := not addr_calc0(3);
            addr_calc1(3) := not addr_calc1(3);
            addr_calc2(3) := not addr_calc2(3);
            addr_calc3(3) := not addr_calc3(3);
         end if;
         
         copySelect0next <= addr_calc0(12) & addr_calc0(3) & (not addr_calc0(2));
         copySelect1next <= addr_calc0(12) & addr_calc1(3) & (not addr_calc1(2));
         copySelect2next <= addr_calc0(12) & addr_calc2(3) & (not addr_calc2(2));
         copySelect3next <= addr_calc0(12) & addr_calc3(3) & (not addr_calc3(2));
         
         if    (copySelect0next(1 downto 0) = "00") then tex_addr(0) <= std_logic_vector(addr_calc0(11 downto 4)); tex_addr(4) <= std_logic_vector(addr_calc0(11 downto 4)); 
         elsif (copySelect1next(1 downto 0) = "00") then tex_addr(0) <= std_logic_vector(addr_calc1(11 downto 4)); tex_addr(4) <= std_logic_vector(addr_calc1(11 downto 4)); 
         elsif (copySelect2next(1 downto 0) = "00") then tex_addr(0) <= std_logic_vector(addr_calc2(11 downto 4)); tex_addr(4) <= std_logic_vector(addr_calc2(11 downto 4)); 
         elsif (copySelect3next(1 downto 0) = "00") then tex_addr(0) <= std_logic_vector(addr_calc3(11 downto 4)); tex_addr(4) <= std_logic_vector(addr_calc3(11 downto 4));
         else tex_addr(0) <= (others => '0'); tex_addr(4) <= (others => '0'); end if;
         
         if    (copySelect0next(1 downto 0) = "01") then tex_addr(1) <= std_logic_vector(addr_calc0(11 downto 4)); tex_addr(5) <= std_logic_vector(addr_calc0(11 downto 4)); 
         elsif (copySelect1next(1 downto 0) = "01") then tex_addr(1) <= std_logic_vector(addr_calc1(11 downto 4)); tex_addr(5) <= std_logic_vector(addr_calc1(11 downto 4)); 
         elsif (copySelect2next(1 downto 0) = "01") then tex_addr(1) <= std_logic_vector(addr_calc2(11 downto 4)); tex_addr(5) <= std_logic_vector(addr_calc2(11 downto 4)); 
         elsif (copySelect3next(1 downto 0) = "01") then tex_addr(1) <= std_logic_vector(addr_calc3(11 downto 4)); tex_addr(5) <= std_logic_vector(addr_calc3(11 downto 4));
         else tex_addr(1) <= (others => '0'); tex_addr(5) <= (others => '0'); end if;
         
         if    (copySelect0next(1 downto 0) = "10") then tex_addr(2) <= std_logic_vector(addr_calc0(11 downto 4)); tex_addr(6) <= std_logic_vector(addr_calc0(11 downto 4)); 
         elsif (copySelect1next(1 downto 0) = "10") then tex_addr(2) <= std_logic_vector(addr_calc1(11 downto 4)); tex_addr(6) <= std_logic_vector(addr_calc1(11 downto 4)); 
         elsif (copySelect2next(1 downto 0) = "10") then tex_addr(2) <= std_logic_vector(addr_calc2(11 downto 4)); tex_addr(6) <= std_logic_vector(addr_calc2(11 downto 4)); 
         elsif (copySelect3next(1 downto 0) = "10") then tex_addr(2) <= std_logic_vector(addr_calc3(11 downto 4)); tex_addr(6) <= std_logic_vector(addr_calc3(11 downto 4));
         else tex_addr(2) <= (others => '0'); tex_addr(6) <= (others => '0'); end if;
         
         if    (copySelect0next(1 downto 0) = "11") then tex_addr(3) <= std_logic_vector(addr_calc0(11 downto 4)); tex_addr(7) <= std_logic_vector(addr_calc0(11 downto 4)); 
         elsif (copySelect1next(1 downto 0) = "11") then tex_addr(3) <= std_logic_vector(addr_calc1(11 downto 4)); tex_addr(7) <= std_logic_vector(addr_calc1(11 downto 4)); 
         elsif (copySelect2next(1 downto 0) = "11") then tex_addr(3) <= std_logic_vector(addr_calc2(11 downto 4)); tex_addr(7) <= std_logic_vector(addr_calc2(11 downto 4)); 
         elsif (copySelect3next(1 downto 0) = "11") then tex_addr(3) <= std_logic_vector(addr_calc3(11 downto 4)); tex_addr(7) <= std_logic_vector(addr_calc3(11 downto 4));
         else tex_addr(3) <= (others => '0'); tex_addr(7) <= (others => '0'); end if;
   
         if (settings_otherModes.enTlut = '1') then
            case (settings_tile.Tile_size) is
               when SIZE_4BIT =>
                  tex_addr(4) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(tex_copy_4mux0);
                  tex_addr(5) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(tex_copy_4mux1);
                  tex_addr(6) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(tex_copy_4mux2);
                  tex_addr(7) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(tex_copy_4mux3);
                  
               when SIZE_8BIT =>
                  tex_addr(4) <= std_logic_vector(tex_copy_8mux0);
                  tex_addr(5) <= std_logic_vector(tex_copy_8mux1);
                  tex_addr(6) <= std_logic_vector(tex_copy_8mux2);
                  tex_addr(7) <= std_logic_vector(tex_copy_8mux3);
                  
               when SIZE_16BIT =>
                  tex_addr(4) <= std_logic_vector(tex_copy_in0(15 downto 8));
                  tex_addr(5) <= std_logic_vector(tex_copy_in1(15 downto 8));
                  tex_addr(6) <= std_logic_vector(tex_copy_in2(15 downto 8));
                  tex_addr(7) <= std_logic_vector(tex_copy_in3(15 downto 8));
   
               when SIZE_32BIT =>
                  tex_addr(4) <= std_logic_vector(tex_copy_in0(15 downto 8));
                  tex_addr(5) <= std_logic_vector(tex_copy_in1(15 downto 8));
                  tex_addr(6) <= std_logic_vector(tex_copy_in2(15 downto 8));
                  tex_addr(7) <= std_logic_vector(tex_copy_in3(15 downto 8));
                  copySelect0next(2) <= '0';
                  copySelect1next(2) <= '0';
                  copySelect2next(2) <= '0';
                  copySelect3next(2) <= '0';
                  
               when others => null;
            end case;
         end if;
         
      else
      
         case (settings_tile.Tile_size) is
            
            when SIZE_4BIT =>
               addr_calc := (addr_base(8 downto 0) & "000") + index_S(9 downto 1);
               if (index_T(0) = '1') then
                  addr_calc(2 downto 0) := not addr_calc(2 downto 0);
               else
                  addr_calc(1 downto 0) := not addr_calc(1 downto 0);
               end if;
               
               case (settings_tile.Tile_format) is
                  when FORMAT_RGBA => null;
                  when FORMAT_YUV => null;
                  when FORMAT_CI => null;
                  when FORMAT_IA => null;
                  when FORMAT_I => null;
                  when others => null;
               end case;
            
            when SIZE_8BIT =>
               addr_calc := (addr_base(8 downto 0) & "000") + index_S;
               if (index_T(0) = '1') then
                  addr_calc(2 downto 0) := not addr_calc(2 downto 0);
               else
                  addr_calc(1 downto 0) := not addr_calc(1 downto 0);
               end if;
            
               case (settings_tile.Tile_format) is
                  when FORMAT_RGBA => null;
                  when FORMAT_YUV => null;
                  when FORMAT_CI => null;
                  when FORMAT_IA => null;
                  when FORMAT_I => null;
                  when others => null;
               end case;
            
            when SIZE_16BIT =>
               addr_calc := (addr_base(8 downto 0) & "000") + (index_S & '0');
               if (index_T(0) = '1') then
                  addr_calc(2 downto 1) := not addr_calc(2 downto 1);
               else
                  addr_calc(1) := not addr_calc(1);
               end if;
               
               case (settings_tile.Tile_format) is
                  when FORMAT_RGBA => null;
                  when FORMAT_YUV => null;
                  when FORMAT_CI => null;
                  when FORMAT_IA => null;
                  when FORMAT_I => null;
                  when others => null;
               end case;
            
            when SIZE_32BIT =>
               addr_calc := (addr_base(8 downto 0) & "000") + (index_S & '0');
               if (index_T(0) = '1') then
                  addr_calc(2 downto 1) := not addr_calc(2 downto 1);
               else
                  addr_calc(1) := not addr_calc(1);
               end if;
            
               case (settings_tile.Tile_format) is
                  when FORMAT_RGBA =>
                  when FORMAT_YUV => null;
                  when FORMAT_CI => null;
                  when FORMAT_IA => null;
                  when FORMAT_I => null;
                  when others => null;
               end case;
            
            when others => null;
         end case;
         
         tex_addr(0) <= std_logic_vector(addr_calc(10 downto 3));
         tex_addr(1) <= std_logic_vector(addr_calc(10 downto 3));
         tex_addr(2) <= std_logic_vector(addr_calc(10 downto 3));
         tex_addr(3) <= std_logic_vector(addr_calc(10 downto 3));
         tex_addr(4) <= std_logic_vector(addr_calc(10 downto 3));
         tex_addr(5) <= std_logic_vector(addr_calc(10 downto 3));
         tex_addr(6) <= std_logic_vector(addr_calc(10 downto 3));
         tex_addr(7) <= std_logic_vector(addr_calc(10 downto 3));
      
         -- synthesis translate_off
         export_TextureAddr <= addr_calc;
         -- synthesis translate_on
         
         if (settings_otherModes.enTlut = '1') then
            case (settings_tile.Tile_size) is
               when SIZE_4BIT =>
                  tex_addr(4) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(dataMuxed4);
                  tex_addr(5) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(dataMuxed4);
                  tex_addr(6) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(dataMuxed4);
                  tex_addr(7) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(dataMuxed4);
                  
               when SIZE_8BIT =>
                  tex_addr(4) <= std_logic_vector(dataMuxed8);
                  tex_addr(5) <= std_logic_vector(dataMuxed8);
                  tex_addr(6) <= std_logic_vector(dataMuxed8);
                  tex_addr(7) <= std_logic_vector(dataMuxed8);
                  
               when SIZE_16BIT =>
                  tex_addr(4) <= std_logic_vector(dataMuxed16(15 downto 8));
                  tex_addr(5) <= std_logic_vector(dataMuxed16(15 downto 8));
                  tex_addr(6) <= std_logic_vector(dataMuxed16(15 downto 8));
                  tex_addr(7) <= std_logic_vector(dataMuxed16(15 downto 8));
   
               when SIZE_32BIT =>
                  tex_addr(4) <= std_logic_vector(dataMuxed32(31 downto 24));
                  tex_addr(5) <= std_logic_vector(dataMuxed32(31 downto 24));
                  tex_addr(6) <= std_logic_vector(dataMuxed32(31 downto 24));
                  tex_addr(7) <= std_logic_vector(dataMuxed32(31 downto 24));
                  
               when others => null;
            end case;
         end if;
         
      end if;
      
      dataSelect_next4HL   <= addr_calc(0) & (not index_S(0));
      dataSelect_next8HL   <= addr_calc(0);
      dataSelect_next32    <= to_integer(addr_calc(2 downto 1));
      
      if (settings_otherModes.enTlut = '1') then
         dataSelect_next16    <= to_integer(addr_calc(2 downto 1));
      else
         dataSelect_next16    <= to_integer(addr_calc(11) & addr_calc(2 downto 1));
      end if;
      
      copyPal4Index0Next   <= not addr_calc0(1 downto 0);
      copyPal4Index1Next   <= not addr_calc1(1 downto 0);
      copyPal4Index2Next   <= not addr_calc2(1 downto 0);
      copyPal4Index3Next   <= not addr_calc3(1 downto 0);
      copyPal8Index0Next   <= not addr_calc0(1);
      copyPal8Index1Next   <= not addr_calc1(1);
      copyPal8Index2Next   <= not addr_calc2(1);
      copyPal8Index3Next   <= not addr_calc3(1);
      
   end process;
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then

         if (trigger = '1') then
            
            dataSelect4HL  <= dataSelect_next4HL;
            dataSelect8HL  <= dataSelect_next8HL;
            dataSelect16   <= dataSelect_next16;
            dataSelect32   <= dataSelect_next32;
            
            copySelect0 <= to_integer(copySelect0next);
            copySelect1 <= to_integer(copySelect1next);
            copySelect2 <= to_integer(copySelect2next);
            copySelect3 <= to_integer(copySelect3next);
            
            copyPal4Index0 <= copyPal4Index0Next;
            copyPal4Index1 <= copyPal4Index1Next;
            copyPal4Index2 <= copyPal4Index2Next;
            copyPal4Index3 <= copyPal4Index3Next;
            
            copyPal8Index0 <= copyPal8Index0Next;
            copyPal8Index1 <= copyPal8Index1Next;
            copyPal8Index2 <= copyPal8Index2Next;
            copyPal8Index3 <= copyPal8Index3Next;
            
            -- synthesis translate_off
            addr_base_1 <= addr_base;
            -- synthesis translate_on
            
         end if;
      
      end if;
   end process;
   
   -- data select
   dataMuxed16 <= unsigned(tex_data(dataSelect16));
   dataMuxed32 <= unsigned(tex_data(dataSelect32)) & unsigned(tex_data(dataSelect32 + 4));  
   
   dataMuxed4  <= dataMuxed16( 3 downto  0) when (dataSelect4HL = "00") else
                  dataMuxed16( 7 downto  4) when (dataSelect4HL = "01") else
                  dataMuxed16(11 downto  8) when (dataSelect4HL = "10") else
                  dataMuxed16(15 downto 12);
   
   dataMuxed8  <= dataMuxed16(15 downto 8) when (dataSelect8HL = '1') else dataMuxed16(7 downto 0);
   
   tex_copy_in0 <= unsigned(tex_data(copySelect0));
   tex_copy_in1 <= unsigned(tex_data(copySelect1));
   tex_copy_in2 <= unsigned(tex_data(copySelect2));
   tex_copy_in3 <= unsigned(tex_data(copySelect3));
   
   tex_copy_4mux0 <= tex_copy_in0( 3 downto  0) when (copyPal4Index0 = "00") else
                     tex_copy_in0( 7 downto  4) when (copyPal4Index0 = "01") else
                     tex_copy_in0(11 downto  8) when (copyPal4Index0 = "10") else
                     tex_copy_in0(15 downto 12);
                     
   tex_copy_4mux1 <= tex_copy_in1( 3 downto  0) when (copyPal4Index1 = "00") else
                     tex_copy_in1( 7 downto  4) when (copyPal4Index1 = "01") else
                     tex_copy_in1(11 downto  8) when (copyPal4Index1 = "10") else
                     tex_copy_in1(15 downto 12);
                     
   tex_copy_4mux2 <= tex_copy_in2( 3 downto  0) when (copyPal4Index2 = "00") else
                     tex_copy_in2( 7 downto  4) when (copyPal4Index2 = "01") else
                     tex_copy_in2(11 downto  8) when (copyPal4Index2 = "10") else
                     tex_copy_in2(15 downto 12);
                     
   tex_copy_4mux3 <= tex_copy_in3( 3 downto  0) when (copyPal4Index3 = "00") else
                     tex_copy_in3( 7 downto  4) when (copyPal4Index3 = "01") else
                     tex_copy_in3(11 downto  8) when (copyPal4Index3 = "10") else
                     tex_copy_in3(15 downto 12);
   
   tex_copy_8mux0 <= tex_copy_in0(15 downto 8) when (copyPal8Index0 = '1') else tex_copy_in0(7 downto 0);
   tex_copy_8mux1 <= tex_copy_in1(15 downto 8) when (copyPal8Index1 = '1') else tex_copy_in1(7 downto 0); 
   tex_copy_8mux2 <= tex_copy_in2(15 downto 8) when (copyPal8Index2 = '1') else tex_copy_in2(7 downto 0); 
   tex_copy_8mux3 <= tex_copy_in3(15 downto 8) when (copyPal8Index3 = '1') else tex_copy_in3(7 downto 0); 
   
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
   
         error_texMode <= '0';
   
         if (trigger = '1') then
         
            tex_color_read(0) <= (others => '0');
            tex_color_read(1) <= (others => '0');
            tex_color_read(2) <= (others => '0');
            tex_alpha_read    <= (others => '0');
            
            tex_copy_read(15 downto  0) <= tex_copy_in3;
            tex_copy_read(31 downto 16) <= tex_copy_in2;
            tex_copy_read(47 downto 32) <= tex_copy_in1;
            tex_copy_read(63 downto 48) <= tex_copy_in0;
            
            -- synthesis translate_off
            exportNext_TexFt_addr <= (others => '0');
            exportNext_TexFt_data <= (others => '0');
            exportNext_TexFt_db1  <= (others => '0');
            exportNext_TexFt_db3  <= (others => '0');
            -- synthesis translate_on
            
            case (settings_tile.Tile_size) is
               
               when SIZE_4BIT =>
                  case (settings_tile.Tile_format) is
                     when FORMAT_RGBA => error_texMode <= '1'; -- should not be allowed
                     when FORMAT_YUV => error_texMode <= '1'; -- should not be allowed
                     
                     when FORMAT_CI =>
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 20x"0" & '1' & unsigned(tex_addr(4)) & "000";
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"0000000" & dataMuxed4;
                        -- synthesis translate_on
                        
                     when FORMAT_IA =>
                        tex_color_read(0) <= dataMuxed4(3 downto 1) & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 2);
                        tex_color_read(1) <= dataMuxed4(3 downto 1) & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 2);
                        tex_color_read(2) <= dataMuxed4(3 downto 1) & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 2);
                        tex_alpha_read    <= dataMuxed4(3 downto 1) & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 2);
                        if (dataMuxed4(0) = '1') then tex_alpha_read <= (others => '1'); else tex_alpha_read <= (others => '0'); end if;
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 2);
                        exportNext_TexFt_data(23 downto 16) <= dataMuxed4(3 downto 1) & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 2);
                        exportNext_TexFt_data(15 downto  8) <= dataMuxed4(3 downto 1) & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 2);
                        exportNext_TexFt_data( 7 downto  0) <= dataMuxed4(3 downto 1) & dataMuxed4(3 downto 1) & dataMuxed4(3 downto 2);
                        if (dataMuxed4(0) = '1') then exportNext_TexFt_data(31 downto 24) <= (others => '1'); else exportNext_TexFt_data(31 downto 24) <= (others => '0'); end if;
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"0000000" & dataMuxed4;
                        -- synthesis translate_on
                     
                     when FORMAT_I => null;
                        tex_color_read(0) <= dataMuxed4 & dataMuxed4;
                        tex_color_read(1) <= dataMuxed4 & dataMuxed4;
                        tex_color_read(2) <= dataMuxed4 & dataMuxed4;
                        tex_alpha_read    <= dataMuxed4 & dataMuxed4;
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & dataMuxed4 & dataMuxed4;
                        exportNext_TexFt_data(23 downto 16) <= dataMuxed4 & dataMuxed4;
                        exportNext_TexFt_data(15 downto  8) <= dataMuxed4 & dataMuxed4;
                        exportNext_TexFt_data( 7 downto  0) <= dataMuxed4 & dataMuxed4;
                        exportNext_TexFt_data(31 downto 24) <= dataMuxed4 & dataMuxed4;
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"000000" & dataMuxed8;
                        -- synthesis translate_on
                     
                     when others => null;
                  end case;
               
               when SIZE_8BIT =>
                  case (settings_tile.Tile_format) is
                     when FORMAT_RGBA => error_texMode <= '1'; -- should not be allowed
                     when FORMAT_YUV => error_texMode <= '1'; -- should not be allowed
                     when FORMAT_CI =>
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 20x"0" & '1' & unsigned(tex_addr(4)) & "000";
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"000000" & dataMuxed8;
                        -- synthesis translate_on
                        
                     when FORMAT_IA =>
                        tex_color_read(0) <= dataMuxed8(7 downto 4) & dataMuxed8(7 downto 4);
                        tex_color_read(1) <= dataMuxed8(7 downto 4) & dataMuxed8(7 downto 4);
                        tex_color_read(2) <= dataMuxed8(7 downto 4) & dataMuxed8(7 downto 4);
                        tex_alpha_read    <= dataMuxed8(3 downto 0) & dataMuxed8(3 downto 0);
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & dataMuxed8(7 downto 4) & dataMuxed8(7 downto 4);
                        exportNext_TexFt_data(23 downto 16) <= dataMuxed8(7 downto 4) & dataMuxed8(7 downto 4);
                        exportNext_TexFt_data(15 downto  8) <= dataMuxed8(7 downto 4) & dataMuxed8(7 downto 4);
                        exportNext_TexFt_data( 7 downto  0) <= dataMuxed8(7 downto 4) & dataMuxed8(7 downto 4);
                        exportNext_TexFt_data(31 downto 24) <= dataMuxed8(3 downto 0) & dataMuxed8(3 downto 0);
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"000000" & dataMuxed8;
                        -- synthesis translate_on
                     
                     when FORMAT_I =>
                        tex_color_read(0) <= dataMuxed8;
                        tex_color_read(1) <= dataMuxed8;
                        tex_color_read(2) <= dataMuxed8;
                        tex_alpha_read    <= dataMuxed8;
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & dataMuxed8;
                        exportNext_TexFt_data(23 downto 16) <= dataMuxed8;
                        exportNext_TexFt_data(15 downto  8) <= dataMuxed8;
                        exportNext_TexFt_data( 7 downto  0) <= dataMuxed8;
                        exportNext_TexFt_data(31 downto 24) <= dataMuxed8;
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"00000000";
                        -- synthesis translate_on
                     
                     when others => null;
                  end case;
               
               when SIZE_16BIT =>
                  case (settings_tile.Tile_format) is
                     when FORMAT_RGBA => 
                        tex_color_read(0) <= dataMuxed16(15 downto 11) & dataMuxed16(15 downto 13);
                        tex_color_read(1) <= dataMuxed16(10 downto  6) & dataMuxed16(10 downto  8);
                        tex_color_read(2) <= dataMuxed16( 5 downto  1) & dataMuxed16( 5 downto  3);
                        if (dataMuxed16(0) = '1') then tex_alpha_read <= (others => '1'); else tex_alpha_read <= (others => '0'); end if;
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= (others => '0');
                        exportNext_TexFt_data(23 downto 16) <= dataMuxed16(15 downto 11) & dataMuxed16(15 downto 13);
                        exportNext_TexFt_data(15 downto  8) <= dataMuxed16(10 downto  6) & dataMuxed16(10 downto  8);
                        exportNext_TexFt_data( 7 downto  0) <= dataMuxed16( 5 downto  1) & dataMuxed16( 5 downto  3);
                        if (dataMuxed16(0) = '1') then exportNext_TexFt_data(31 downto 24) <= (others => '1'); else exportNext_TexFt_data(31 downto 24) <= (others => '0'); end if;
                        exportNext_TexFt_db1  <= resize(addr_base_1 & '0', 32);
                        exportNext_TexFt_db3  <= x"0000" & dataMuxed16;
                        -- synthesis translate_on
                     
                     when FORMAT_YUV => error_texMode <= '1';
                     when FORMAT_CI => error_texMode <= '1'; -- should not be allowed
                     when FORMAT_IA =>
                        tex_color_read(0) <= dataMuxed16(15 downto 8);
                        tex_color_read(1) <= dataMuxed16(15 downto 8);
                        tex_color_read(2) <= dataMuxed16(15 downto 8);
                        tex_alpha_read    <= dataMuxed16(7 downto 0);
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & dataMuxed16(15 downto 8);
                        exportNext_TexFt_data(23 downto 16) <= dataMuxed16(15 downto 8);
                        exportNext_TexFt_data(15 downto  8) <= dataMuxed16(15 downto 8);
                        exportNext_TexFt_data( 7 downto  0) <= dataMuxed16(15 downto 8);
                        exportNext_TexFt_data(31 downto 24) <= dataMuxed16(7 downto 0);
                        exportNext_TexFt_db1  <= resize(addr_base_1 & '0', 32);
                        exportNext_TexFt_db3  <= x"0000" & dataMuxed16;
                        -- synthesis translate_on
                     
                     when FORMAT_I => error_texMode <= '1'; -- should not be allowed
                     when others => null;
                  end case;
               
               when SIZE_32BIT =>
                  case (settings_tile.Tile_format) is
                     when FORMAT_RGBA =>
                        tex_color_read(0) <= dataMuxed32(31 downto 24);
                        tex_color_read(1) <= dataMuxed32(23 downto 16);
                        tex_color_read(2) <= dataMuxed32(15 downto  8);
                        tex_alpha_read    <= dataMuxed32( 7 downto  0);
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= (others => '0');
                        exportNext_TexFt_data(31 downto 24) <= dataMuxed32( 7 downto  0);
                        exportNext_TexFt_data(23 downto 16) <= dataMuxed32(31 downto 24);
                        exportNext_TexFt_data(15 downto  8) <= dataMuxed32(23 downto 16);
                        exportNext_TexFt_data( 7 downto  0) <= dataMuxed32(15 downto  8);
                        exportNext_TexFt_db1  <= resize(addr_base_1 & '0', 32);
                        exportNext_TexFt_db3  <= dataMuxed32;
                        -- synthesis translate_on
                     
                     when FORMAT_YUV => error_texMode <= '1'; -- should not be allowed
                     when FORMAT_CI => error_texMode <= '1';  -- should not be allowed
                     when FORMAT_IA => error_texMode <= '1';  -- should not be allowed
                     when FORMAT_I => error_texMode <= '1';   -- should not be allowed
                     when others => null;
                  end case;
               
               when others => null;
            end case;
            
         end if;
      end if;
   end process;
   
   -- Palette select
   paletteMuxed16 <= unsigned(tex_data(4));
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (trigger = '1') then
         
            -- synthesis translate_off
            export_TexFt_addr <= exportNext_TexFt_addr;
            export_TexFt_data <= exportNext_TexFt_data;
            export_TexFt_db1  <= exportNext_TexFt_db1;
            export_TexFt_db3  <= exportNext_TexFt_db3;
            -- synthesis translate_on
            
            if (settings_otherModes.enTlut = '1') then
               tex_copy(15 downto  0) <= unsigned(tex_data(7));
               tex_copy(31 downto 16) <= unsigned(tex_data(6));
               tex_copy(47 downto 32) <= unsigned(tex_data(5));
               tex_copy(63 downto 48) <= unsigned(tex_data(4));
            else
               tex_copy <= tex_copy_read;
            end if;
         
            if (settings_otherModes.enTlut = '1') then
               tex_color(0) <= (others => '0');
               tex_color(1) <= (others => '0');
               tex_color(2) <= (others => '0');
               tex_alpha    <= (others => '0');
            
               case (settings_tile.Tile_format) is
                  when FORMAT_RGBA => null;
                  when FORMAT_YUV => null;
                  when FORMAT_CI =>
                     if (settings_otherModes.tlutType = '1') then
                        tex_color(0) <= paletteMuxed16(15 downto 8);
                        tex_color(1) <= paletteMuxed16(15 downto 8);
                        tex_color(2) <= paletteMuxed16(15 downto 8);
                        tex_alpha    <= paletteMuxed16(7 downto 0);
                        -- synthesis translate_off
                        export_TexFt_data(23 downto 16) <= paletteMuxed16(15 downto 8);
                        export_TexFt_data(15 downto  8) <= paletteMuxed16(15 downto 8);
                        export_TexFt_data( 7 downto  0) <= paletteMuxed16(15 downto 8);
                        export_TexFt_data(31 downto 24) <= paletteMuxed16(7 downto 0);
                        export_TexFt_db3  <= x"00" & paletteMuxed16 & exportNext_TexFt_db3(7 downto 0);
                        -- synthesis translate_on
                     else
                        tex_color(0) <= paletteMuxed16(15 downto 11) & paletteMuxed16(15 downto 13);
                        tex_color(1) <= paletteMuxed16(10 downto  6) & paletteMuxed16(10 downto  8);
                        tex_color(2) <= paletteMuxed16( 5 downto  1) & paletteMuxed16( 5 downto  3);
                        if (paletteMuxed16(0) = '1') then tex_alpha <= (others => '1'); else tex_alpha <= (others => '0'); end if;
                        -- synthesis translate_off
                        export_TexFt_data(23 downto 16) <= paletteMuxed16(15 downto 11) & paletteMuxed16(15 downto 13);
                        export_TexFt_data(15 downto  8) <= paletteMuxed16(10 downto  6) & paletteMuxed16(10 downto  8);
                        export_TexFt_data( 7 downto  0) <= paletteMuxed16( 5 downto  1) & paletteMuxed16( 5 downto  3);
                        if (paletteMuxed16(0) = '1') then export_TexFt_data(31 downto 24) <= (others => '1'); else export_TexFt_data(31 downto 24) <= (others => '0'); end if;
                        export_TexFt_db3  <= x"00" & paletteMuxed16 & exportNext_TexFt_db3(7 downto 0);
                        -- synthesis translate_on
                     end if;
                  when FORMAT_IA => null;
                  when FORMAT_I => null;
                  when others => null;
               end case;
            else
               tex_color <= tex_color_read;
               tex_alpha <= tex_alpha_read;
            end if;
            
         end if;
      
      end if;
   end process;
   
   
end architecture;





