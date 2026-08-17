# L1 cache RTL

The synthesizable AP hart-private L1 cache controllers are:

- `icache.sv`: implemented 32 KiB/two-way/64-byte physical instruction cache;
  reset fetch stays in Boot ROM and DDR fetches use its independent AXI ingress.
- `dcache.sv`: implemented 32 KiB/two-way/64-byte physical data cache, RV64A
  reservation state, and maintenance control.
- `dcache_cpu_router.sv`: current physical-address cacheable versus uncached
  selection.

They are owned by `ap_hart_tile`: ITLB precedes I-Cache, DTLB precedes D-Cache
or the uncached peripheral path, and the shared PTW uses a dedicated cacheable
D-Cache port. Cache behavior must not move into the shared AXI fabric.

The cache backing transport is not a memory model. Project-owned AXI adapters
live in `../axi/`; verification-only line-memory models live under `dv/`.
