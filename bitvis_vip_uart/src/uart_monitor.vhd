--================================================================================================================================
-- Copyright 2024 UVVM
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and in the provided LICENSE.TXT.
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and limitations under the License.
--================================================================================================================================
-- Note : Any functionality not explicitly described in the documentation is subject to change at any time
----------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
-- Description   : See library quick reference (under 'doc') and README-file(s)
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

use work.monitor_cmd_pkg.all;
use work.monitor_cmd_support_pkg.all;
use work.monitor_cmd_shared_variables_pkg.all;
use work.vvc_cmd_pkg.all;
use work.vvc_methods_pkg.all;
use work.vvc_transaction_pkg.all;
use work.vvc_transaction_shared_variables_pkg.all;
use work.protected_transaction_group_pkg.all;

--=================================================================================================
entity uart_monitor is
  generic(
    GC_INSTANCE_IDX   : natural := 1;
    GC_MONITOR_CONFIG : t_uart_monitor_config
  );
  port(
    uart_dut_rx : in std_logic;
    uart_dut_tx : in std_logic
  );
end entity uart_monitor;
--=================================================================================================
--=================================================================================================

architecture behave of uart_monitor is

  -- alias tx_transaction_info       : t_base_transaction is shared_uart_monitor_transaction_info(TX, GC_INSTANCE_IDX).bt;
  -- alias rx_transaction_info       : t_base_transaction is shared_uart_monitor_transaction_info(RX, GC_INSTANCE_IDX).bt;

  alias tx_transaction_trigger : std_logic is global_uart_monitor_transaction_trigger(TX, GC_INSTANCE_IDX);
  alias rx_transaction_trigger : std_logic is global_uart_monitor_transaction_trigger(RX, GC_INSTANCE_IDX);

  signal tx_i : std_logic;
  signal rx_i : std_logic;

  procedure monitor_uart_line(
    constant operation         : in t_operation;
    constant C_LOG_PREFIX      : in string;
    constant instance_idx      : in natural;
    constant channel           : in t_channel;
    signal   transaction_trigger : inout std_logic;
    variable transaction_info  : inout work.protected_transaction_group_pkg.t_generic_array;
    signal   uart_line           : in std_logic
    --variable monitor_config      : in t_uart_monitor_config -- v3 edited out
  ) is
    --alias interface_config       : t_uart_interface_config is monitor_config.interface_config;
    variable v_data              : std_logic_vector(C_MAX_BITS_IN_DATA - 1 downto 0) := (others => '0');
    variable v_parity_error      : boolean;
    variable v_stop_bit_error    : boolean_vector(0 to 1);
    variable v_legal_transaction : boolean;
    variable v_time_stamp        : time;
    variable v_timeout           : time;
    variable v_transaction_info  : t_transaction_group;
  begin
    -- Give constructor some time to set values
    -- wait for 0 ns;
    -- wait for 0 ns;

    -- Set constructor values
    shared_uart_monitor_config.set(GC_MONITOR_CONFIG, instance_idx, channel);

    v_transaction_info                       := transaction_info.get(instance_idx, channel);
    v_transaction_info.bt.operation          := NO_OPERATION;
    v_transaction_info.bt.transaction_status := INACTIVE;
    transaction_info.set(v_transaction_info, instance_idx, channel);

    -- Await idle state
    if uart_line /= '1' then
      wait until uart_line = '1';
    end if;

    loop
      -- Reset meta data
      v_parity_error   := false;
      v_stop_bit_error := (others => false);

      if uart_line /= '0' then
        -- Await start bit
        -- If transaction_display_time > 0 then change operation after specified time
        if shared_uart_monitor_config.get(instance_idx, channel).transaction_display_time > 0 ns then
          wait until falling_edge(uart_line) for shared_uart_monitor_config.get(instance_idx, channel).transaction_display_time;
          v_transaction_info                       := transaction_info.get(instance_idx, channel);
          v_transaction_info.bt.operation          := NO_OPERATION;
          v_transaction_info.bt.transaction_status := INACTIVE;
          transaction_info.set(v_transaction_info, instance_idx, channel);
        end if;
        if uart_line /= '0' then
          wait until falling_edge(uart_line);
        end if;

        -- Start bit registered and transaction is active
        log(ID_FRAME_INITIATE, C_LOG_PREFIX & "Start bit detected", shared_uart_monitor_config.get(instance_idx, channel).scope_name, shared_uart_monitor_config.get(instance_idx, channel).msg_id_panel);
        v_transaction_info                       := transaction_info.get(instance_idx, channel);
        v_transaction_info.bt.transaction_status := IN_PROGRESS;
        transaction_info.set(v_transaction_info, instance_idx, channel);

        -- Align to end of start bit
        wait for shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time;
      else
        -- Second stop bit interpreted as start bit transaction is active
        log(ID_FRAME_INITIATE, C_LOG_PREFIX & "Second stop bit interpreted as start bit.", shared_uart_monitor_config.get(instance_idx, channel).scope_name, shared_uart_monitor_config.get(instance_idx, channel).msg_id_panel);
        v_transaction_info                       := transaction_info.get(instance_idx, channel);
        v_transaction_info.bt.transaction_status := IN_PROGRESS;
        transaction_info.set(v_transaction_info, instance_idx, channel);
        -- Align to end of start bit
        wait for (shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time - uart_line'last_event);
      end if;

      -- Data bits
      for i in 0 to shared_uart_monitor_config.get(instance_idx, channel).interface_config.num_data_bits - 1 loop
        -- Align sampling point to middle of bit period
        wait for (shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time / 2);
        v_data(i) := uart_line;
        wait for (shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time / 2);
      end loop;

      if shared_uart_monitor_config.get(instance_idx, channel).interface_config.parity = PARITY_NONE then
        v_parity_error := false;
      else
        -- middle of the parity bit
        wait for (shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time / 2);
        -- Parity bit
        if shared_uart_monitor_config.get(instance_idx, channel).interface_config.parity = PARITY_ODD then
          v_parity_error := xor(v_data & uart_line) = '0';
        elsif shared_uart_monitor_config.get(instance_idx, channel).interface_config.parity = PARITY_EVEN then
          v_parity_error := xor(v_data & uart_line) = '1';
        end if;
        wait for (shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time / 2);
      end if;

      -- First stop bit (middle of the first stop bit)
      wait for (shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time / 2);
      if uart_line /= '1' then
        v_stop_bit_error(0) := true;
      end if;

      -- If two or one and a half stop bit
      if shared_uart_monitor_config.get(instance_idx, channel).interface_config.num_stop_bits = STOP_BITS_TWO then
        wait for shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time;
        if uart_line /= '1' then
          v_stop_bit_error(1) := true;
        end if;
      elsif shared_uart_monitor_config.get(instance_idx, channel).interface_config.num_stop_bits = STOP_BITS_ONE_AND_HALF then
        wait for shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time / 2 + shared_uart_monitor_config.get(instance_idx, channel).interface_config.bit_time / 4; -- Middle of half bit period
        if uart_line /= '1' then
          v_stop_bit_error(1) := true;
        end if;
      end if;

      -- Determine legal transaction
      if v_parity_error or or(v_stop_bit_error) then
        log(ID_MONITOR, C_LOG_PREFIX & "Non-legal transaction detected: parity_error: " & to_string(v_parity_error) & "; stop_bit_error: " & to_string(or(v_stop_bit_error)) & ".", shared_uart_monitor_config.get(instance_idx, channel).scope_name, shared_uart_monitor_config.get(instance_idx, channel).msg_id_panel);
      else
        log(ID_MONITOR, C_LOG_PREFIX & "Legal transaction completed.", shared_uart_monitor_config.get(instance_idx, channel).scope_name, shared_uart_monitor_config.get(instance_idx, channel).msg_id_panel);
      end if;

      -- Update transaction
      v_transaction_info               := transaction_info.get(instance_idx, channel);
      v_transaction_info.bt.operation  := operation;
      v_transaction_info.bt.data       := v_data;
      v_transaction_info.bt.error_info := (parity_bit_error => v_parity_error,
                                           stop_bit_error   => or(v_stop_bit_error));
      if v_parity_error or or(v_stop_bit_error) then
        v_transaction_info.bt.transaction_status := FAILED;
      else
        v_transaction_info.bt.transaction_status := SUCCEEDED;
      end if;
      transaction_info.set(v_transaction_info, instance_idx, channel);

      -- Pulse transaction info trigger signal for updated transaction information
      gen_pulse(transaction_trigger, 0 ns, BLOCKING, "pulsing monitor transaction info trigger");

      -- Await non-active line if no stop bit has been detected
      if (and(v_stop_bit_error) or (shared_uart_monitor_config.get(instance_idx, channel).interface_config.num_stop_bits = STOP_BITS_ONE and v_stop_bit_error(0))) and uart_line /= '1' then
        wait until uart_line = '1';
      end if;

    end loop;

  end procedure;
begin

  -- p_tx_monitor_constructor : monitor_constructor(GC_MONITOR_CONFIG, shared_uart_monitor_config(TX, GC_INSTANCE_IDX));
  -- p_rx_monitor_constructor : monitor_constructor(GC_MONITOR_CONFIG, shared_uart_monitor_config(RX, GC_INSTANCE_IDX));

  -- Strength reduction functions to handle H/L
  p_tx_i : tx_i <= to_ux01(uart_dut_tx);
  p_rx_i : rx_i <= to_ux01(uart_dut_rx);

  p_tx_monitor : monitor_uart_line(TRANSMIT, "TX: ", GC_INSTANCE_IDX, TX, tx_transaction_trigger, shared_uart_monitor_transaction_info, tx_i);
  p_rx_monitor : monitor_uart_line(RECEIVE, "RX: ", GC_INSTANCE_IDX, RX, rx_transaction_trigger, shared_uart_monitor_transaction_info, rx_i);

end architecture behave;
