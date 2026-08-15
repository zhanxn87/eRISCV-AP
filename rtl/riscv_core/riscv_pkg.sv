// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// RISC-V ISA constants, pipeline types, and platform address map shared
// across the Phase 12 teaching core, testbench, and core-only CLINT/PLIC MMIO shim.
//
// Consolidated from rv32i_types, platform_pkg, csr_file, and riscv_core.
package riscv_pkg;

  // =========================================================================
  // Product configuration -- eRISCV-AP RV64 baseline
  // =========================================================================
  // This package is the reviewed product configuration. Individual RTL
  // modules expose XLEN_P parameters defaulting to this value; an instance
  // must not mix widths with the packed pipeline packets below.
  localparam int unsigned CORE_XLEN = 64;
  // Architectural PCs and effective addresses stay XLEN-wide. Sv39 consumes
  // canonical 39-bit virtual addresses; first-system physical interfaces are
  // constrained to 48 bits (not an assertion that all 64 address bits exist
  // in DDR or MMIO).
  localparam int unsigned VADDR_W = 39;
  localparam int unsigned PADDR_W = 48;
  localparam int unsigned ADDR_WIDTH = CORE_XLEN;
  typedef logic [CORE_XLEN-1:0] xlen_t;
  typedef logic [VADDR_W-1:0]   vaddr_t;
  typedef logic [PADDR_W-1:0]   paddr_t;

  function automatic logic sv39_canonical(input xlen_t addr);
    sv39_canonical = (addr[CORE_XLEN-1:VADDR_W] ==
                      {(CORE_XLEN-VADDR_W){addr[VADDR_W-1]}});
  endfunction

  localparam bit HAS_M_EXT       = 1'b1;
  localparam bit HAS_A_EXT       = 1'b1;
  localparam bit HAS_D_EXT       = 1'b1;
  localparam bit HAS_F_EXT       = 1'b1;
  localparam bit HAS_ZCA         = 1'b1;
  localparam bit HAS_ZICSR       = 1'b1;
  localparam bit HAS_ZIFENCEI    = 1'b1;
  localparam bit HAS_ZICNTR      = 1'b1;
  localparam bit HAS_ZBA         = 1'b0;
  localparam bit HAS_ZBB         = 1'b0;
  localparam bit HAS_ZBS         = 1'b0;
  localparam bit HAS_ZICOND      = 1'b0;
  localparam bit HAS_B_EXT       = 1'b0;
  localparam bit HAS_WFI         = 1'b1;
  localparam bit HAS_DEBUG       = 1'b1;
  localparam bit HAS_UMODE      = 1'b1;
  localparam bit HAS_SMODE      = 1'b1;
  localparam bit HAS_MPRV       = 1'b1;
  localparam bit HAS_MCOUNTEREN = 1'b1;

  localparam int unsigned HPM_COUNTER_FIRST = 3;
  localparam int unsigned HPM_COUNTER_COUNT = 4;
  localparam int unsigned HPM_COUNTER_LAST  =
      HPM_COUNTER_FIRST + HPM_COUNTER_COUNT - 1;
  localparam xlen_t MCOUNTEREN_WRITABLE_MASK = xlen_t'(32'h0000_007f);

  // =========================================================================
  // Architectural types and ISA constants
  // =========================================================================
  // Pipeline stage enums and structs (was rv32i_types)
  // =========================================================================

  typedef enum logic [1:0] {
    OP_A_RS1  = 2'b00,
    OP_A_PC   = 2'b01,
    OP_A_ZERO = 2'b10
  } op_a_sel_e;

  typedef enum logic [1:0] {
    OP_B_RS2  = 2'b00,
    OP_B_IMM  = 2'b01,
    OP_B_FOUR = 2'b10
  } op_b_sel_e;

  typedef enum logic [1:0] {
    WB_ALU = 2'b00,
    WB_MEM = 2'b01,
    WB_PC4 = 2'b10,
    WB_CSR = 2'b11
  } wb_sel_e;

  // Product-local CVFPU adapter transport. These encodings intentionally do
  // not expose fpnew_pkg types above the adapter boundary.
  typedef enum logic {
    FP_FMT_S = 1'b0,
    FP_FMT_D = 1'b1
  } fp_fmt_e;

  typedef struct packed {
    logic [63:0] operand_a;
    logic [63:0] operand_b;
    logic [63:0] operand_c;
    logic [4:0]  operation;
    logic [2:0]  rounding_mode;
    logic        operation_modifier;
    fp_fmt_e     src_fmt;
    fp_fmt_e     dst_fmt;
    logic        int_fmt_d;
    logic        result_word;
    logic        write_gpr;
    logic [4:0]  rd_addr;
    logic [7:0]  tag;
  } fp_issue_t;

  typedef struct packed {
    logic [63:0] result;
    logic [4:0]  fflags;
    logic        write_gpr;
    logic [4:0]  rd_addr;
    logic [7:0]  tag;
  } fp_complete_t;

  typedef enum logic [4:0] {
    FP_OP_FMADD    = 5'd0,
    FP_OP_FNMSUB   = 5'd1,
    FP_OP_ADD      = 5'd2,
    FP_OP_MUL      = 5'd3,
    FP_OP_DIV      = 5'd8,
    FP_OP_SQRT     = 5'd9,
    FP_OP_SGNJ     = 5'd10,
    FP_OP_MINMAX   = 5'd11,
    FP_OP_CMP      = 5'd12,
    FP_OP_CLASSIFY = 5'd13,
    FP_OP_F2F      = 5'd14,
    FP_OP_F2I      = 5'd15,
    FP_OP_I2F      = 5'd16
  } fp_operation_e;

  typedef enum logic [2:0] {
    BR_NONE = 3'd0,
    BR_EQ   = 3'd1,
    BR_NE   = 3'd2,
    BR_LT   = 3'd3,
    BR_GE   = 3'd4,
    BR_LTU  = 3'd5,
    BR_GEU  = 3'd6
  } branch_op_e;

  typedef enum logic [1:0] {
    JUMP_NONE = 2'd0,
    JUMP_JAL  = 2'd1,
    JUMP_JALR = 2'd2
  } jump_op_e;

  typedef enum logic [2:0] {
    MULDIV_MUL    = 3'd0,
    MULDIV_MULH   = 3'd1,
    MULDIV_MULHSU = 3'd2,
    MULDIV_MULHU  = 3'd3,
    MULDIV_DIV    = 3'd4,
    MULDIV_DIVU   = 3'd5,
    MULDIV_REM    = 3'd6,
    MULDIV_REMU   = 3'd7
  } muldiv_op_e;

  // Atomic operations carried over the data-memory boundary.  The memory
  // system owns the reservation set and must execute every non-LR operation
  // as one indivisible read-modify-write transaction.
  typedef enum logic [3:0] {
    ATOMIC_NONE = 4'd0,
    ATOMIC_LR   = 4'd1,
    ATOMIC_SC   = 4'd2,
    ATOMIC_SWAP = 4'd3,
    ATOMIC_ADD  = 4'd4,
    ATOMIC_XOR  = 4'd5,
    ATOMIC_AND  = 4'd6,
    ATOMIC_OR   = 4'd7,
    ATOMIC_MIN  = 4'd8,
    ATOMIC_MAX  = 4'd9,
    ATOMIC_MINU = 4'd10,
    ATOMIC_MAXU = 4'd11
  } atomic_op_e;

  typedef enum logic [5:0] {
    ALU_ADD   = 6'd0,
    ALU_SUB   = 6'd1,
    ALU_SLL   = 6'd2,
    ALU_SLT   = 6'd3,
    ALU_SLTU  = 6'd4,
    ALU_XOR   = 6'd5,
    ALU_SRL   = 6'd6,
    ALU_SRA   = 6'd7,
    ALU_OR    = 6'd8,
    ALU_AND   = 6'd9,
    ALU_ADDW  = 6'd10,
    ALU_SUBW  = 6'd11,
    ALU_SLLW  = 6'd12,
    ALU_SRLW  = 6'd13,
    ALU_SRAW  = 6'd14
  } alu_op_e;

  typedef enum logic [3:0] {
    SYS_NONE   = 4'd0,
    SYS_ECALL  = 4'd1,
    SYS_MRET   = 4'd2,
    SYS_EBREAK = 4'd3,
    SYS_DRET   = 4'd4,
    SYS_WFI    = 4'd5,
    SYS_SRET   = 4'd6,
    SYS_SFENCE_VMA = 4'd7
  } sys_op_e;

  typedef enum logic [1:0] {
    PRIV_U = 2'b00,
    PRIV_S = 2'b01,
    PRIV_M = 2'b11
  } privilege_mode_e;

  typedef enum logic [1:0] {
    CSR_OP_NONE  = 2'd0,
    CSR_OP_WRITE = 2'd1,
    CSR_OP_SET   = 2'd2,
    CSR_OP_CLEAR = 2'd3
  } csr_op_e;

  // Serialized low-frequency control events. A non-NONE source owns exactly
  // one EX/MEM-to-WB control packet.
  typedef enum logic [3:0] {
    CONTROL_NONE        = 4'd0,
    CONTROL_EXCEPTION   = 4'd1,
    CONTROL_MRET        = 4'd2,
    CONTROL_DEBUG_ENTER = 4'd3,
    CONTROL_DEBUG_STEP  = 4'd4,
    CONTROL_DRET        = 4'd5,
    CONTROL_WFI         = 4'd6,
    CONTROL_SRET        = 4'd7,
    CONTROL_SFENCE_VMA  = 4'd8
  } control_source_e;

  // Pipeline register structs — double as the inter-stage contract.
  typedef struct packed {
    logic        valid;
    xlen_t       pc;
    logic [31:0] instr;
    logic        compressed;  // 1 if this is a 16-bit compressed instruction
    // Fetch responses carry translation failures as architectural packets so
    // older instructions retire before the fault enters EX.
    logic        instruction_page_fault;
    logic        instruction_access_fault;
  } if_id_t;

  typedef struct packed {
    logic        valid;
    xlen_t       pc;
    logic [31:0] instr;
    logic        compressed;
    logic        instruction_page_fault;
    logic        instruction_access_fault;
    xlen_t       rs1_data;
    xlen_t       rs2_data;
    xlen_t       imm;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;
    logic [1:0]  op_a_sel;
    logic [1:0]  op_b_sel;
    alu_op_e     alu_op;
    logic        muldiv_en;
    logic        word_op;
    muldiv_op_e  muldiv_op;
    branch_op_e  branch_op;
    jump_op_e    jump_op;
    logic        jal_early;
    logic        return_pred_valid;
    xlen_t       return_pred_target;
    logic        branch_pred_valid;
    logic        branch_pred_taken;
    logic        branch_pred_bht_used;
    logic        illegal_instr;
    // A regular FENCE drains the D-side memory system.  FENCE.I also sets
    // fence_i so IF discards a prefetched instruction and refetches it.
    logic        fence;
    logic        fence_i;
    logic        csr_access;
    logic        csr_use_imm;
    logic [4:0]  csr_imm;
    csr_op_e     csr_op;
    logic [11:0] csr_addr;
    sys_op_e     sys_op;
    logic        mem_load;
    logic        mem_store;
    logic [2:0]  mem_type;
    atomic_op_e  atomic_op;
    logic        atomic_aq;
    logic        atomic_rl;

    // Floating-point decode, FPR operands, and rounding control
    logic        fp_op;
    logic        fp_access;
    logic        fp_write;
    logic        fp_dirty;
    logic [63:0] fp_rs1_data;
    logic [63:0] fp_rs2_data;
    logic [63:0] fp_rs3_data;
    logic [4:0]  fp_rs1_addr;
    logic [4:0]  fp_rs2_addr;
    logic [4:0]  fp_rs3_addr;
    fp_operation_e fp_operation;
    logic        fp_operation_modifier;
    fp_fmt_e     fp_src_fmt;
    fp_fmt_e     fp_dst_fmt;
    logic        fp_int_fmt_d;
    logic        fp_result_word;
    logic [2:0]  fp_rounding_mode;
    logic        fp_rounding_dynamic;
    logic        rd_we;
    logic [1:0]  wb_sel;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    // A non-NONE source is transported to WB without normal retirement,
    // except CONTROL_DEBUG_STEP, which retires before entering Debug.
    control_source_e control_source;
    xlen_t       pc;
    logic [31:0] instr;
    xlen_t       control_trap_pc;
    xlen_t       control_trap_cause;
    xlen_t       control_trap_value;
    xlen_t       control_debug_dpc;
    logic [2:0]  control_debug_cause;
    xlen_t       control_sfence_vma_vaddr;
    logic [15:0] control_sfence_vma_asid;
    logic        compressed;
    xlen_t       ex_result;
    xlen_t       data_addr;
    xlen_t       store_data;
    logic [4:0]  store_rs2_addr;
    logic        load_store_data_bypass;
    logic        fence;
    logic [4:0]  rd_addr;
    logic        mem_load;
    logic        mem_store;
    logic [2:0]  mem_type;
    atomic_op_e  atomic_op;
    logic        atomic_aq;
    logic        atomic_rl;
    logic        word_op;

    // FPR writeback payload and deferred FCSR flags
    logic        fp_write;
    logic        fp_dirty;
    fp_fmt_e     fp_dst_fmt;
    logic [4:0]  fp_rd_addr;
    logic [4:0]  fp_fflags;
    logic        rd_we;
    logic [1:0]  wb_sel;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    control_source_e control_source;
    xlen_t       pc;
    logic [31:0] instr;
    xlen_t       control_trap_pc;
    xlen_t       control_trap_cause;
    xlen_t       control_trap_value;
    xlen_t       control_debug_dpc;
    logic [2:0]  control_debug_cause;
    xlen_t       control_sfence_vma_vaddr;
    logic [15:0] control_sfence_vma_asid;
    xlen_t       wb_data;
    logic [4:0]  rd_addr;
    logic        rd_we;

    // FPR writeback payload and FCSR retirement state
    logic        fp_write;
    logic        fp_dirty;
    fp_fmt_e     fp_dst_fmt;
    logic [4:0]  fp_rd_addr;
    logic [4:0]  fp_fflags;
  } mem_wb_t;

  // =========================================================================
  // Core-visible reset and debug vectors
  // =========================================================================

  localparam xlen_t IMEM_BASE_ADDR = xlen_t'(32'h0000_0000);

  // Boot vector (offset from IMEM_BASE so the ACT harness can place a small
  // trampoline in the bottom 128 bytes).
  localparam xlen_t RESET_VECTOR_ADDR = xlen_t'(32'h0000_0080);

  // RISC-V debug-spec entry point for the Debug Module handler.
  localparam xlen_t DEBUG_BASE_ADDR   = xlen_t'(32'h0000_0100);

  // =========================================================================
  // Machine-mode CSR addresses (RV64, privileged spec v1.12)
  // =========================================================================

  // Machine Information
  localparam logic [11:0] CSR_MVENDORID    = 12'hf11;
  localparam logic [11:0] CSR_MARCHID      = 12'hf12;
  localparam logic [11:0] CSR_MIMPID       = 12'hf13;
  localparam logic [11:0] CSR_MHARTID      = 12'hf14;

  // Supervisor Trap Setup
  localparam logic [11:0] CSR_SSTATUS      = 12'h100;
  localparam logic [11:0] CSR_SIE          = 12'h104;
  localparam logic [11:0] CSR_STVEC        = 12'h105;
  localparam logic [11:0] CSR_SCOUNTEREN   = 12'h106;

  // Supervisor Trap Handling
  localparam logic [11:0] CSR_SSCRATCH     = 12'h140;
  localparam logic [11:0] CSR_SEPC         = 12'h141;
  localparam logic [11:0] CSR_SCAUSE       = 12'h142;
  localparam logic [11:0] CSR_STVAL        = 12'h143;
  localparam logic [11:0] CSR_SIP          = 12'h144;
  // Sv39 address-translation and protection root.
  localparam logic [11:0] CSR_SATP         = 12'h180;

  // Machine Trap Setup
  localparam logic [11:0] CSR_MSTATUS      = 12'h300;
  localparam logic [11:0] CSR_MISA         = 12'h301;
  localparam logic [11:0] CSR_FFLAGS       = 12'h001;
  localparam logic [11:0] CSR_FRM          = 12'h002;
  localparam logic [11:0] CSR_FCSR         = 12'h003;
  localparam logic [11:0] CSR_MEDELEG      = 12'h302;
  localparam logic [11:0] CSR_MIDELEG      = 12'h303;
  localparam logic [11:0] CSR_MIE          = 12'h304;
  localparam logic [11:0] CSR_MTVEC        = 12'h305;
  localparam logic [11:0] CSR_MCOUNTEREN   = 12'h306;
  localparam logic [11:0] CSR_MCOUNTINHIBIT = 12'h320;

  // Machine Trap Handling
  localparam logic [11:0] CSR_MSCRATCH     = 12'h340;
  localparam logic [11:0] CSR_MEPC         = 12'h341;
  localparam logic [11:0] CSR_MCAUSE       = 12'h342;
  localparam logic [11:0] CSR_MTVAL        = 12'h343;
  localparam logic [11:0] CSR_MIP          = 12'h344;

  // Machine Counters / Timers
  localparam logic [11:0] CSR_MCYCLE       = 12'hb00;
  localparam logic [11:0] CSR_MINSTRET     = 12'hb02;
  localparam logic [11:0] CSR_MHPMCOUNTER3  = 12'hb03;
  localparam logic [11:0] CSR_MHPMCOUNTER4  = 12'hb04;
  localparam logic [11:0] CSR_MHPMCOUNTER5  = 12'hb05;
  localparam logic [11:0] CSR_MHPMCOUNTER6  = 12'hb06;
  localparam logic [11:0] CSR_MHPMEVENT3    = 12'h323;
  localparam logic [11:0] CSR_MHPMEVENT4    = 12'h324;
  localparam logic [11:0] CSR_MHPMEVENT5    = 12'h325;
  localparam logic [11:0] CSR_MHPMEVENT6    = 12'h326;

  // Unprivileged counter/timer aliases (read-only views)
  localparam logic [11:0] CSR_CYCLE        = 12'hc00;
  localparam logic [11:0] CSR_TIME         = 12'hc01;
  localparam logic [11:0] CSR_INSTRET      = 12'hc02;
  localparam logic [11:0] CSR_HPMCOUNTER3  = 12'hc03;
  localparam logic [11:0] CSR_HPMCOUNTER4  = 12'hc04;
  localparam logic [11:0] CSR_HPMCOUNTER5  = 12'hc05;
  localparam logic [11:0] CSR_HPMCOUNTER6  = 12'hc06;

  // =========================================================================
  // eRISCV HPM event identifiers
  // =========================================================================

  localparam int unsigned HPM_EVENT_COUNT = 22;

  localparam logic [7:0] HPM_EVENT_NONE                     = 8'h00;
  localparam logic [7:0] HPM_EVENT_LOAD_RETIRED             = 8'h01;
  localparam logic [7:0] HPM_EVENT_STORE_RETIRED            = 8'h02;
  localparam logic [7:0] HPM_EVENT_BRANCH_RETIRED           = 8'h03;
  localparam logic [7:0] HPM_EVENT_BRANCH_TAKEN             = 8'h04;
  localparam logic [7:0] HPM_EVENT_CONTROL_TRANSFER_RETIRED = 8'h05;
  localparam logic [7:0] HPM_EVENT_EXCEPTION_TAKEN          = 8'h06;
  localparam logic [7:0] HPM_EVENT_INTERRUPT_TAKEN          = 8'h07;
  localparam logic [7:0] HPM_EVENT_IFETCH_WAIT_CYCLES       = 8'h08;
  localparam logic [7:0] HPM_EVENT_DATA_WAIT_CYCLES         = 8'h09;
  localparam logic [7:0] HPM_EVENT_PIPELINE_STALL_CYCLES    = 8'h0a;
  localparam logic [7:0] HPM_EVENT_LOAD_USE_STALL_CYCLES    = 8'h0b;
  localparam logic [7:0] HPM_EVENT_MUL_BUSY_CYCLES          = 8'h0c;
  localparam logic [7:0] HPM_EVENT_DIV_BUSY_CYCLES          = 8'h0d;
  localparam logic [7:0] HPM_EVENT_WFI_CYCLES               = 8'h0e;
  localparam logic [7:0] HPM_EVENT_BUS_ERROR                = 8'h0f;
  localparam logic [7:0] HPM_EVENT_COMPRESSED_RETIRED       = 8'h10;
  localparam logic [7:0] HPM_EVENT_DEBUG_ENTRY              = 8'h12;
  localparam logic [7:0] HPM_EVENT_IRQ_PENDING_CYCLES       = 8'h13;
  localparam logic [7:0] HPM_EVENT_PREFETCH_WAIT_CYCLES     = 8'h14;
  localparam logic [7:0] HPM_EVENT_DMA_CONTENTION_CYCLES    = 8'h15;

  // Debug / Trigger CSRs
  localparam logic [11:0] CSR_DCSR         = 12'h7b0;
  localparam logic [11:0] CSR_DPC          = 12'h7b1;
  localparam logic [11:0] CSR_DSCRATCH0    = 12'h7b2;
  localparam logic [11:0] CSR_DSCRATCH1    = 12'h7b3;
  localparam logic [11:0] CSR_TSELECT       = 12'h7a0;
  localparam logic [11:0] CSR_TDATA1        = 12'h7a1;
  localparam logic [11:0] CSR_TDATA2        = 12'h7a2;

endpackage
