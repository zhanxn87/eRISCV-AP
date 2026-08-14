// Locked PULP AXI v0.35.3 synthesis/source manifest.
// The dependency on common_cells v1.21.0 is provided by the AP-local
// rtl/vendor/common_cells/filelist.f through the core manifest.

+incdir+include

// Level 0
src/axi_pkg.sv
// Level 1
src/axi_intf.sv
// Level 2
src/axi_atop_filter.sv
src/axi_burst_splitter.sv
src/axi_cdc_dst.sv
src/axi_cdc_src.sv
src/axi_cut.sv
src/axi_delayer.sv
src/axi_demux.sv
src/axi_dw_downsizer.sv
src/axi_dw_upsizer.sv
src/axi_id_remap.sv
src/axi_id_prepend.sv
src/axi_isolate.sv
src/axi_join.sv
src/axi_lite_demux.sv
src/axi_lite_join.sv
src/axi_lite_mailbox.sv
src/axi_lite_mux.sv
src/axi_lite_regs.sv
src/axi_lite_to_apb.sv
src/axi_lite_to_axi.sv
src/axi_modify_address.sv
src/axi_mux.sv
src/axi_serializer.sv
// Level 3
src/axi_cdc.sv
src/axi_err_slv.sv
src/axi_dw_converter.sv
src/axi_id_serialize.sv
src/axi_multicut.sv
src/axi_to_axi_lite.sv
// Level 4
src/axi_iw_converter.sv
src/axi_lite_xbar.sv
src/axi_xbar.sv
