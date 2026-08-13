/*
 * SPDX-FileCopyrightText: 1988 Reinhold P. Weicker
 * SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
 * SPDX-License-Identifier: BSD-2-Clause
 */

/*
 * Dhrystone Benchmark Program, C Version 2.1.
 *
 * Algorithm source: Reinhold P. Weicker, May 25, 1988.
 * The eRISCV port replaces only system allocation, timing, I/O, and the
 * automated completion signal.
 */
#ifndef ERISCV_DHRY_H
#define ERISCV_DHRY_H

typedef enum {
  Ident_1,
  Ident_2,
  Ident_3,
  Ident_4,
  Ident_5
} Enumeration;

typedef int  Boolean;
typedef char Capital_Letter;
typedef int  One_Fifty;
typedef int  One_Thirty;
typedef char Str_30[31];
typedef int  Arr_1_Dim[50];
typedef int  Arr_2_Dim[50][50];

typedef struct Record {
  struct Record *Ptr_Comp;
  Enumeration    Discr;
  union {
    struct {
      Enumeration Enum_Comp;
      int         Int_Comp;
      Str_30      Str_Comp;
    } var_1;
    struct {
      Enumeration E_Comp_2;
      Str_30      Str_2_Comp;
    } var_2;
    struct {
      char Ch_1_Comp;
      char Ch_2_Comp;
    } var_3;
  } variant;
} Rec_Type, *Rec_Pointer;

#define Null 0
#define false 0
#define true  1

extern Rec_Pointer Ptr_Glob;
extern Rec_Pointer Next_Ptr_Glob;
extern int         Int_Glob;
extern Boolean     Bool_Glob;
extern char        Ch_1_Glob;
extern char        Ch_2_Glob;
extern Arr_1_Dim   Arr_1_Glob;
extern Arr_2_Dim   Arr_2_Glob;
extern volatile unsigned int eriscv_dhrystone_result;

#ifndef DHRY_HPM
#define DHRY_HPM 0
#endif

#if DHRY_HPM
#define DHRY_HPM_REPORT_MAGIC 0x44524859u
#define DHRY_HPM_REPORT_WORDS 8u

enum dhry_hpm_report_index {
  DHRY_HPM_REPORT_MAGIC_INDEX = 0,
  DHRY_HPM_REPORT_ARR2_INDEX,
  DHRY_HPM_REPORT_CYCLES_INDEX,
  DHRY_HPM_REPORT_INSTRET_INDEX,
  DHRY_HPM_REPORT_BRANCH_TAKEN_INDEX,
  DHRY_HPM_REPORT_IFETCH_WAIT_INDEX,
  DHRY_HPM_REPORT_DATA_WAIT_INDEX,
  DHRY_HPM_REPORT_LOAD_USE_STALL_INDEX
};

struct dhry_hpm_counts {
  unsigned int instret;
  unsigned int branch_taken;
  unsigned int ifetch_wait;
  unsigned int data_wait;
  unsigned int load_use_stall;
};

extern volatile unsigned int eriscv_dhrystone_hpm_report[DHRY_HPM_REPORT_WORDS];
#endif

char *strcpy(char *restrict destination, const char *restrict source);
int strcmp(const char *left, const char *right);

void Proc_1(Rec_Pointer Ptr_Val_Par);
void Proc_2(One_Fifty *Int_Par_Ref);
void Proc_3(Rec_Pointer *Ptr_Ref_Par);
void Proc_4(void);
void Proc_5(void);
void Proc_6(Enumeration Enum_Val_Par, Enumeration *Enum_Ref_Par);
void Proc_7(One_Fifty Int_1_Par_Val, One_Fifty Int_2_Par_Val,
            One_Fifty *Int_Par_Ref);
void Proc_8(Arr_1_Dim Arr_1_Par_Ref, Arr_2_Dim Arr_2_Par_Ref,
            int Int_1_Par_Val, int Int_2_Par_Val);
Enumeration Func_1(Capital_Letter Ch_1_Par_Val,
                   Capital_Letter Ch_2_Par_Val);
Boolean Func_2(Str_30 Str_1_Par_Ref, Str_30 Str_2_Par_Ref);
Boolean Func_3(Enumeration Enum_Par_Val);

void dhry_port_init(void);
void dhry_port_start_time(void);
void dhry_port_stop_time(void);
unsigned int dhry_port_get_cycles(void);
#if DHRY_HPM
void dhry_port_get_hpm_counts(struct dhry_hpm_counts *counts);
#endif
void dhry_port_puts(const char *text);

#ifndef DHRY_ITERATIONS
#define DHRY_ITERATIONS 100000
#endif

#endif
