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
 -- Параметры кадра
     generic (
         HAV : integer := 640; -- активная часть по горизонтали
         HFP : integer := 16; -- отступ по горизонтали справа
         HSP : integer := 96; -- отступ по горизонтали на синхронизацию (hsync = 0)
         HBP : integer := 48; -- отступ по горизонтали слева
         
         VAV : integer := 480; -- активная часть по вертикали
         VFP : integer := 10; -- отступ по вертикали снизу
         VSP : integer := 2; -- отступ по вертикали на синхронизацию (vsync = 0)
         VBP : integer := 33; -- отступ по вертикали сверху
         
         HPL : std_logic := '0';
         VPL : std_logic := '0';
         
         -- минимальное количество значение для запроса данных.
         INT_REQ : integer := 2--2048
         );
 -- Порты
 port(
 -- сигнал синхронизации и сброса.
 -- !!! сброс синхронный с активным низким уровнем.
     clk : in std_logic;
     reset_n : in std_logic;
     
     -- шина AXIS
     axis_data : in std_logic_vector(15 downto 0);
     axis_valid : in std_logic;
     axis_tready : out std_logic := '0';
     
     -- счетчик данных в FIFO
     fifo_data_c : in std_logic_vector(31 downto 0);
     
     -- сигнал прерывания
     int_r : out std_logic := '0';
     
     -- интерфейс VGA 
     vga_red : out std_logic_vector(3 downto 0);
     vga_green : out std_logic_vector(3 downto 0);
     vga_blue : out std_logic_vector(3 downto 0);
     vga_hsync : out std_logic;
     vga_vsync : out std_logic
 );
end AXIS2VGA_IP;

architecture AXIS2VGA_IP_arch of AXIS2VGA_IP is
 -- эти атрибуты позволят Vivado в дальнейшем автоматический обнаружить 
 -- сигналы шины AXIS, и понять что это именно шина, а на отдельные сигналы.
    ATTRIBUTE X_INTERFACE_INFO : STRING;
    ATTRIBUTE X_INTERFACE_INFO of axis_data: SIGNAL is
    "xilinx.com:interface:axis:1.0 AXIS_S TDATA";
    ATTRIBUTE X_INTERFACE_INFO of axis_valid: SIGNAL is
    "xilinx.com:interface:axis:1.0 AXIS_S TVALID";
    ATTRIBUTE X_INTERFACE_INFO of axis_tready: SIGNAL is
    "xilinx.com:interface:axis:1.0 AXIS_S TREADY";
    ---------------------------------------------------------------------------
    -- Константы с максимальными размерами по горизонтали и вертикали.
    -- Для удобства дальнейшего объявления и работы с сигналами.
    constant H_MAX : integer := HAV + HBP + HFP + HSP;
    constant V_MAX : integer := VAV + VBP + VFP + VSP;
    
    -- Константы активной части кадра
    constant HAV_START : integer := HSP + HBP;
    constant HAV_END : integer := HAV + HSP + HBP;
    constant VAV_START : integer := VSP + VBP;
    constant VAV_END : integer := VAV + VSP + VBP;
    
    -- константы для цветов
    constant COLOR_RED : std_logic_vector(11 downto 0) := "1111" & "0000" & "0000"; -- стена
    constant COLOR_YELLOW : std_logic_vector(11 downto 0) := "1111" & "1111" & "0000"; -- игрок
    constant COLOR_WHITE : std_logic_vector(11 downto 0) := "1111" & "1111" & "1111"; -- снаряд
    constant COLOR_GREEN : std_logic_vector(11 downto 0) := "0000" & "1111" & "0000"; -- враг
    constant COLOR_GRAY : std_logic_vector(11 downto 0) := "1000" & "1000" & "1000"; -- враг
    constant COLOR_BLACK : std_logic_vector(11 downto 0) := "0000" & "0000" & "0000"; -- пустота
    
    -- максимально возможное количество динамических объектов в кадре
    constant MAX_SPRITES_COUNT : integer := 16;
    
    -- размер тайла в пикселях
    constant TILE_SIZE : integer := 16;
    
    -- количество возможных текстур (типов объектов)
    constant OBJECT_TYPES_COUNT : integer := 16;
    
    ---------------------------------------------------------------------------
    -- автомат состояний. Для описания автомата создаем свой перечисляемый тип.
--    type state_s is (
--        IDEL, -- состояние после сброса
--        SKIP, -- пропуск пикселей до нового кадра
--        WAIT_AV, -- ожидание начала активного кадра
--        SEND -- передача данных
--    );
    
--    type state_s is (
--        IDLE, -- состояние после сброса
--        SKIP, -- пропуск объектов до нового пакета
--        GET_OBJECT_H, -- получение координат объекта по горизонтали
--        GET_OBJECT_V, -- получение координат объекта по вертикали
--        SEND -- отправка сформированного кадра
--    );

    type state_s is (
        IDLE,  -- состояние после сброса
        SKIP, -- пропуск объектов до нового пакета
        READ_DYNAMIC, -- получение спрайтов в кадре
        READ_STATIC, -- получение статических тайлов в кадре
        SEND -- получение тайлов и отправка формируемого на лету кадра
    );
    
    signal state, next_state : state_s := IDLE;
    
    ---------------------------------------------------------------------------
    -- счетчики пикселей
    signal h_cnt : integer range 0 to H_MAX-1 := 0;
    signal v_cnt : integer range 0 to V_MAX-1 := 0;
    
    -- счетчики координат активной карты
    signal x_cnt : integer range 0 to HAV-1 := 0;
    signal y_cnt : integer range 0 to VAV-1 := 0;
    
    -- флаг активной части кадра.
    signal av : std_logic;
    signal av_d : std_logic;
     
    alias next_f : std_logic is axis_data(15);
    alias is_object : std_logic is axis_data(14);
    alias object_type : std_logic_vector is axis_data(13 downto 11);
    alias color: std_logic is axis_data(10);
    alias cord: std_logic_vector is axis_data(9 downto 0);
    
    -- текстуры тайлов
    type TILE_TEXTURES_T is array(0 to OBJECT_TYPES_COUNT-1, 0 to TILE_SIZE-1, 0 to TILE_SIZE-1) of std_logic_vector(11 downto 0);
    signal tile_textures : TILE_TEXTURES_T := (
        1 => (others => (others => (others => '1'))),
        others => (others => (others => (others => '0')))
    );
    
    -- сами тайлы
    type TILES_T is array(0 to 39, 0 to 29) of integer;
    signal tiles : TILES_T := (others => (others => 0));
    signal static_counter_x : integer range 0 to 39 := 0;
    signal static_counter_y : integer range 0 to 29 := 0;
    
    type SPRITES is array (0 to MAX_SPRITES_COUNT-1) of std_logic_vector(9 downto 0);
    type OBJECT_TYPES is array(0 to MAX_SPRITES_COUNT-1) of std_logic_vector(2 downto 0);
    
    signal sprites_xs : SPRITES := (others => (others => '0'));
    signal sprites_ys : SPRITES := (others => (others => '0'));
    signal sprites_types : OBJECT_TYPES := (others => (others => '0'));
    
    -- счетчик количества динамических объектов для записи их координат в sprites_xs, sprites_ys
    signal dynamic_counter: integer range 0 to MAX_SPRITES_COUNT-1 := 0;
    
    -- flip flop для записи в sprites_xs или sprites_ys
    signal is_cord_y : std_logic := '0';
    
    signal current_pixel : std_logic_vector(11 downto 0) := "0000" & "0000" & "0000";
    
    
    begin
        -- регистр автомата состояний
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
        
        -- КС на входе автомата состояний, формирующая следующее состояние
        next_state_p : process(clk, state, axis_valid) 
            variable tile_x : integer range 0 to 39;
            variable tile_y : integer range 0 to 29;
            variable x_logic: std_logic_vector(9 downto 0);
            variable y_logic: std_logic_vector(9 downto 0);
            variable current_pixel : std_logic_vector(11 downto 0);
            variable current_tile: integer range 0 to OBJECT_TYPES_COUNT-1;
            variable tile_offset_x : integer range 0 to TILE_SIZE-1;
            variable tile_offset_y : integer range 0 to TILE_SIZE-1;
            
        begin
            if clk'event and clk = '1' then
                case state is 
                    -- из исходного состояния сразу переходим в состояние 
                    -- поиска начала кадра во входном потоке
                    when IDLE =>
                        state <= SKIP;
                    -- когда нашли начало пакета, переходим к получению динамических объектов
                    when SKIP =>
                        if next_f = '1' and axis_valid = '1' then 
                            state <= READ_DYNAMIC;
                        else
                            state <= SKIP;
                        end if;
                    -- когда получили горизонтальную координату, переходим к получению вертикальной координаты
                    when READ_DYNAMIC =>
                        if next_f = '1' and axis_valid = '1' and dynamic_counter < MAX_SPRITES_COUNT then 
                            if is_cord_y = '1' then
                                sprites_ys(dynamic_counter) <= cord;
                            else 
                                sprites_xs(dynamic_counter) <= cord;
                            end if;
                            
                            sprites_types(dynamic_counter) <= object_type;
                            is_cord_y <= not is_cord_y;
                            dynamic_counter <= dynamic_counter + 1;
                        else 
                            state <= READ_STATIC;
                            dynamic_counter <= 0;
                        end if;
                    when READ_STATIC =>
                        if next_f = '1' and axis_valid = '1' then 
                            tiles(static_counter_x, static_counter_y) <= conv_integer(object_type);
                            
                            if static_counter_x = 39 then
                                static_counter_y <= static_counter_y + 1;
                                static_counter_x <= 0;
                            else
                                static_counter_x <= static_counter_x + 1;
                            end if;
                            
                        else
                            state <= SEND;
                        end if;
                    when SEND =>
                        if next_f = '1' and axis_valid = '1' then
                            -- todo проверять, есть ли пересечение с динамическим объектом                
                            if av = '1' then 
                                -- передаём очередной пиксель из кадра
                                x_logic := std_logic_vector(to_unsigned(x_cnt, 10));
                                y_logic := std_logic_vector(to_unsigned(y_cnt, 10));
                                
                                tile_x := conv_integer(x_logic(9 downto 4));
                                tile_y := conv_integer(y_logic(9 downto 4));
                                
                                current_tile := tiles(tile_x, tile_y);
                                
                                tile_offset_x := conv_integer(x_logic(3 downto 0));
                                tile_offset_y := conv_integer(y_logic(3 downto 0));
                                
                                current_pixel := tile_textures(current_tile, tile_offset_x, tile_offset_y);
                                
                                vga_red <= current_pixel(11 downto 8);
                                vga_green <= current_pixel(7 downto 4);
                                vga_blue <= current_pixel(3 downto 0);
                                
                                
                                if x_cnt = HAV-1 then 
                                    y_cnt <= y_cnt + 1;
                                    x_cnt <= 0;
                                else
                                    x_cnt <= x_cnt + 1;
                                end if;
                                
--                                vga_red <=                        std_logic_vector(to_unsigned(y_cnt(9 downto 4), 6)) , x_cnt, y_cnt)(11 downto 8);
--                                vga_green <= tile_textures(conv_integer(object_type), x_cnt, y_cnt)(7 downto 4);
--                                vga_blue <= tile_textures(conv_integer(object_type), x_cnt, y_cnt)(3 downto 0);
                            else 
                                -- иначе мы находимся вне активной зоны, передаём нули
                                vga_red <= "0000";
                                vga_green <= "0000";
                                vga_blue <= "0000";
                            end if;
                        end if;
    
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
                        
                        
                end case;
            else 
                if reset_n = '0' then
                    state <= IDLE;
                end if;
            end if;
        end process next_state_p;
        
        ---------------------------------------------------------------------------
        -- счетчики пикселей и строк. По ним формируются сигналы синхронизации и 
        -- вспомогательные флаги, такие как av.
        -- ПОКА оставим так. Может, нужна для передачи кадра
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
--    --регистр автомата состояний
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
    
--    -- КС на входе автомата состояний, формирующая следующее состояние.
--    next_state_p : process(state,first_f,h_cnt,v_cnt,axis_valid)
--    begin
--        case state is
--        -- из исходного состояния сразу переходим в состояние 
--        -- поиска начала кадра во входном потоке
--            when IDEL =>
--                next_state <= SKIP;

--        -- когда нашли первый пиксель переходим к ожиданию начала 
--        -- активной части кадра.
--            when SKIP =>
--                if first_f = '1' and axis_valid = '1' then
--                    next_state <= WAIT_AV;
--                else
--                    next_state <= SKIP;
--                end if;

--            -- после начала активной части кадра переходим в состояние 
--            -- отправки кадра
--            when WAIT_AV => 
--                if h_cnt = HAV_START-1 and v_cnt = VAV_START then
--                    next_state <= SEND;
--                else
--                    next_state <= WAIT_AV;
--            end if;
    
--            -- после завершения передачи кадра снова ищем начало 
--            -- следующего во входном потоке. Так же если неожиданно кончились данные.
--            when SEND =>
--                if (h_cnt = HAV_END and v_cnt = VAV_END) or axis_valid = '0' then
--                    next_state <= SKIP;
--                else
--                    next_state <= SEND;
--                end if;
--        end case;
--    end process next_state_p;
    
--    ---------------------------------------------------------------------------
--    -- счетчики пикселей и строк. По ним формируются сигналы синхронизации и 
--    -- вспомогательные флаги, такие как av.
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
    
    -- сигналы синхронизации
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
    -- формирование сигнала прерывания
    int_r <= '1' when conv_integer(fifo_data_c) < INT_REQ and reset_n = '1' else '0';
--    int_r <= '1' when conv_integer(fifo_data_c) < INT_REQ else '0';
end AXIS2VGA_IP_arch;
