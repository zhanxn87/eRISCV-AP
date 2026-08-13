# eRISCV-M2

`eriscv-m2` is the cacheless performance MCU product. Its frozen contract is
`RV32IMFC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause_Zba_Zbb_Zbs_Zicond_Zcf` (standard B plus Zicond) with `ilp32f`, M/U modes, the common 32-source PLIC
v1.0.0 and Debug 1.0 Minimal platform, and the common 16-entry PMP
contract.

It adds a faster core, single-precision FPU, ITCM/DTCM, shared System SRAM,
and a single generic DMA channel. The channel supports direct System
SRAM-to-System SRAM copies, 32-byte linked descriptors, and a fixed UART0 TX
byte-stream endpoint; UART RX, SPI, and Timer endpoints remain deferred. It
deliberately uses directly addressed memories rather than any cache mechanism.
B is implemented as Zba/Zbb/Zbs; Zicond provides branchless conditional-zero operations. Zbc, D, and Zfa are deferred. The FPU uses a pinned, product-local CVFPU
snapshot with one documented M2-local FMA underflow correctness patch; it is
therefore not an unmodified top-level third-party dependency. See the
[CVFPU vendor lock](rtl/vendor/cvfpu/LOCK.md) for provenance and scope.

## Start Here

- [Architecture contract](docs/eriscv-m2-architecture.md)
- [Verification contract](docs/eriscv-m2-verification.md)
- [Family product manual](https://eriscv-mcu-product-manual.zhanxnse.chatgpt.site/products/eriscv-m2)
- [Family evidence snapshot](../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md)
- [Design verification inventory](dv/README.md)
- [ACT4 profile](compliance/riscv-arch-test/README.md)
- [BSP, DMA driver, and examples](sw/README.md)
- [DMA descriptor ABI](docs/eriscv-m2-dma-descriptor-spec.md)
- [FPGA VCU108 flow](fpga/vcu108/README.md)

Run `make eriscv-m2-full` from the repository root for the product-level
regression entry point. FPGA implementation and physical-board status are
separate evidence; see [the family documentation map](../docs/README.md).
