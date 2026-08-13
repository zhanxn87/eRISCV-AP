// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Optional, non-architectural M2 performance profile.  It observes the
// delivered SoC hierarchy only when +perf_profile=1 is present; no RTL signal or
// software-visible HPM definition is altered.
// Cycle counters sample pre-NBA signal levels at each SoC-clock posedge.
// Latency is accepted-request edge to matching-response edge: a synchronous
// next-cycle response is 1, while a same-cycle fast store completion is 0.
// Stall counters are level cycles and may overlap; they are not event counts.

localparam int PERF_DBUS_DMEM  = 0;
localparam int PERF_DBUS_IMEM  = 1;
localparam int PERF_DBUS_CLINT = 2;
localparam int PERF_DBUS_PLIC  = 3;
localparam int PERF_DBUS_APB   = 4;
localparam int PERF_DBUS_OTHER = 5;
localparam int PERF_DBUS_TARGET_COUNT = PERF_DBUS_OTHER + 1;

localparam int PERF_LOAD_USE_ALU        = 0;
localparam int PERF_LOAD_USE_LOAD_ADDR  = 1;
localparam int PERF_LOAD_USE_BRANCH     = 2;
localparam int PERF_LOAD_USE_JALR       = 3;
localparam int PERF_LOAD_USE_STORE_ADDR = 4;
localparam int PERF_LOAD_USE_STORE_DATA = 5;
localparam int PERF_LOAD_USE_STORE_BOTH = 6;
localparam int PERF_LOAD_USE_SYSTEM     = 7;
localparam int PERF_LOAD_USE_CLASS_COUNT = PERF_LOAD_USE_SYSTEM + 1;
localparam int PERF_RAS_ENTRIES = 4;
localparam logic [2:0] PERF_IDEX_BUBBLE_NONE           = 3'd0;
localparam logic [2:0] PERF_IDEX_BUBBLE_IFID_INVALID   = 3'd1;
localparam logic [2:0] PERF_IDEX_BUBBLE_FLUSH          = 3'd2;
localparam logic [2:0] PERF_IDEX_BUBBLE_HOLD           = 3'd3;
localparam logic [2:0] PERF_IDEX_BUBBLE_DECODE_INVALID = 3'd4;
// `can_issue` is an IF request-admission predicate. Keep the primary
// attribution mutually exclusive for closure, and retain the complete mask in
// the optional trace because multiple admission guards can be active together.
localparam logic [3:0] PERF_IF_ISSUE_BLOCK_FETCH_DISABLED = 4'd1;
localparam logic [3:0] PERF_IF_ISSUE_BLOCK_BOOT_INIT      = 4'd2;
localparam logic [3:0] PERF_IF_ISSUE_BLOCK_HOLD_VALID     = 4'd3;
localparam logic [3:0] PERF_IF_ISSUE_BLOCK_IMEM_RESPONSE  = 4'd4;
localparam logic [3:0] PERF_IF_ISSUE_BLOCK_TWO_C16        = 4'd5;
localparam logic [3:0] PERF_IF_ISSUE_BLOCK_UPPER_START    = 4'd6;
localparam logic [3:0] PERF_IF_ISSUE_BLOCK_CROSS_WORD     = 4'd7;
localparam logic [3:0] PERF_IF_ISSUE_BLOCK_UNCLASSIFIED   = 4'd8;
localparam logic [1:0] PERF_IF_ISSUE_READY_NO_REQUEST     = 2'd0;
localparam logic [1:0] PERF_IF_ISSUE_READY_WAIT_IMEM      = 2'd1;
localparam logic [1:0] PERF_IF_ISSUE_READY_ACCEPTED       = 2'd2;
localparam logic [4:0] PERF_IF_DELIVERY_VALID              = 5'd0;
localparam logic [4:0] PERF_IF_DELIVERY_REDIRECT_ID_BRANCH = 5'd1;
localparam logic [4:0] PERF_IF_DELIVERY_REDIRECT_ID_JAL    = 5'd2;
localparam logic [4:0] PERF_IF_DELIVERY_REDIRECT_ID_RAS    = 5'd3;
localparam logic [4:0] PERF_IF_DELIVERY_REDIRECT_EX        = 5'd4;
localparam logic [4:0] PERF_IF_DELIVERY_REDIRECT_TRAP      = 5'd5;
localparam logic [4:0] PERF_IF_DELIVERY_REDIRECT_DEBUG     = 5'd6;
localparam logic [4:0] PERF_IF_DELIVERY_REDIRECT_FENCE_I   = 5'd7;
localparam logic [4:0] PERF_IF_DELIVERY_REDIRECT_WFI       = 5'd8;
localparam logic [4:0] PERF_IF_DELIVERY_FLUSH              = 5'd9;
localparam logic [4:0] PERF_IF_DELIVERY_CROSS_WORD_WAIT    = 5'd10;
localparam logic [4:0] PERF_IF_DELIVERY_UPPER_START_32     = 5'd11;
localparam logic [4:0] PERF_IF_DELIVERY_RESPONSE_WAIT      = 5'd12;
localparam logic [4:0] PERF_IF_DELIVERY_NO_SOURCE_STARTED  = 5'd13;
localparam logic [4:0] PERF_IF_DELIVERY_NO_SOURCE_DEMAND   = 5'd14;
localparam logic [4:0] PERF_IF_DELIVERY_NO_SOURCE_GUARD    = 5'd15;
localparam logic [4:0] PERF_IF_DELIVERY_ID_HOLD_EMPTY      = 5'd16;
localparam logic [4:0] PERF_IF_DELIVERY_DROP_RESPONSE      = 5'd17;
localparam logic [4:0] PERF_IF_DELIVERY_ID_HOLD_FRONT      = 5'd18;
localparam logic [4:0] PERF_IF_DELIVERY_ID_HOLD_FULL       = 5'd19;
localparam logic [4:0] PERF_IF_DELIVERY_UNCLASSIFIED       = 5'd21;

bit perf_profile_started_q;
bit perf_profile_completed_q;
bit perf_if_pending_q;
bit perf_if_counted_q;
bit perf_dbus_pending_q;
bit perf_dbus_counted_q;
bit perf_dbus_write_q;
bit perf_redirect_recovery_q;
logic [2:0] perf_idex_bubble_cause_q;
bit perf_if_delivery_sample_q;
logic perf_if_delivery_valid_q;
logic [4:0] perf_if_delivery_reason_q;
logic [31:0] perf_if_delivery_pc_q;
logic [31:0] perf_if_delivery_value0_q;
bit perf_ifid_invalid_delivery_sample_q;
logic [4:0] perf_ifid_invalid_delivery_reason_q;
logic [31:0] perf_ifid_invalid_delivery_pc_q;
logic [31:0] perf_ifid_invalid_delivery_value0_q;
bit perf_has_start_pc;
bit perf_has_stop_pc;
int perf_dbus_target_q;
logic [31:0] perf_dbus_pc_q;
logic [31:0] perf_start_pc;
logic [31:0] perf_stop_pc;
longint unsigned perf_cycle_q;
longint unsigned perf_if_start_cycle_q;
longint unsigned perf_dbus_start_cycle_q;
integer perf_target_index;
integer perf_load_use_class_index;
integer perf_ras_index;
integer perf_trace_fd;
string perf_trace_file;

longint unsigned perf_soc_cycles;
longint unsigned perf_core_enabled_cycles;
longint unsigned perf_no_retire_cycles;
longint unsigned perf_no_retire_clock_off_cycles;
longint unsigned perf_no_retire_wfi_sleep_cycles;
longint unsigned perf_no_retire_debug_halted_cycles;
longint unsigned perf_no_retire_stall_cycles;
longint unsigned perf_no_retire_redirect_recovery_cycles;
longint unsigned perf_no_retire_idex_empty_cycles;
longint unsigned perf_idex_empty_ifid_invalid_cycles;
longint unsigned perf_if_can_issue_ready_cycles;
longint unsigned perf_if_can_issue_ready_no_request_cycles;
longint unsigned perf_if_can_issue_ready_wait_imem_cycles;
longint unsigned perf_if_can_issue_ready_accepted_cycles;
longint unsigned perf_if_can_issue_blocked_cycles;
longint unsigned perf_if_can_issue_blocked_multi_cycles;
longint unsigned perf_if_issue_block_fetch_disabled_cycles;
longint unsigned perf_if_issue_block_boot_init_cycles;
longint unsigned perf_if_issue_block_hold_valid_cycles;
longint unsigned perf_if_issue_block_imem_response_cycles;
longint unsigned perf_if_issue_block_two_c16_cycles;
longint unsigned perf_if_issue_block_upper_start_cycles;
longint unsigned perf_if_issue_block_cross_word_cycles;
longint unsigned perf_if_issue_block_unclassified_cycles;
longint unsigned perf_if_issue_raw_fetch_disabled_cycles;
longint unsigned perf_if_issue_raw_boot_init_cycles;
longint unsigned perf_if_issue_raw_hold_valid_cycles;
longint unsigned perf_if_issue_raw_imem_response_cycles;
longint unsigned perf_if_issue_raw_two_c16_cycles;
longint unsigned perf_if_issue_raw_upper_start_cycles;
longint unsigned perf_if_issue_raw_cross_word_cycles;
longint unsigned perf_ifid_invalid_delivery_redirect_id_branch_cycles;
longint unsigned perf_ifid_invalid_delivery_redirect_id_jal_cycles;
longint unsigned perf_ifid_invalid_delivery_redirect_id_ras_cycles;
longint unsigned perf_ifid_invalid_delivery_redirect_ex_cycles;
longint unsigned perf_ifid_invalid_delivery_redirect_trap_cycles;
longint unsigned perf_ifid_invalid_delivery_redirect_debug_cycles;
longint unsigned perf_ifid_invalid_delivery_redirect_fence_i_cycles;
longint unsigned perf_ifid_invalid_delivery_redirect_wfi_cycles;
longint unsigned perf_ifid_invalid_delivery_flush_cycles;
longint unsigned perf_ifid_invalid_delivery_cross_word_wait_cycles;
longint unsigned perf_ifid_invalid_delivery_upper_start_32_cycles;
longint unsigned perf_ifid_invalid_delivery_response_wait_cycles;
longint unsigned perf_ifid_invalid_delivery_no_source_started_cycles;
longint unsigned perf_ifid_invalid_delivery_no_source_demand_cycles;
longint unsigned perf_ifid_invalid_delivery_no_source_guard_cycles;
longint unsigned perf_ifid_invalid_delivery_id_hold_empty_cycles;
longint unsigned perf_ifid_invalid_delivery_id_hold_front_cycles;
longint unsigned perf_ifid_invalid_delivery_id_hold_full_cycles;
longint unsigned perf_ifid_invalid_delivery_drop_response_cycles;
longint unsigned perf_ifid_invalid_delivery_unclassified_cycles;
longint unsigned perf_ifid_invalid_delivery_outside_window_cycles;
longint unsigned perf_idex_empty_flush_cycles;
longint unsigned perf_idex_empty_hold_cycles;
longint unsigned perf_idex_empty_decode_invalid_cycles;
longint unsigned perf_idex_empty_other_cycles;
longint unsigned perf_no_retire_other_cycles;
longint unsigned perf_if_id_valid_cycles;
longint unsigned perf_id_ex_valid_cycles;
longint unsigned perf_ex_mem_valid_cycles;
longint unsigned perf_mem_wb_valid_cycles;
longint unsigned perf_ifetch_wait_cycles;
longint unsigned perf_dbus_wait_cycles;
longint unsigned perf_load_use_stall_cycles;
longint unsigned perf_idex_load_use_stall_cycles;
longint unsigned perf_exmem_load_use_wait_cycles;
longint unsigned perf_selected_hold_cycles;
longint unsigned perf_muldiv_wait_cycles;
longint unsigned perf_mul_wait_cycles;
longint unsigned perf_div_wait_cycles;
longint unsigned perf_muldiv_only_cycles;
longint unsigned perf_muldiv_overlap_cycles;
longint unsigned perf_fpu_wait_cycles;
longint unsigned perf_fpu_busy_cycles;
longint unsigned perf_fpu_dependency_stall_cycles;
longint unsigned perf_fpu_issue_accepted;
longint unsigned perf_fpu_completion_accepted;
longint unsigned perf_stall_ifetch_only_cycles;
longint unsigned perf_stall_dbus_only_cycles;
longint unsigned perf_stall_load_use_only_cycles;
longint unsigned perf_stall_ifetch_dbus_cycles;
longint unsigned perf_stall_ifetch_load_use_cycles;
longint unsigned perf_stall_dbus_load_use_cycles;
longint unsigned perf_stall_all_cycles;
longint unsigned perf_ex_redirects;
longint unsigned perf_cond_branch_resolved;
longint unsigned perf_cond_branch_not_taken;
longint unsigned perf_cond_branch_backward_resolved;
longint unsigned perf_cond_branch_forward_resolved;
longint unsigned perf_cond_branch_taken;
longint unsigned perf_cond_branch_backward_taken;
longint unsigned perf_cond_branch_forward_taken;
longint unsigned perf_branch_predictions;
longint unsigned perf_branch_direction_correct;
longint unsigned perf_branch_prediction_corrections;
longint unsigned perf_branch_predicted_taken;
longint unsigned perf_branch_bht_predictions;
longint unsigned perf_branch_bht_direction_correct;
longint unsigned perf_branch_bht_corrections;
longint unsigned perf_branch_cold_predictions;
longint unsigned perf_branch_cold_direction_correct;
longint unsigned perf_branch_cold_corrections;
longint unsigned perf_direct_jump_predictions;
longint unsigned perf_redirect_recovery_cycles;
longint unsigned perf_redirect_recovery_max;
longint unsigned perf_redirect_recovery_current_q;
longint unsigned perf_jump_redirects;
longint unsigned perf_trap_redirects;
longint unsigned perf_debug_redirects;
longint unsigned perf_fence_i_redirects;
longint unsigned perf_wfi_redirects;

longint unsigned perf_jalr_returns;
longint unsigned perf_jalr_indirect_calls;
longint unsigned perf_jalr_other;
longint unsigned perf_ras_hw_predictions;
longint unsigned perf_ras_hw_correct;
longint unsigned perf_ras_hw_corrections;
longint unsigned perf_ras_hw_unpredicted;
longint unsigned perf_ras_pushes;
longint unsigned perf_ras_return_matches;
longint unsigned perf_ras_return_mismatches;
longint unsigned perf_ras_empty_returns;
longint unsigned perf_ras_overflows;
integer perf_ras_depth_q;
integer perf_call_depth_q;
integer perf_ras_depth_max;
integer perf_call_depth_max;
logic [31:0] perf_ras_stack_q [0:PERF_RAS_ENTRIES-1];

longint unsigned perf_retired;
longint unsigned perf_retired_load;
longint unsigned perf_retired_store;
longint unsigned perf_retired_branch;
longint unsigned perf_retired_jump;
longint unsigned perf_retired_system;
longint unsigned perf_retired_other;
longint unsigned perf_mul_completions;
longint unsigned perf_div_completions;
longint unsigned perf_retired_compressed;
longint unsigned perf_retired_32b;
longint unsigned perf_retired_32b_upper_half;

longint unsigned perf_fwd_rs1_triggers;
longint unsigned perf_fwd_rs2_triggers;
longint unsigned perf_fwd_exmem_rs1_selected;
longint unsigned perf_fwd_exmem_rs2_selected;
longint unsigned perf_fwd_memwb_rs1_selected;
longint unsigned perf_fwd_memwb_rs2_selected;
longint unsigned perf_fwd_memwb_rs1_overridden;
longint unsigned perf_fwd_memwb_rs2_overridden;
longint unsigned perf_fwd_rs1_value_checks;
longint unsigned perf_fwd_rs2_value_checks;
longint unsigned perf_fwd_rs1_value_mismatches;
longint unsigned perf_fwd_rs2_value_mismatches;
longint unsigned perf_load_branch_rs1_selected;
longint unsigned perf_load_branch_rs2_selected;
longint unsigned perf_load_store_data_selected;
longint unsigned perf_load_branch_rs1_mismatches;
longint unsigned perf_load_branch_rs2_mismatches;
longint unsigned perf_load_store_data_mismatches;
longint unsigned perf_lmem_candidates;
longint unsigned perf_lmem_accepted;
longint unsigned perf_lmem_responses;

longint unsigned perf_ifetch_requests;
longint unsigned perf_ifetch_latency_total;
longint unsigned perf_ifetch_latency_0;
longint unsigned perf_ifetch_latency_1;
longint unsigned perf_ifetch_latency_ge2;
longint unsigned perf_ifetch_latency_max;

longint unsigned perf_dbus_load_requests;
longint unsigned perf_dbus_store_requests;
longint unsigned perf_dbus_load_latency_total;
longint unsigned perf_dbus_store_latency_total;
longint unsigned perf_dbus_load_latency_0;
longint unsigned perf_dbus_load_latency_1;
longint unsigned perf_dbus_load_latency_ge2;
longint unsigned perf_dbus_store_latency_0;
longint unsigned perf_dbus_store_latency_1;
longint unsigned perf_dbus_store_latency_ge2;
longint unsigned perf_dbus_latency_max;
longint unsigned perf_dbus_error_responses;
longint unsigned perf_dbus_load_latency_total_by_target [0:PERF_DBUS_TARGET_COUNT-1];
longint unsigned perf_dbus_store_latency_total_by_target [0:PERF_DBUS_TARGET_COUNT-1];
longint unsigned perf_dbus_load_latency_0_by_target [0:PERF_DBUS_TARGET_COUNT-1];
longint unsigned perf_dbus_load_latency_1_by_target [0:PERF_DBUS_TARGET_COUNT-1];
longint unsigned perf_dbus_load_latency_ge2_by_target [0:PERF_DBUS_TARGET_COUNT-1];
longint unsigned perf_dbus_store_latency_0_by_target [0:PERF_DBUS_TARGET_COUNT-1];
longint unsigned perf_dbus_store_latency_1_by_target [0:PERF_DBUS_TARGET_COUNT-1];
longint unsigned perf_dbus_store_latency_ge2_by_target [0:PERF_DBUS_TARGET_COUNT-1];
longint unsigned perf_dbus_latency_max_by_target [0:PERF_DBUS_TARGET_COUNT-1];

longint unsigned perf_dmem_loads,  perf_dmem_stores;
longint unsigned perf_imem_loads,  perf_imem_stores;
longint unsigned perf_clint_loads, perf_clint_stores;
longint unsigned perf_plic_loads,  perf_plic_stores;
longint unsigned perf_apb_loads,   perf_apb_stores;
longint unsigned perf_other_loads, perf_other_stores;
longint unsigned perf_if_dbus_imem_request_collisions;
longint unsigned perf_if_dbus_imem_service_blocks;
longint unsigned perf_load_use_idex_by_class [0:PERF_LOAD_USE_CLASS_COUNT-1];
longint unsigned perf_load_use_exmem_by_class [0:PERF_LOAD_USE_CLASS_COUNT-1];

// The optional trace deliberately has no implicit cap: it is for offline
// hotspot analysis, and callers explicitly opt in with a file path.
initial begin
  perf_trace_fd = 0;
  perf_has_start_pc = $value$plusargs("perf_profile_start_pc=%h", perf_start_pc);
  perf_has_stop_pc = $value$plusargs("perf_profile_stop_pc=%h", perf_stop_pc);
  if (perf_has_start_pc && perf_has_stop_pc && (perf_start_pc == perf_stop_pc))
    $fatal(1, "perf_profile_start_pc and perf_profile_stop_pc must differ");
  if ($value$plusargs("perf_profile_trace=%s", perf_trace_file)) begin
    perf_trace_fd = $fopen(perf_trace_file, "w");
    if (perf_trace_fd == 0)
      $fatal(1, "Cannot open perf_profile_trace file: %s", perf_trace_file);
    $fwrite(perf_trace_fd, "cycle,event,pc,value0,value1\n");
  end
end

function automatic int perf_dbus_target(input logic [31:0] addr);
  begin
    if (soc_pkg::is_dmem_addr(addr))
      perf_dbus_target = PERF_DBUS_DMEM;
    else if (soc_pkg::is_imem_addr(addr))
      perf_dbus_target = PERF_DBUS_IMEM;
    else if (soc_pkg::is_clint_addr(addr))
      perf_dbus_target = PERF_DBUS_CLINT;
    else if (soc_pkg::is_plic_addr(addr))
      perf_dbus_target = PERF_DBUS_PLIC;
    else if (soc_pkg::is_apb_addr(addr))
      perf_dbus_target = PERF_DBUS_APB;
    else
      perf_dbus_target = PERF_DBUS_OTHER;
  end
endfunction

function automatic logic perf_instr_uses_rs1(input logic [31:0] instr);
  begin
    perf_instr_uses_rs1 = 1'b0;
    unique case (instr[6:0])
      7'b011_0011, // OP, including RV32M
      7'b001_0011, // OP-IMM
      7'b000_0011, // LOAD
      7'b110_0111, // JALR
      7'b010_0011, // STORE
      7'b110_0011: // BRANCH
        perf_instr_uses_rs1 = 1'b1;
      7'b111_0011:
        perf_instr_uses_rs1 = (instr[14:12] == 3'b001) ||
                               (instr[14:12] == 3'b010) ||
                               (instr[14:12] == 3'b011);
      default: ;
    endcase
  end
endfunction

function automatic logic perf_instr_uses_rs2(input logic [31:0] instr);
  begin
    perf_instr_uses_rs2 = 1'b0;
    unique case (instr[6:0])
      7'b011_0011, // OP, including RV32M
      7'b010_0011, // STORE
      7'b110_0011: // BRANCH
        perf_instr_uses_rs2 = 1'b1;
      default: ;
    endcase
  end
endfunction

function automatic logic [31:0] perf_dbus_trace_meta(
  input int target,
  input logic is_write
);
  begin
    perf_dbus_trace_meta = {28'd0, target[2:0], is_write};
  end
endfunction

task automatic perf_count_dbus_target(input int target, input logic is_write);
  begin
    unique case (target)
      PERF_DBUS_DMEM:  if (is_write) perf_dmem_stores  <= perf_dmem_stores + 1;  else perf_dmem_loads  <= perf_dmem_loads + 1;
      PERF_DBUS_IMEM:  if (is_write) perf_imem_stores  <= perf_imem_stores + 1;  else perf_imem_loads  <= perf_imem_loads + 1;
      PERF_DBUS_CLINT: if (is_write) perf_clint_stores <= perf_clint_stores + 1; else perf_clint_loads <= perf_clint_loads + 1;
      PERF_DBUS_PLIC:  if (is_write) perf_plic_stores  <= perf_plic_stores + 1;  else perf_plic_loads  <= perf_plic_loads + 1;
      PERF_DBUS_APB:   if (is_write) perf_apb_stores   <= perf_apb_stores + 1;   else perf_apb_loads   <= perf_apb_loads + 1;
      default:          if (is_write) perf_other_stores <= perf_other_stores + 1; else perf_other_loads <= perf_other_loads + 1;
    endcase
  end
endtask

task automatic perf_record_ifetch_latency(input longint unsigned latency);
  begin
    perf_ifetch_latency_total <= perf_ifetch_latency_total + latency;
    if (latency > perf_ifetch_latency_max)
      perf_ifetch_latency_max <= latency;
    if (latency == 0)
      perf_ifetch_latency_0 <= perf_ifetch_latency_0 + 1;
    else if (latency == 1)
      perf_ifetch_latency_1 <= perf_ifetch_latency_1 + 1;
    else
      perf_ifetch_latency_ge2 <= perf_ifetch_latency_ge2 + 1;
  end
endtask

task automatic perf_record_dbus_latency(
  input int target,
  input logic is_write,
  input longint unsigned latency
);
  begin
    if (latency > perf_dbus_latency_max)
      perf_dbus_latency_max <= latency;
    if (latency > perf_dbus_latency_max_by_target[target])
      perf_dbus_latency_max_by_target[target] <= latency;
    if (is_write) begin
      perf_dbus_store_latency_total <= perf_dbus_store_latency_total + latency;
      perf_dbus_store_latency_total_by_target[target] <=
        perf_dbus_store_latency_total_by_target[target] + latency;
      if (latency == 0)
        perf_dbus_store_latency_0 <= perf_dbus_store_latency_0 + 1;
      else if (latency == 1)
        perf_dbus_store_latency_1 <= perf_dbus_store_latency_1 + 1;
      else
        perf_dbus_store_latency_ge2 <= perf_dbus_store_latency_ge2 + 1;
      if (latency == 0)
        perf_dbus_store_latency_0_by_target[target] <=
          perf_dbus_store_latency_0_by_target[target] + 1;
      else if (latency == 1)
        perf_dbus_store_latency_1_by_target[target] <=
          perf_dbus_store_latency_1_by_target[target] + 1;
      else
        perf_dbus_store_latency_ge2_by_target[target] <=
          perf_dbus_store_latency_ge2_by_target[target] + 1;
    end else begin
      perf_dbus_load_latency_total <= perf_dbus_load_latency_total + latency;
      perf_dbus_load_latency_total_by_target[target] <=
        perf_dbus_load_latency_total_by_target[target] + latency;
      if (latency == 0)
        perf_dbus_load_latency_0 <= perf_dbus_load_latency_0 + 1;
      else if (latency == 1)
        perf_dbus_load_latency_1 <= perf_dbus_load_latency_1 + 1;
      else
        perf_dbus_load_latency_ge2 <= perf_dbus_load_latency_ge2 + 1;
      if (latency == 0)
        perf_dbus_load_latency_0_by_target[target] <=
          perf_dbus_load_latency_0_by_target[target] + 1;
      else if (latency == 1)
        perf_dbus_load_latency_1_by_target[target] <=
          perf_dbus_load_latency_1_by_target[target] + 1;
      else
        perf_dbus_load_latency_ge2_by_target[target] <=
          perf_dbus_load_latency_ge2_by_target[target] + 1;
    end
  end
endtask

task automatic perf_count_load_use_consumer(
  input logic idex_phase,
  input logic rs1_match,
  input logic rs2_match
);
  int consumer;
  begin
    if (dut.riscv_core_i.id_stage_i.id_ex_d.mem_store) begin
      if (rs1_match && rs2_match)
        consumer = PERF_LOAD_USE_STORE_BOTH;
      else if (rs1_match)
        consumer = PERF_LOAD_USE_STORE_ADDR;
      else
        consumer = PERF_LOAD_USE_STORE_DATA;
    end else if (dut.riscv_core_i.id_stage_i.id_ex_d.mem_load) begin
      consumer = PERF_LOAD_USE_LOAD_ADDR;
    end else if (dut.riscv_core_i.id_stage_i.id_ex_d.branch_op != riscv_pkg::BR_NONE) begin
      consumer = PERF_LOAD_USE_BRANCH;
    end else if (dut.riscv_core_i.id_stage_i.id_ex_d.jump_op == riscv_pkg::JUMP_JALR) begin
      consumer = PERF_LOAD_USE_JALR;
    end else if (dut.riscv_core_i.id_stage_i.id_ex_d.csr_access ||
                 dut.riscv_core_i.id_stage_i.id_ex_d.sys_op != riscv_pkg::SYS_NONE) begin
      consumer = PERF_LOAD_USE_SYSTEM;
    end else begin
      consumer = PERF_LOAD_USE_ALU;
    end

    if (idex_phase)
      perf_load_use_idex_by_class[consumer] <=
        perf_load_use_idex_by_class[consumer] + 1;
    else
      perf_load_use_exmem_by_class[consumer] <=
        perf_load_use_exmem_by_class[consumer] + 1;
  end
endtask

task automatic perf_trace_event(
  input string event_name,
  input logic [31:0] pc,
  input logic [31:0] value0,
  input logic [31:0] value1
);
  begin
    if (perf_trace_fd != 0)
      $fwrite(perf_trace_fd, "%0d,%s,%08h,%08h,%08h\n",
              perf_cycle_q, event_name, pc, value0, value1);
  end
endtask

function automatic logic [3:0] perf_if_issue_primary_cause(
  input logic [6:0] blocker_mask
);
  begin
    // This order matches the admission predicate from externally disabling
    // fetch through to response packing. The raw mask remains available for
    // intersections rather than hiding them behind the primary attribution.
    if (blocker_mask[0])
      perf_if_issue_primary_cause = PERF_IF_ISSUE_BLOCK_FETCH_DISABLED;
    else if (blocker_mask[1])
      perf_if_issue_primary_cause = PERF_IF_ISSUE_BLOCK_BOOT_INIT;
    else if (blocker_mask[2])
      perf_if_issue_primary_cause = PERF_IF_ISSUE_BLOCK_HOLD_VALID;
    else if (blocker_mask[3])
      perf_if_issue_primary_cause = PERF_IF_ISSUE_BLOCK_IMEM_RESPONSE;
    else if (blocker_mask[4])
      perf_if_issue_primary_cause = PERF_IF_ISSUE_BLOCK_TWO_C16;
    else if (blocker_mask[5])
      perf_if_issue_primary_cause = PERF_IF_ISSUE_BLOCK_UPPER_START;
    else if (blocker_mask[6])
      perf_if_issue_primary_cause = PERF_IF_ISSUE_BLOCK_CROSS_WORD;
    else
      perf_if_issue_primary_cause = PERF_IF_ISSUE_BLOCK_UNCLASSIFIED;
  end
endfunction

task automatic perf_trace_if_delivery_to_bubble(
  input logic [4:0] delivery_reason,
  input logic [31:0] pc,
  input logic [31:0] value0
);
  begin
    unique case (delivery_reason)
      PERF_IF_DELIVERY_REDIRECT_ID_BRANCH:
        perf_trace_event("if_delivery_to_bubble_redirect_id_branch", pc, value0, 32'd0);
      PERF_IF_DELIVERY_REDIRECT_ID_JAL:
        perf_trace_event("if_delivery_to_bubble_redirect_id_jal", pc, value0, 32'd0);
      PERF_IF_DELIVERY_REDIRECT_ID_RAS:
        perf_trace_event("if_delivery_to_bubble_redirect_id_ras", pc, value0, 32'd0);
      PERF_IF_DELIVERY_REDIRECT_EX:
        perf_trace_event("if_delivery_to_bubble_redirect_ex", pc, value0, 32'd0);
      PERF_IF_DELIVERY_REDIRECT_TRAP:
        perf_trace_event("if_delivery_to_bubble_redirect_trap", pc, value0, 32'd0);
      PERF_IF_DELIVERY_REDIRECT_DEBUG:
        perf_trace_event("if_delivery_to_bubble_redirect_debug", pc, value0, 32'd0);
      PERF_IF_DELIVERY_REDIRECT_FENCE_I:
        perf_trace_event("if_delivery_to_bubble_redirect_fence_i", pc, value0, 32'd0);
      PERF_IF_DELIVERY_REDIRECT_WFI:
        perf_trace_event("if_delivery_to_bubble_redirect_wfi", pc, value0, 32'd0);
      PERF_IF_DELIVERY_FLUSH:
        perf_trace_event("if_delivery_to_bubble_flush", pc, value0, 32'd0);
      PERF_IF_DELIVERY_CROSS_WORD_WAIT:
        perf_trace_event("if_delivery_to_bubble_cross_word_wait", pc, value0, 32'd0);
      PERF_IF_DELIVERY_UPPER_START_32:
        perf_trace_event("if_delivery_to_bubble_upper_start_32", pc, value0, 32'd0);
      PERF_IF_DELIVERY_RESPONSE_WAIT:
        perf_trace_event("if_delivery_to_bubble_response_wait", pc, value0, 32'd0);
      PERF_IF_DELIVERY_NO_SOURCE_STARTED:
        perf_trace_event("if_delivery_to_bubble_no_source_started", pc, value0, 32'd0);
      PERF_IF_DELIVERY_NO_SOURCE_DEMAND:
        perf_trace_event("if_delivery_to_bubble_no_source_no_demand", pc, value0, 32'd0);
      PERF_IF_DELIVERY_NO_SOURCE_GUARD:
        perf_trace_event("if_delivery_to_bubble_no_source_guard", pc, value0, 32'd0);
      PERF_IF_DELIVERY_ID_HOLD_EMPTY:
        perf_trace_event("if_delivery_to_bubble_id_hold_empty", pc, value0, 32'd0);
      PERF_IF_DELIVERY_ID_HOLD_FRONT:
        perf_trace_event("if_delivery_to_bubble_id_hold_front", pc, value0, 32'd0);
      PERF_IF_DELIVERY_ID_HOLD_FULL:
        perf_trace_event("if_delivery_to_bubble_id_hold_full", pc, value0, 32'd0);
      PERF_IF_DELIVERY_DROP_RESPONSE:
        perf_trace_event("if_delivery_to_bubble_drop_response", pc, value0, 32'd0);
      default:
        perf_trace_event("if_delivery_to_bubble_unclassified", pc, value0, 32'd0);
    endcase
  end
endtask

// Event contract:
// - retire is the exact architectural pulse presented to csr_file;
// - IF requests are counted only when IF accepts them;
// - the optional PC window is inclusive at both retired-PC boundaries.
wire perf_arch_retire =
  dut.core_clk_en && dut.riscv_core_i.ex_stage_i.csr_file_i.retire_i;
wire perf_window_start_now =
  !perf_profile_started_q && !perf_profile_completed_q &&
  (perf_has_start_pc ?
    (perf_arch_retire && (dut.riscv_core_i.id_ex_q.pc == perf_start_pc)) :
    dut.core_fetch_enable);
wire perf_window_stop_now =
  perf_profile_started_q && perf_has_stop_pc && perf_arch_retire &&
  (dut.riscv_core_i.id_ex_q.pc == perf_stop_pc);
wire perf_window_sample =
  !perf_profile_completed_q && (perf_profile_started_q || perf_window_start_now);
wire perf_if_request_accepted =
  dut.riscv_core_i.if_stage_i.issue_redirect_request ||
  dut.riscv_core_i.if_stage_i.issue_sequential_request;
wire perf_fpu_dependency_stall =
  dut.riscv_core_i.fp_load_use_stall ||
  dut.riscv_core_i.mem_fp_load_use_stall ||
  dut.riscv_core_i.fp_write_use_stall ||
  dut.riscv_core_i.mem_fp_write_use_stall;
wire [1:0] perf_if_issue_ready_state =
  perf_if_request_accepted ? PERF_IF_ISSUE_READY_ACCEPTED :
  (dut.riscv_core_i.if_stage_i.imem_req_o ?
    PERF_IF_ISSUE_READY_WAIT_IMEM : PERF_IF_ISSUE_READY_NO_REQUEST);
// Observe only core-clock opportunities. A stopped core does not evaluate an
// IF admission opportunity, so counting it as `can_issue=0` would invent a
// front-end loss during WFI/debug clock gating.
wire perf_if_issue_sample = perf_window_sample && dut.core_clk_en;
wire perf_if_block_fetch_disabled =
  !dut.riscv_core_i.if_stage_i.fetch_enable_i;
wire perf_if_block_boot_init = dut.riscv_core_i.if_stage_i.boot_init_q;
wire perf_if_block_hold_valid = dut.riscv_core_i.if_stage_i.hold_valid_q;
wire perf_if_block_imem_response =
  dut.riscv_core_i.if_stage_i.req_pending_q &&
  !dut.riscv_core_i.if_stage_i.response_valid;
wire perf_if_block_two_c16 = dut.riscv_core_i.if_stage_i.response_has_two_c;
wire perf_if_block_upper_start =
  dut.riscv_core_i.if_stage_i.response_starts_upper &&
  !dut.riscv_core_i.if_stage_i.response_upper_32_prefetch;
wire perf_if_block_cross_word =
  dut.riscv_core_i.if_stage_i.upper_valid_q &&
  (dut.riscv_core_i.if_stage_i.upper_data_q[1:0] == 2'b11) &&
  dut.riscv_core_i.if_stage_i.response_valid &&
  (!dut.riscv_core_i.if_stage_i.if_id_en_i ||
   (dut.riscv_core_i.if_stage_i.imem_rdata_i[17:16] != 2'b11));
wire [6:0] perf_if_issue_blocker_mask = {
  perf_if_block_cross_word,
  perf_if_block_upper_start,
  perf_if_block_two_c16,
  perf_if_block_imem_response,
  perf_if_block_hold_valid,
  perf_if_block_boot_init,
  perf_if_block_fetch_disabled
};
wire [3:0] perf_if_issue_primary =
  perf_if_issue_primary_cause(perf_if_issue_blocker_mask);
wire [31:0] perf_if_issue_candidate_pc =
  dut.riscv_core_i.if_stage_i.redirect_request ?
    dut.riscv_core_i.if_stage_i.request_pc : dut.riscv_core_i.if_stage_i.pc_q;
// Predict the IF/ID valid bit written at this edge from the delivered IF
// state. This is deliberately separate from `can_issue`: a request-admission
// block may still deliver an instruction, while an accepted request may only
// supply the following edge. The registered prediction is checked one edge
// later against the actual IF/ID state before it is used for bubble evidence.
logic perf_if_delivery_next_valid;
logic [4:0] perf_if_delivery_next_reason;
logic [31:0] perf_if_delivery_next_pc;
logic [31:0] perf_if_delivery_next_value0;
always_comb begin
  perf_if_delivery_next_valid = dut.riscv_core_i.if_id_q.valid;
  if (dut.riscv_core_i.if_id_q.valid) begin
    perf_if_delivery_next_reason = PERF_IF_DELIVERY_VALID;
  end else if (!dut.riscv_core_i.if_stage_i.if_id_en_i) begin
    if (dut.riscv_core_i.if_fetch_wait ||
        dut.riscv_core_i.load_use_stall ||
        dut.riscv_core_i.mem_load_use_stall ||
        perf_fpu_dependency_stall)
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_ID_HOLD_FRONT;
    else if (dut.riscv_core_i.mem_wait || dut.riscv_core_i.muldiv_wait ||
             dut.riscv_core_i.fpu_wait)
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_ID_HOLD_FULL;
    else
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_ID_HOLD_EMPTY;
  end else begin
    perf_if_delivery_next_reason = PERF_IF_DELIVERY_VALID;
  end
  perf_if_delivery_next_pc = perf_if_issue_candidate_pc;
  perf_if_delivery_next_value0 = '0;
  if (dut.riscv_core_i.if_stage_i.redirect_valid_i) begin
    perf_if_delivery_next_valid = 1'b0;
    perf_if_delivery_next_pc = dut.riscv_core_i.if_stage_i.redirect_pc_i;
    // The core-level redirect arbitration has priority over the ID predictor.
    // Preserve that distinction: correct ID prediction is not recovery loss.
    if (dut.riscv_core_i.redirect_valid) begin
      if (dut.riscv_core_i.trap_redirect)
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_REDIRECT_TRAP;
      else if (dut.riscv_core_i.debug_redirect ||
               dut.riscv_core_i.debug_resume_redirect)
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_REDIRECT_DEBUG;
      else if (dut.riscv_core_i.fence_i_redirect)
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_REDIRECT_FENCE_I;
      else if (dut.riscv_core_i.wfi_redirect)
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_REDIRECT_WFI;
      else if (dut.riscv_core_i.branch_redirect)
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_REDIRECT_EX;
      else
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_UNCLASSIFIED;
    end else if (dut.riscv_core_i.id_predict_redirect) begin
      if (dut.riscv_core_i.id_stage_i.id_ex_bypassed.return_pred_valid)
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_REDIRECT_ID_RAS;
      else if (dut.riscv_core_i.id_stage_i.id_ex_bypassed.jal_early)
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_REDIRECT_ID_JAL;
      else if (dut.riscv_core_i.id_stage_i.id_ex_bypassed.branch_pred_valid &&
               dut.riscv_core_i.id_stage_i.id_ex_bypassed.branch_pred_taken)
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_REDIRECT_ID_BRANCH;
      else
        perf_if_delivery_next_reason = PERF_IF_DELIVERY_UNCLASSIFIED;
    end else begin
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_UNCLASSIFIED;
    end
  end else if (dut.riscv_core_i.if_stage_i.if_id_flush_i) begin
    perf_if_delivery_next_valid = 1'b0;
    perf_if_delivery_next_reason = PERF_IF_DELIVERY_FLUSH;
  end else if (dut.riscv_core_i.if_stage_i.hold_valid_q &&
               dut.riscv_core_i.if_stage_i.if_id_en_i) begin
    perf_if_delivery_next_valid = 1'b1;
  end else if (dut.riscv_core_i.if_stage_i.upper_valid_q &&
               (dut.riscv_core_i.if_stage_i.upper_data_q[1:0] == 2'b11) &&
               dut.riscv_core_i.if_stage_i.response_valid &&
               dut.riscv_core_i.if_stage_i.if_id_en_i &&
               !dut.riscv_core_i.if_stage_i.drop_resp_q) begin
    perf_if_delivery_next_valid = 1'b1;
  end else if (dut.riscv_core_i.if_stage_i.upper_valid_q &&
               dut.riscv_core_i.if_stage_i.if_id_en_i &&
               !dut.riscv_core_i.if_stage_i.drop_resp_q) begin
    if (dut.riscv_core_i.if_stage_i.upper_data_q[1:0] == 2'b11) begin
      perf_if_delivery_next_valid = 1'b0;
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_CROSS_WORD_WAIT;
      perf_if_delivery_next_pc = dut.riscv_core_i.if_stage_i.upper_pc_q;
    end else begin
      perf_if_delivery_next_valid = 1'b1;
    end
  end else if (dut.riscv_core_i.if_stage_i.response_valid &&
               !dut.riscv_core_i.if_stage_i.drop_resp_q &&
               dut.riscv_core_i.if_stage_i.if_id_en_i) begin
    if (dut.riscv_core_i.if_stage_i.resp_pc_q[1] &&
        (dut.riscv_core_i.if_stage_i.imem_rdata_i[17:16] == 2'b11)) begin
      perf_if_delivery_next_valid = 1'b0;
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_UPPER_START_32;
      perf_if_delivery_next_pc = dut.riscv_core_i.if_stage_i.resp_pc_q;
    end else begin
      perf_if_delivery_next_valid = 1'b1;
    end
  end else if (dut.riscv_core_i.if_stage_i.if_id_en_i) begin
    perf_if_delivery_next_valid = 1'b0;
    if (dut.riscv_core_i.if_stage_i.response_valid &&
        dut.riscv_core_i.if_stage_i.drop_resp_q) begin
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_DROP_RESPONSE;
      perf_if_delivery_next_pc = dut.riscv_core_i.if_stage_i.resp_pc_q;
    end else if (dut.riscv_core_i.if_stage_i.req_pending_q) begin
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_RESPONSE_WAIT;
    end else if (perf_if_request_accepted) begin
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_NO_SOURCE_STARTED;
    end else if (perf_if_issue_blocker_mask != '0) begin
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_NO_SOURCE_GUARD;
      perf_if_delivery_next_value0 = {{25{1'b0}}, perf_if_issue_blocker_mask};
    end else if (dut.riscv_core_i.if_stage_i.can_issue &&
                 !dut.riscv_core_i.if_stage_i.redirect_request &&
                 !dut.riscv_core_i.if_stage_i.pc_en_i) begin
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_NO_SOURCE_DEMAND;
    end else begin
      perf_if_delivery_next_reason = PERF_IF_DELIVERY_UNCLASSIFIED;
    end
  end else if (!dut.riscv_core_i.if_id_q.valid) begin
    perf_if_delivery_next_valid = 1'b0;
    perf_if_delivery_next_reason = PERF_IF_DELIVERY_ID_HOLD_EMPTY;
  end
end
wire perf_any_selected_stall =
  dut.riscv_core_i.if_fetch_wait ||
  dut.riscv_core_i.mem_wait ||
  dut.riscv_core_i.load_use_stall ||
  dut.riscv_core_i.mem_load_use_stall ||
  dut.riscv_core_i.muldiv_wait ||
  dut.riscv_core_i.fpu_wait ||
  perf_fpu_dependency_stall;
// Return classification is deliberately ABI-shaped rather than target-shaped:
// RISC-V standard returns are JALR x0, 0(x1/x5), including decompressed C.JR.
// A small RAS would push any JAL/JALR that writes a standard link register.
wire perf_jalr_return =
  perf_arch_retire &&
  (dut.riscv_core_i.id_ex_q.jump_op == riscv_pkg::JUMP_JALR) &&
  (dut.riscv_core_i.id_ex_q.rd_addr == 5'd0) &&
  ((dut.riscv_core_i.id_ex_q.rs1_addr == 5'd1) ||
   (dut.riscv_core_i.id_ex_q.rs1_addr == 5'd5)) &&
  (dut.riscv_core_i.id_ex_q.imm == 32'd0);
wire perf_ras_push =
  perf_arch_retire &&
  ((dut.riscv_core_i.id_ex_q.jump_op == riscv_pkg::JUMP_JAL) ||
   (dut.riscv_core_i.id_ex_q.jump_op == riscv_pkg::JUMP_JALR)) &&
  ((dut.riscv_core_i.id_ex_q.rd_addr == 5'd1) ||
   (dut.riscv_core_i.id_ex_q.rd_addr == 5'd5));
wire [31:0] perf_ras_push_addr =
  dut.riscv_core_i.id_ex_q.pc + (dut.riscv_core_i.id_ex_q.compressed ? 32'd2 : 32'd4);
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    perf_profile_started_q <= 1'b0;
    perf_profile_completed_q <= 1'b0;
    perf_if_pending_q <= 1'b0;
    perf_if_counted_q <= 1'b0;
    perf_dbus_pending_q <= 1'b0;
    perf_dbus_counted_q <= 1'b0;
    perf_dbus_write_q <= 1'b0;
    perf_redirect_recovery_q <= 1'b0;
    perf_idex_bubble_cause_q <= PERF_IDEX_BUBBLE_NONE;
    perf_if_delivery_sample_q <= 1'b0;
    perf_if_delivery_valid_q <= 1'b0;
    perf_if_delivery_reason_q <= PERF_IF_DELIVERY_VALID;
    perf_if_delivery_pc_q <= '0;
    perf_if_delivery_value0_q <= '0;
    perf_ifid_invalid_delivery_sample_q <= 1'b0;
    perf_ifid_invalid_delivery_reason_q <= PERF_IF_DELIVERY_VALID;
    perf_ifid_invalid_delivery_pc_q <= '0;
    perf_ifid_invalid_delivery_value0_q <= '0;
    perf_dbus_target_q <= PERF_DBUS_OTHER;
    perf_dbus_pc_q <= '0;
    perf_cycle_q <= 0;
    perf_if_start_cycle_q <= 0;
    perf_dbus_start_cycle_q <= 0;
    perf_soc_cycles <= 0;
    perf_core_enabled_cycles <= 0;
    perf_no_retire_cycles <= 0;
    perf_no_retire_clock_off_cycles <= 0;
    perf_no_retire_wfi_sleep_cycles <= 0;
    perf_no_retire_debug_halted_cycles <= 0;
    perf_no_retire_stall_cycles <= 0;
    perf_no_retire_redirect_recovery_cycles <= 0;
    perf_no_retire_idex_empty_cycles <= 0;
    perf_idex_empty_ifid_invalid_cycles <= 0;
    perf_if_can_issue_ready_cycles <= 0;
    perf_if_can_issue_ready_no_request_cycles <= 0;
    perf_if_can_issue_ready_wait_imem_cycles <= 0;
    perf_if_can_issue_ready_accepted_cycles <= 0;
    perf_if_can_issue_blocked_cycles <= 0;
    perf_if_can_issue_blocked_multi_cycles <= 0;
    perf_if_issue_block_fetch_disabled_cycles <= 0;
    perf_if_issue_block_boot_init_cycles <= 0;
    perf_if_issue_block_hold_valid_cycles <= 0;
    perf_if_issue_block_imem_response_cycles <= 0;
    perf_if_issue_block_two_c16_cycles <= 0;
    perf_if_issue_block_upper_start_cycles <= 0;
    perf_if_issue_block_cross_word_cycles <= 0;
    perf_if_issue_block_unclassified_cycles <= 0;
    perf_if_issue_raw_fetch_disabled_cycles <= 0;
    perf_if_issue_raw_boot_init_cycles <= 0;
    perf_if_issue_raw_hold_valid_cycles <= 0;
    perf_if_issue_raw_imem_response_cycles <= 0;
    perf_if_issue_raw_two_c16_cycles <= 0;
    perf_if_issue_raw_upper_start_cycles <= 0;
    perf_if_issue_raw_cross_word_cycles <= 0;
    perf_ifid_invalid_delivery_redirect_id_branch_cycles <= 0;
    perf_ifid_invalid_delivery_redirect_id_jal_cycles <= 0;
    perf_ifid_invalid_delivery_redirect_id_ras_cycles <= 0;
    perf_ifid_invalid_delivery_redirect_ex_cycles <= 0;
    perf_ifid_invalid_delivery_redirect_trap_cycles <= 0;
    perf_ifid_invalid_delivery_redirect_debug_cycles <= 0;
    perf_ifid_invalid_delivery_redirect_fence_i_cycles <= 0;
    perf_ifid_invalid_delivery_redirect_wfi_cycles <= 0;
    perf_ifid_invalid_delivery_flush_cycles <= 0;
    perf_ifid_invalid_delivery_cross_word_wait_cycles <= 0;
    perf_ifid_invalid_delivery_upper_start_32_cycles <= 0;
    perf_ifid_invalid_delivery_response_wait_cycles <= 0;
    perf_ifid_invalid_delivery_no_source_started_cycles <= 0;
    perf_ifid_invalid_delivery_no_source_demand_cycles <= 0;
    perf_ifid_invalid_delivery_no_source_guard_cycles <= 0;
    perf_ifid_invalid_delivery_id_hold_empty_cycles <= 0;
    perf_ifid_invalid_delivery_id_hold_front_cycles <= 0;
    perf_ifid_invalid_delivery_id_hold_full_cycles <= 0;
    perf_ifid_invalid_delivery_drop_response_cycles <= 0;
    perf_ifid_invalid_delivery_unclassified_cycles <= 0;
    perf_ifid_invalid_delivery_outside_window_cycles <= 0;
    perf_idex_empty_flush_cycles <= 0;
    perf_idex_empty_hold_cycles <= 0;
    perf_idex_empty_decode_invalid_cycles <= 0;
    perf_idex_empty_other_cycles <= 0;
    perf_no_retire_other_cycles <= 0;
    perf_if_id_valid_cycles <= 0;
    perf_id_ex_valid_cycles <= 0;
    perf_ex_mem_valid_cycles <= 0;
    perf_mem_wb_valid_cycles <= 0;
    perf_ifetch_wait_cycles <= 0;
    perf_dbus_wait_cycles <= 0;
    perf_load_use_stall_cycles <= 0;
    perf_idex_load_use_stall_cycles <= 0;
    perf_exmem_load_use_wait_cycles <= 0;
    perf_selected_hold_cycles <= 0;
    perf_muldiv_wait_cycles <= 0;
    perf_mul_wait_cycles <= 0;
    perf_div_wait_cycles <= 0;
    perf_muldiv_only_cycles <= 0;
    perf_muldiv_overlap_cycles <= 0;
    perf_fpu_wait_cycles <= 0;
    perf_fpu_busy_cycles <= 0;
    perf_fpu_dependency_stall_cycles <= 0;
    perf_fpu_issue_accepted <= 0;
    perf_fpu_completion_accepted <= 0;
    perf_stall_ifetch_only_cycles <= 0;
    perf_stall_dbus_only_cycles <= 0;
    perf_stall_load_use_only_cycles <= 0;
    perf_stall_ifetch_dbus_cycles <= 0;
    perf_stall_ifetch_load_use_cycles <= 0;
    perf_stall_dbus_load_use_cycles <= 0;
    perf_stall_all_cycles <= 0;
    perf_ex_redirects <= 0;
    perf_cond_branch_resolved <= 0;
    perf_cond_branch_not_taken <= 0;
    perf_cond_branch_backward_resolved <= 0;
    perf_cond_branch_forward_resolved <= 0;
    perf_cond_branch_taken <= 0;
    perf_cond_branch_backward_taken <= 0;
    perf_cond_branch_forward_taken <= 0;
    perf_branch_predictions <= 0;
    perf_branch_direction_correct <= 0;
    perf_branch_prediction_corrections <= 0;
    perf_branch_predicted_taken <= 0;
    perf_branch_bht_predictions <= 0;
    perf_branch_bht_direction_correct <= 0;
    perf_branch_bht_corrections <= 0;
    perf_branch_cold_predictions <= 0;
    perf_branch_cold_direction_correct <= 0;
    perf_branch_cold_corrections <= 0;
    perf_direct_jump_predictions <= 0;
    perf_redirect_recovery_cycles <= 0;
    perf_redirect_recovery_max <= 0;
    perf_redirect_recovery_current_q <= 0;
    perf_jump_redirects <= 0;
    perf_trap_redirects <= 0;
    perf_debug_redirects <= 0;
    perf_fence_i_redirects <= 0;
    perf_wfi_redirects <= 0;
    perf_jalr_returns <= 0;
    perf_jalr_indirect_calls <= 0;
    perf_jalr_other <= 0;
    perf_ras_hw_predictions <= 0;
    perf_ras_hw_correct <= 0;
    perf_ras_hw_corrections <= 0;
    perf_ras_hw_unpredicted <= 0;
    perf_ras_pushes <= 0;
    perf_ras_return_matches <= 0;
    perf_ras_return_mismatches <= 0;
    perf_ras_empty_returns <= 0;
    perf_ras_overflows <= 0;
    perf_ras_depth_max <= 0;
    perf_call_depth_max <= 0;
    perf_ras_depth_q <= 0;
    perf_call_depth_q <= 0;
    perf_retired <= 0;
    perf_retired_load <= 0;
    perf_retired_store <= 0;
    perf_retired_branch <= 0;
    perf_retired_jump <= 0;
    perf_retired_system <= 0;
    perf_retired_other <= 0;
    perf_mul_completions <= 0;
    perf_div_completions <= 0;
    perf_retired_compressed <= 0;
    perf_retired_32b <= 0;
    perf_retired_32b_upper_half <= 0;
    perf_fwd_rs1_triggers <= 0;
    perf_fwd_rs2_triggers <= 0;
    perf_fwd_exmem_rs1_selected <= 0;
    perf_fwd_exmem_rs2_selected <= 0;
    perf_fwd_memwb_rs1_selected <= 0;
    perf_fwd_memwb_rs2_selected <= 0;
    perf_fwd_memwb_rs1_overridden <= 0;
    perf_fwd_memwb_rs2_overridden <= 0;
    perf_fwd_rs1_value_checks <= 0;
    perf_fwd_rs2_value_checks <= 0;
    perf_fwd_rs1_value_mismatches <= 0;
    perf_fwd_rs2_value_mismatches <= 0;
    perf_load_branch_rs1_selected <= 0;
    perf_load_branch_rs2_selected <= 0;
    perf_load_store_data_selected <= 0;
    perf_load_branch_rs1_mismatches <= 0;
    perf_load_branch_rs2_mismatches <= 0;
    perf_load_store_data_mismatches <= 0;
    perf_lmem_candidates <= 0;
    perf_lmem_accepted <= 0;
    perf_lmem_responses <= 0;
    perf_ifetch_requests <= 0;
    perf_ifetch_latency_total <= 0;
    perf_ifetch_latency_0 <= 0;
    perf_ifetch_latency_1 <= 0;
    perf_ifetch_latency_ge2 <= 0;
    perf_ifetch_latency_max <= 0;
    perf_dbus_load_requests <= 0;
    perf_dbus_store_requests <= 0;
    perf_dbus_load_latency_total <= 0;
    perf_dbus_store_latency_total <= 0;
    perf_dbus_load_latency_0 <= 0;
    perf_dbus_load_latency_1 <= 0;
    perf_dbus_load_latency_ge2 <= 0;
    perf_dbus_store_latency_0 <= 0;
    perf_dbus_store_latency_1 <= 0;
    perf_dbus_store_latency_ge2 <= 0;
    perf_dbus_latency_max <= 0;
    perf_dbus_error_responses <= 0;
    perf_dmem_loads <= 0; perf_dmem_stores <= 0;
    perf_imem_loads <= 0; perf_imem_stores <= 0;
    perf_clint_loads <= 0; perf_clint_stores <= 0;
    perf_plic_loads <= 0; perf_plic_stores <= 0;
    perf_apb_loads <= 0; perf_apb_stores <= 0;
    perf_other_loads <= 0; perf_other_stores <= 0;
    perf_if_dbus_imem_request_collisions <= 0;
    perf_if_dbus_imem_service_blocks <= 0;
    for (perf_target_index = 0;
         perf_target_index < PERF_DBUS_TARGET_COUNT;
         perf_target_index = perf_target_index + 1) begin
      perf_dbus_load_latency_total_by_target[perf_target_index] <= 0;
      perf_dbus_store_latency_total_by_target[perf_target_index] <= 0;
      perf_dbus_load_latency_0_by_target[perf_target_index] <= 0;
      perf_dbus_load_latency_1_by_target[perf_target_index] <= 0;
      perf_dbus_load_latency_ge2_by_target[perf_target_index] <= 0;
      perf_dbus_store_latency_0_by_target[perf_target_index] <= 0;
      perf_dbus_store_latency_1_by_target[perf_target_index] <= 0;
      perf_dbus_store_latency_ge2_by_target[perf_target_index] <= 0;
      perf_dbus_latency_max_by_target[perf_target_index] <= 0;
    end
    for (perf_load_use_class_index = 0;
         perf_load_use_class_index < PERF_LOAD_USE_CLASS_COUNT;
         perf_load_use_class_index = perf_load_use_class_index + 1) begin
      perf_load_use_idex_by_class[perf_load_use_class_index] <= 0;
      perf_load_use_exmem_by_class[perf_load_use_class_index] <= 0;
    end
    for (perf_ras_index = 0; perf_ras_index < PERF_RAS_ENTRIES;
         perf_ras_index = perf_ras_index + 1) begin
      perf_ras_stack_q[perf_ras_index] <= '0;
    end
  end else if (perf_profile_en) begin
    // Observation-cycle labels remain monotonic even when a PC window is
    // inactive. Event counters below advance only while perf_window_sample.
    perf_cycle_q <= perf_cycle_q + 1;

    if (perf_if_delivery_sample_q &&
        (dut.riscv_core_i.if_id_q.valid !== perf_if_delivery_valid_q))
      $error("TB PERF invariant: IF delivery-valid prediction mismatch");
    if (perf_window_sample) begin
      perf_if_delivery_sample_q <= 1'b1;
      perf_if_delivery_valid_q <= perf_if_delivery_next_valid;
      perf_if_delivery_reason_q <= perf_if_delivery_next_reason;
      perf_if_delivery_pc_q <= perf_if_delivery_next_pc;
      perf_if_delivery_value0_q <= perf_if_delivery_next_value0;
    end else begin
      perf_if_delivery_sample_q <= 1'b0;
      perf_if_delivery_valid_q <= 1'b0;
      perf_if_delivery_reason_q <= PERF_IF_DELIVERY_VALID;
      perf_if_delivery_pc_q <= '0;
      perf_if_delivery_value0_q <= '0;
    end
    // Capture the reason an invalid ID/EX packet is written. On the following
    // cycle that packet is observed as ID/EX empty, so live IF/ID signals are
    // no longer sufficient to explain its origin.
    if (dut.riscv_core_i.id_ex_flush) begin
      perf_idex_bubble_cause_q <= PERF_IDEX_BUBBLE_FLUSH;
      perf_ifid_invalid_delivery_sample_q <= 1'b0;
      perf_ifid_invalid_delivery_reason_q <= PERF_IF_DELIVERY_VALID;
      perf_ifid_invalid_delivery_pc_q <= '0;
      perf_ifid_invalid_delivery_value0_q <= '0;
    end else if (dut.riscv_core_i.backend_advance) begin
      if (!dut.riscv_core_i.if_id_q.valid) begin
        perf_idex_bubble_cause_q <= PERF_IDEX_BUBBLE_IFID_INVALID;
        perf_ifid_invalid_delivery_sample_q <= perf_if_delivery_sample_q;
        perf_ifid_invalid_delivery_reason_q <= perf_if_delivery_reason_q;
        perf_ifid_invalid_delivery_pc_q <= perf_if_delivery_pc_q;
        perf_ifid_invalid_delivery_value0_q <= perf_if_delivery_value0_q;
      end else if (!dut.riscv_core_i.id_stage_i.id_ex_bypassed.valid) begin
        perf_idex_bubble_cause_q <= PERF_IDEX_BUBBLE_DECODE_INVALID;
        perf_ifid_invalid_delivery_sample_q <= 1'b0;
        perf_ifid_invalid_delivery_reason_q <= PERF_IF_DELIVERY_VALID;
        perf_ifid_invalid_delivery_pc_q <= '0;
        perf_ifid_invalid_delivery_value0_q <= '0;
      end else begin
        perf_idex_bubble_cause_q <= PERF_IDEX_BUBBLE_NONE;
        perf_ifid_invalid_delivery_sample_q <= 1'b0;
        perf_ifid_invalid_delivery_reason_q <= PERF_IF_DELIVERY_VALID;
        perf_ifid_invalid_delivery_pc_q <= '0;
        perf_ifid_invalid_delivery_value0_q <= '0;
      end
    end else if (!dut.riscv_core_i.id_ex_q.valid) begin
      perf_idex_bubble_cause_q <= PERF_IDEX_BUBBLE_HOLD;
      perf_ifid_invalid_delivery_sample_q <= 1'b0;
      perf_ifid_invalid_delivery_reason_q <= PERF_IF_DELIVERY_VALID;
      perf_ifid_invalid_delivery_pc_q <= '0;
      perf_ifid_invalid_delivery_value0_q <= '0;
    end else begin
      perf_idex_bubble_cause_q <= PERF_IDEX_BUBBLE_NONE;
      perf_ifid_invalid_delivery_sample_q <= 1'b0;
      perf_ifid_invalid_delivery_reason_q <= PERF_IF_DELIVERY_VALID;
      perf_ifid_invalid_delivery_pc_q <= '0;
      perf_ifid_invalid_delivery_value0_q <= '0;
    end

    if (perf_window_start_now)
      perf_profile_started_q <= 1'b1;
    if (perf_window_stop_now) begin
      perf_profile_started_q <= 1'b0;
      perf_profile_completed_q <= 1'b1;
    end

    if (perf_window_sample) begin
      perf_soc_cycles <= perf_soc_cycles + 1;
      if (dut.core_clk_en)
        perf_core_enabled_cycles <= perf_core_enabled_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.if_id_q.valid)
        perf_if_id_valid_cycles <= perf_if_id_valid_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.id_ex_q.valid)
        perf_id_ex_valid_cycles <= perf_id_ex_valid_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.ex_mem_q.valid)
        perf_ex_mem_valid_cycles <= perf_ex_mem_valid_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.mem_wb_q.valid)
        perf_mem_wb_valid_cycles <= perf_mem_wb_valid_cycles + 1;

      // Directly classify each false IF admission decision. This is separate
      // from the delayed IF/ID-bubble classification below: `can_issue=0`
      // identifies why a new fetch could not start even when an older decoded
      // instruction may still retire in this same cycle.
      if (perf_if_issue_sample) begin
        if (dut.riscv_core_i.if_stage_i.can_issue) begin
          perf_if_can_issue_ready_cycles <= perf_if_can_issue_ready_cycles + 1;
          unique case (perf_if_issue_ready_state)
            PERF_IF_ISSUE_READY_ACCEPTED:
              perf_if_can_issue_ready_accepted_cycles <=
                perf_if_can_issue_ready_accepted_cycles + 1;
            PERF_IF_ISSUE_READY_WAIT_IMEM:
              perf_if_can_issue_ready_wait_imem_cycles <=
                perf_if_can_issue_ready_wait_imem_cycles + 1;
            default:
              perf_if_can_issue_ready_no_request_cycles <=
                perf_if_can_issue_ready_no_request_cycles + 1;
          endcase
        end else begin
          perf_if_can_issue_blocked_cycles <= perf_if_can_issue_blocked_cycles + 1;
          if ((perf_if_issue_blocker_mask &
               (perf_if_issue_blocker_mask - 7'd1)) != 7'd0)
            perf_if_can_issue_blocked_multi_cycles <=
              perf_if_can_issue_blocked_multi_cycles + 1;
          if (perf_if_block_fetch_disabled)
            perf_if_issue_raw_fetch_disabled_cycles <=
              perf_if_issue_raw_fetch_disabled_cycles + 1;
          if (perf_if_block_boot_init)
            perf_if_issue_raw_boot_init_cycles <=
              perf_if_issue_raw_boot_init_cycles + 1;
          if (perf_if_block_hold_valid)
            perf_if_issue_raw_hold_valid_cycles <=
              perf_if_issue_raw_hold_valid_cycles + 1;
          if (perf_if_block_imem_response)
            perf_if_issue_raw_imem_response_cycles <=
              perf_if_issue_raw_imem_response_cycles + 1;
          if (perf_if_block_two_c16)
            perf_if_issue_raw_two_c16_cycles <=
              perf_if_issue_raw_two_c16_cycles + 1;
          if (perf_if_block_upper_start) begin
            perf_if_issue_raw_upper_start_cycles <=
              perf_if_issue_raw_upper_start_cycles + 1;
          end
          if (perf_if_block_cross_word) begin
            perf_if_issue_raw_cross_word_cycles <=
              perf_if_issue_raw_cross_word_cycles + 1;
          end
          unique case (perf_if_issue_primary)
            PERF_IF_ISSUE_BLOCK_FETCH_DISABLED:
              perf_if_issue_block_fetch_disabled_cycles <=
                perf_if_issue_block_fetch_disabled_cycles + 1;
            PERF_IF_ISSUE_BLOCK_BOOT_INIT:
              perf_if_issue_block_boot_init_cycles <=
                perf_if_issue_block_boot_init_cycles + 1;
            PERF_IF_ISSUE_BLOCK_HOLD_VALID:
              perf_if_issue_block_hold_valid_cycles <=
                perf_if_issue_block_hold_valid_cycles + 1;
            PERF_IF_ISSUE_BLOCK_IMEM_RESPONSE:
              perf_if_issue_block_imem_response_cycles <=
                perf_if_issue_block_imem_response_cycles + 1;
            PERF_IF_ISSUE_BLOCK_TWO_C16:
              perf_if_issue_block_two_c16_cycles <=
                perf_if_issue_block_two_c16_cycles + 1;
            PERF_IF_ISSUE_BLOCK_UPPER_START:
              perf_if_issue_block_upper_start_cycles <=
                perf_if_issue_block_upper_start_cycles + 1;
            PERF_IF_ISSUE_BLOCK_CROSS_WORD:
              perf_if_issue_block_cross_word_cycles <=
                perf_if_issue_block_cross_word_cycles + 1;
            default:
              perf_if_issue_block_unclassified_cycles <=
                perf_if_issue_block_unclassified_cycles + 1;
          endcase
        end
      end

      // Mutually exclusive no-retire reasons close exactly against window
      // cycles. Selected stalls have priority over redirect recovery because
      // they are the immediate reason retirement could not advance.
      if (!perf_arch_retire) begin
        perf_no_retire_cycles <= perf_no_retire_cycles + 1;
        if (dut.riscv_core_i.debug_halted_q)
          perf_no_retire_debug_halted_cycles <= perf_no_retire_debug_halted_cycles + 1;
        else if (dut.riscv_core_i.wfi_sleep_q)
          perf_no_retire_wfi_sleep_cycles <= perf_no_retire_wfi_sleep_cycles + 1;
        else if (!dut.core_clk_en)
          perf_no_retire_clock_off_cycles <= perf_no_retire_clock_off_cycles + 1;
        else if (perf_any_selected_stall)
          perf_no_retire_stall_cycles <= perf_no_retire_stall_cycles + 1;
        else if (perf_redirect_recovery_q)
          perf_no_retire_redirect_recovery_cycles <=
            perf_no_retire_redirect_recovery_cycles + 1;
        else if (!dut.riscv_core_i.id_ex_q.valid) begin
          perf_no_retire_idex_empty_cycles <= perf_no_retire_idex_empty_cycles + 1;
          // Attribute against the registered write cause, not current live
          // controls: ID/EX is observed one cycle after its bubble is formed.
          unique case (perf_idex_bubble_cause_q)
            PERF_IDEX_BUBBLE_IFID_INVALID:
              begin
                perf_idex_empty_ifid_invalid_cycles <=
                  perf_idex_empty_ifid_invalid_cycles + 1;
                // This is the exact source of the IF/ID packet, predicted
                // before the IF clock edge and checked against the resulting
                // IF/ID valid state on the following edge.
                if (!perf_ifid_invalid_delivery_sample_q) begin
                  perf_ifid_invalid_delivery_outside_window_cycles <=
                    perf_ifid_invalid_delivery_outside_window_cycles + 1;
                end else begin
                  unique case (perf_ifid_invalid_delivery_reason_q)
                    PERF_IF_DELIVERY_REDIRECT_ID_BRANCH:
                      perf_ifid_invalid_delivery_redirect_id_branch_cycles <=
                        perf_ifid_invalid_delivery_redirect_id_branch_cycles + 1;
                    PERF_IF_DELIVERY_REDIRECT_ID_JAL:
                      perf_ifid_invalid_delivery_redirect_id_jal_cycles <=
                        perf_ifid_invalid_delivery_redirect_id_jal_cycles + 1;
                    PERF_IF_DELIVERY_REDIRECT_ID_RAS:
                      perf_ifid_invalid_delivery_redirect_id_ras_cycles <=
                        perf_ifid_invalid_delivery_redirect_id_ras_cycles + 1;
                    PERF_IF_DELIVERY_REDIRECT_EX:
                      perf_ifid_invalid_delivery_redirect_ex_cycles <=
                        perf_ifid_invalid_delivery_redirect_ex_cycles + 1;
                    PERF_IF_DELIVERY_REDIRECT_TRAP:
                      perf_ifid_invalid_delivery_redirect_trap_cycles <=
                        perf_ifid_invalid_delivery_redirect_trap_cycles + 1;
                    PERF_IF_DELIVERY_REDIRECT_DEBUG:
                      perf_ifid_invalid_delivery_redirect_debug_cycles <=
                        perf_ifid_invalid_delivery_redirect_debug_cycles + 1;
                    PERF_IF_DELIVERY_REDIRECT_FENCE_I:
                      perf_ifid_invalid_delivery_redirect_fence_i_cycles <=
                        perf_ifid_invalid_delivery_redirect_fence_i_cycles + 1;
                    PERF_IF_DELIVERY_REDIRECT_WFI:
                      perf_ifid_invalid_delivery_redirect_wfi_cycles <=
                        perf_ifid_invalid_delivery_redirect_wfi_cycles + 1;
                    PERF_IF_DELIVERY_FLUSH:
                      perf_ifid_invalid_delivery_flush_cycles <=
                        perf_ifid_invalid_delivery_flush_cycles + 1;
                    PERF_IF_DELIVERY_CROSS_WORD_WAIT:
                      perf_ifid_invalid_delivery_cross_word_wait_cycles <=
                        perf_ifid_invalid_delivery_cross_word_wait_cycles + 1;
                    PERF_IF_DELIVERY_UPPER_START_32:
                      perf_ifid_invalid_delivery_upper_start_32_cycles <=
                        perf_ifid_invalid_delivery_upper_start_32_cycles + 1;
                    PERF_IF_DELIVERY_RESPONSE_WAIT:
                      perf_ifid_invalid_delivery_response_wait_cycles <=
                        perf_ifid_invalid_delivery_response_wait_cycles + 1;
                    PERF_IF_DELIVERY_NO_SOURCE_STARTED:
                      perf_ifid_invalid_delivery_no_source_started_cycles <=
                        perf_ifid_invalid_delivery_no_source_started_cycles + 1;
                    PERF_IF_DELIVERY_NO_SOURCE_DEMAND:
                      perf_ifid_invalid_delivery_no_source_demand_cycles <=
                        perf_ifid_invalid_delivery_no_source_demand_cycles + 1;
                    PERF_IF_DELIVERY_NO_SOURCE_GUARD:
                      perf_ifid_invalid_delivery_no_source_guard_cycles <=
                        perf_ifid_invalid_delivery_no_source_guard_cycles + 1;
                    PERF_IF_DELIVERY_ID_HOLD_EMPTY:
                      perf_ifid_invalid_delivery_id_hold_empty_cycles <=
                        perf_ifid_invalid_delivery_id_hold_empty_cycles + 1;
                    PERF_IF_DELIVERY_ID_HOLD_FRONT:
                      perf_ifid_invalid_delivery_id_hold_front_cycles <=
                        perf_ifid_invalid_delivery_id_hold_front_cycles + 1;
                    PERF_IF_DELIVERY_ID_HOLD_FULL:
                      perf_ifid_invalid_delivery_id_hold_full_cycles <=
                        perf_ifid_invalid_delivery_id_hold_full_cycles + 1;
                    PERF_IF_DELIVERY_DROP_RESPONSE:
                      perf_ifid_invalid_delivery_drop_response_cycles <=
                        perf_ifid_invalid_delivery_drop_response_cycles + 1;
                    default:
                      perf_ifid_invalid_delivery_unclassified_cycles <=
                        perf_ifid_invalid_delivery_unclassified_cycles + 1;
                  endcase
                  perf_trace_if_delivery_to_bubble(
                    perf_ifid_invalid_delivery_reason_q,
                    perf_ifid_invalid_delivery_pc_q,
                    perf_ifid_invalid_delivery_value0_q);
                end
              end
            PERF_IDEX_BUBBLE_FLUSH:
              perf_idex_empty_flush_cycles <= perf_idex_empty_flush_cycles + 1;
            PERF_IDEX_BUBBLE_HOLD:
              perf_idex_empty_hold_cycles <= perf_idex_empty_hold_cycles + 1;
            PERF_IDEX_BUBBLE_DECODE_INVALID:
              perf_idex_empty_decode_invalid_cycles <=
                perf_idex_empty_decode_invalid_cycles + 1;
            default:
              perf_idex_empty_other_cycles <= perf_idex_empty_other_cycles + 1;
          endcase
        end else
          perf_no_retire_other_cycles <= perf_no_retire_other_cycles + 1;
      end

      if (dut.core_clk_en && dut.riscv_core_i.if_fetch_wait)
        perf_ifetch_wait_cycles <= perf_ifetch_wait_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.mem_wait)
        perf_dbus_wait_cycles <= perf_dbus_wait_cycles + 1;
      if (dut.core_clk_en &&
          (dut.riscv_core_i.load_use_stall || dut.riscv_core_i.mem_load_use_stall))
        perf_load_use_stall_cycles <= perf_load_use_stall_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.load_use_stall)
        perf_idex_load_use_stall_cycles <= perf_idex_load_use_stall_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.mem_load_use_stall)
        perf_exmem_load_use_wait_cycles <= perf_exmem_load_use_wait_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.muldiv_wait) begin
        perf_muldiv_wait_cycles <= perf_muldiv_wait_cycles + 1;
        if (dut.riscv_core_i.id_ex_q.muldiv_op[2])
          perf_div_wait_cycles <= perf_div_wait_cycles + 1;
        else
          perf_mul_wait_cycles <= perf_mul_wait_cycles + 1;
        if (dut.riscv_core_i.if_fetch_wait || dut.riscv_core_i.mem_wait ||
            dut.riscv_core_i.load_use_stall || dut.riscv_core_i.mem_load_use_stall)
          perf_muldiv_overlap_cycles <= perf_muldiv_overlap_cycles + 1;
        else
          perf_muldiv_only_cycles <= perf_muldiv_only_cycles + 1;
      end
      if (dut.core_clk_en && dut.riscv_core_i.fpu_wait)
        perf_fpu_wait_cycles <= perf_fpu_wait_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.fpu_busy)
        perf_fpu_busy_cycles <= perf_fpu_busy_cycles + 1;
      if (dut.core_clk_en && perf_fpu_dependency_stall)
        perf_fpu_dependency_stall_cycles <=
          perf_fpu_dependency_stall_cycles + 1;
      if (dut.core_clk_en && dut.riscv_core_i.fpu_issue_valid &&
          dut.riscv_core_i.fpu_issue_ready)
        perf_fpu_issue_accepted <= perf_fpu_issue_accepted + 1;
      if (dut.core_clk_en && dut.riscv_core_i.fpu_complete_valid &&
          dut.riscv_core_i.fpu_complete_ready)
        perf_fpu_completion_accepted <= perf_fpu_completion_accepted + 1;
      if (dut.core_clk_en && perf_any_selected_stall)
        perf_selected_hold_cycles <= perf_selected_hold_cycles + 1;
      if (dut.core_clk_en) begin
        unique case ({dut.riscv_core_i.if_fetch_wait,
                     dut.riscv_core_i.mem_wait,
                     dut.riscv_core_i.load_use_stall || dut.riscv_core_i.mem_load_use_stall})
          3'b001: perf_stall_load_use_only_cycles <= perf_stall_load_use_only_cycles + 1;
          3'b010: perf_stall_dbus_only_cycles <= perf_stall_dbus_only_cycles + 1;
          3'b011: perf_stall_dbus_load_use_cycles <= perf_stall_dbus_load_use_cycles + 1;
          3'b100: perf_stall_ifetch_only_cycles <= perf_stall_ifetch_only_cycles + 1;
          3'b101: perf_stall_ifetch_load_use_cycles <= perf_stall_ifetch_load_use_cycles + 1;
          3'b110: perf_stall_ifetch_dbus_cycles <= perf_stall_ifetch_dbus_cycles + 1;
          3'b111: perf_stall_all_cycles <= perf_stall_all_cycles + 1;
          default: ;
        endcase
      end

      if (dut.core_clk_en && dut.riscv_core_i.load_use_stall) begin
        perf_count_load_use_consumer(
          1'b1,
          dut.riscv_core_i.if_id_uses_rs1 &&
            (dut.riscv_core_i.id_ex_q.rd_addr == dut.riscv_core_i.if_id_rs1_addr),
          dut.riscv_core_i.if_id_uses_rs2 &&
            (dut.riscv_core_i.id_ex_q.rd_addr == dut.riscv_core_i.if_id_rs2_addr)
        );
        perf_trace_event("load_use_idex", dut.riscv_core_i.if_id_q.pc,
                         dut.riscv_core_i.id_ex_q.pc,
                         {30'd0, dut.riscv_core_i.if_id_uses_rs2,
                          dut.riscv_core_i.if_id_uses_rs1});
      end
      if (dut.core_clk_en && dut.riscv_core_i.mem_load_use_stall) begin
        perf_count_load_use_consumer(
          1'b0,
          dut.riscv_core_i.if_id_uses_rs1 &&
            (dut.riscv_core_i.ex_mem_q.rd_addr == dut.riscv_core_i.if_id_rs1_addr),
          dut.riscv_core_i.if_id_uses_rs2 &&
            (dut.riscv_core_i.ex_mem_q.rd_addr == dut.riscv_core_i.if_id_rs2_addr)
        );
        perf_trace_event("load_use_exmem", dut.riscv_core_i.if_id_q.pc,
                         dut.riscv_core_i.ex_mem_q.pc,
                         {30'd0, dut.riscv_core_i.if_id_uses_rs2,
                          dut.riscv_core_i.if_id_uses_rs1});
      end
      // A correction/unpredicted-jump redirect begins a recovery interval.
      // The interval ends at the next architectural retirement.
      if (dut.core_clk_en && dut.riscv_core_i.branch_redirect) begin
        perf_ex_redirects <= perf_ex_redirects + 1;
        perf_redirect_recovery_q <= 1'b1;
        perf_redirect_recovery_current_q <= 0;
        if (dut.riscv_core_i.id_ex_q.branch_op == riscv_pkg::BR_NONE)
          perf_jump_redirects <= perf_jump_redirects + 1;
      end else if (perf_redirect_recovery_q) begin
        if (perf_arch_retire) begin
          perf_redirect_recovery_q <= 1'b0;
          if (perf_redirect_recovery_current_q > perf_redirect_recovery_max)
            perf_redirect_recovery_max <= perf_redirect_recovery_current_q;
        end else begin
          perf_redirect_recovery_current_q <= perf_redirect_recovery_current_q + 1;
          perf_redirect_recovery_cycles <= perf_redirect_recovery_cycles + 1;
        end
      end

      if (perf_arch_retire &&
          dut.riscv_core_i.id_ex_q.branch_op != riscv_pkg::BR_NONE) begin
        perf_cond_branch_resolved <= perf_cond_branch_resolved + 1;
        if ((dut.riscv_core_i.id_ex_q.pc + dut.riscv_core_i.id_ex_q.imm) <
            dut.riscv_core_i.id_ex_q.pc)
          perf_cond_branch_backward_resolved <= perf_cond_branch_backward_resolved + 1;
        else
          perf_cond_branch_forward_resolved <= perf_cond_branch_forward_resolved + 1;
        if (dut.riscv_core_i.ex_stage_i.branch_taken) begin
          perf_cond_branch_taken <= perf_cond_branch_taken + 1;
          if ((dut.riscv_core_i.id_ex_q.pc + dut.riscv_core_i.id_ex_q.imm) <
              dut.riscv_core_i.id_ex_q.pc)
            perf_cond_branch_backward_taken <= perf_cond_branch_backward_taken + 1;
          else
            perf_cond_branch_forward_taken <= perf_cond_branch_forward_taken + 1;
        end else begin
          perf_cond_branch_not_taken <= perf_cond_branch_not_taken + 1;
        end
        if (dut.riscv_core_i.id_ex_q.branch_pred_valid) begin
          perf_branch_predictions <= perf_branch_predictions + 1;
          if (dut.riscv_core_i.id_ex_q.branch_pred_taken)
            perf_branch_predicted_taken <= perf_branch_predicted_taken + 1;
          if (dut.riscv_core_i.ex_stage_i.branch_taken ==
              dut.riscv_core_i.id_ex_q.branch_pred_taken)
            perf_branch_direction_correct <= perf_branch_direction_correct + 1;
          else
            perf_branch_prediction_corrections <= perf_branch_prediction_corrections + 1;
          if (dut.riscv_core_i.id_ex_q.branch_pred_bht_used) begin
            perf_branch_bht_predictions <= perf_branch_bht_predictions + 1;
            if (dut.riscv_core_i.ex_stage_i.branch_taken ==
                dut.riscv_core_i.id_ex_q.branch_pred_taken)
              perf_branch_bht_direction_correct <= perf_branch_bht_direction_correct + 1;
            else
              perf_branch_bht_corrections <= perf_branch_bht_corrections + 1;
          end else begin
            perf_branch_cold_predictions <= perf_branch_cold_predictions + 1;
            if (dut.riscv_core_i.ex_stage_i.branch_taken ==
                dut.riscv_core_i.id_ex_q.branch_pred_taken)
              perf_branch_cold_direction_correct <=
                perf_branch_cold_direction_correct + 1;
            else
              perf_branch_cold_corrections <= perf_branch_cold_corrections + 1;
          end
        end
      end
      if (perf_arch_retire &&
          dut.riscv_core_i.id_ex_q.jump_op == riscv_pkg::JUMP_JAL &&
          dut.riscv_core_i.id_ex_q.jal_early)
        perf_direct_jump_predictions <= perf_direct_jump_predictions + 1;
      if (perf_arch_retire &&
          dut.riscv_core_i.id_ex_q.jump_op == riscv_pkg::JUMP_JALR) begin
        if (perf_jalr_return) begin
          perf_jalr_returns <= perf_jalr_returns + 1;
          if (dut.riscv_core_i.id_ex_q.return_pred_valid) begin
            perf_ras_hw_predictions <= perf_ras_hw_predictions + 1;
            if (dut.riscv_core_i.ex_stage_i.jalr_target ==
                dut.riscv_core_i.id_ex_q.return_pred_target)
              perf_ras_hw_correct <= perf_ras_hw_correct + 1;
            else
              perf_ras_hw_corrections <= perf_ras_hw_corrections + 1;
          end else begin
            perf_ras_hw_unpredicted <= perf_ras_hw_unpredicted + 1;
          end
        end else if ((dut.riscv_core_i.id_ex_q.rd_addr == 5'd1) ||
                 (dut.riscv_core_i.id_ex_q.rd_addr == 5'd5))
          perf_jalr_indirect_calls <= perf_jalr_indirect_calls + 1;
        else
          perf_jalr_other <= perf_jalr_other + 1;
      end
      // This is a non-architectural four-entry RAS model used only to decide
      // whether a hardware return predictor is justified. A stack overflow is
      // retained as a miss rather than silently overwriting an older return.
      if (perf_ras_push) begin
        perf_ras_pushes <= perf_ras_pushes + 1;
        perf_call_depth_q <= perf_call_depth_q + 1;
        if ((perf_call_depth_q + 1) > perf_call_depth_max)
          perf_call_depth_max <= perf_call_depth_q + 1;
        if (perf_ras_depth_q < PERF_RAS_ENTRIES) begin
          perf_ras_stack_q[perf_ras_depth_q] <= perf_ras_push_addr;
          perf_ras_depth_q <= perf_ras_depth_q + 1;
          if ((perf_ras_depth_q + 1) > perf_ras_depth_max)
            perf_ras_depth_max <= perf_ras_depth_q + 1;
        end else begin
          perf_ras_overflows <= perf_ras_overflows + 1;
        end
      end else if (perf_jalr_return) begin
        if (perf_call_depth_q > 0)
          perf_call_depth_q <= perf_call_depth_q - 1;
        if (perf_ras_depth_q > 0) begin
          if (perf_ras_stack_q[perf_ras_depth_q - 1] ==
              dut.riscv_core_i.ex_stage_i.jalr_target)
            perf_ras_return_matches <= perf_ras_return_matches + 1;
          else
            perf_ras_return_mismatches <= perf_ras_return_mismatches + 1;
          perf_ras_depth_q <= perf_ras_depth_q - 1;
        end else begin
          perf_ras_empty_returns <= perf_ras_empty_returns + 1;
        end
      end
      if (dut.core_clk_en && dut.riscv_core_i.trap_redirect)
        perf_trap_redirects <= perf_trap_redirects + 1;
      if (dut.core_clk_en && dut.riscv_core_i.debug_redirect)
        perf_debug_redirects <= perf_debug_redirects + 1;
      if (dut.core_clk_en && dut.riscv_core_i.fence_i_redirect)
        perf_fence_i_redirects <= perf_fence_i_redirects + 1;
      if (dut.core_clk_en && dut.riscv_core_i.wfi_redirect)
        perf_wfi_redirects <= perf_wfi_redirects + 1;

      // Instruction mix and width share one canonical architectural-retire
      // pulse. A held MEM/WB packet and serialized control packets are not
      // retirement events.
      if (perf_arch_retire) begin
        perf_retired <= perf_retired + 1;
        unique case (dut.riscv_core_i.id_ex_q.instr[6:0])
          7'b0000011: perf_retired_load <= perf_retired_load + 1;
          7'b0100011: perf_retired_store <= perf_retired_store + 1;
          7'b1100011: perf_retired_branch <= perf_retired_branch + 1;
          7'b1101111,
          7'b1100111: perf_retired_jump <= perf_retired_jump + 1;
          7'b1110011: perf_retired_system <= perf_retired_system + 1;
          default:    perf_retired_other <= perf_retired_other + 1;
        endcase
        if (dut.riscv_core_i.id_ex_q.compressed) begin
          perf_retired_compressed <= perf_retired_compressed + 1;
        end else begin
          perf_retired_32b <= perf_retired_32b + 1;
          if (dut.riscv_core_i.id_ex_q.pc[1])
            perf_retired_32b_upper_half <= perf_retired_32b_upper_half + 1;
        end
        if (dut.riscv_core_i.id_ex_q.muldiv_en) begin
          if (dut.riscv_core_i.id_ex_q.muldiv_op[2])
            perf_div_completions <= perf_div_completions + 1;
          else
            perf_mul_completions <= perf_mul_completions + 1;
        end
      end

      // Sample forwarding when an instruction consumes its EX operands. A
      // multi-cycle M instruction consumes once at start, not again at its
      // later completion. Trigger counts are source operands, not instructions.
      if ((perf_arch_retire && !dut.riscv_core_i.id_ex_q.muldiv_en) ||
          (dut.core_clk_en && dut.riscv_core_i.ex_stage_i.muldiv_start)) begin
        if (perf_instr_uses_rs1(dut.riscv_core_i.id_ex_q.instr) &&
            !dut.riscv_core_i.ex_stage_i.load_branch_rs1_match &&
            (dut.riscv_core_i.ex_stage_i.forwarding_unit_i.ex_mem_rs1_match ||
             dut.riscv_core_i.ex_stage_i.forwarding_unit_i.mem_wb_rs1_match)) begin
          perf_fwd_rs1_triggers <= perf_fwd_rs1_triggers + 1;
          perf_fwd_rs1_value_checks <= perf_fwd_rs1_value_checks + 1;
          if (dut.riscv_core_i.ex_stage_i.forwarding_unit_i.ex_mem_rs1_match) begin
            perf_fwd_exmem_rs1_selected <= perf_fwd_exmem_rs1_selected + 1;
            if (dut.riscv_core_i.ex_stage_i.forwarding_unit_i.mem_wb_rs1_match)
              perf_fwd_memwb_rs1_overridden <= perf_fwd_memwb_rs1_overridden + 1;
            if (dut.riscv_core_i.ex_stage_i.rs1_data !==
                dut.riscv_core_i.ex_mem_q.ex_result)
              perf_fwd_rs1_value_mismatches <= perf_fwd_rs1_value_mismatches + 1;
          end else begin
            perf_fwd_memwb_rs1_selected <= perf_fwd_memwb_rs1_selected + 1;
            if (dut.riscv_core_i.ex_stage_i.rs1_data !==
                dut.riscv_core_i.mem_wb_q.wb_data)
              perf_fwd_rs1_value_mismatches <= perf_fwd_rs1_value_mismatches + 1;
          end
        end
        if (perf_instr_uses_rs2(dut.riscv_core_i.id_ex_q.instr) &&
            !dut.riscv_core_i.ex_stage_i.load_branch_rs2_match &&
            !dut.riscv_core_i.ex_stage_i.load_store_data_match &&
            (dut.riscv_core_i.ex_stage_i.forwarding_unit_i.ex_mem_rs2_match ||
             dut.riscv_core_i.ex_stage_i.forwarding_unit_i.mem_wb_rs2_match)) begin
          perf_fwd_rs2_triggers <= perf_fwd_rs2_triggers + 1;
          perf_fwd_rs2_value_checks <= perf_fwd_rs2_value_checks + 1;
          if (dut.riscv_core_i.ex_stage_i.forwarding_unit_i.ex_mem_rs2_match) begin
            perf_fwd_exmem_rs2_selected <= perf_fwd_exmem_rs2_selected + 1;
            if (dut.riscv_core_i.ex_stage_i.forwarding_unit_i.mem_wb_rs2_match)
              perf_fwd_memwb_rs2_overridden <= perf_fwd_memwb_rs2_overridden + 1;
            if (dut.riscv_core_i.ex_stage_i.rs2_data !==
                dut.riscv_core_i.ex_mem_q.ex_result)
              perf_fwd_rs2_value_mismatches <= perf_fwd_rs2_value_mismatches + 1;
          end else begin
            perf_fwd_memwb_rs2_selected <= perf_fwd_memwb_rs2_selected + 1;
            if (dut.riscv_core_i.ex_stage_i.rs2_data !==
                dut.riscv_core_i.mem_wb_q.wb_data)
              perf_fwd_rs2_value_mismatches <= perf_fwd_rs2_value_mismatches + 1;
          end
        end

        if (dut.riscv_core_i.ex_stage_i.load_branch_rs1_match) begin
          perf_load_branch_rs1_selected <= perf_load_branch_rs1_selected + 1;
          if (dut.riscv_core_i.ex_stage_i.branch_operand_a !==
              dut.riscv_core_i.load_result_bypass_data)
            perf_load_branch_rs1_mismatches <=
              perf_load_branch_rs1_mismatches + 1;
        end
        if (dut.riscv_core_i.ex_stage_i.load_branch_rs2_match) begin
          perf_load_branch_rs2_selected <= perf_load_branch_rs2_selected + 1;
          if (dut.riscv_core_i.ex_stage_i.branch_operand_b !==
              dut.riscv_core_i.load_result_bypass_data)
            perf_load_branch_rs2_mismatches <=
              perf_load_branch_rs2_mismatches + 1;
        end
      end

      if (dut.core_clk_en &&
          dut.riscv_core_i.mem_stage_i.load_store_data_match) begin
        perf_load_store_data_selected <= perf_load_store_data_selected + 1;
        if (dut.riscv_core_i.mem_stage_i.store_data !==
            dut.riscv_core_i.mem_wb_q.wb_data)
          perf_load_store_data_mismatches <=
            perf_load_store_data_mismatches + 1;
      end

      if (dut.lmem_req)
        perf_lmem_candidates <= perf_lmem_candidates + 1;
      if (dut.lmem_accept)
        perf_lmem_accepted <= perf_lmem_accepted + 1;
      if (dut.lmem_resp_valid)
        perf_lmem_responses <= perf_lmem_responses + 1;

      if (dut.imem_req && dut.imem_dbus_req)
        perf_if_dbus_imem_request_collisions <=
          perf_if_dbus_imem_request_collisions + 1;
      if (dut.imem_req && !dut.imem_ready)
        perf_if_dbus_imem_service_blocks <= perf_if_dbus_imem_service_blocks + 1;
    end

    // Track IF protocol ownership continuously. A response may retire while a
    // replacement request is accepted in the same cycle.
    if (perf_if_pending_q && dut.imem_rvalid) begin
      if (perf_if_counted_q)
        perf_record_ifetch_latency(perf_cycle_q - perf_if_start_cycle_q);
      if (perf_if_request_accepted) begin
        if (perf_window_sample)
          perf_ifetch_requests <= perf_ifetch_requests + 1;
        perf_if_pending_q <= 1'b1;
        perf_if_counted_q <= perf_window_sample;
        perf_if_start_cycle_q <= perf_cycle_q;
      end else begin
        perf_if_pending_q <= 1'b0;
        perf_if_counted_q <= 1'b0;
      end
    end else if (!perf_if_pending_q && perf_if_request_accepted) begin
      if (perf_window_sample)
        perf_ifetch_requests <= perf_ifetch_requests + 1;
      if (dut.imem_rvalid) begin
        if (perf_window_sample)
          perf_record_ifetch_latency(64'd0);
        perf_if_pending_q <= 1'b0;
        perf_if_counted_q <= 1'b0;
      end else begin
        perf_if_pending_q <= 1'b1;
        perf_if_counted_q <= perf_window_sample;
        perf_if_start_cycle_q <= perf_cycle_q;
      end
    end

    // DBus requests are one-shot accepted requests in the current core. Keep
    // response ownership explicit so future same-cycle replacement requests
    // remain measurable without pairing against the previous response.
    if (perf_dbus_pending_q && dut.data_resp_valid) begin
      if (perf_dbus_counted_q) begin
        perf_record_dbus_latency(perf_dbus_target_q, perf_dbus_write_q,
                                 perf_cycle_q - perf_dbus_start_cycle_q);
        if (dut.data_err || ((perf_cycle_q - perf_dbus_start_cycle_q) > 64'd1))
          perf_trace_event("dbus_slow_or_error_resp", perf_dbus_pc_q,
                           perf_dbus_trace_meta(perf_dbus_target_q, perf_dbus_write_q),
                           perf_cycle_q[31:0] - perf_dbus_start_cycle_q[31:0]);
        if (dut.data_err)
          perf_dbus_error_responses <= perf_dbus_error_responses + 1;
      end
      if (dut.data_req) begin
        if (perf_window_sample) begin
          perf_count_dbus_target(perf_dbus_target(dut.data_addr), dut.data_we);
          if (dut.data_we)
            perf_dbus_store_requests <= perf_dbus_store_requests + 1;
          else
            perf_dbus_load_requests <= perf_dbus_load_requests + 1;
        end
        perf_dbus_pending_q <= 1'b1;
        perf_dbus_counted_q <= perf_window_sample;
        perf_dbus_write_q <= dut.data_we;
        perf_dbus_target_q <= perf_dbus_target(dut.data_addr);
        perf_dbus_pc_q <= dut.riscv_core_i.ex_mem_q.pc;
        perf_dbus_start_cycle_q <= perf_cycle_q;
      end else begin
        perf_dbus_pending_q <= 1'b0;
        perf_dbus_counted_q <= 1'b0;
      end
    end else if (!perf_dbus_pending_q && dut.data_req) begin
      if (perf_window_sample) begin
        perf_count_dbus_target(perf_dbus_target(dut.data_addr), dut.data_we);
        if (dut.data_we)
          perf_dbus_store_requests <= perf_dbus_store_requests + 1;
        else
          perf_dbus_load_requests <= perf_dbus_load_requests + 1;
      end
      if (dut.data_resp_valid) begin
        if (perf_window_sample) begin
          perf_record_dbus_latency(perf_dbus_target(dut.data_addr), dut.data_we, 64'd0);
          if (dut.data_err)
            perf_trace_event("dbus_slow_or_error_resp", dut.riscv_core_i.ex_mem_q.pc,
                             perf_dbus_trace_meta(perf_dbus_target(dut.data_addr), dut.data_we),
                             32'd0);
          if (dut.data_err)
            perf_dbus_error_responses <= perf_dbus_error_responses + 1;
        end
        perf_dbus_pending_q <= 1'b0;
        perf_dbus_counted_q <= 1'b0;
      end else begin
        perf_dbus_pending_q <= 1'b1;
        perf_dbus_counted_q <= perf_window_sample;
        perf_dbus_write_q <= dut.data_we;
        perf_dbus_target_q <= perf_dbus_target(dut.data_addr);
        perf_dbus_pc_q <= dut.riscv_core_i.ex_mem_q.pc;
        perf_dbus_start_cycle_q <= perf_cycle_q;
      end
    end
  end
end

task automatic perf_report_dbus_target_latency(input string name, input int target);
  begin
    $display("TB PERF DBUS %s: load(lat_total=%0d hist0=%0d hist1=%0d hist2plus=%0d) store(lat_total=%0d hist0=%0d hist1=%0d hist2plus=%0d) max=%0d",
             name,
             perf_dbus_load_latency_total_by_target[target],
             perf_dbus_load_latency_0_by_target[target],
             perf_dbus_load_latency_1_by_target[target],
             perf_dbus_load_latency_ge2_by_target[target],
             perf_dbus_store_latency_total_by_target[target],
             perf_dbus_store_latency_0_by_target[target],
             perf_dbus_store_latency_1_by_target[target],
             perf_dbus_store_latency_ge2_by_target[target],
             perf_dbus_latency_max_by_target[target]);
  end
endtask

task automatic report_perf_profile;
  begin
    if (perf_has_start_pc)
      $display("TB PERF WINDOW: retired_pc_inclusive start=%08h stop=%08h stop_enabled=%0d completed=%0d",
               perf_start_pc, perf_stop_pc, perf_has_stop_pc, perf_profile_completed_q);
    else if (perf_has_stop_pc)
      $display("TB PERF WINDOW: core_fetch_enable_to_retired_pc_inclusive stop=%08h completed=%0d",
               perf_stop_pc, perf_profile_completed_q);
    else
      $display("TB PERF WINDOW: core_fetch_enable_to_test_end");
    $display("TB PERF PROFILE: raw_global_csr(mcycle=%0d minstret=%0d) window_cycles=%0d core_clock_enabled=%0d",
             dut.riscv_core_i.ex_stage_i.csr_file_i.mcycle_q,
             dut.riscv_core_i.ex_stage_i.csr_file_i.minstret_q,
             perf_soc_cycles, perf_core_enabled_cycles);
    $display("TB PERF CYCLE CLOSURE: retired=%0d no_retire=%0d no_retire_reason(clock_off=%0d wfi_sleep=%0d debug_halted=%0d selected_stall=%0d redirect_recovery=%0d idex_empty=%0d other=%0d)",
             perf_retired, perf_no_retire_cycles,
             perf_no_retire_clock_off_cycles, perf_no_retire_wfi_sleep_cycles,
             perf_no_retire_debug_halted_cycles, perf_no_retire_stall_cycles,
             perf_no_retire_redirect_recovery_cycles,
             perf_no_retire_idex_empty_cycles, perf_no_retire_other_cycles);
    $display("TB PERF IDEX EMPTY: ifid_invalid=%0d flush=%0d hold=%0d decode_invalid=%0d other=%0d",
             perf_idex_empty_ifid_invalid_cycles, perf_idex_empty_flush_cycles,
             perf_idex_empty_hold_cycles, perf_idex_empty_decode_invalid_cycles,
             perf_idex_empty_other_cycles);
    $display("TB PERF IF ADMISSION: core_opportunities=%0d ready=%0d guard_active=%0d multi_guard=%0d",
             perf_if_can_issue_ready_cycles + perf_if_can_issue_blocked_cycles,
             perf_if_can_issue_ready_cycles, perf_if_can_issue_blocked_cycles,
             perf_if_can_issue_blocked_multi_cycles);
    $display("TB PERF IF ADMISSION READY: no_request=%0d wait_imem=%0d accepted=%0d",
             perf_if_can_issue_ready_no_request_cycles,
             perf_if_can_issue_ready_wait_imem_cycles,
             perf_if_can_issue_ready_accepted_cycles);
    $display("TB PERF IF ADMISSION PRIMARY GUARD: fetch_disabled=%0d boot_init=%0d hold_valid=%0d imem_response=%0d two_c16=%0d upper_start=%0d cross_word=%0d unclassified=%0d",
             perf_if_issue_block_fetch_disabled_cycles,
             perf_if_issue_block_boot_init_cycles,
             perf_if_issue_block_hold_valid_cycles,
             perf_if_issue_block_imem_response_cycles,
             perf_if_issue_block_two_c16_cycles,
             perf_if_issue_block_upper_start_cycles,
             perf_if_issue_block_cross_word_cycles,
             perf_if_issue_block_unclassified_cycles);
    $display("TB PERF IF ADMISSION RAW FLAGS (overlap allowed): fetch_disabled=%0d boot_init=%0d hold_valid=%0d imem_response=%0d two_c16=%0d upper_start=%0d cross_word=%0d",
             perf_if_issue_raw_fetch_disabled_cycles,
             perf_if_issue_raw_boot_init_cycles,
             perf_if_issue_raw_hold_valid_cycles,
             perf_if_issue_raw_imem_response_cycles,
             perf_if_issue_raw_two_c16_cycles,
             perf_if_issue_raw_upper_start_cycles,
             perf_if_issue_raw_cross_word_cycles);
    $display("TB PERF IF DELIVERY TO IDEX_BUBBLE: redirect(id_branch=%0d id_jal=%0d id_ras=%0d ex=%0d trap=%0d debug=%0d fence_i=%0d wfi=%0d) flush=%0d cross_word_wait=%0d upper_start_32=%0d response_wait=%0d no_source(started=%0d demand=%0d guard=%0d) id_hold(front=%0d full=%0d empty=%0d) drop_response=%0d unclassified=%0d outside_window=%0d",
             perf_ifid_invalid_delivery_redirect_id_branch_cycles,
             perf_ifid_invalid_delivery_redirect_id_jal_cycles,
             perf_ifid_invalid_delivery_redirect_id_ras_cycles,
             perf_ifid_invalid_delivery_redirect_ex_cycles,
             perf_ifid_invalid_delivery_redirect_trap_cycles,
             perf_ifid_invalid_delivery_redirect_debug_cycles,
             perf_ifid_invalid_delivery_redirect_fence_i_cycles,
             perf_ifid_invalid_delivery_redirect_wfi_cycles,
             perf_ifid_invalid_delivery_flush_cycles,
             perf_ifid_invalid_delivery_cross_word_wait_cycles,
             perf_ifid_invalid_delivery_upper_start_32_cycles,
             perf_ifid_invalid_delivery_response_wait_cycles,
             perf_ifid_invalid_delivery_no_source_started_cycles,
             perf_ifid_invalid_delivery_no_source_demand_cycles,
             perf_ifid_invalid_delivery_no_source_guard_cycles,
             perf_ifid_invalid_delivery_id_hold_front_cycles,
             perf_ifid_invalid_delivery_id_hold_full_cycles,
             perf_ifid_invalid_delivery_id_hold_empty_cycles,
             perf_ifid_invalid_delivery_drop_response_cycles,
             perf_ifid_invalid_delivery_unclassified_cycles,
             perf_ifid_invalid_delivery_outside_window_cycles);
    $display("TB PERF STAGE OCCUPANCY: if_id_valid=%0d id_ex_valid=%0d ex_mem_valid=%0d mem_wb_valid=%0d",
             perf_if_id_valid_cycles, perf_id_ex_valid_cycles,
             perf_ex_mem_valid_cycles, perf_mem_wb_valid_cycles);
    $display("TB PERF RETIRE: total=%0d load=%0d store=%0d branch=%0d jump=%0d system=%0d other=%0d completion_width(compressed=%0d instr32=%0d instr32_upper_half=%0d)",
             perf_retired, perf_retired_load, perf_retired_store, perf_retired_branch,
             perf_retired_jump, perf_retired_system, perf_retired_other,
             perf_retired_compressed, perf_retired_32b, perf_retired_32b_upper_half);
    $display("TB PERF STALL LEVEL CYCLES: ifetch=%0d dbus=%0d load_use(total=%0d idex=%0d exmem_wait=%0d) muldiv(total=%0d mul=%0d divrem=%0d) fpu(wait=%0d busy=%0d dependency=%0d issue=%0d completion=%0d) selected_hold_union=%0d",
             perf_ifetch_wait_cycles, perf_dbus_wait_cycles, perf_load_use_stall_cycles,
             perf_idex_load_use_stall_cycles, perf_exmem_load_use_wait_cycles,
             perf_muldiv_wait_cycles, perf_mul_wait_cycles, perf_div_wait_cycles,
             perf_fpu_wait_cycles, perf_fpu_busy_cycles,
             perf_fpu_dependency_stall_cycles, perf_fpu_issue_accepted,
             perf_fpu_completion_accepted,
             perf_selected_hold_cycles);
    $display("TB PERF CONTROL: ex_redirects=%0d branch_resolved=%0d branch_taken=%0d branch_not_taken=%0d branch_backward=%0d branch_forward=%0d taken_backward=%0d taken_forward=%0d jump_redirects=%0d direct_jal_early=%0d trap_redirects=%0d debug_redirects=%0d fencei_redirects=%0d wfi_redirects=%0d",
             perf_ex_redirects, perf_cond_branch_resolved,
             perf_cond_branch_taken, perf_cond_branch_not_taken,
             perf_cond_branch_backward_resolved, perf_cond_branch_forward_resolved,
             perf_cond_branch_backward_taken, perf_cond_branch_forward_taken,
             perf_jump_redirects, perf_direct_jump_predictions, perf_trap_redirects,
             perf_debug_redirects, perf_fence_i_redirects, perf_wfi_redirects);
    $display("TB PERF REDIRECT RECOVERY: lost_cycles=%0d max_interval=%0d open_interval=%0d",
             perf_redirect_recovery_cycles, perf_redirect_recovery_max,
             perf_redirect_recovery_q);
    $display("TB PERF JALR CLASS: returns=%0d indirect_calls=%0d other=%0d",
             perf_jalr_returns, perf_jalr_indirect_calls, perf_jalr_other);
    $display("TB PERF RAS MODEL: entries=%0d pushes=%0d return_matches=%0d return_mismatches=%0d empty_returns=%0d overflows=%0d depth_max=%0d call_depth_max=%0d",
             PERF_RAS_ENTRIES, perf_ras_pushes, perf_ras_return_matches,
             perf_ras_return_mismatches, perf_ras_empty_returns,
             perf_ras_overflows, perf_ras_depth_max, perf_call_depth_max);
    $display("TB PERF MULDIV: completions(mul=%0d divrem=%0d) wait_per_completion(mul=%0d divrem=%0d)",
             perf_mul_completions, perf_div_completions,
             (perf_mul_completions == 0) ? 0 : (perf_mul_wait_cycles / perf_mul_completions),
             (perf_div_completions == 0) ? 0 : (perf_div_wait_cycles / perf_div_completions));
    $display("TB PERF FWD: triggers(rs1=%0d rs2=%0d total=%0d) selected(exmem=%0d memwb=%0d) memwb_overridden=%0d value_checks=%0d mismatches=%0d",
             perf_fwd_rs1_triggers, perf_fwd_rs2_triggers,
             perf_fwd_rs1_triggers + perf_fwd_rs2_triggers,
             perf_fwd_exmem_rs1_selected + perf_fwd_exmem_rs2_selected,
             perf_fwd_memwb_rs1_selected + perf_fwd_memwb_rs2_selected,
             perf_fwd_memwb_rs1_overridden + perf_fwd_memwb_rs2_overridden,
             perf_fwd_rs1_value_checks + perf_fwd_rs2_value_checks,
             perf_fwd_rs1_value_mismatches + perf_fwd_rs2_value_mismatches);
    $display("TB PERF LOAD BYPASS: branch(rs1=%0d rs2=%0d) store_data=%0d value_checks=%0d mismatches=%0d",
             perf_load_branch_rs1_selected, perf_load_branch_rs2_selected,
             perf_load_store_data_selected,
             perf_load_branch_rs1_selected + perf_load_branch_rs2_selected +
               perf_load_store_data_selected,
             perf_load_branch_rs1_mismatches + perf_load_branch_rs2_mismatches +
               perf_load_store_data_mismatches);
    $display("TB PERF LMEM: candidates=%0d accepted=%0d responses=%0d",
             perf_lmem_candidates, perf_lmem_accepted,
             perf_lmem_responses);
    $display("TB PERF STALL OVERLAP: ifetch_only=%0d dbus_only=%0d load_use_only=%0d ifetch_dbus=%0d ifetch_load_use=%0d dbus_load_use=%0d all_three=%0d muldiv_only=%0d muldiv_with_other=%0d",
             perf_stall_ifetch_only_cycles, perf_stall_dbus_only_cycles,
             perf_stall_load_use_only_cycles, perf_stall_ifetch_dbus_cycles,
             perf_stall_ifetch_load_use_cycles, perf_stall_dbus_load_use_cycles,
             perf_stall_all_cycles, perf_muldiv_only_cycles,
             perf_muldiv_overlap_cycles);
    $display("TB PERF LOAD_USE IDEX: alu=%0d load_addr=%0d branch=%0d jalr=%0d store_addr=%0d store_data=%0d store_both=%0d system=%0d",
             perf_load_use_idex_by_class[PERF_LOAD_USE_ALU],
             perf_load_use_idex_by_class[PERF_LOAD_USE_LOAD_ADDR],
             perf_load_use_idex_by_class[PERF_LOAD_USE_BRANCH],
             perf_load_use_idex_by_class[PERF_LOAD_USE_JALR],
             perf_load_use_idex_by_class[PERF_LOAD_USE_STORE_ADDR],
             perf_load_use_idex_by_class[PERF_LOAD_USE_STORE_DATA],
             perf_load_use_idex_by_class[PERF_LOAD_USE_STORE_BOTH],
             perf_load_use_idex_by_class[PERF_LOAD_USE_SYSTEM]);
    $display("TB PERF LOAD_USE EXMEM_WAIT: alu=%0d load_addr=%0d branch=%0d jalr=%0d store_addr=%0d store_data=%0d store_both=%0d system=%0d",
             perf_load_use_exmem_by_class[PERF_LOAD_USE_ALU],
             perf_load_use_exmem_by_class[PERF_LOAD_USE_LOAD_ADDR],
             perf_load_use_exmem_by_class[PERF_LOAD_USE_BRANCH],
             perf_load_use_exmem_by_class[PERF_LOAD_USE_JALR],
             perf_load_use_exmem_by_class[PERF_LOAD_USE_STORE_ADDR],
             perf_load_use_exmem_by_class[PERF_LOAD_USE_STORE_DATA],
             perf_load_use_exmem_by_class[PERF_LOAD_USE_STORE_BOTH],
             perf_load_use_exmem_by_class[PERF_LOAD_USE_SYSTEM]);
    $display("TB PERF BRANCH PREDICTION: predicted=%0d correct=%0d corrections=%0d predicted_taken=%0d bht_used=%0d bht_correct=%0d bht_corrections=%0d cold_btfnt_used=%0d cold_btfnt_correct=%0d cold_btfnt_corrections=%0d",
             perf_branch_predictions, perf_branch_direction_correct,
             perf_branch_prediction_corrections, perf_branch_predicted_taken,
             perf_branch_bht_predictions, perf_branch_bht_direction_correct,
             perf_branch_bht_corrections, perf_branch_cold_predictions,
             perf_branch_cold_direction_correct, perf_branch_cold_corrections);
    $display("TB PERF RAS HW: predictions=%0d correct=%0d corrections=%0d unpredicted_returns=%0d",
             perf_ras_hw_predictions, perf_ras_hw_correct,
             perf_ras_hw_corrections, perf_ras_hw_unpredicted);
    $display("TB PERF IFETCH ACCEPTED: req=%0d latency(total=%0d max=%0d hist0=%0d hist1=%0d hist2plus=%0d) counted_pending=%0d",
             perf_ifetch_requests, perf_ifetch_latency_total, perf_ifetch_latency_max,
             perf_ifetch_latency_0, perf_ifetch_latency_1, perf_ifetch_latency_ge2,
             perf_if_pending_q && perf_if_counted_q);
    $display("TB PERF IMEM CONTENTION: simultaneous_if_dbus_requests=%0d blocked_fetch_request_cycles=%0d",
             perf_if_dbus_imem_request_collisions, perf_if_dbus_imem_service_blocks);
    $display("TB PERF DBUS: load_req=%0d store_req=%0d load_latency(total=%0d hist0=%0d hist1=%0d hist2plus=%0d) store_latency(total=%0d hist0=%0d hist1=%0d hist2plus=%0d) max=%0d errors=%0d",
             perf_dbus_load_requests, perf_dbus_store_requests,
             perf_dbus_load_latency_total, perf_dbus_load_latency_0,
             perf_dbus_load_latency_1, perf_dbus_load_latency_ge2,
             perf_dbus_store_latency_total, perf_dbus_store_latency_0,
             perf_dbus_store_latency_1, perf_dbus_store_latency_ge2,
             perf_dbus_latency_max, perf_dbus_error_responses);
    $display("TB PERF DBUS TARGET: dmem(r=%0d w=%0d) imem(r=%0d w=%0d) clint(r=%0d w=%0d) plic(r=%0d w=%0d) apb(r=%0d w=%0d) other(r=%0d w=%0d)",
             perf_dmem_loads, perf_dmem_stores, perf_imem_loads, perf_imem_stores,
             perf_clint_loads, perf_clint_stores, perf_plic_loads, perf_plic_stores,
             perf_apb_loads, perf_apb_stores, perf_other_loads, perf_other_stores);
    perf_report_dbus_target_latency("DTCM", PERF_DBUS_DMEM);
    perf_report_dbus_target_latency("IMEM", PERF_DBUS_IMEM);
    perf_report_dbus_target_latency("CLINT", PERF_DBUS_CLINT);
    perf_report_dbus_target_latency("PLIC", PERF_DBUS_PLIC);
    perf_report_dbus_target_latency("APB", PERF_DBUS_APB);
    perf_report_dbus_target_latency("OTHER", PERF_DBUS_OTHER);
    if (perf_has_stop_pc && !perf_profile_completed_q)
      $error("TB PERF invariant: requested stop PC was not retired");
    if (perf_soc_cycles != (perf_retired + perf_no_retire_cycles))
      $error("TB PERF invariant: window cycle closure failed");
    if (perf_no_retire_cycles !=
        (perf_no_retire_clock_off_cycles + perf_no_retire_wfi_sleep_cycles +
         perf_no_retire_debug_halted_cycles + perf_no_retire_stall_cycles +
         perf_no_retire_redirect_recovery_cycles + perf_no_retire_idex_empty_cycles +
         perf_no_retire_other_cycles))
      $error("TB PERF invariant: no-retire reason closure failed");
    if (perf_retired !=
        (perf_retired_load + perf_retired_store + perf_retired_branch +
         perf_retired_jump + perf_retired_system + perf_retired_other))
      $error("TB PERF invariant: retire instruction-class closure failed");
    if (perf_retired != (perf_retired_compressed + perf_retired_32b))
      $error("TB PERF invariant: retire instruction-width closure failed");
    if (perf_branch_predictions !=
        (perf_branch_direction_correct + perf_branch_prediction_corrections))
      $error("TB PERF invariant: branch direction prediction closure failed");
    if (perf_branch_predictions !=
        (perf_branch_bht_predictions + perf_branch_cold_predictions))
      $error("TB PERF invariant: BHT/cold branch prediction closure failed");
    if (perf_branch_bht_predictions !=
        (perf_branch_bht_direction_correct + perf_branch_bht_corrections))
      $error("TB PERF invariant: BHT branch prediction closure failed");
    if (perf_branch_cold_predictions !=
        (perf_branch_cold_direction_correct + perf_branch_cold_corrections))
      $error("TB PERF invariant: cold BTFNT prediction closure failed");
    if (perf_jalr_returns !=
        (perf_ras_hw_predictions + perf_ras_hw_unpredicted))
      $error("TB PERF invariant: RAS return prediction coverage failed");
    if (perf_ras_hw_predictions !=
        (perf_ras_hw_correct + perf_ras_hw_corrections))
      $error("TB PERF invariant: RAS return prediction closure failed");
    if (perf_no_retire_idex_empty_cycles !=
        (perf_idex_empty_ifid_invalid_cycles + perf_idex_empty_flush_cycles +
         perf_idex_empty_hold_cycles + perf_idex_empty_decode_invalid_cycles +
         perf_idex_empty_other_cycles))
      $error("TB PERF invariant: ID/EX empty attribution closure failed");
    if (perf_core_enabled_cycles !=
        (perf_if_can_issue_ready_cycles + perf_if_can_issue_blocked_cycles))
      $error("TB PERF invariant: IF can_issue opportunity closure failed");
    if (perf_if_can_issue_ready_cycles !=
        (perf_if_can_issue_ready_no_request_cycles +
         perf_if_can_issue_ready_wait_imem_cycles +
         perf_if_can_issue_ready_accepted_cycles))
      $error("TB PERF invariant: IF can_issue ready classification closure failed");
    if (perf_if_can_issue_blocked_cycles !=
        (perf_if_issue_block_fetch_disabled_cycles +
         perf_if_issue_block_boot_init_cycles +
         perf_if_issue_block_hold_valid_cycles +
         perf_if_issue_block_imem_response_cycles +
         perf_if_issue_block_two_c16_cycles +
         perf_if_issue_block_upper_start_cycles +
         perf_if_issue_block_cross_word_cycles +
         perf_if_issue_block_unclassified_cycles))
      $error("TB PERF invariant: IF can_issue primary attribution closure failed");
    if (perf_if_issue_block_unclassified_cycles != 0)
      $error("TB PERF invariant: IF can_issue blocker was not classified");
    if (perf_idex_empty_ifid_invalid_cycles !=
        (perf_ifid_invalid_delivery_redirect_id_branch_cycles +
         perf_ifid_invalid_delivery_redirect_id_jal_cycles +
         perf_ifid_invalid_delivery_redirect_id_ras_cycles +
         perf_ifid_invalid_delivery_redirect_ex_cycles +
         perf_ifid_invalid_delivery_redirect_trap_cycles +
         perf_ifid_invalid_delivery_redirect_debug_cycles +
         perf_ifid_invalid_delivery_redirect_fence_i_cycles +
         perf_ifid_invalid_delivery_redirect_wfi_cycles +
         perf_ifid_invalid_delivery_flush_cycles +
         perf_ifid_invalid_delivery_cross_word_wait_cycles +
         perf_ifid_invalid_delivery_upper_start_32_cycles +
         perf_ifid_invalid_delivery_response_wait_cycles +
         perf_ifid_invalid_delivery_no_source_started_cycles +
         perf_ifid_invalid_delivery_no_source_demand_cycles +
         perf_ifid_invalid_delivery_no_source_guard_cycles +
         perf_ifid_invalid_delivery_id_hold_empty_cycles +
         perf_ifid_invalid_delivery_id_hold_front_cycles +
         perf_ifid_invalid_delivery_id_hold_full_cycles +
         perf_ifid_invalid_delivery_drop_response_cycles +
         perf_ifid_invalid_delivery_unclassified_cycles +
         perf_ifid_invalid_delivery_outside_window_cycles))
      $error("TB PERF invariant: IF delivery-to-bubble closure failed");
    if (perf_ifid_invalid_delivery_unclassified_cycles != 0)
      $error("TB PERF invariant: IF delivery bubble was not classified");
    if ((perf_fwd_rs1_triggers + perf_fwd_rs2_triggers) !=
        (perf_fwd_exmem_rs1_selected + perf_fwd_exmem_rs2_selected +
         perf_fwd_memwb_rs1_selected + perf_fwd_memwb_rs2_selected))
      $error("TB PERF invariant: forwarding selection closure failed");
    if (perf_ifetch_latency_0 != 0)
      $error("TB PERF invariant: fixed one-cycle IMEM reported zero-cycle response");
    if (perf_trace_fd != 0) begin
      $fclose(perf_trace_fd);
      perf_trace_fd = 0;
    end
  end
endtask
