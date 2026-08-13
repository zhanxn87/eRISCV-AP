set pagination off
set confirm off
set verbose off
set remotetimeout 10
set print pretty off
set logging file __TRANSCRIPT__
set logging overwrite on
set logging enabled on

printf "eRISCV-M2 OpenOCD/GDB smoke start\n"
target extended-remote :__GDB_PORT__
monitor halt

printf "Read basic registers\n"
info registers pc
info registers x0
info registers x1

printf "GPR write/read smoke\n"
set $x5 = 0x12345678
p/x $x5
set $x6 = 0xcafebabe
p/x $x6

python
import gdb
x5 = int(gdb.parse_and_eval('$x5')) & 0xffffffff
x6 = int(gdb.parse_and_eval('$x6')) & 0xffffffff
if x5 != 0x12345678 or x6 != 0xcafebabe:
    raise gdb.GdbError('GPR write/read smoke failed: x5=%08x x6=%08x' % (x5, x6))
end

if __HAS_ELF__
  printf "Load ELF and run breakpoint/step smoke\n"
  file __FIRMWARE_ELF__
  load
  break *_start
  monitor reset halt
  continue
  info registers pc
  stepi
  info registers pc
end

monitor halt
printf "ERISCV_M2_OPENOCD_GDB PASS\n"
set logging enabled off
detach
quit
