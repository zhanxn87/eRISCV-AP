// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Route one blocking RV64 CPU data request to either the cacheable DDR path
// or the uncached device AXI path. The latter terminates at the AP peripheral
// egress, where the AXI-to-APB/boot/interrupt slave complex will be attached.
module dcache_cpu_router
  import ap_soc_pkg::*;
#(
  parameter int unsigned PADDR_W_P = AP_PADDR_W
) (
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   cpu_req_i,
  input  logic [PADDR_W_P-1:0]   cpu_addr_i,
  input  logic [63:0]            cpu_wdata_i,
  input  logic                   cpu_we_i,
  input  logic [7:0]             cpu_be_i,
  input  logic [3:0]             cpu_atomic_op_i,
  output logic                   cpu_resp_valid_o,
  output logic [63:0]            cpu_rdata_o,
  output logic                   cpu_err_o,

  output logic                   cache_req_o,
  output logic [PADDR_W_P-1:0]   cache_addr_o,
  output logic [63:0]            cache_wdata_o,
  output logic                   cache_we_o,
  output logic [7:0]             cache_be_o,
  output logic [3:0]             cache_atomic_op_o,
  input  logic                   cache_resp_valid_i,
  input  logic [63:0]            cache_rdata_i,
  input  logic                   cache_err_i,

  output logic                   uncached_req_o,
  output logic [PADDR_W_P-1:0]   uncached_addr_o,
  output logic [63:0]            uncached_wdata_o,
  output logic                   uncached_we_o,
  output logic [7:0]             uncached_be_o,
  input  logic                   uncached_resp_valid_i,
  input  logic [63:0]            uncached_rdata_i,
  input  logic                   uncached_err_i
);

  typedef enum logic [1:0] {
    ROUTER_IDLE,
    ROUTER_CACHE_WAIT,
    ROUTER_UNCACHED_WAIT,
    ROUTER_ERR_RESP
  } router_state_e;

  router_state_e state_q;
  logic cacheable_req;
  logic uncached_atomic_req;

  assign cacheable_req = ap_is_ddr_addr(cpu_addr_i);
  assign uncached_atomic_req = !cacheable_req && (cpu_atomic_op_i != 4'd0);

  assign cache_req_o = (state_q == ROUTER_IDLE) && cpu_req_i && cacheable_req;
  assign cache_addr_o = cpu_addr_i;
  assign cache_wdata_o = cpu_wdata_i;
  assign cache_we_o = cpu_we_i;
  assign cache_be_o = cpu_be_i;
  assign cache_atomic_op_o = cpu_atomic_op_i;

  assign uncached_req_o = (state_q == ROUTER_IDLE) && cpu_req_i &&
                        !cacheable_req && !uncached_atomic_req;
  assign uncached_addr_o = cpu_addr_i;
  assign uncached_wdata_o = cpu_wdata_i;
  assign uncached_we_o = cpu_we_i;
  assign uncached_be_o = cpu_be_i;

  always_comb begin
    cpu_resp_valid_o = 1'b0;
    cpu_rdata_o = '0;
    cpu_err_o = 1'b0;
    unique case (state_q)
      ROUTER_CACHE_WAIT: begin
        cpu_resp_valid_o = cache_resp_valid_i;
        cpu_rdata_o = cache_rdata_i;
        cpu_err_o = cache_resp_valid_i && cache_err_i;
      end
      ROUTER_UNCACHED_WAIT: begin
        cpu_resp_valid_o = uncached_resp_valid_i;
        cpu_rdata_o = uncached_rdata_i;
        cpu_err_o = uncached_resp_valid_i && uncached_err_i;
      end
      ROUTER_ERR_RESP: begin
        cpu_resp_valid_o = 1'b1;
        cpu_err_o = 1'b1;
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ROUTER_IDLE;
    end else begin
      unique case (state_q)
        ROUTER_IDLE: begin
          if (cpu_req_i) begin
            if (cacheable_req)
              state_q <= ROUTER_CACHE_WAIT;
            else if (uncached_atomic_req)
              state_q <= ROUTER_ERR_RESP;
            else
              state_q <= ROUTER_UNCACHED_WAIT;
          end
        end
        ROUTER_CACHE_WAIT:
          if (cache_resp_valid_i)
            state_q <= ROUTER_IDLE;
        ROUTER_UNCACHED_WAIT:
          if (uncached_resp_valid_i)
            state_q <= ROUTER_IDLE;
        ROUTER_ERR_RESP: state_q <= ROUTER_IDLE;
        default: state_q <= ROUTER_IDLE;
      endcase
    end
  end

endmodule
