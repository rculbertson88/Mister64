library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;

entity RDP_TexFetch is
   port 
   (
      clk1x             : in  std_logic;
      trigger           : in  std_logic;
         
      settings_tile     : in  tsettings_tile;
      index_S           : in  unsigned(9 downto 0);
      index_T           : in  unsigned(9 downto 0);
         
      tex_addr          : out unsigned(11 downto 0);
      tex_data          : in  tTextureRamData;
      
      -- synthesis translate_off
      export_TexFt_addr : out unsigned(31 downto 0);
      export_TexFt_data : out unsigned(31 downto 0);
      export_TexFt_db1  : out unsigned(31 downto 0);
      export_TexFt_db3  : out unsigned(31 downto 0);
      -- synthesis translate_on
      
      tex_color         : out tcolor3_u8;
      tex_alpha         : out unsigned(7 downto 0)
   );
end entity;

architecture arch of RDP_TexFetch is

   signal addr_base       : unsigned(11 downto 0);
   
   signal dataSelect_next : integer range 0 to 3;
   signal dataSelect      : integer range 0 to 3;
   
   signal dataMuxed16     : unsigned(15 downto 0);
   signal dataMuxed32     : unsigned(31 downto 0);
  
   -- synthesis translate_off
   signal addr_base_1     : unsigned(11 downto 0);
   -- synthesis translate_on
  
begin 

   addr_base <= to_unsigned(to_integer(settings_tile.Tile_TmemAddr) + (to_integer(index_T) * to_integer(settings_tile.Tile_line)), 12);

   -- address select
   process (all)
      variable addr_calc : unsigned(11 downto 0);
   begin
   
      addr_calc       := (others => '0');
   
      case (settings_tile.Tile_size) is
         
         when SIZE_4BIT =>
            case (settings_tile.Tile_format) is
               when FORMAT_RGBA => null;
               when FORMAT_YUV => null;
               when FORMAT_CI => null;
               when FORMAT_IA => null;
               when FORMAT_I => null;
               when others => null;
            end case;
         
         when SIZE_8BIT =>
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
      
      tex_addr <= addr_calc;
      
      dataSelect_next <= to_integer(addr_calc(2 downto 1));
      
   end process;
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (trigger = '1') then
         
            dataSelect <= dataSelect_next;
            
            -- synthesis translate_off
            addr_base_1 <= addr_base;
            -- synthesis translate_on
            
         end if;
      
      end if;
   end process;
   
   -- data select
   dataMuxed16 <= unsigned(tex_data(dataSelect));
   
   dataMuxed32 <= unsigned(tex_data(dataSelect)) & unsigned(tex_data(dataSelect + 4)); 
   
   process (all)
   begin
   
      tex_color(0) <= (others => '0');
      tex_color(1) <= (others => '0');
      tex_color(2) <= (others => '0');
      tex_alpha    <= (others => '0');
      
      -- synthesis translate_off
      export_TexFt_addr <= (others => '0');
      export_TexFt_data <= (others => '0');
      export_TexFt_db1  <= (others => '0');
      export_TexFt_db3  <= (others => '0');
      -- synthesis translate_on
      
      case (settings_tile.Tile_size) is
         
         when SIZE_4BIT =>
            case (settings_tile.Tile_format) is
               when FORMAT_RGBA => null;
               when FORMAT_YUV => null;
               when FORMAT_CI => null;
               when FORMAT_IA => null;
               when FORMAT_I => null;
               when others => null;
            end case;
         
         when SIZE_8BIT =>
            case (settings_tile.Tile_format) is
               when FORMAT_RGBA => null;
               when FORMAT_YUV => null;
               when FORMAT_CI => null;
               when FORMAT_IA => null;
               when FORMAT_I => null;
               when others => null;
            end case;
         
         when SIZE_16BIT =>
            case (settings_tile.Tile_format) is
               when FORMAT_RGBA => 
                  tex_color(0) <= dataMuxed16(15 downto 11) & dataMuxed16(15 downto 13);
                  tex_color(1) <= dataMuxed16(10 downto  6) & dataMuxed16(10 downto  8);
                  tex_color(2) <= dataMuxed16( 5 downto  1) & dataMuxed16( 5 downto  3);
                  if (dataMuxed16(0) = '1') then tex_alpha <= (others => '1'); else tex_alpha <= (others => '0'); end if;
                  -- synthesis translate_off
                  export_TexFt_addr <= (others => '0');
                  export_TexFt_data(23 downto 16) <= dataMuxed16(15 downto 11) & dataMuxed16(15 downto 13);
                  export_TexFt_data(15 downto  8) <= dataMuxed16(10 downto  6) & dataMuxed16(10 downto  8);
                  export_TexFt_data( 7 downto  0) <= dataMuxed16( 5 downto  1) & dataMuxed16( 5 downto  3);
                  if (dataMuxed16(0) = '1') then export_TexFt_data(31 downto 24) <= (others => '1'); else export_TexFt_data(31 downto 24) <= (others => '0'); end if;
                  export_TexFt_db1  <= resize(addr_base_1 & '0', 32);
                  export_TexFt_db3  <= x"0000" & dataMuxed16;
                  -- synthesis translate_on
               
               when FORMAT_YUV => null;
               when FORMAT_CI => null;
               when FORMAT_IA => null;
               when FORMAT_I => null;
               when others => null;
            end case;
         
         when SIZE_32BIT =>
            case (settings_tile.Tile_format) is
               when FORMAT_RGBA =>
                  tex_color(0) <= dataMuxed32(31 downto 24);
                  tex_color(1) <= dataMuxed32(23 downto 16);
                  tex_color(2) <= dataMuxed32(15 downto  8);
                  tex_alpha    <= dataMuxed32( 7 downto  0);
                  -- synthesis translate_off
                  export_TexFt_addr <= (others => '0');
                  export_TexFt_data(31 downto 24) <= dataMuxed32( 7 downto  0);
                  export_TexFt_data(23 downto 16) <= dataMuxed32(31 downto 24);
                  export_TexFt_data(15 downto  8) <= dataMuxed32(23 downto 16);
                  export_TexFt_data( 7 downto  0) <= dataMuxed32(15 downto  8);
                  export_TexFt_db1  <= resize(addr_base_1 & '0', 32);
                  export_TexFt_db3  <= dataMuxed32;
                  -- synthesis translate_on
               
               when FORMAT_YUV => null;
               when FORMAT_CI => null;
               when FORMAT_IA => null;
               when FORMAT_I => null;
               when others => null;
            end case;
         
         when others => null;
      end case;

   end process;
   
   
end architecture;





