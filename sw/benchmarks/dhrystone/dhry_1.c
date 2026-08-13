/*
 * SPDX-FileCopyrightText: 1988 Reinhold P. Weicker
 * SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
 * SPDX-License-Identifier: BSD-2-Clause
 */

/*
 * Dhrystone Benchmark Program, C Version 2.1, adapted for eRISCV bare metal.
 *
 * Source: https://www.netlib.org/benchmark/dhry-c
 *
 * The measured loop and Dhrystone procedures retain the Weicker 2.1
 * algorithm. Static records replace the original malloc calls because this
 * freestanding target has no heap.
 */
#include "dhry.h"

Rec_Pointer Ptr_Glob;
Rec_Pointer Next_Ptr_Glob;
int         Int_Glob;
Boolean     Bool_Glob;
char        Ch_1_Glob;
char        Ch_2_Glob;
Arr_1_Dim   Arr_1_Glob;
Arr_2_Dim   Arr_2_Glob;

volatile unsigned int eriscv_dhrystone_result;
#if DHRY_HPM
volatile unsigned int eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_WORDS];
#endif

static Rec_Type ptr_glob_record;
static Rec_Type next_ptr_glob_record;

static Boolean dhry_final_values_valid(One_Fifty Int_1_Loc,
                                       One_Fifty Int_2_Loc,
                                       One_Fifty Int_3_Loc,
                                       Enumeration Enum_Loc,
                                       Str_30 Str_1_Loc,
                                       Str_30 Str_2_Loc)
{
  return Int_Glob == 5 && Bool_Glob == true && Ch_1_Glob == 'A' &&
         Ch_2_Glob == 'B' && Arr_1_Glob[8] == 7 &&
         Arr_2_Glob[8][7] == DHRY_ITERATIONS + 10 &&
         Ptr_Glob->Ptr_Comp == Next_Ptr_Glob &&
         Ptr_Glob->Discr == Ident_1 &&
         Ptr_Glob->variant.var_1.Enum_Comp == Ident_3 &&
         Ptr_Glob->variant.var_1.Int_Comp == 17 &&
         strcmp(Ptr_Glob->variant.var_1.Str_Comp,
                "DHRYSTONE PROGRAM, SOME STRING") == 0 &&
         Next_Ptr_Glob->Discr == Ident_1 &&
         Next_Ptr_Glob->Ptr_Comp == Ptr_Glob->Ptr_Comp &&
         Next_Ptr_Glob->variant.var_1.Enum_Comp == Ident_2 &&
         Next_Ptr_Glob->variant.var_1.Int_Comp == 18 &&
         strcmp(Next_Ptr_Glob->variant.var_1.Str_Comp,
                "DHRYSTONE PROGRAM, SOME STRING") == 0 &&
         Int_1_Loc == 5 && Int_2_Loc == 13 && Int_3_Loc == 7 &&
         Enum_Loc == Ident_2 &&
         strcmp(Str_1_Loc, "DHRYSTONE PROGRAM, 1'ST STRING") == 0 &&
         strcmp(Str_2_Loc, "DHRYSTONE PROGRAM, 2'ND STRING") == 0;
}

int main(void)
{
  One_Fifty       Int_1_Loc;
  One_Fifty       Int_2_Loc;
  One_Fifty       Int_3_Loc;
  Capital_Letter  Ch_Index;
  Enumeration     Enum_Loc;
  Str_30          Str_1_Loc;
  Str_30          Str_2_Loc;
  int             Run_Index;
  unsigned int    cycles;
#if DHRY_HPM
  struct dhry_hpm_counts hpm_counts;
#endif

  dhry_port_init();
  dhry_port_puts("Dhrystone Benchmark, Version 2.1 (Language: C)\n");

  Next_Ptr_Glob = &next_ptr_glob_record;
  Ptr_Glob = &ptr_glob_record;
  Ptr_Glob->Ptr_Comp = Next_Ptr_Glob;
  Ptr_Glob->Discr = Ident_1;
  Ptr_Glob->variant.var_1.Enum_Comp = Ident_3;
  Ptr_Glob->variant.var_1.Int_Comp = 40;
  strcpy(Ptr_Glob->variant.var_1.Str_Comp,
         "DHRYSTONE PROGRAM, SOME STRING");
  strcpy(Str_1_Loc, "DHRYSTONE PROGRAM, 1'ST STRING");
  Arr_2_Glob[8][7] = 10;

  dhry_port_start_time();

  for (Run_Index = 1; Run_Index <= DHRY_ITERATIONS; ++Run_Index) {
    Proc_5();
    Proc_4();
    Int_1_Loc = 2;
    Int_2_Loc = 3;
    strcpy(Str_2_Loc, "DHRYSTONE PROGRAM, 2'ND STRING");
    Enum_Loc = Ident_2;
    Bool_Glob = !Func_2(Str_1_Loc, Str_2_Loc);
    while (Int_1_Loc < Int_2_Loc) {
      Int_3_Loc = 5 * Int_1_Loc - Int_2_Loc;
      Proc_7(Int_1_Loc, Int_2_Loc, &Int_3_Loc);
      Int_1_Loc += 1;
    }
    Proc_8(Arr_1_Glob, Arr_2_Glob, Int_1_Loc, Int_3_Loc);
    Proc_1(Ptr_Glob);
    for (Ch_Index = 'A'; Ch_Index <= Ch_2_Glob; ++Ch_Index) {
      if (Enum_Loc == Func_1(Ch_Index, 'C')) {
        Proc_6(Ident_1, &Enum_Loc);
        strcpy(Str_2_Loc, "DHRYSTONE PROGRAM, 3'RD STRING");
        Int_2_Loc = Run_Index;
        Int_Glob = Run_Index;
      }
    }
    Int_2_Loc = Int_2_Loc * Int_1_Loc;
    Int_1_Loc = Int_2_Loc / Int_3_Loc;
    Int_2_Loc = 7 * (Int_2_Loc - Int_3_Loc) - Int_1_Loc;
    Proc_2(&Int_1_Loc);
  }

  dhry_port_stop_time();
  cycles = dhry_port_get_cycles();
#if DHRY_HPM
  dhry_port_get_hpm_counts(&hpm_counts);
#endif

  if (dhry_final_values_valid(Int_1_Loc, Int_2_Loc, Int_3_Loc, Enum_Loc,
                              Str_1_Loc, Str_2_Loc)) {
#if DHRY_HPM
    eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_MAGIC_INDEX] = DHRY_HPM_REPORT_MAGIC;
    eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_ARR2_INDEX] = (unsigned int)Arr_2_Glob[8][7];
    eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_CYCLES_INDEX] = cycles;
    eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_INSTRET_INDEX] = hpm_counts.instret;
    eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_BRANCH_TAKEN_INDEX] = hpm_counts.branch_taken;
    eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_IFETCH_WAIT_INDEX] = hpm_counts.ifetch_wait;
    eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_DATA_WAIT_INDEX] = hpm_counts.data_wait;
    eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_LOAD_USE_STALL_INDEX] = hpm_counts.load_use_stall;
#endif
    eriscv_dhrystone_result = 0x80000000u | (cycles & 0x3fffffffu);
    dhry_port_puts("Dhrystone 2.1 PASS\n");
  } else {
    eriscv_dhrystone_result = 0x40000000u;
    dhry_port_puts("Dhrystone 2.1 FAIL\n");
  }

  return 0;
}

void Proc_1(Rec_Pointer Ptr_Val_Par)
{
  Rec_Pointer Next_Record = Ptr_Val_Par->Ptr_Comp;

  *Ptr_Val_Par->Ptr_Comp = *Ptr_Glob;
  Ptr_Val_Par->variant.var_1.Int_Comp = 5;
  Next_Record->variant.var_1.Int_Comp = Ptr_Val_Par->variant.var_1.Int_Comp;
  Next_Record->Ptr_Comp = Ptr_Val_Par->Ptr_Comp;
  Proc_3(&Next_Record->Ptr_Comp);
  if (Next_Record->Discr == Ident_1) {
    Next_Record->variant.var_1.Int_Comp = 6;
    Proc_6(Ptr_Val_Par->variant.var_1.Enum_Comp,
           &Next_Record->variant.var_1.Enum_Comp);
    Next_Record->Ptr_Comp = Ptr_Glob->Ptr_Comp;
    Proc_7(Next_Record->variant.var_1.Int_Comp, 10,
           &Next_Record->variant.var_1.Int_Comp);
  } else {
    *Ptr_Val_Par = *Ptr_Val_Par->Ptr_Comp;
  }
}

void Proc_2(One_Fifty *Int_Par_Ref)
{
  One_Fifty Int_Loc;
  Enumeration Enum_Loc;

  Int_Loc = *Int_Par_Ref + 10;
  do {
    if (Ch_1_Glob == 'A') {
      Int_Loc -= 1;
      *Int_Par_Ref = Int_Loc - Int_Glob;
      Enum_Loc = Ident_1;
    }
  } while (Enum_Loc != Ident_1);
}

void Proc_3(Rec_Pointer *Ptr_Ref_Par)
{
  if (Ptr_Glob != Null)
    *Ptr_Ref_Par = Ptr_Glob->Ptr_Comp;
  Proc_7(10, Int_Glob, &Ptr_Glob->variant.var_1.Int_Comp);
}

void Proc_4(void)
{
  Boolean Bool_Loc;

  Bool_Loc = Ch_1_Glob == 'A';
  Bool_Glob = Bool_Loc | Bool_Glob;
  Ch_2_Glob = 'B';
}

void Proc_5(void)
{
  Ch_1_Glob = 'A';
  Bool_Glob = false;
}
