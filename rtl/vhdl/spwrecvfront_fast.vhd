--
--  Front-end for SpaceWire Receiver
--
--  This entity samples the input signals DataIn and StrobeIn to detect
--  valid bit transitions. Received bits are handed to the application
--  in groups of "rxchunk" bits at a time, synchronous to the system clock.
--
--  This receiver is based on synchronous oversampling of the input signals.
--  Inputs are sampled on the rising and falling edges of an externally
--  supplied sample clock "rxclk". Therefore the maximum bitrate of the
--  incoming signal must be significantly lower than two times the "rxclk"
--  clock frequency. The maximum incoming bitrate must also be strictly
--  lower than rxchunk times the system clock frequency.
--
--  This code is tuned for implementation on Xilinx Spartan-3.
--
--  Details
--  -------
--
--  Stage A: The inputs "spw_di" and "spw_si" are handled as DDR signals,
--  synchronously sampled on both edges of "rxclk".
--
--  Stage B: The input signals are re-registered on the rising edge of "rxclk"
--  for further processing. This implies that every rising edge of "rxclk"
--  produces two new samples of "spw_di" and two new samples of "spw_si".
--  Some preparation is done for data/strobe decoding.
--
--  Stage C: Transitions in input signals are detected by comparing the XOR
--  of data and strobe to the XOR of the previous data and strobe samples.
--  If there is a difference, we know that either data or strobe has changed
--  and the new value of data is a valid new bit. Every rising edge of "rxclk"
--  thus produces either zero, one or two new data bits.
--
--  Received data bits are pushed into a cyclic buffer. A two-hot array marks
--  the two positions where the next received bits will go into the buffer.
--  In addition, a 4-step gray-encoded counter "headptr" indicates the current
--  position in the cyclic buffer.
--
--  The contents of the cyclic buffer and the head pointer are re-registered
--  on the rising edge of the system clock. A binary counter "tailptr" points
--  to next group of bits to read from the cyclic buffer. A comparison between
--  "tailptr" and "headptr" determines whether those bits have already been
--  received and safely stored in the buffer.
--
--  Implementation guidelines 
--  -------------------------
--
--  IOB flip-flops must be used to sample spw_di and spw_si.
--  Clock skew between the IOBs for spw_di and spw_si must be minimized.
--
--  "rxclk" must be at least as fast as the system clock;
--  "rxclk" does not need to be phase-related to the system clock;
--  it is allowed for "rxclk" to be equal to the system clock.
--
--  The following timing constraints are needed:
--   * PERIOD constraint on the system clock;
--   * PERIOD constraint on "rxclk";
--   * FROM-TO constraint from "rxclk" to system clock, equal to one "rxclk" period;
--   * FROM-TO constraint from system clock to "rxclk", equal to one "rxclk" period.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spwrecvfront_fast is

    generic (
        -- Number of bits to pass to the application per system clock.
        rxchunk:        integer range 1 to 4 );

    port (
        -- System clock.
        clk:        in  std_logic;

        -- Sample clock.
        rxclk:      in  std_logic;

        -- High to enable receiver; low to disable and reset receiver.
        rxen:       in  std_logic;

        -- High if there has been recent activity on the input lines.
        inact:      out std_logic;

        -- High if inbits contains a valid group of received bits.
        -- If inbvalid='1', the application must sample inbits on
        -- the rising edge of clk.
        inbvalid:   out std_logic;

        -- Received bits (bit 0 is the earliest received bit).
        inbits:     out std_logic_vector(rxchunk-1 downto 0);

        -- Data In signal from SpaceWire bus.
        spw_di:     in  std_logic;

        -- Strobe In signal from SpaceWire bus.
        spw_si:     in  std_logic );

    -- Turn off FSM extraction.
    -- Without this, XST will happily apply one-hot encoding to rrx.headptr.
    attribute FSM_EXTRACT: string;
    attribute FSM_EXTRACT of spwrecvfront_fast: entity is "NO";

    -- Turn off register replication.
    -- Without this, XST will happily replicate my synchronization flip-flops.
    attribute REGISTER_DUPLICATION: string;
    attribute REGISTER_DUPLICATION of spwrecvfront_fast: entity is "FALSE";

end entity spwrecvfront_fast;

architecture spwrecvfront_arch of spwrecvfront_fast is

    -- size of the cyclic buffer in bits;
    -- typically 4 times rxchunk, except when rxchunk = 1
    type chunk_array_type is array(1 to 4) of integer;
    constant chunk_to_buflen: chunk_array_type := ( 8, 8, 12, 16 );
    constant c_buflen: integer := chunk_to_buflen(rxchunk);

    -- convert from straight binary to reflected binary gray code
    function gray_encode(b: in std_logic_vector) return std_logic_vector is
        variable g: std_logic_vector(b'high downto b'low);
    begin
        g(b'high) := b(b'high);
        for i in b'high-1 downto b'low loop
            g(i) := b(i) xor b(i+1);
        end loop;
        return g;
    end function;

    -- convert from reflected binary gray code to straight binary
    function gray_decode(g: in std_logic_vector) return std_logic_vector is
        variable b: std_logic_vector(g'high downto g'low);
    begin
        b(g'high) := g(g'high);
        for i in g'high-1 downto g'low loop
            b(i) := g(i) xor b(i+1);
        end loop;
        return b;
    end function;

    -- stage A: input flip-flops for rising/falling rxclk
    signal s_a_di0:     std_logic;
    signal s_a_di1:     std_logic;
    signal s_a_si0:     std_logic;
    signal s_a_si1:     std_logic;

    -- registers in rxclk domain
    type rxregs_type is record
        -- reset synchronizer
        reset:      std_logic_vector(1 downto 0);
        -- stage B: re-register input samples and prepare for data/strobe decoding
        b_di0:      std_ulogic;
        b_di1:      std_ulogic;
        b_si1:      std_ulogic;
        b_xor0:     std_ulogic;     -- b_xor0 = b_di0 xor b_si0
        -- stage C: after data/strobe decoding
        c_bit:      std_logic_vector(1 downto 0);
        c_val:      std_logic_vector(1 downto 0);
        c_xor1:     std_ulogic;
        -- cyclic bit buffer
        bufdata:    std_logic_vector(c_buflen-1 downto 0);  -- data bits
        bufmark:    std_logic_vector(c_buflen-1 downto 0);  -- two-hot, marking destination of next two bits
        headptr:    std_logic_vector(1 downto 0);           -- gray encoded head position
        headlow:    std_logic_vector(1 downto 0);           -- least significant bits of head position
        headinc:    std_ulogic;                             -- must update headptr on next clock
        -- activity detection
        bitcnt:     std_logic_vector(2 downto 0);           -- gray counter
    end record;

    -- registers in system clock domain
    type regs_type is record
        -- cyclic bit buffer, re-registered to the system clock
        bufdata:    std_logic_vector(c_buflen-1 downto 0);  -- data bits
        headptr:    std_logic_vector(1 downto 0);           -- gray encoded head position
        -- tail pointer (binary)
        tailptr:    std_logic_vector(2 downto 0);
        -- activity detection
        bitcnt:     std_logic_vector(2 downto 0);
        bitcntp:    std_logic_vector(2 downto 0);
        bitcntpp:   std_logic_vector(2 downto 0);
        -- output registers
        inact:      std_ulogic;
        inbvalid:   std_ulogic;
        inbits:     std_logic_vector(rxchunk-1 downto 0);
        rxen:       std_ulogic;
    end record;

    -- registers
    signal r, rin:      regs_type;
    signal rrx, rrxin:  rxregs_type;

    -- force use of IOB flip-flops
    attribute IOB: string;
    attribute IOB of s_a_di0: signal is "TRUE";
    attribute IOB of s_a_di1: signal is "TRUE";
    attribute IOB of s_a_si0: signal is "TRUE";
    attribute IOB of s_a_si1: signal is "TRUE";

begin

    -- sample inputs on rising edge of rxclk
    process (rxclk) is
    begin
        if rising_edge(rxclk) then
            s_a_di0     <= spw_di;
            s_a_si0     <= spw_si;
        end if;
    end process;

    -- sample inputs on falling edge of rxclk
    process (rxclk) is
    begin
        if falling_edge(rxclk) then
            s_a_di1     <= spw_di;
            s_a_si1     <= spw_si;
        end if;
    end process;

    -- combinatorial process
    process  (r, rrx, rxen, s_a_di0, s_a_di1, s_a_si0, s_a_si1)
        variable v:     regs_type;
        variable vrx:   rxregs_type;
        variable v_i:   integer range 0 to 7;
        variable v_tail: std_logic_vector(1 downto 0);
    begin
        v       := r;
        vrx     := rrx;
        v_i     := 0;
        v_tail  := (others => '0');

        -- ---- SAMPLE CLOCK DOMAIN ----

        -- stage B: re-register input samples
        vrx.b_di0   := s_a_di0;
        vrx.b_di1   := s_a_di1;
        vrx.b_xor0  := s_a_di0 xor s_a_si0;
        vrx.b_si1   := s_a_si1;

        -- stage C: decode data/strobe and detect valid bits
        if (rrx.b_xor0 xor rrx.c_xor1) = '1' then
            -- b_di0 is a valid new bit
            vrx.c_bit(0) := rrx.b_di0;
        else
            -- skip b_di0 and try b_di1
            vrx.c_bit(0) := rrx.b_di1;
        end if;
        vrx.c_bit(1) := rrx.b_di1;
        vrx.c_val(0) := (rrx.b_xor0 xor rrx.c_xor1) or  (rrx.b_di1 xor rrx.b_si1 xor rrx.b_xor0);
        vrx.c_val(1) := (rrx.b_xor0 xor rrx.c_xor1) and (rrx.b_di1 xor rrx.b_si1 xor rrx.b_xor0);
        vrx.c_xor1   := rrx.b_di1 xor rrx.b_si1;

        -- Note:
        -- c_val = "00" if no new bits are received
        -- c_val = "01" if one new bit is received; the new bit is in c_bit(0)
        -- c_val = "11" if two new bits are received

        -- Note:
        -- bufmark contains two '1' bits in neighbouring positions, marking
        -- the positions that newly received bits will be written to.

        -- Update the cyclic buffer.
        for i in 0 to c_buflen-1 loop
            -- update data bit at position (i)
            if rrx.bufmark(i) = '1' then
                if rrx.bufmark((i+1) mod rrx.bufmark'length) = '1' then
                    -- this is the first of the two marked positions;
                    -- put the first received bit here (if any)
                    vrx.bufdata(i) := rrx.c_bit(0);
                else
                    -- this is the second of the two marked positions;
                    -- put the second received bit here (if any)
                    vrx.bufdata(i) := rrx.c_bit(1);
                end if;
            end if;
            -- update marker at position (i)
            if rrx.c_val(0) = '1' then
                if rrx.c_val(1) = '1' then
                    -- shift two positions
                    vrx.bufmark(i) := rrx.bufmark((i+rrx.bufmark'length-2) mod rrx.bufmark'length);
                else
                    -- shift one position
                    vrx.bufmark(i) := rrx.bufmark((i+rrx.bufmark'length-1) mod rrx.bufmark'length);
                end if;
            end if;
        end loop;

        -- Update "headlow", the least significant bits of the head position.
        -- This is a binary counter from 0 to rxchunk-1, or from 0 to 1
        -- if rxchunk = 1. If the counter overflows, "headptr" will be
        -- updated in the next clock cycle.
        case rxchunk is
            when 1 | 2 =>
                -- count from "00" to "01"
                if rrx.c_val(1) = '1' then      -- got two new bits
                    vrx.headlow(0) := rrx.headlow(0);
                    vrx.headinc    := '1';
                elsif rrx.c_val(0) = '1' then   -- got one new bit
                    vrx.headlow(0) := not rrx.headlow(0);
                    vrx.headinc    := rrx.headlow(0);
                else                            -- got nothing
                    vrx.headlow(0) := rrx.headlow(0);
                    vrx.headinc    := '0';
                end if;
            when 3 =>
                -- count from "00" to "10"
                if rrx.c_val(1) = '1' then      -- got two new bits
                    case rrx.headlow is
                        when "00" =>   vrx.headlow := "10";
                        when "01" =>   vrx.headlow := "00";
                        when others => vrx.headlow := "01";
                    end case;
                    vrx.headinc := rrx.headlow(0) or rrx.headlow(1);
                elsif rrx.c_val(0) = '1' then   -- got one new bit
                    if rrx.headlow(1) = '1' then
                        vrx.headlow := "00";
                        vrx.headinc := '1';
                    else
                        vrx.headlow(0) := not rrx.headlow(0);
                        vrx.headlow(1) := rrx.headlow(0);
                        vrx.headinc    := '0';
                    end if;
                else                            -- got nothing
                    vrx.headlow := rrx.headlow;
                    vrx.headinc := '0';
                end if;
            when 4 =>
                -- count from "00" to "11"
                if rrx.c_val(1) = '1' then      -- got two new bits
                    vrx.headlow(0) := rrx.headlow(0);
                    vrx.headlow(1) := not rrx.headlow(1);
                    vrx.headinc    := rrx.headlow(1);
                elsif rrx.c_val(0) = '1' then   -- got one new bit
                    vrx.headlow(0) := not rrx.headlow(0);
                    vrx.headlow(1) := rrx.headlow(1) xor rrx.headlow(0);
                    vrx.headinc    := rrx.headlow(0) and rrx.headlow(1);
                else                            -- got nothing
                    vrx.headlow := rrx.headlow;
                    vrx.headinc := '0';
                end if;
        end case;

        -- Update the gray-encoded head position.
        if rrx.headinc = '1' then
            case rrx.headptr is
                when "00" =>   vrx.headptr := "01";
                when "01" =>   vrx.headptr := "11";
                when "11" =>   vrx.headptr := "10";
                when others => vrx.headptr := "00";
            end case;
        end if;

        -- Activity detection.
        if rrx.c_val(0) = '1' then
            vrx.bitcnt  := gray_encode(
                std_logic_vector(unsigned(gray_decode(rrx.bitcnt)) + 1));
        end if;

        -- Synchronize reset signal for rxclk domain.
        if r.rxen = '0' then
            vrx.reset   := "11";
        else
            vrx.reset   := "0" & rrx.reset(1);
        end if;

        -- Synchronous reset of rxclk domain.
        if rrx.reset(0) = '1' then
            vrx.bufmark := (0 => '1', 1 => '1', others => '0');
            vrx.headptr := "00";
            vrx.headlow := "00";
            vrx.headinc := '0';
            vrx.bitcnt  := "000";
        end if;

        -- ---- SYSTEM CLOCK DOMAIN ----

        -- Re-register cyclic buffer and head pointer in the system clock domain.
        v.bufdata   := rrx.bufdata;
        v.headptr   := rrx.headptr;

        -- Increment tailptr if there was new data on the previous clock.
        if r.inbvalid = '1' then
            v.tailptr   := std_logic_vector(unsigned(r.tailptr) + 1);
        end if;

        -- Compare tailptr to headptr to decide whether there is new data.
        -- If the values are equal, we are about to read data which were not
        -- yet released by the rxclk domain
        -- Note: headptr is gray-coded while tailptr is normal binary.
        if rxchunk = 1 then
            -- headptr counts blocks of 2 bits while tailptr counts single bits
            v_tail      := v.tailptr(2 downto 1);
        else
            -- headptr and tailptr both count blocks of rxchunk bits
            v_tail      := v.tailptr(1 downto 0);
        end if;
        if (r.headptr(1) = v_tail(1)) and
           ((r.headptr(0) xor r.headptr(1)) = v_tail(0)) then
            -- pointers have the same value
            v.inbvalid  := '0';
        else
            v.inbvalid  := '1';
        end if;
       
        -- Multiplex bits from the cyclic buffer into the output register.
        if rxen = '1' then
            if rxchunk = 1 then
                -- cyclic buffer contains 8 slots of 1 bit wide
                v_i         := to_integer(unsigned(v.tailptr));
                v.inbits    := r.bufdata(v_i downto v_i);
            else
                -- cyclic buffer contains 4 slots of rxchunk bits wide
                v_i         := to_integer(unsigned(v.tailptr(1 downto 0)));
                v.inbits    := r.bufdata(rxchunk*v_i+rxchunk-1 downto rxchunk*v_i);
            end if;
        end if;

        -- Activity detection.
        v.bitcnt    := rrx.bitcnt;
        v.bitcntp   := r.bitcnt;
        v.bitcntpp  := r.bitcntp;
        if rxen = '1' then
            if r.bitcntp = r.bitcntpp then
                v.inact     := r.inbvalid;
            else
                v.inact     := '1';
            end if;
        end if;

        -- Synchronous reset of system clock domain.
        if rxen = '0' then
            v.tailptr   := "000";
            v.inact     := '0';
            v.inbvalid  := '0';
            v.inbits    := (others => '0');
        end if;

        -- Register rxen to ensure glitch-free signal to rxclk domain
        v.rxen      := rxen;

        -- drive outputs
        inact       <= r.inact;
        inbvalid    <= r.inbvalid;
        inbits      <= r.inbits;

        -- update registers
        rrxin       <= vrx;
        rin         <= v;

    end process;

    -- update registers on rising edge of rxclk
    process (rxclk) is
    begin
        if rising_edge(rxclk) then
            rrx <= rrxin;
        end if;
    end process;

    -- update registers on rising edge of system clock
    process (clk) is
    begin
        if rising_edge(clk) then
            r <= rin;
        end if;
    end process;

end architecture spwrecvfront_arch;
