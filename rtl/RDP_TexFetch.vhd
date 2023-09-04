library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;

entity RDP_TexFetch is
   port 
   (
      clk1x                : in  std_logic;
      trigger              : in  std_logic;
      
      DISABLEFILTER        : in  std_logic;
         
      error_texMode        : out std_logic;       
         
      settings_otherModes  : in  tsettings_otherModes;
      settings_tile        : in  tsettings_tile;
      index_S              : in  unsigned(9 downto 0);
      index_S1             : in  unsigned(9 downto 0);
      index_S2             : in  unsigned(9 downto 0);
      index_S3             : in  unsigned(9 downto 0);
      index_SN             : in  unsigned(9 downto 0);
      index_T              : in  unsigned(9 downto 0);
      index_TN             : in  unsigned(9 downto 0);
      
      frac_S               : in  unsigned(4 downto 0);
      frac_T               : in  unsigned(4 downto 0);
            
      tex_addr             : out tTextureRamAddr;
      tex_data             : in  tTextureRamData;
      
      -- synthesis translate_off
      export_TextureAddr   : out tcolor4_u12;
      export_TexFt_addr    : out tcolor4_u32;
      export_TexFt_data    : out tcolor4_u32;
      export_TexFt_db1     : out tcolor4_u32;
      export_TexFt_db3     : out tcolor4_u32;
      export_TexFt_mode    : out unsigned(1 downto 0);
      -- synthesis translate_on
      
      tex_color_out        : out tcolor3_u8;
      tex_alpha_out        : out unsigned(7 downto 0);
      tex_copy             : out unsigned(63 downto 0)
   );
end entity;

architecture arch of RDP_TexFetch is

   -- address calculation
   signal addr_base              : unsigned(11 downto 0);
   signal addr_baseN             : unsigned(11 downto 0);
               
   signal addr_calcS0            : unsigned(12 downto 0);
   signal addr_calcS1            : unsigned(12 downto 0);
   signal addr_calcS2            : unsigned(12 downto 0);
   signal addr_calcS3            : unsigned(12 downto 0);
               
   signal addr_calcT0            : unsigned(12 downto 0);
   signal addr_calcT1            : unsigned(12 downto 0);
   signal addr_calcT2            : unsigned(12 downto 0);
   signal addr_calcT3            : unsigned(12 downto 0);
               
   signal addr_calcR0            : unsigned(12 downto 0);
   signal addr_calcR1            : unsigned(12 downto 0);
   signal addr_calcR2            : unsigned(12 downto 0);
   signal addr_calcR3            : unsigned(12 downto 0);

   -- first cycle   
   signal frac_S_1               : unsigned(4 downto 0) := (others => '0');
   signal frac_T_1               : unsigned(4 downto 0) := (others => '0');
   
   signal select0next            : unsigned(2 downto 0);
   signal select1next            : unsigned(2 downto 0);
   signal select2next            : unsigned(2 downto 0);
   signal select3next            : unsigned(2 downto 0);
   signal select0                : integer range 0 to 7 := 0;
   signal select1                : integer range 0 to 7 := 0;
   signal select2                : integer range 0 to 7 := 0;
   signal select3                : integer range 0 to 7 := 0;
                                 
   signal pal4Index0Next         : unsigned(1 downto 0);
   signal pal4Index1Next         : unsigned(1 downto 0);
   signal pal4Index2Next         : unsigned(1 downto 0);
   signal pal4Index3Next         : unsigned(1 downto 0);
   signal pal8Index0Next         : std_logic;
   signal pal8Index1Next         : std_logic;
   signal pal8Index2Next         : std_logic;
   signal pal8Index3Next         : std_logic;
                                 
   signal pal4Index0             : unsigned(1 downto 0) := (others => '0');
   signal pal4Index1             : unsigned(1 downto 0) := (others => '0');
   signal pal4Index2             : unsigned(1 downto 0) := (others => '0');
   signal pal4Index3             : unsigned(1 downto 0) := (others => '0');
   signal pal8Index0             : std_logic := '0';
   signal pal8Index1             : std_logic := '0';
   signal pal8Index2             : std_logic := '0';
   signal pal8Index3             : std_logic := '0';
   
   signal tex_in0                : unsigned(15 downto 0);
   signal tex_in1                : unsigned(15 downto 0);
   signal tex_in2                : unsigned(15 downto 0);
   signal tex_in3                : unsigned(15 downto 0);
   signal tex_in4                : unsigned(15 downto 0);
   signal tex_in5                : unsigned(15 downto 0);
   signal tex_in6                : unsigned(15 downto 0);
   signal tex_in7                : unsigned(15 downto 0);
   
   signal tex4_0                 : unsigned(3 downto 0);
   signal tex4_1                 : unsigned(3 downto 0);
   signal tex4_2                 : unsigned(3 downto 0);
   signal tex4_3                 : unsigned(3 downto 0);
   
   signal tex8_0                 : unsigned(7 downto 0);
   signal tex8_1                 : unsigned(7 downto 0);
   signal tex8_2                 : unsigned(7 downto 0);
   signal tex8_3                 : unsigned(7 downto 0);
  
   -- synthesis translate_off
   signal addr_base_1            : unsigned(11 downto 0) := (others => '0');
   signal addr_base_1N           : unsigned(11 downto 0) := (others => '0');
   -- synthesis translate_on
  
   -- second cycle
   signal frac_S_2               : signed(5 downto 0) := (others => '0');
   signal frac_T_2               : signed(5 downto 0) := (others => '0');
   signal texmode                : unsigned(1 downto 0) := (others => '0');
   
   signal tex_color_read         : tcolor3_u8 := (others => (others => '0'));
   signal tex_alpha_read         : unsigned(7 downto 0) := (others => '0');
   
   signal tex_copy_read          : unsigned(63 downto 0) := (others => '0');
   
   signal tex_color              : tcolor44_u8;
   
   signal filter_sub1_a          : tcolor4_u8;
   signal filter_sub1_b          : tcolor4_u8;
   signal filter_sub2_a          : tcolor4_u8;
   signal filter_sub2_b          : tcolor4_u8;
   
   type tfilter_sub is array(0 to 3) of signed(9 downto 0);
   signal filter_sub1            : tfilter_sub;
   signal filter_sub2            : tfilter_sub;
   
   type tfilter_mul is array(0 to 3) of signed(15 downto 0);
   signal filter_mul1            : tfilter_mul;
   signal filter_mul2            : tfilter_mul;
   signal filter_sum1            : tfilter_mul;
   
   type tfilter_sum is array(0 to 3) of signed(10 downto 0);
   signal filter_sum2            : tfilter_sum;
   
   -- synthesis translate_off
   signal exportNext_TexFt_addr  : tcolor4_u32;
   signal exportNext_TexFt_data  : tcolor4_u32;
   signal exportNext_TexFt_db1   : tcolor4_u32;
   signal exportNext_TexFt_db3   : tcolor4_u32;
   -- synthesis translate_on
  
begin 

   addr_base  <= to_unsigned(to_integer(settings_tile.Tile_TmemAddr) + (to_integer(index_T)  * to_integer(settings_tile.Tile_line)), 12);
   addr_baseN <= to_unsigned(to_integer(settings_tile.Tile_TmemAddr) + (to_integer(index_TN) * to_integer(settings_tile.Tile_line)), 12);

   -- address select
   process (all)
   begin
      
      if (settings_otherModes.cycleType = "10") then
      
         if (settings_tile.Tile_size = SIZE_8BIT or settings_tile.Tile_format = FORMAT_YUV) then
            addr_calcS0 <= "00" & index_S  & '0';
            addr_calcS1 <= "00" & index_S1 & '0';
            addr_calcS2 <= "00" & index_S2 & '0';
            addr_calcS3 <= "00" & index_S3 & '0';
         elsif (settings_tile.Tile_size = SIZE_16BIT or settings_tile.Tile_size = SIZE_32BIT) then
            addr_calcS0 <= "0" & index_S  & "00";
            addr_calcS1 <= "0" & index_S1 & "00";
            addr_calcS2 <= "0" & index_S2 & "00";
            addr_calcS3 <= "0" & index_S3 & "00";
         else
            addr_calcS0 <= "000" & index_S;
            addr_calcS1 <= "000" & index_S1;
            addr_calcS2 <= "000" & index_S2;
            addr_calcS3 <= "000" & index_S3;
         end if;
      
         addr_calcT0 <= addr_calcS0 + (addr_base(8 downto 0) & "0000");
         addr_calcT1 <= addr_calcS1 + (addr_base(8 downto 0) & "0000");
         addr_calcT2 <= addr_calcS2 + (addr_base(8 downto 0) & "0000");
         addr_calcT3 <= addr_calcS3 + (addr_base(8 downto 0) & "0000");
         
         -- todo: special handling for YUV
      
      else
      
         if (settings_tile.Tile_size = SIZE_8BIT or settings_tile.Tile_format = FORMAT_YUV) then
            addr_calcS0 <= "00" & index_S  & '0';
            addr_calcS1 <= "00" & index_SN & '0';
            addr_calcS2 <= "00" & index_S  & '0';
            addr_calcS3 <= "00" & index_SN & '0';
         elsif (settings_tile.Tile_size = SIZE_16BIT or settings_tile.Tile_size = SIZE_32BIT) then
            addr_calcS0 <= "0" & index_S  & "00";
            addr_calcS1 <= "0" & index_SN & "00";
            addr_calcS2 <= "0" & index_S  & "00";
            addr_calcS3 <= "0" & index_SN & "00";
         else
            addr_calcS0 <= "000" & index_S;
            addr_calcS1 <= "000" & index_SN;
            addr_calcS2 <= "000" & index_S;
            addr_calcS3 <= "000" & index_SN;
         end if;
      
         addr_calcT0 <= addr_calcS0 + (addr_base(8 downto 0)  & "0000");
         addr_calcT1 <= addr_calcS1 + (addr_base(8 downto 0)  & "0000");
         addr_calcT2 <= addr_calcS2 + (addr_baseN(8 downto 0) & "0000");
         addr_calcT3 <= addr_calcS3 + (addr_baseN(8 downto 0) & "0000");
      
      end if;
     
      addr_calcR0 <= addr_calcT0;
      addr_calcR1 <= addr_calcT1;
      addr_calcR2 <= addr_calcT2;
      addr_calcR3 <= addr_calcT3;
      
      if (settings_otherModes.cycleType = "10" or index_T = index_TN) then
         if (index_T(0) = '1') then
            addr_calcR0(3) <= not addr_calcT0(3);
            addr_calcR1(3) <= not addr_calcT1(3);
            addr_calcR2(3) <= not addr_calcT2(3);
            addr_calcR3(3) <= not addr_calcT3(3);
         end if;
      elsif (index_T(0) = '1') then
         addr_calcR0(3) <= not addr_calcT0(3);
         addr_calcR1(3) <= not addr_calcT1(3);
      else
         addr_calcR2(3) <= not addr_calcT2(3);
         addr_calcR3(3) <= not addr_calcT3(3);
      end if;
      
      select0next <= addr_calcR0(12) & addr_calcR0(3) & (not addr_calcR0(2));
      select1next <= addr_calcR1(12) & addr_calcR1(3) & (not addr_calcR1(2));
      select2next <= addr_calcR2(12) & addr_calcR2(3) & (not addr_calcR2(2));
      select3next <= addr_calcR3(12) & addr_calcR3(3) & (not addr_calcR3(2));
         
      if    (select0next(1 downto 0) = "00") then tex_addr(0) <= std_logic_vector(addr_calcR0(11 downto 4)); tex_addr(4) <= std_logic_vector(addr_calcR0(11 downto 4)); 
      elsif (select1next(1 downto 0) = "00") then tex_addr(0) <= std_logic_vector(addr_calcR1(11 downto 4)); tex_addr(4) <= std_logic_vector(addr_calcR1(11 downto 4)); 
      elsif (select2next(1 downto 0) = "00") then tex_addr(0) <= std_logic_vector(addr_calcR2(11 downto 4)); tex_addr(4) <= std_logic_vector(addr_calcR2(11 downto 4)); 
      elsif (select3next(1 downto 0) = "00") then tex_addr(0) <= std_logic_vector(addr_calcR3(11 downto 4)); tex_addr(4) <= std_logic_vector(addr_calcR3(11 downto 4));
      else tex_addr(0) <= (others => '0'); tex_addr(4) <= (others => '0'); end if;
      
      if    (select0next(1 downto 0) = "01") then tex_addr(1) <= std_logic_vector(addr_calcR0(11 downto 4)); tex_addr(5) <= std_logic_vector(addr_calcR0(11 downto 4)); 
      elsif (select1next(1 downto 0) = "01") then tex_addr(1) <= std_logic_vector(addr_calcR1(11 downto 4)); tex_addr(5) <= std_logic_vector(addr_calcR1(11 downto 4)); 
      elsif (select2next(1 downto 0) = "01") then tex_addr(1) <= std_logic_vector(addr_calcR2(11 downto 4)); tex_addr(5) <= std_logic_vector(addr_calcR2(11 downto 4)); 
      elsif (select3next(1 downto 0) = "01") then tex_addr(1) <= std_logic_vector(addr_calcR3(11 downto 4)); tex_addr(5) <= std_logic_vector(addr_calcR3(11 downto 4));
      else tex_addr(1) <= (others => '0'); tex_addr(5) <= (others => '0'); end if;
      
      if    (select0next(1 downto 0) = "10") then tex_addr(2) <= std_logic_vector(addr_calcR0(11 downto 4)); tex_addr(6) <= std_logic_vector(addr_calcR0(11 downto 4)); 
      elsif (select1next(1 downto 0) = "10") then tex_addr(2) <= std_logic_vector(addr_calcR1(11 downto 4)); tex_addr(6) <= std_logic_vector(addr_calcR1(11 downto 4)); 
      elsif (select2next(1 downto 0) = "10") then tex_addr(2) <= std_logic_vector(addr_calcR2(11 downto 4)); tex_addr(6) <= std_logic_vector(addr_calcR2(11 downto 4)); 
      elsif (select3next(1 downto 0) = "10") then tex_addr(2) <= std_logic_vector(addr_calcR3(11 downto 4)); tex_addr(6) <= std_logic_vector(addr_calcR3(11 downto 4));
      else tex_addr(2) <= (others => '0'); tex_addr(6) <= (others => '0'); end if;
      
      if    (select0next(1 downto 0) = "11") then tex_addr(3) <= std_logic_vector(addr_calcR0(11 downto 4)); tex_addr(7) <= std_logic_vector(addr_calcR0(11 downto 4)); 
      elsif (select1next(1 downto 0) = "11") then tex_addr(3) <= std_logic_vector(addr_calcR1(11 downto 4)); tex_addr(7) <= std_logic_vector(addr_calcR1(11 downto 4)); 
      elsif (select2next(1 downto 0) = "11") then tex_addr(3) <= std_logic_vector(addr_calcR2(11 downto 4)); tex_addr(7) <= std_logic_vector(addr_calcR2(11 downto 4)); 
      elsif (select3next(1 downto 0) = "11") then tex_addr(3) <= std_logic_vector(addr_calcR3(11 downto 4)); tex_addr(7) <= std_logic_vector(addr_calcR3(11 downto 4));
      else tex_addr(3) <= (others => '0'); tex_addr(7) <= (others => '0'); end if;
   
      if (settings_otherModes.enTlut = '1') then
         case (settings_tile.Tile_size) is
            when SIZE_4BIT =>
               tex_addr(4) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(tex4_0);
               tex_addr(5) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(tex4_1);
               tex_addr(6) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(tex4_2);
               tex_addr(7) <= std_logic_vector(settings_tile.Tile_palette) & std_logic_vector(tex4_3);
               
            when SIZE_8BIT =>
               tex_addr(4) <= std_logic_vector(tex8_0);
               tex_addr(5) <= std_logic_vector(tex8_1);
               tex_addr(6) <= std_logic_vector(tex8_2);
               tex_addr(7) <= std_logic_vector(tex8_3);
               
            when SIZE_16BIT =>
               tex_addr(4) <= std_logic_vector(tex_in0(15 downto 8));
               tex_addr(5) <= std_logic_vector(tex_in1(15 downto 8));
               tex_addr(6) <= std_logic_vector(tex_in2(15 downto 8));
               tex_addr(7) <= std_logic_vector(tex_in3(15 downto 8));
   
            when SIZE_32BIT =>
               tex_addr(4) <= std_logic_vector(tex_in0(15 downto 8));
               tex_addr(5) <= std_logic_vector(tex_in1(15 downto 8));
               tex_addr(6) <= std_logic_vector(tex_in2(15 downto 8));
               tex_addr(7) <= std_logic_vector(tex_in3(15 downto 8));
               select0next(2) <= '0';
               select1next(2) <= '0';
               select2next(2) <= '0';
               select3next(2) <= '0';
               
            when others => null;
         end case;
      end if;

      -- synthesis translate_off
      export_TextureAddr(0) <= addr_calcR0(12 downto 1);
      export_TextureAddr(0)(1) <= not addr_calcR0(2);      
      export_TextureAddr(1) <= addr_calcR1(12 downto 1);
      export_TextureAddr(1)(1) <= not addr_calcR1(2);
      export_TextureAddr(2) <= addr_calcR2(12 downto 1);
      export_TextureAddr(2)(1) <= not addr_calcR2(2);
      export_TextureAddr(3) <= addr_calcR3(12 downto 1);
      export_TextureAddr(3)(1) <= not addr_calcR3(2);
      if (settings_tile.Tile_size = SIZE_8BIT or settings_tile.Tile_size = SIZE_4BIT) then
         export_TextureAddr(0)(0) <= not addr_calcR0(1); 
         export_TextureAddr(1)(0) <= not addr_calcR1(1); 
         export_TextureAddr(2)(0) <= not addr_calcR2(1); 
         export_TextureAddr(3)(0) <= not addr_calcR3(1); 
      end if;      
      -- synthesis translate_on
      
      pal4Index0Next   <= not addr_calcR0(1 downto 0);
      pal4Index1Next   <= not addr_calcR1(1 downto 0);
      pal4Index2Next   <= not addr_calcR2(1 downto 0);
      pal4Index3Next   <= not addr_calcR3(1 downto 0);
      pal8Index0Next   <= not addr_calcR0(1);
      pal8Index1Next   <= not addr_calcR1(1);
      pal8Index2Next   <= not addr_calcR2(1);
      pal8Index3Next   <= not addr_calcR3(1);
      
   end process;
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then

         if (trigger = '1') then
         
            frac_S_1 <= frac_S;
            frac_T_1 <= frac_T;
            
            select0 <= to_integer(select0next);
            select1 <= to_integer(select1next);
            select2 <= to_integer(select2next);
            select3 <= to_integer(select3next);
            
            pal4Index0 <= pal4Index0Next;
            pal4Index1 <= pal4Index1Next;
            pal4Index2 <= pal4Index2Next;
            pal4Index3 <= pal4Index3Next;
            
            pal8Index0 <= pal8Index0Next;
            pal8Index1 <= pal8Index1Next;
            pal8Index2 <= pal8Index2Next;
            pal8Index3 <= pal8Index3Next;
            
            -- synthesis translate_off
            addr_base_1  <= addr_base;
            addr_base_1N <= addr_baseN;
            -- synthesis translate_on
            
         end if;
      
      end if;
   end process;
   
   -- data select   
   tex_in0 <= unsigned(tex_data(select0));
   tex_in1 <= unsigned(tex_data(select1));
   tex_in2 <= unsigned(tex_data(select2));
   tex_in3 <= unsigned(tex_data(select3));
   tex_in4 <= unsigned(tex_data((select0 mod 4) + 4));
   tex_in5 <= unsigned(tex_data((select1 mod 4) + 4));
   tex_in6 <= unsigned(tex_data((select2 mod 4) + 4));
   tex_in7 <= unsigned(tex_data((select3 mod 4) + 4));
   
   tex4_0 <= tex_in0( 3 downto  0) when (pal4Index0 = "00") else
             tex_in0( 7 downto  4) when (pal4Index0 = "01") else
             tex_in0(11 downto  8) when (pal4Index0 = "10") else
             tex_in0(15 downto 12);
                     
   tex4_1 <= tex_in1( 3 downto  0) when (pal4Index1 = "00") else
             tex_in1( 7 downto  4) when (pal4Index1 = "01") else
             tex_in1(11 downto  8) when (pal4Index1 = "10") else
             tex_in1(15 downto 12);
                     
   tex4_2 <= tex_in2( 3 downto  0) when (pal4Index2 = "00") else
             tex_in2( 7 downto  4) when (pal4Index2 = "01") else
             tex_in2(11 downto  8) when (pal4Index2 = "10") else
             tex_in2(15 downto 12);
                     
   tex4_3 <= tex_in3( 3 downto  0) when (pal4Index3 = "00") else
             tex_in3( 7 downto  4) when (pal4Index3 = "01") else
             tex_in3(11 downto  8) when (pal4Index3 = "10") else
             tex_in3(15 downto 12);
   
   tex8_0 <= tex_in0(15 downto 8) when (pal8Index0 = '1') else tex_in0(7 downto 0);
   tex8_1 <= tex_in1(15 downto 8) when (pal8Index1 = '1') else tex_in1(7 downto 0); 
   tex8_2 <= tex_in2(15 downto 8) when (pal8Index2 = '1') else tex_in2(7 downto 0); 
   tex8_3 <= tex_in3(15 downto 8) when (pal8Index3 = '1') else tex_in3(7 downto 0); 
   
   iRDP_TexSingle0 : entity work.RDP_TexSingle
   port map
   (
      clk1x                => clk1x,              
      trigger              => trigger,            
                                             
      error_texMode        => error_texMode,      
                                             
      settings_otherModes  => settings_otherModes,
      settings_tile        => settings_tile,      
                                            
      data4                => tex4_0,
      data8                => tex8_0,
      data16               => tex_in0,
      data32               => tex_in0 & tex_in4,  
      palette16            => unsigned(tex_data(4)),     
      
      -- synthesis translate_off
      addr_base_1          => addr_base_1,       
      tex_palette_addr     => tex_addr(4),
                                            
      export_TexFt_addr    => exportNext_TexFt_addr(0), 
      export_TexFt_data    => exportNext_TexFt_data(0), 
      export_TexFt_db1     => exportNext_TexFt_db1(0),  
      export_TexFt_db3     => exportNext_TexFt_db3(0),  
      -- synthesis translate_on
      
      tex_color            => tex_color(0)
   );
   
   iRDP_TexSingle1 : entity work.RDP_TexSingle
   port map
   (
      clk1x                => clk1x,              
      trigger              => trigger,            
                                             
      error_texMode        => open,      
                                             
      settings_otherModes  => settings_otherModes,
      settings_tile        => settings_tile,      
                                            
      data4                => tex4_1,
      data8                => tex8_1,
      data16               => tex_in1,
      data32               => tex_in1 & tex_in5,  
      palette16            => unsigned(tex_data(5)),     
      
      -- synthesis translate_off
      addr_base_1          => addr_base_1,       
      tex_palette_addr     => tex_addr(5),
                                            
      export_TexFt_addr    => exportNext_TexFt_addr(1), 
      export_TexFt_data    => exportNext_TexFt_data(1), 
      export_TexFt_db1     => exportNext_TexFt_db1(1),  
      export_TexFt_db3     => exportNext_TexFt_db3(1),  
      -- synthesis translate_on
      
      tex_color            => tex_color(1)
   );
   
   iRDP_TexSingle2 : entity work.RDP_TexSingle
   port map
   (
      clk1x                => clk1x,              
      trigger              => trigger,            
                                             
      error_texMode        => open,      
                                             
      settings_otherModes  => settings_otherModes,
      settings_tile        => settings_tile,      
                                            
      data4                => tex4_2,
      data8                => tex8_2,
      data16               => tex_in2,
      data32               => tex_in2 & tex_in6,  
      palette16            => unsigned(tex_data(6)),     
      
      -- synthesis translate_off
      addr_base_1          => addr_base_1N,       
      tex_palette_addr     => tex_addr(6),
                                            
      export_TexFt_addr    => exportNext_TexFt_addr(2), 
      export_TexFt_data    => exportNext_TexFt_data(2), 
      export_TexFt_db1     => exportNext_TexFt_db1(2),  
      export_TexFt_db3     => exportNext_TexFt_db3(2),  
      -- synthesis translate_on
      
      tex_color            => tex_color(2)
   );
   
   iRDP_TexSingle3 : entity work.RDP_TexSingle
   port map
   (
      clk1x                => clk1x,              
      trigger              => trigger,            
                                             
      error_texMode        => open,      
                                             
      settings_otherModes  => settings_otherModes,
      settings_tile        => settings_tile,      
                                            
      data4                => tex4_3,
      data8                => tex8_3,
      data16               => tex_in3,
      data32               => tex_in3 & tex_in7,  
      palette16            => unsigned(tex_data(7)),     
      
      -- synthesis translate_off
      addr_base_1          => addr_base_1N,       
      tex_palette_addr     => tex_addr(7),
                                            
      export_TexFt_addr    => exportNext_TexFt_addr(3), 
      export_TexFt_data    => exportNext_TexFt_data(3), 
      export_TexFt_db1     => exportNext_TexFt_db1(3),  
      export_TexFt_db3     => exportNext_TexFt_db3(3),  
      -- synthesis translate_on
      
      tex_color            => tex_color(3)
   );
   
   -- filtering 
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (trigger = '1') then
         
            frac_S_2 <= '0' & signed(frac_S_1);
            frac_T_2 <= '0' & signed(frac_T_1);
            
            texmode <= TEXMODE_UNFILTERED;
            if (DISABLEFILTER = '0' and (settings_otherModes.sampleType = '1' or settings_otherModes.enTlut = '1')) then
               if (to_integer(frac_S_1) + to_integer(frac_T_1) >= 16#20#) then
                  texmode <= TEXMODE_UPPER;
                  frac_S_2 <= to_signed(16#20#, 6) - ('0' & signed(frac_S_1));
                  frac_T_2 <= to_signed(16#20#, 6) - ('0' & signed(frac_T_1));
               else
                  texmode <= TEXMODE_LOWER;
               end if;
            end if;
         
         end if;
      
      end if;
   end process;
   
   filter_sub1_a <= tex_color(2) when (texmode(0) = '0') else tex_color(1);
   filter_sub1_b <= tex_color(3) when (texmode(0) = '0') else tex_color(0);
   filter_sub2_a <= tex_color(1) when (texmode(0) = '0') else tex_color(2);
   filter_sub2_b <= tex_color(3) when (texmode(0) = '0') else tex_color(0);
   
   process (all)
   begin
      for i in 0 to 3 loop
      
         filter_sub1(i) <= ("00" & signed(filter_sub1_a(i))) - ("00" & signed(filter_sub1_b(i)));
         filter_sub2(i) <= ("00" & signed(filter_sub2_a(i))) - ("00" & signed(filter_sub2_b(i)));
         
         filter_mul1(i) <= frac_S_2 * filter_sub1(i);
         filter_mul2(i) <= frac_T_2 * filter_sub2(i);
         
         filter_sum1(i)  <= filter_mul1(i) + filter_mul2(i) + to_signed(16#10#, 16);
         filter_sum2(i)  <= (3x"0" & signed(filter_sub1_b(i))) + filter_sum1(i)(15 downto 5);
         
      end loop;
   end process;
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (trigger = '1') then
         
            if (texmode = TEXMODE_UNFILTERED) then
               tex_color_out(0) <= tex_color(0)(0);
               tex_color_out(1) <= tex_color(0)(1);
               tex_color_out(2) <= tex_color(0)(2);
               tex_alpha_out    <= tex_color(0)(3);
            else
               tex_color_out(0) <= unsigned(filter_sum2(0)(7 downto 0));
               tex_color_out(1) <= unsigned(filter_sum2(1)(7 downto 0));
               tex_color_out(2) <= unsigned(filter_sum2(2)(7 downto 0));
               tex_alpha_out    <= unsigned(filter_sum2(3)(7 downto 0));
            end if;
            
            
            -- synthesis translate_off
            export_TexFt_addr <= exportNext_TexFt_addr; 
            export_TexFt_data <= exportNext_TexFt_data; 
            export_TexFt_db1  <= exportNext_TexFt_db1; 
            export_TexFt_db3  <= exportNext_TexFt_db3; 
            export_TexFt_mode <= texmode;
            -- synthesis translate_on
         
         end if;
      
      end if;
   end process;
   
   -- copy mode data
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (trigger = '1') then
            
            if (settings_otherModes.enTlut = '1') then
               tex_copy(15 downto  0) <= unsigned(tex_data(7));
               tex_copy(31 downto 16) <= unsigned(tex_data(6));
               tex_copy(47 downto 32) <= unsigned(tex_data(5));
               tex_copy(63 downto 48) <= unsigned(tex_data(4));
            else
               tex_copy <= tex_copy_read;
            end if;
         
         end if;
      
      end if;
   end process;
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
   
         if (trigger = '1') then
         
            tex_copy_read(15 downto  0) <= tex_in3;
            tex_copy_read(31 downto 16) <= tex_in2;
            tex_copy_read(47 downto 32) <= tex_in1;
            tex_copy_read(63 downto 48) <= tex_in0;
            
         end if;
      end if;
   end process;
   
   
end architecture;





