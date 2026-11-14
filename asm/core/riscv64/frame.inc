/*
 * Frame and helper macros of the RISC-V core (RISC-V ELF psABI, LP64D).
 * The functions and their steps follow the ARM64 core one for one, with its
 * registers x0-x7 as a0-a7, x9-x15 as t0-t6, x19-x26 as s1-s8, d0-d7 as
 * fa0-fa7 and d16-d17 as ft0-ft1. Inside libp2p_step, s9 holds the state
 * and s10 the scratch; no function changes them.
 */

.set FL, 112                        /* ra, s0-s11 */

/*
 * Frame of a non-leaf function: ra and s0-s11 at sp, extra bytes of locals
 * at sp + FL (ARM64 [sp, k] for k below extra), then locals at
 * sp + FL + extra (ARM64 [sp, extra + 96 + k]). Both are multiples of 16.
 */
.macro ENTER locals, extra=0
    addi    sp, sp, -(FL + \extra + \locals)
    UNWIND_ALLOC (FL + \extra + \locals)
    sd      ra, 0(sp)
    UNWIND_SAVE ra, 0
    sd      s0, 8(sp)
    UNWIND_SAVE s0, 8
    sd      s1, 16(sp)
    UNWIND_SAVE s1, 16
    sd      s2, 24(sp)
    UNWIND_SAVE s2, 24
    sd      s3, 32(sp)
    UNWIND_SAVE s3, 32
    sd      s4, 40(sp)
    UNWIND_SAVE s4, 40
    sd      s5, 48(sp)
    UNWIND_SAVE s5, 48
    sd      s6, 56(sp)
    UNWIND_SAVE s6, 56
    sd      s7, 64(sp)
    UNWIND_SAVE s7, 64
    sd      s8, 72(sp)
    UNWIND_SAVE s8, 72
    sd      s9, 80(sp)
    UNWIND_SAVE s9, 80
    sd      s10, 88(sp)
    UNWIND_SAVE s10, 88
    sd      s11, 96(sp)
    UNWIND_SAVE s11, 96
    UNWIND_END_PROLOGUE
.endm

.macro LEAVE locals, extra=0
    UNWIND_BEGIN_EPILOGUE
    ld      ra, 0(sp)
    UNWIND_RESTORE ra
    ld      s0, 8(sp)
    UNWIND_RESTORE s0
    ld      s1, 16(sp)
    UNWIND_RESTORE s1
    ld      s2, 24(sp)
    UNWIND_RESTORE s2
    ld      s3, 32(sp)
    UNWIND_RESTORE s3
    ld      s4, 40(sp)
    UNWIND_RESTORE s4
    ld      s5, 48(sp)
    UNWIND_RESTORE s5
    ld      s6, 56(sp)
    UNWIND_RESTORE s6
    ld      s7, 64(sp)
    UNWIND_RESTORE s7
    ld      s8, 72(sp)
    UNWIND_RESTORE s8
    ld      s9, 80(sp)
    UNWIND_RESTORE s9
    ld      s10, 88(sp)
    UNWIND_RESTORE s10
    ld      s11, 96(sp)
    UNWIND_RESTORE s11
    addi    sp, sp, (FL + \extra + \locals)
    UNWIND_FREE (FL + \extra + \locals)
    UNWIND_END_EPILOGUE
    ret
.endm

/* reg = state + the u64 at state + field: a table base. */
.macro TABLE reg, field
    ld      \reg, \field(s9)
    add     \reg, s9, \reg
.endm

/* reg = the config field of the state. */
.macro CFG reg, field
    ld      \reg, (ST_CONFIG + \field)(s9)
.endm

/* reg = scratch + off. */
.macro SCR reg, off
    li      \reg, \off
    add     \reg, s10, \reg
.endm

/* reg = the u64 at scratch + off, for any off. */
.macro LDSC reg, off
    li      \reg, \off
    add     \reg, s10, \reg
    ld      \reg, 0(\reg)
.endm

/* Frame of a function that keeps only ra. */
.macro FRAME
    addi    sp, sp, -16
    UNWIND_ALLOC 16
    sd      ra, 8(sp)
    UNWIND_SAVE ra, 8
    UNWIND_END_PROLOGUE
.endm

.macro UNFRAME
    UNWIND_BEGIN_EPILOGUE
    ld      ra, 8(sp)
    UNWIND_RESTORE ra
    addi    sp, sp, 16
    UNWIND_FREE 16
    UNWIND_END_EPILOGUE
    ret
.endm
