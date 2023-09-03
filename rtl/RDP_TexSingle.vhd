library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;

entity RDP_TexSingle is
   port 
   (
      clk1x                : in  std_logic;
      trigger              : in  std_logic;
         
      error_texMode        : out std_logic;  

      settings_otherModes  : in  tsettings_otherModes;
      settings_tile        : in  tsettings_tile;      
      
      data4                : in  unsigned(3 downto 0);
      data8                : in  unsigned(7 downto 0);
      data16               : in  unsigned(15 downto 0);
      data32               : in  unsigned(31 downto 0);
      palette16            : in  unsigned(15 downto 0);
      
      -- synthesis translate_off
      addr_base_1          : in  unsigned(11 downto 0);
      tex_palette_addr     : in  std_logic_vector(7 downto 0);
      
      export_TexFt_addr    : out unsigned(31 downto 0);
      export_TexFt_data    : out unsigned(31 downto 0);
      export_TexFt_db1     : out unsigned(31 downto 0);
      export_TexFt_db3     : out unsigned(31 downto 0);
      -- synthesis translate_on
      
      tex_color            : out tcolor4_u8
   );
end entity;

architecture arch of RDP_TexSingle is
  
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
  
begin 
    
   process (clk1x)
   begin
      if rising_edge(clk1x) then
   
         error_texMode <= '0';
   
         if (trigger = '1') then
         
            tex_color_read(0) <= (others => '0');
            tex_color_read(1) <= (others => '0');
            tex_color_read(2) <= (others => '0');
            tex_alpha_read    <= (others => '0');
            
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
                        exportNext_TexFt_addr <= 20x"0" & '1' & unsigned(tex_palette_addr) & "000";
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"0000000" & data4;
                        -- synthesis translate_on
                        
                     when FORMAT_IA =>
                        tex_color_read(0) <= data4(3 downto 1) & data4(3 downto 1) & data4(3 downto 2);
                        tex_color_read(1) <= data4(3 downto 1) & data4(3 downto 1) & data4(3 downto 2);
                        tex_color_read(2) <= data4(3 downto 1) & data4(3 downto 1) & data4(3 downto 2);
                        tex_alpha_read    <= data4(3 downto 1) & data4(3 downto 1) & data4(3 downto 2);
                        if (data4(0) = '1') then tex_alpha_read <= (others => '1'); else tex_alpha_read <= (others => '0'); end if;
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & data4(3 downto 1) & data4(3 downto 1) & data4(3 downto 2);
                        exportNext_TexFt_data(23 downto 16) <= data4(3 downto 1) & data4(3 downto 1) & data4(3 downto 2);
                        exportNext_TexFt_data(15 downto  8) <= data4(3 downto 1) & data4(3 downto 1) & data4(3 downto 2);
                        exportNext_TexFt_data( 7 downto  0) <= data4(3 downto 1) & data4(3 downto 1) & data4(3 downto 2);
                        if (data4(0) = '1') then exportNext_TexFt_data(31 downto 24) <= (others => '1'); else exportNext_TexFt_data(31 downto 24) <= (others => '0'); end if;
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"0000000" & data4;
                        -- synthesis translate_on
                     
                     when FORMAT_I => null;
                        tex_color_read(0) <= data4 & data4;
                        tex_color_read(1) <= data4 & data4;
                        tex_color_read(2) <= data4 & data4;
                        tex_alpha_read    <= data4 & data4;
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & data4 & data4;
                        exportNext_TexFt_data(23 downto 16) <= data4 & data4;
                        exportNext_TexFt_data(15 downto  8) <= data4 & data4;
                        exportNext_TexFt_data( 7 downto  0) <= data4 & data4;
                        exportNext_TexFt_data(31 downto 24) <= data4 & data4;
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"000000" & data8;
                        -- synthesis translate_on
                     
                     when others => null;
                  end case;
               
               when SIZE_8BIT =>
                  case (settings_tile.Tile_format) is
                     when FORMAT_RGBA => error_texMode <= '1'; -- should not be allowed
                     when FORMAT_YUV => error_texMode <= '1'; -- should not be allowed
                     when FORMAT_CI =>
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 20x"0" & '1' & unsigned(tex_palette_addr) & "000";
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"000000" & data8;
                        -- synthesis translate_on
                        
                     when FORMAT_IA =>
                        tex_color_read(0) <= data8(7 downto 4) & data8(7 downto 4);
                        tex_color_read(1) <= data8(7 downto 4) & data8(7 downto 4);
                        tex_color_read(2) <= data8(7 downto 4) & data8(7 downto 4);
                        tex_alpha_read    <= data8(3 downto 0) & data8(3 downto 0);
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & data8(7 downto 4) & data8(7 downto 4);
                        exportNext_TexFt_data(23 downto 16) <= data8(7 downto 4) & data8(7 downto 4);
                        exportNext_TexFt_data(15 downto  8) <= data8(7 downto 4) & data8(7 downto 4);
                        exportNext_TexFt_data( 7 downto  0) <= data8(7 downto 4) & data8(7 downto 4);
                        exportNext_TexFt_data(31 downto 24) <= data8(3 downto 0) & data8(3 downto 0);
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"000000" & data8;
                        -- synthesis translate_on
                     
                     when FORMAT_I =>
                        tex_color_read(0) <= data8;
                        tex_color_read(1) <= data8;
                        tex_color_read(2) <= data8;
                        tex_alpha_read    <= data8;
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & data8;
                        exportNext_TexFt_data(23 downto 16) <= data8;
                        exportNext_TexFt_data(15 downto  8) <= data8;
                        exportNext_TexFt_data( 7 downto  0) <= data8;
                        exportNext_TexFt_data(31 downto 24) <= data8;
                        exportNext_TexFt_db1  <= resize(addr_base_1, 32);
                        exportNext_TexFt_db3  <= x"00000000";
                        -- synthesis translate_on
                     
                     when others => null;
                  end case;
               
               when SIZE_16BIT =>
                  case (settings_tile.Tile_format) is
                     when FORMAT_RGBA => 
                        tex_color_read(0) <= data16(15 downto 11) & data16(15 downto 13);
                        tex_color_read(1) <= data16(10 downto  6) & data16(10 downto  8);
                        tex_color_read(2) <= data16( 5 downto  1) & data16( 5 downto  3);
                        if (data16(0) = '1') then tex_alpha_read <= (others => '1'); else tex_alpha_read <= (others => '0'); end if;
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= (others => '0');
                        exportNext_TexFt_data(23 downto 16) <= data16(15 downto 11) & data16(15 downto 13);
                        exportNext_TexFt_data(15 downto  8) <= data16(10 downto  6) & data16(10 downto  8);
                        exportNext_TexFt_data( 7 downto  0) <= data16( 5 downto  1) & data16( 5 downto  3);
                        if (data16(0) = '1') then exportNext_TexFt_data(31 downto 24) <= (others => '1'); else exportNext_TexFt_data(31 downto 24) <= (others => '0'); end if;
                        exportNext_TexFt_db1  <= resize(addr_base_1 & '0', 32);
                        exportNext_TexFt_db3  <= x"0000" & data16;
                        -- synthesis translate_on
                     
                     when FORMAT_YUV => error_texMode <= '1';
                     when FORMAT_CI => error_texMode <= '1'; -- should not be allowed
                     when FORMAT_IA =>
                        tex_color_read(0) <= data16(15 downto 8);
                        tex_color_read(1) <= data16(15 downto 8);
                        tex_color_read(2) <= data16(15 downto 8);
                        tex_alpha_read    <= data16(7 downto 0);
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= 24x"0" & data16(15 downto 8);
                        exportNext_TexFt_data(23 downto 16) <= data16(15 downto 8);
                        exportNext_TexFt_data(15 downto  8) <= data16(15 downto 8);
                        exportNext_TexFt_data( 7 downto  0) <= data16(15 downto 8);
                        exportNext_TexFt_data(31 downto 24) <= data16(7 downto 0);
                        exportNext_TexFt_db1  <= resize(addr_base_1 & '0', 32);
                        exportNext_TexFt_db3  <= x"0000" & data16;
                        -- synthesis translate_on
                     
                     when FORMAT_I => error_texMode <= '1'; -- should not be allowed
                     when others => null;
                  end case;
               
               when SIZE_32BIT =>
                  case (settings_tile.Tile_format) is
                     when FORMAT_RGBA =>
                        tex_color_read(0) <= data32(31 downto 24);
                        tex_color_read(1) <= data32(23 downto 16);
                        tex_color_read(2) <= data32(15 downto  8);
                        tex_alpha_read    <= data32( 7 downto  0);
                        -- synthesis translate_off
                        exportNext_TexFt_addr <= (others => '0');
                        exportNext_TexFt_data(31 downto 24) <= data32( 7 downto  0);
                        exportNext_TexFt_data(23 downto 16) <= data32(31 downto 24);
                        exportNext_TexFt_data(15 downto  8) <= data32(23 downto 16);
                        exportNext_TexFt_data( 7 downto  0) <= data32(15 downto  8);
                        exportNext_TexFt_db1  <= resize(addr_base_1 & '0', 32);
                        exportNext_TexFt_db3  <= data32;
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
   
   process (all)
   begin
   
      -- synthesis translate_off
      export_TexFt_addr <= exportNext_TexFt_addr;
      export_TexFt_data <= exportNext_TexFt_data;
      export_TexFt_db1  <= exportNext_TexFt_db1;
      export_TexFt_db3  <= exportNext_TexFt_db3;
      -- synthesis translate_on
      
      if (settings_otherModes.enTlut = '1') then
         tex_color(0) <= (others => '0');
         tex_color(1) <= (others => '0');
         tex_color(2) <= (others => '0');
         tex_color(3) <= (others => '0');
      
         case (settings_tile.Tile_format) is
            when FORMAT_RGBA => null;
            when FORMAT_YUV => null;
            when FORMAT_CI =>
               if (settings_otherModes.tlutType = '1') then
                  tex_color(0) <= palette16(15 downto 8);
                  tex_color(1) <= palette16(15 downto 8);
                  tex_color(2) <= palette16(15 downto 8);
                  tex_color(3) <= palette16(7 downto 0);
                  -- synthesis translate_off
                  export_TexFt_data(23 downto 16) <= palette16(15 downto 8);
                  export_TexFt_data(15 downto  8) <= palette16(15 downto 8);
                  export_TexFt_data( 7 downto  0) <= palette16(15 downto 8);
                  export_TexFt_data(31 downto 24) <= palette16(7 downto 0);
                  export_TexFt_db3  <= x"00" & palette16 & exportNext_TexFt_db3(7 downto 0);
                  -- synthesis translate_on
               else
                  tex_color(0) <= palette16(15 downto 11) & palette16(15 downto 13);
                  tex_color(1) <= palette16(10 downto  6) & palette16(10 downto  8);
                  tex_color(2) <= palette16( 5 downto  1) & palette16( 5 downto  3);
                  if (palette16(0) = '1') then tex_color(3) <= (others => '1'); else tex_color(3) <= (others => '0'); end if;
                  -- synthesis translate_off
                  export_TexFt_data(23 downto 16) <= palette16(15 downto 11) & palette16(15 downto 13);
                  export_TexFt_data(15 downto  8) <= palette16(10 downto  6) & palette16(10 downto  8);
                  export_TexFt_data( 7 downto  0) <= palette16( 5 downto  1) & palette16( 5 downto  3);
                  if (palette16(0) = '1') then export_TexFt_data(31 downto 24) <= (others => '1'); else export_TexFt_data(31 downto 24) <= (others => '0'); end if;
                  export_TexFt_db3  <= x"00" & palette16 & exportNext_TexFt_db3(7 downto 0);
                  -- synthesis translate_on
               end if;
            when FORMAT_IA => null;
            when FORMAT_I => null;
            when others => null;
         end case;
      else
         tex_color(0) <= tex_color_read(0);
         tex_color(1) <= tex_color_read(1);
         tex_color(2) <= tex_color_read(2);
         tex_color(3) <= tex_alpha_read;
      end if;
            
   end process;
   
   
end architecture;





