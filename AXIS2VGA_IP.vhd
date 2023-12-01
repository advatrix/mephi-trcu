----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10/06/2023 05:01:36 PM
-- Design Name: 
-- Module Name: AXIS2VGA_IP - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_unsigned.ALL;
USE ieee.numeric_std.ALL;

entity AXIS2VGA_IP is
 -- ��������� �����
     generic (
         HAV : integer := 640; -- �������� ����� �� �����������
         HFP : integer := 16; -- ������ �� ����������� ������
         HSP : integer := 96; -- ������ �� ����������� �� ������������� (hsync = 0)
         HBP : integer := 48; -- ������ �� ����������� �����
         
         VAV : integer := 480; -- �������� ����� �� ���������
         VFP : integer := 10; -- ������ �� ��������� �����
         VSP : integer := 2; -- ������ �� ��������� �� ������������� (vsync = 0)
         VBP : integer := 33; -- ������ �� ��������� ������
         
         HPL : std_logic := '0';
         VPL : std_logic := '0';
         
         -- ����������� ���������� �������� ��� ������� ������.
         INT_REQ : integer := 2--2048
         );
 -- �����
 port(
 -- ������ ������������� � ������.
 -- !!! ����� ���������� � �������� ������ �������.
     clk : in std_logic;
     reset_n : in std_logic;
     
     -- ���� AXIS
     axis_data : in std_logic_vector(15 downto 0);
     axis_valid : in std_logic;
     axis_tready : out std_logic := '0';
     
     -- ������� ������ � FIFO
     fifo_data_c : in std_logic_vector(31 downto 0);
     
     -- ������ ����������
     int_r : out std_logic := '0';
     
     -- ��������� VGA 
     vga_red : out std_logic_vector(3 downto 0);
     vga_green : out std_logic_vector(3 downto 0);
     vga_blue : out std_logic_vector(3 downto 0);
     vga_hsync : out std_logic;
     vga_vsync : out std_logic
 );
end AXIS2VGA_IP;

architecture AXIS2VGA_IP_arch of AXIS2VGA_IP is
 -- ��� �������� �������� Vivado � ���������� �������������� ���������� 
 -- ������� ���� AXIS, � ������ ��� ��� ������ ����, � �� ��������� �������.
    ATTRIBUTE X_INTERFACE_INFO : STRING;
    ATTRIBUTE X_INTERFACE_INFO of axis_data: SIGNAL is
    "xilinx.com:interface:axis:1.0 AXIS_S TDATA";
    ATTRIBUTE X_INTERFACE_INFO of axis_valid: SIGNAL is
    "xilinx.com:interface:axis:1.0 AXIS_S TVALID";
    ATTRIBUTE X_INTERFACE_INFO of axis_tready: SIGNAL is
    "xilinx.com:interface:axis:1.0 AXIS_S TREADY";
    ---------------------------------------------------------------------------
    -- ��������� � ������������� ��������� �� ����������� � ���������.
    -- ��� �������� ����������� ���������� � ������ � ���������.
    constant H_MAX : integer := HAV + HBP + HFP + HSP;
    constant V_MAX : integer := VAV + VBP + VFP + VSP;
    
    -- ��������� �������� ����� �����
    constant HAV_START : integer := HSP + HBP;
    constant HAV_END : integer := HAV + HSP + HBP;
    constant VAV_START : integer := VSP + VBP;
    constant VAV_END : integer := VAV + VSP + VBP;
    
    -- ��������� ��� ����� �������� � �����
    constant PLAYER : integer := 0;
    constant ENEMY : integer := 1;
    constant BULLET : integer := 2;
    constant WALL : integer := 3;
    
    -- ��������� ��� ����������� ������� � �����
    constant UP : integer := 0;
    constant RIGHT : integer := 1;
    constant DOWN : integer := 2;
    constant LEFT : integer := 3;
    
    -- ��������� ��� ������
    constant COLOR_RED : std_logic_vector(11 downto 0) := "1111" & "0000" & "0000"; -- �����
    constant COLOR_YELLOW : std_logic_vector(11 downto 0) := "1111" & "1111" & "0000"; -- �����
    constant COLOR_WHITE : std_logic_vector(11 downto 0) := "1111" & "1111" & "1111"; -- ������
    constant COLOR_GREEN : std_logic_vector(11 downto 0) := "0000" & "1111" & "0000"; -- ����
    constant COLOR_GRAY : std_logic_vector(11 downto 0) := "1000" & "1000" & "1000"; -- ����
    constant COLOR_BLACK : std_logic_vector(11 downto 0) := "0000" & "0000" & "0000"; -- �������
    
    ---------------------------------------------------------------------------
    -- ������� ���������. ��� �������� �������� ������� ���� ������������� ���.
--    type state_s is (
--        IDEL, -- ��������� ����� ������
--        SKIP, -- ������� �������� �� ������ �����
--        WAIT_AV, -- �������� ������ ��������� �����
--        SEND -- �������� ������
--    );
    
    type state_s is (
        IDLE, -- ��������� ����� ������
        SKIP, -- ������� �������� �� ������ ������
        GET_OBJECT_H, -- ��������� ��������� ������� �� �����������
        GET_OBJECT_V, -- ��������� ��������� ������� �� ���������
        SEND -- �������� ��������������� �����
    );
    
    signal state, next_state : state_s := IDLE;
    
    ---------------------------------------------------------------------------
    -- �������� ��������
    signal h_cnt : integer range 0 to H_MAX-1 := 0;
    signal v_cnt : integer range 0 to V_MAX-1 := 0;
    
    -- ���� �������� ����� �����.
    signal av : std_logic;
    signal av_d : std_logic;
    
    -- ��������, ����������� �������������� signal 
    signal object_type : integer range 0 to 15 := 0;
    signal object_direction : integer range 0 to 15 := 0;
    signal object_cord_h : integer range 0 to 1023 := 0;
    signal object_cord_v: integer range 0 to 1023 := 0;
    
    
    -- �������� ��� �������� ������� ������� ������
    
--    alias first_f : std_logic is axis_data(13);
--    alias finish_f : std_logic is axis_data(12);
--    alias red : std_logic_vector(3 downto 0) is axis_data(11 downto 8);
--    alias green : std_logic_vector(3 downto 0) is axis_data(7 downto 4);
--    alias blue : std_logic_vector(3 downto 0) is axis_data(3 downto 0);
    
    alias next_f : std_logic is axis_data(15);
    alias object_type_or_direction_raw : std_logic_vector(3 downto 0) is axis_data(14 downto 11);
    alias object_cord_axis : std_logic is axis_data(10);
    alias object_cord_raw : std_logic_vector(9 downto 0) is axis_data(9 downto 0);
    
    -- �������� ����� ��������� � ����...
    
    -- ������� ��� �������� �������� ������������ �����
    type FRAME is array (0 to HAV-1, 0 to VAV-1) of std_logic_vector(11 downto 0);
    signal frame_reg : FRAME := (others => (others => (others => '0')));
    
    signal current_pixel : std_logic_vector(11 downto 0) := "0000" & "0000" & "0000";
    
    begin
        -- ������� �������� ���������
--        state_p : process(clk) 
--        begin
--            if clk'event and clk = '1' then 
--                if reset_n = '0' then
--                    state <= IDLE;
----                else
----                    state <= next_state;
--                end if;
--            end if;
--        end process state_p;
        
        -- �� �� ����� �������� ���������, ����������� ��������� ���������
        next_state_p : process(clk, state, axis_valid) 
        begin
            if clk'event and clk = '1' then
                case state is 
                    -- �� ��������� ��������� ����� ��������� � ��������� 
                    -- ������ ������ ����� �� ������� ������
                    when IDLE =>
                        state <= SKIP;
                    -- ����� ����� ������ ������, ��������� � ��������� �������������� ���������� ������� �������
                    when SKIP =>
                        if next_f = '1' and axis_valid = '1' then 
                            state <= GET_OBJECT_H;
                        else
                            state <= SKIP;
                        end if;
                    -- ����� �������� �������������� ����������, ��������� � ��������� ������������ ����������
                    when GET_OBJECT_H =>
                        if next_f = '1' and axis_valid = '1' then 
                            object_cord_h <= to_integer(unsigned(object_cord_raw));
                            object_type <= to_integer(unsigned(object_type_or_direction_raw));
                            state <= GET_OBJECT_V;
                        else 
                            -- ��������, ��� ���� ���������� � ������ ���������, �������� SKIP, 
                            -- �� ���������, ����� �� ���� ���, ��� ����� ��������� �� �����
                            -- � � ������ ������ ����� ��������� ������������� �������
                            -- ������ �� ����� ������ �� ������� � ������� ���������, ���� ������ �����-�� �����
                            -- � ��� ��������� ���������� ������
                            --next_state <= GET_OBJECT_H;
                            -- ���� ��������� ���������� � ��������� SEND
                            state <= SEND;
                        end if;
                    -- ����� �������� ������������ ����������
                    when GET_OBJECT_V =>
                        if axis_valid = '1' then
                            object_cord_v <= to_integer(unsigned(object_cord_raw));
                            object_direction <= to_integer(unsigned(object_type_or_direction_raw));
                            
                            -- ������ ������������ ����������� ������� �� �����
                            case object_type is
                                when PLAYER =>
                                    -- � ����� ��� ���� ��������������� �������� ��������� ������ �����
                                    -- ������: ��� ������ �������?
                                        -- ���� �� ����� �����
                                    -- ��������� 10x10 �������� ������
                                    for i in 0 to 9 loop
                                        for j in 0 to 9 loop
                                            frame_reg(
                                                object_cord_h + i, 
                                                to_integer(unsigned(object_cord_raw)) + j
                                            ) <= COLOR_YELLOW;
                                        end loop;
                                    end loop;
                                    
                                when ENEMY =>
                                    for i in 0 to 9 loop
                                        for j in 0 to 9 loop
                                            frame_reg(
                                                object_cord_h + i, 
                                                to_integer(unsigned(object_cord_raw)) + j
                                            ) <= COLOR_GRAY;
                                        end loop;
                                    end loop;
                                when BULLET =>
                                    -- frame_reg[h][v] <- white
                                    frame_reg(object_cord_h, to_integer(unsigned(object_cord_raw))) <= COLOR_WHITE;
                                when WALL =>
                                    for i in 0 to 9 loop
                                        for j in 0 to 9 loop
                                            frame_reg(
                                                object_cord_h + i, 
                                                to_integer(unsigned(object_cord_raw)) + j
                                            ) <= COLOR_RED;
                                        end loop;
                                    end loop;
                                when others =>
                                    frame_reg(object_cord_h, to_integer(unsigned(object_cord_raw))) <= COLOR_BLACK;
                            end case;
                            -- ���� ���� ��� �������, ��������� � ��������� �������������� ���������� ���������� �������
                            if next_f = '1' then
                                state <= GET_OBJECT_H;
                            -- ���� ��� ������ ��������, ��������� � �������� ��������������� �����
                            else
                                state <= SEND;
                            end if;
                        else
                            state <= GET_OBJECT_V;
                        end if;
                    when SEND =>
                        -- ���� ���� �������� ��� �������, ��������� � �������� ���������� ������
                        if (h_cnt = HAV_END and v_cnt = VAV_END) then
                            state <= SKIP;
                        else
                            
                            if av = '1' then 
                                -- ������� ��������� ������� �� �����
                                vga_red <= frame_reg(h_cnt - HAV_START, v_cnt - VAV_START)(11 downto 8);
                                vga_green <= frame_reg(h_cnt - HAV_START, v_cnt - VAV_START)(7 downto 4);
                                vga_blue <= frame_reg(h_cnt - HAV_START, v_cnt - VAV_START)(3 downto 0);
                            else 
                                -- ����� �� ��������� ��� �������� ����, ������� ����
                                vga_red <= "0000";
                                vga_green <= "0000";
                                vga_blue <= "0000";
                            end if;
    
    --                            vga_red <= "0000";
    --                            vga_green <= "0000";
    --                            vga_blue <= "0000";
                            
                            if reset_n = '0' then
                                h_cnt <= 0;
                                v_cnt <= 0;
                            else
                                if h_cnt = H_MAX-1 then
                                    h_cnt <= 0;
                                    if v_cnt = V_MAX-1 then
                                        v_cnt <= 0;
                                    else
                                        v_cnt <= v_cnt + 1;
                                    end if;
                                else
                                    h_cnt <= h_cnt + 1;
                                end if;
                            end if;
                            
                            state <= SEND;
                        end if;
                        
                end case;
            else 
                if reset_n = '0' then
                    state <= IDLE;
                end if;
            end if;
        end process next_state_p;
        
        ---------------------------------------------------------------------------
        -- �������� �������� � �����. �� ��� ����������� ������� ������������� � 
        -- ��������������� �����, ����� ��� av.
        -- ���� ������� ���. �����, ����� ��� �������� �����
--        cnt_p : process(clk)
--        begin
--            if clk'event and clk = '1' then
--                if reset_n = '0' then
--                    h_cnt <= 0;
--                    v_cnt <= 0;
--                else
--                    if h_cnt = H_MAX-1 then
--                        h_cnt <= 0;
--                        if v_cnt = V_MAX-1 then
--                            v_cnt <= 0;
--                        else
--                            v_cnt <= v_cnt + 1;
--                        end if;
--                    else
--                        h_cnt <= h_cnt + 1;
--                    end if;
--                end if;
--            end if;
--        end process cnt_p;
        
    
--    -------------------------------------------------------------------------------
--    begin
--    -------------------------------------------------------------------------------
--    --������� �������� ���������
--    state_p : process(clk)
--    begin
--        if clk'event and clk = '1' then
--            if reset_n = '0' then
--                state <= IDEL;
--            else
--                state <= next_state;
--            end if;
--        end if;
--    end process state_p;
    
--    -- �� �� ����� �������� ���������, ����������� ��������� ���������.
--    next_state_p : process(state,first_f,h_cnt,v_cnt,axis_valid)
--    begin
--        case state is
--        -- �� ��������� ��������� ����� ��������� � ��������� 
--        -- ������ ������ ����� �� ������� ������
--            when IDEL =>
--                next_state <= SKIP;

--        -- ����� ����� ������ ������� ��������� � �������� ������ 
--        -- �������� ����� �����.
--            when SKIP =>
--                if first_f = '1' and axis_valid = '1' then
--                    next_state <= WAIT_AV;
--                else
--                    next_state <= SKIP;
--                end if;

--            -- ����� ������ �������� ����� ����� ��������� � ��������� 
--            -- �������� �����
--            when WAIT_AV => 
--                if h_cnt = HAV_START-1 and v_cnt = VAV_START then
--                    next_state <= SEND;
--                else
--                    next_state <= WAIT_AV;
--            end if;
    
--            -- ����� ���������� �������� ����� ����� ���� ������ 
--            -- ���������� �� ������� ������. ��� �� ���� ���������� ��������� ������.
--            when SEND =>
--                if (h_cnt = HAV_END and v_cnt = VAV_END) or axis_valid = '0' then
--                    next_state <= SKIP;
--                else
--                    next_state <= SEND;
--                end if;
--        end case;
--    end process next_state_p;
    
--    ---------------------------------------------------------------------------
--    -- �������� �������� � �����. �� ��� ����������� ������� ������������� � 
--    -- ��������������� �����, ����� ��� av.
--    cnt_p : process(clk)
--    begin
--        if clk'event and clk = '1' then
--            if reset_n = '0' then
--                h_cnt <= 0;
--                v_cnt <= 0;
--            else
--                if h_cnt = H_MAX-1 then
--                    h_cnt <= 0;
--                    if v_cnt = V_MAX-1 then
--                        v_cnt <= 0;
--                    else
--                        v_cnt <= v_cnt + 1;
--                    end if;
--                else
--                    h_cnt <= h_cnt + 1;
--                end if;
--            end if;
--        end if;
--    end process cnt_p;
    
    -- ������� �������������
    vga_hsync <= HPL when h_cnt < HSP else not HPL;
    vga_vsync <= VPL when v_cnt < VSP else not VPL;
    
    av <= '1' when h_cnt >= HAV_START
                and h_cnt < HAV_END 
                and v_cnt >= VAV_START 
                and v_cnt < VAV_END 
            else '0';
           
    av_d <= av when clk'event and clk = '1' else '0';
    
    ---------------------------------------------------------------------------
--    vga_red <= red when av_d = '1' and axis_valid = '1' else "0000";
--    vga_green <= green when av_d = '1' and axis_valid = '1' else "0000";
--    vga_blue <= blue when av_d = '1' and axis_valid = '1' else "0000";
    ---------------------------------------------------------------------------
    
--    axis_tready <= '1' when av = '1' and state = SEND else '1' when state = SKIP else '0'; 
--    axis_tready <= '1' when state = SKIP else '0'; 
      axis_tready <= '1';        
--    axis_tready <= '1' when state = SEND else '1' when state = SKIP else '0'; 

    ---------------------------------------------------------------------------
    -- ������������ ������� ����������
    int_r <= '1' when conv_integer(fifo_data_c) < INT_REQ and reset_n = '1' else '0';
--    int_r <= '1' when conv_integer(fifo_data_c) < INT_REQ else '0';
end AXIS2VGA_IP_arch;
