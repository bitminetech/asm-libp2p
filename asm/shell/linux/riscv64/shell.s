/*
 * asm-libp2p shell for Linux on RISC-V: TCP sockets, the clock and random
 * bytes, through direct system calls. Requirements: docs/reference/shell.md.
 * Layouts: include/libp2p.inc.
 *
 * System calls: the number in a7, arguments in a0 to a5, "ecall"; a0 holds
 * the result, or minus the error number (-4095 to -1). The steps follow the
 * ARM64 shell one for one, with its x19-x28 as s1-s10 and x9-x15 as t0-t6.
 * 8-byte loads and stores only touch 8-byte aligned addresses.
 */
.set ISA_RISCV64, 1
.include "libp2p.inc"
.include "platform.inc"

/* Linux numbers: asm-generic/unistd.h and the uapi headers. */
.set SYS_CLOSE, 57
.set SYS_PPOLL, 73
.set SYS_CLOCK_GETTIME, 113
.set SYS_SOCKET, 198
.set SYS_BIND, 200
.set SYS_LISTEN, 201
.set SYS_CONNECT, 203
.set SYS_GETSOCKNAME, 204
.set SYS_SENDTO, 206
.set SYS_RECVFROM, 207
.set SYS_SETSOCKOPT, 208
.set SYS_GETSOCKOPT, 209
.set SYS_ACCEPT4, 242
.set SYS_GETRANDOM, 278
.set OS_AF_INET, 2
.set OS_AF_INET6, 10
.set OS_SOCK_STREAM, 1
.set OS_SOCK_NONBLOCK, 0x800        /* O_NONBLOCK of asm-generic/fcntl.h */
.set OS_SOCK_CLOEXEC, 0x80000
.set OS_SOL_SOCKET, 1
.set OS_SO_LISTEN, 2                /* the option of a listener: SO_REUSEADDR */
.set OS_SO_ERROR, 4
.set OS_IPPROTO_TCP, 6
.set OS_TCP_NODELAY, 1
.set OS_IPPROTO_IPV6, 41
.set OS_IPV6_V6ONLY, 26
.set OS_MSG_DONTWAIT, 0x40
.set OS_MSG_NOSIGNAL, 0x4000
.set OS_POLLIN, 1
.set OS_POLLOUT, 4
.set OS_POLLERR, 8
.set OS_POLLHUP, 16
.set OS_EAGAIN, 11
.set OS_EINVAL, 22
.set OS_EINPROGRESS, 115
.set OS_CLOCK_MONOTONIC, 1
.set POLL_STRIDE, 16                /* context bytes per poll entry: the largest of every OS (Windows) */
.set POLL_SHIFT, 3                  /* struct pollfd: 8 bytes, fd at 0, events at 4, revents at 6 */

.set NONE_SOCKET, -1
.set FL, 112                        /* ra, s0-s11; locals at sp + FL */

.macro SYSCALL number
    li      a7, \number
    ecall
.endm

/* Branch to label when a0 is minus an error number (-4095 to -1). Uses t6. */
.macro IF_ERROR_NEG label
    li      t6, -4095
    bgeu    a0, t6, \label
.endm

/* Branch to label when the call would block. Uses t6. */
.macro IF_WOULDBLOCK label
    li      t6, -OS_EAGAIN
    beq     a0, t6, \label
.endm

/* Branch to label when a connect is in progress. Uses t6. */
.macro IF_INPROGRESS label
    li      t6, -OS_EINPROGRESS
    beq     a0, t6, \label
.endm

/* The family of a socket address of len bytes. */
.macro SET_FAMILY reg, base, len
    sh      \reg, 0(\base)
.endm

.macro GET_FAMILY reg, base
    lhu     \reg, 0(\base)
.endm

/* a0 = the status of starting the OS sockets: nothing to start. */
.macro OS_STARTUP context
    li      a0, LIBP2P_OK
.endm

.macro OS_CLEANUP context
.endm

/* a0 = a non-blocking TCP socket of family a0, or minus the error. */
.macro OS_SOCKET
    li      a1, (OS_SOCK_STREAM | OS_SOCK_NONBLOCK | OS_SOCK_CLOEXEC)
    li      a2, 0
    SYSCALL SYS_SOCKET
.endm

/* setsockopt(a0, a1, a2) to the int 1 (at sp + FL + 152). */
.macro OS_SETSOCKOPT_ONE
    li      t0, 1
    sw      t0, (FL + 152)(sp)
    addi    a3, sp, (FL + 152)
    li      a4, 4
    SYSCALL SYS_SETSOCKOPT
.endm

.macro OS_BIND
    SYSCALL SYS_BIND
.endm

.macro OS_LISTEN
    SYSCALL SYS_LISTEN
.endm

.macro OS_GETSOCKNAME
    SYSCALL SYS_GETSOCKNAME
.endm

.macro OS_CONNECT
    SYSCALL SYS_CONNECT
.endm

/* sendto(a0, a1, a2) without SIGPIPE or blocking. */
.macro OS_SEND
    li      a3, (OS_MSG_NOSIGNAL | OS_MSG_DONTWAIT)
    li      a4, 0
    li      a5, 0
    SYSCALL SYS_SENDTO
.endm

/* recvfrom(a0, a1, a2) without blocking. */
.macro OS_RECV
    li      a3, OS_MSG_DONTWAIT
    li      a4, 0
    li      a5, 0
    SYSCALL SYS_RECVFROM
.endm

/* accept4(a0, a1, a2): the new socket non-blocking. */
.macro OS_ACCEPT
    li      a3, (OS_SOCK_NONBLOCK | OS_SOCK_CLOEXEC)
    SYSCALL SYS_ACCEPT4
.endm

.macro OS_CLOSE
    SYSCALL SYS_CLOSE
.endm

/* a0 = the pending error of socket a0 (SO_ERROR), 0 when none. Uses sp + FL + 136 and sp + FL + 144. */
.macro OS_SOCKET_ERROR
    sw      zero, (FL + 144)(sp)
    li      t0, 4
    sw      t0, (FL + 136)(sp)
    li      a1, OS_SOL_SOCKET
    li      a2, OS_SO_ERROR
    addi    a3, sp, (FL + 144)
    addi    a4, sp, (FL + 136)
    SYSCALL SYS_GETSOCKOPT
    li      t6, -4095
    bgeu    a0, t6, 1000f
    lwu     a0, (FL + 144)(sp)
    j       1001f
1000: neg   a0, a0
1001:
.endm

/* ppoll(a0, a1, timeout a2 ms) -> ready count or minus the error. Uses sp + FL. */
.macro OS_POLL
    li      t0, 1000
    divu    t1, a2, t0
    remu    t2, a2, t0
    li      t0, 1000000
    mul     t2, t2, t0
    sd      t1, FL(sp)
    sd      t2, (FL + 8)(sp)
    addi    a2, sp, FL
    li      a3, 0
    li      a4, 0
    SYSCALL SYS_PPOLL
.endm

/* Frame: ra, s0-s11, then locals at sp + FL. */
.macro SENTER locals
    addi    sp, sp, -(FL + \locals)
    UNWIND_ALLOC (FL + \locals)
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

.macro SLEAVE locals
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
    addi    sp, sp, (FL + \locals)
    UNWIND_FREE (FL + \locals)
    UNWIND_END_EPILOGUE
    ret
.endm

/* rd = the low 16 bits of rs with their two bytes swapped. Uses tmp. */
.macro SWAP16 rd, rs, tmp
    andi    \tmp, \rs, 0xFF
    slli    \tmp, \tmp, 8
    srli    \rd, \rs, 8
    andi    \rd, \rd, 0xFF
    or      \rd, \rd, \tmp
.endm

/* ---------------------------------------------------------------- Addresses */

/* libp2p_shell_sockaddr(addr, sockaddr) -> its length: 16 for IPv4, 28 for IPv6. sockaddr is 8-byte aligned. A leaf. */
LOCAL_FUNCTION libp2p_shell_sockaddr
    UNWIND_END_PROLOGUE
    ld      t0, LIBP2P_ADDR_FAMILY(a0)
    ld      t1, LIBP2P_ADDR_PORT(a0)
    SWAP16  t1, t1, t2
    sd      zero, 0(a1)
    sd      zero, 8(a1)
    sd      zero, 16(a1)
    sd      zero, 24(a1)
    li      t3, 6
    beq     t0, t3, 1f
    li      t2, OS_AF_INET
    SET_FAMILY t2, a1, 16
    sh      t1, 2(a1)
    lwu     t2, LIBP2P_ADDR_IP(a0)
    sw      t2, 4(a1)
    li      a0, 16
    ret
1:  li      t2, OS_AF_INET6
    SET_FAMILY t2, a1, 28
    sh      t1, 2(a1)
    ld      t2, LIBP2P_ADDR_IP(a0)
    ld      t3, (LIBP2P_ADDR_IP + 8)(a0)
    sd      t2, 8(a1)
    sd      t3, 16(a1)
    li      a0, 28
    ret
END_FUNCTION libp2p_shell_sockaddr

/* libp2p_shell_address(sockaddr, addr): an Address of an IPv4 or IPv6 socket address; an IPv4-mapped IPv6 address becomes IPv4. A leaf. */
LOCAL_FUNCTION libp2p_shell_address
    UNWIND_END_PROLOGUE
    sd      zero, 0(a1)
    sd      zero, 8(a1)
    sd      zero, 16(a1)
    sd      zero, 24(a1)
    lhu     t1, 2(a0)
    SWAP16  t1, t1, t2
    sd      t1, LIBP2P_ADDR_PORT(a1)
    GET_FAMILY t0, a0
    li      t2, OS_AF_INET
    bne     t0, t2, 1f
    li      t0, 4
    sd      t0, LIBP2P_ADDR_FAMILY(a1)
    lwu     t2, 4(a0)
    sw      t2, LIBP2P_ADDR_IP(a1)
    ret
1:  ld      t2, 8(a0)
    ld      t3, 16(a0)
    srli    t4, t3, 32                      # ::ffff:a.b.c.d
    bnez    t2, 2f
    slli    t5, t3, 32
    srli    t5, t5, 32
    li      t6, 0xFFFF0000
    bne     t5, t6, 2f
    li      t0, 4
    sd      t0, LIBP2P_ADDR_FAMILY(a1)
    sw      t4, LIBP2P_ADDR_IP(a1)
    ret
2:  li      t0, 6
    sd      t0, LIBP2P_ADDR_FAMILY(a1)
    sd      t2, LIBP2P_ADDR_IP(a1)
    sd      t3, (LIBP2P_ADDR_IP + 8)(a1)
    ret
END_FUNCTION libp2p_shell_address

/* ---------------------------------------------------------------- Layout */

/*
 * libp2p_shell_layout(params, context or 0) -> a0 status, a1 the context
 * size. With a context, writes its fixed fields. A leaf.
 */
LOCAL_FUNCTION libp2p_shell_layout
    UNWIND_END_PROLOGUE
    ld      a2, LIBP2P_SP_CAPACITY(a0)
    ld      a3, LIBP2P_SP_BUFFER(a0)
    beqz    a2, 8f
    li      t0, 65536
    bltu    t0, a2, 8f
    li      t0, 4096
    bltu    a3, t0, 8f
    li      t0, 0x40000000
    bltu    t0, a3, 8f
    addi    a3, a3, 7
    andi    a3, a3, -8
    addi    a4, a3, LIBP2P_SE_FIXED         # stride
    li      a5, (LIBP2P_SH_FIXED + 8 * LIBP2P_SHELL_ACCEPTING)   # poll array
    addi    a6, a2, (LIBP2P_SH_MAX_LISTEN + LIBP2P_SHELL_ACCEPTING)
    li      t0, POLL_STRIDE
    mul     a6, a6, t0
    add     a6, a6, a5                      # entries
    mul     a7, a2, a4
    add     a7, a7, a6                      # total
    beqz    a1, 1f
    sd      a2, LIBP2P_SH_CAPACITY(a1)
    sd      a3, LIBP2P_SH_BUFFER(a1)
    sd      a4, LIBP2P_SH_STRIDE(a1)
    sd      a5, LIBP2P_SH_POLL(a1)
    sd      a6, LIBP2P_SH_ENTRIES(a1)
1:  li      a0, LIBP2P_OK
    mv      a1, a7
    ret
8:  li      a0, LIBP2P_INVALID_CONFIG
    li      a1, 0
    ret
END_FUNCTION libp2p_shell_layout

/* libp2p_shell_size(params, size) -> status: the bytes of a ShellContext for the params. */
FUNCTION libp2p_shell_size
    SENTER  0
    mv      s1, a1
    li      a1, 0
    call    libp2p_shell_layout
    bnez    a0, 9f
    sd      a1, 0(s1)
9:  SLEAVE  0
END_FUNCTION libp2p_shell_size

/*
 * libp2p_shell_init(params, context) -> status: a context with no sockets.
 * The size field of the context gives its bytes.
 */
FUNCTION libp2p_shell_init
    SENTER  0
    mv      s1, a0
    mv      s2, a1
    li      a1, 0
    call    libp2p_shell_layout
    bnez    a0, 9f
    li      a0, LIBP2P_BUFFER_TOO_SMALL
    ld      t0, LIBP2P_SH_SIZE(s2)
    bltu    t0, a1, 9f
    mv      a0, s1
    mv      a1, s2
    call    libp2p_shell_layout
    li      t0, NONE_SOCKET
    sd      zero, LIBP2P_SH_LISTENERS(s2)
    addi    t1, s2, LIBP2P_SH_LISTEN
    li      t2, LIBP2P_SH_MAX_LISTEN
1:  sd      t0, 0(t1)
    addi    t1, t1, 8
    addi    t2, t2, -1
    bnez    t2, 1b
    addi    t1, s2, LIBP2P_SH_FIXED         # accepted sockets
    li      t2, LIBP2P_SHELL_ACCEPTING
2:  sd      t0, 0(t1)
    addi    t1, t1, 8
    addi    t2, t2, -1
    bnez    t2, 2b
    ld      t1, LIBP2P_SH_ENTRIES(s2)
    add     t1, s2, t1
    ld      t2, LIBP2P_SH_CAPACITY(s2)
    ld      t3, LIBP2P_SH_STRIDE(s2)
3:  sd      t0, LIBP2P_SE_SOCKET(t1)
    sd      zero, LIBP2P_SE_STATE(t1)
    sd      zero, LIBP2P_SE_LEN(t1)
    add     t1, t1, t3
    addi    t2, t2, -1
    bnez    t2, 3b
    OS_STARTUP s2                           # a0 = status
9:  SLEAVE  0
END_FUNCTION libp2p_shell_init

/* libp2p_shell_entry(context, handle) -> the entry of the connection slot of the handle, or 0 past the capacity. A leaf. */
LOCAL_FUNCTION libp2p_shell_entry
    UNWIND_END_PROLOGUE
    slli    a1, a1, 32
    srli    a1, a1, 32
    ld      a2, LIBP2P_SH_CAPACITY(a0)
    bgeu    a1, a2, 8f
    ld      a2, LIBP2P_SH_ENTRIES(a0)
    add     a2, a0, a2
    ld      a3, LIBP2P_SH_STRIDE(a0)
    mul     a0, a1, a3
    add     a0, a0, a2
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_shell_entry

/* ---------------------------------------------------------------- Event list */

/*
 * libp2p_shell_event(events, kind, size) -> the new event, zeroed, with
 * size and kind set; 0 when the list has no room.
 */
LOCAL_FUNCTION libp2p_shell_event
    SENTER  0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      t0, LIBP2P_BL_SIZE(s1)
    ld      t1, LIBP2P_BL_OFFSET(s1)
    ld      t2, LIBP2P_BL_COUNT(s1)
    sub     t0, t0, t1
    sub     t0, t0, t2
    li      a0, 0
    bltu    t0, s3, 9f
    add     s4, s1, t1
    add     s4, s4, t2
    add     t2, t2, s3
    sd      t2, LIBP2P_BL_COUNT(s1)
    li      t0, 0
1:  bgeu    t0, s3, 2f
    add     t1, s4, t0
    sd      zero, 0(t1)
    addi    t0, t0, 8
    j       1b
2:  sd      s3, LIBP2P_EV_SIZE(s4)
    sd      s2, LIBP2P_EV_KIND(s4)
    mv      a0, s4
9:  SLEAVE  0
END_FUNCTION libp2p_shell_event

/* libp2p_shell_room(events) -> the bytes left in the event list. A leaf. */
LOCAL_FUNCTION libp2p_shell_room
    UNWIND_END_PROLOGUE
    ld      t0, LIBP2P_BL_SIZE(a0)
    ld      t1, LIBP2P_BL_OFFSET(a0)
    ld      t2, LIBP2P_BL_COUNT(a0)
    sub     t0, t0, t1
    li      a0, 0
    bltu    t0, t2, 1f
    sub     a0, t0, t2
1:  ret
END_FUNCTION libp2p_shell_room

/* libp2p_shell_conn_event(events, kind, handle, value): an event with a connection handle and a value (error or count). */
LOCAL_FUNCTION libp2p_shell_conn_event
    SENTER  0
    mv      s1, a2
    mv      s2, a3
    li      a2, LIBP2P_EV_CONN_SIZE
    call    libp2p_shell_event
    beqz    a0, 9f
    sd      s1, LIBP2P_EV_CONN(a0)
    sd      s2, LIBP2P_EV_ERROR(a0)
9:  SLEAVE  0
END_FUNCTION libp2p_shell_conn_event

/* ---------------------------------------------------------------- Sockets */

/*
 * libp2p_shell_drop(entry, events, error): closes the socket of a
 * connection and gives CLOSED with the error.
 */
LOCAL_FUNCTION libp2p_shell_drop
    SENTER  0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      a0, LIBP2P_SE_SOCKET(s1)
    OS_CLOSE
    li      t0, NONE_SOCKET
    sd      t0, LIBP2P_SE_SOCKET(s1)
    sd      zero, LIBP2P_SE_STATE(s1)
    sd      zero, LIBP2P_SE_LEN(s1)
    mv      a0, s2
    li      a1, LIBP2P_EVENT_CLOSED
    ld      a2, LIBP2P_SE_HANDLE(s1)
    mv      a3, s3
    call    libp2p_shell_conn_event
    SLEAVE  0
END_FUNCTION libp2p_shell_drop

/*
 * libp2p_shell_flush(entry, events): writes what the send buffer holds,
 * until the socket would block; SENT with the bytes written; an error
 * closes the connection (CLOSED).
 * s1 entry, s2 events, s3 written, s4 bytes in the buffer, s5 the error.
 */
LOCAL_FUNCTION libp2p_shell_flush
    SENTER  0
    mv      s1, a0
    mv      s2, a1
    li      s3, 0                           # written
1:  ld      s4, LIBP2P_SE_LEN(s1)
    bgeu    s3, s4, 3f
    ld      a0, LIBP2P_SE_SOCKET(s1)
    addi    a1, s1, LIBP2P_SE_DATA
    add     a1, a1, s3
    sub     a2, s4, s3
    OS_SEND
    IF_WOULDBLOCK 3f
    IF_ERROR_NEG 8f
    add     s3, s3, a0
    j       1b
3:  beqz    s3, 9f
    addi    a0, s1, LIBP2P_SE_DATA          # keep the rest at the front
    add     a1, a0, s3
    sub     a2, s4, s3
    sd      a2, LIBP2P_SE_LEN(s1)
    call    libp2p_shell_move
    mv      a0, s2
    li      a1, LIBP2P_EVENT_SENT
    ld      a2, LIBP2P_SE_HANDLE(s1)
    mv      a3, s3
    call    libp2p_shell_conn_event
    j       9f
8:  neg     s5, a0
    beqz    s3, 81f
    mv      a0, s2
    li      a1, LIBP2P_EVENT_SENT
    ld      a2, LIBP2P_SE_HANDLE(s1)
    mv      a3, s3
    call    libp2p_shell_conn_event
81: mv      a0, s1
    mv      a1, s2
    mv      a2, s5
    call    libp2p_shell_drop
9:  SLEAVE  0
END_FUNCTION libp2p_shell_flush

/* libp2p_shell_move(dst, src, n): copies n bytes forward; dst is below src. A leaf. */
LOCAL_FUNCTION libp2p_shell_move
    UNWIND_END_PROLOGUE
1:  beqz    a2, 2f
    lbu     a3, 0(a1)
    sb      a3, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, 1
    addi    a2, a2, -1
    j       1b
2:  ret
END_FUNCTION libp2p_shell_move

/*
 * libp2p_shell_listen(context, addr, result) -> status: a listening TCP
 * socket bound to the address (port 0: any); result gets 0 and the bound
 * address, or the OS error.
 * s1 context, s2 addr, s3 result, s4 family, s5 the error, s6 the socket.
 * Locals: the socket address at sp + FL, its length at sp + FL + 128.
 */
FUNCTION libp2p_shell_listen
    SENTER  160
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      t0, 0
1:  add     t1, s3, t0
    sd      zero, 0(t1)
    addi    t0, t0, 8
    li      t1, LIBP2P_LR_SIZE
    bltu    t0, t1, 1b
    ld      t0, LIBP2P_SH_LISTENERS(s1)
    li      s5, OS_EINVAL
    li      t1, LIBP2P_SH_MAX_LISTEN
    bgeu    t0, t1, 80f
    ld      t0, LIBP2P_ADDR_FAMILY(s2)
    li      a0, OS_AF_INET
    li      t1, 6
    bne     t0, t1, 11f
    li      a0, OS_AF_INET6
11: mv      s4, a0
    OS_SOCKET
    IF_ERROR_NEG 81f
    mv      s6, a0                          # the socket
    mv      a0, s6
    li      a1, OS_SOL_SOCKET
    li      a2, OS_SO_LISTEN
    OS_SETSOCKOPT_ONE
    li      t0, OS_AF_INET6
    bne     s4, t0, 2f
    mv      a0, s6
    li      a1, OS_IPPROTO_IPV6
    li      a2, OS_IPV6_V6ONLY
    OS_SETSOCKOPT_ONE
2:  mv      a0, s2
    addi    a1, sp, FL
    call    libp2p_shell_sockaddr
    mv      a2, a0
    mv      a0, s6
    addi    a1, sp, FL
    OS_BIND
    IF_ERROR_NEG 82f
    mv      a0, s6
    li      a1, 1024
    OS_LISTEN
    IF_ERROR_NEG 82f
    li      t0, 128
    sd      t0, (FL + 128)(sp)
    mv      a0, s6
    addi    a1, sp, FL
    addi    a2, sp, (FL + 128)
    OS_GETSOCKNAME
    IF_ERROR_NEG 82f
    addi    a0, sp, FL
    addi    a1, s3, LIBP2P_LR_ADDR
    call    libp2p_shell_address
    ld      t0, LIBP2P_SH_LISTENERS(s1)
    addi    t1, s1, LIBP2P_SH_LISTEN
    slli    t2, t0, 3
    add     t1, t1, t2
    sd      s6, 0(t1)
    addi    t0, t0, 1
    sd      t0, LIBP2P_SH_LISTENERS(s1)
    j       90f
82: neg     s5, a0
    mv      a0, s6
    OS_CLOSE
    j       80f
81: neg     s5, a0
80: sd      s5, LIBP2P_LR_ERROR(s3)
90: li      a0, LIBP2P_OK
    SLEAVE  160
END_FUNCTION libp2p_shell_listen

/*
 * libp2p_shell_perform(context, actions, events) -> status: does the shell
 * actions of a step in order: DIAL, ADOPT, REFUSE, SEND and CLOSE; results
 * known at once go to events (CONNECTED, DIAL_FAILED, SENT, CLOSED). Other
 * kinds are the application's.
 * s1 context, s2 events, s3 action, s4 end, s5 entry, s6 socket or count,
 * s7 kind. Locals: the socket address at sp + FL.
 */
FUNCTION libp2p_shell_perform
    SENTER  160
    mv      s1, a0
    mv      s2, a2
    ld      t0, LIBP2P_BL_OFFSET(a1)
    add     s3, a1, t0
    ld      t0, LIBP2P_BL_COUNT(a1)
    add     s4, s3, t0
1:  bgeu    s3, s4, 90f
    ld      s7, LIBP2P_ACT_KIND(s3)
    li      t0, LIBP2P_ACTION_DIAL
    bne     s7, t0, 20f

    /* DIAL */
    mv      a0, s1
    ld      a1, LIBP2P_ACT_CONN(s3)
    call    libp2p_shell_entry
    beqz    a0, 80f
    mv      s5, a0
    ld      t0, LIBP2P_SE_STATE(s5)
    beqz    t0, 11f
    ld      a0, LIBP2P_SE_SOCKET(s5)        # a stale socket in the slot
    OS_CLOSE
11: ld      t0, LIBP2P_ACT_CONN(s3)
    sd      t0, LIBP2P_SE_HANDLE(s5)
    sd      zero, LIBP2P_SE_LEN(s5)
    sd      zero, LIBP2P_SE_STATE(s5)
    li      t0, NONE_SOCKET
    sd      t0, LIBP2P_SE_SOCKET(s5)
    ld      t0, (LIBP2P_ACT_DIAL_ADDR + LIBP2P_ADDR_FAMILY)(s3)
    li      a0, OS_AF_INET
    li      t1, 6
    bne     t0, t1, 12f
    li      a0, OS_AF_INET6
12: OS_SOCKET
    IF_ERROR_NEG 15f
    sd      a0, LIBP2P_SE_SOCKET(s5)
    li      a1, OS_IPPROTO_TCP
    li      a2, OS_TCP_NODELAY
    OS_SETSOCKOPT_ONE
    addi    a0, s3, LIBP2P_ACT_DIAL_ADDR
    addi    a1, sp, FL
    call    libp2p_shell_sockaddr
    mv      a2, a0
    ld      a0, LIBP2P_SE_SOCKET(s5)
    addi    a1, sp, FL
    OS_CONNECT
    IF_INPROGRESS 13f
    IF_ERROR_NEG 14f
    li      t0, 2                           # connected at once
    sd      t0, LIBP2P_SE_STATE(s5)
    mv      a0, s2
    li      a1, LIBP2P_EVENT_CONNECTED
    ld      a2, LIBP2P_SE_HANDLE(s5)
    li      a3, 0
    call    libp2p_shell_conn_event
    j       80f
13: li      t0, 1
    sd      t0, LIBP2P_SE_STATE(s5)
    j       80f
14: neg     s6, a0
    ld      a0, LIBP2P_SE_SOCKET(s5)
    OS_CLOSE
    li      t0, NONE_SOCKET
    sd      t0, LIBP2P_SE_SOCKET(s5)
    neg     a0, s6
15: neg     a3, a0
    mv      a0, s2
    li      a1, LIBP2P_EVENT_DIAL_FAILED
    ld      a2, LIBP2P_ACT_CONN(s3)
    call    libp2p_shell_conn_event
    j       80f

    /* ADOPT and REFUSE: the accepted socket of the token. */
20: li      t0, LIBP2P_ACTION_ADOPT
    beq     s7, t0, 21f
    li      t0, LIBP2P_ACTION_REFUSE
    bne     s7, t0, 30f
21: ld      t1, LIBP2P_ACT_TOKEN(s3)
    addi    t2, s1, LIBP2P_SH_FIXED
    li      t3, 0
22: li      t0, LIBP2P_SHELL_ACCEPTING
    bgeu    t3, t0, 80f
    slli    t4, t3, 3
    add     t4, t2, t4
    ld      t5, 0(t4)
    beq     t5, t1, 23f
    addi    t3, t3, 1
    j       22b
23: li      t0, NONE_SOCKET
    sd      t0, 0(t4)
    mv      s6, t5
    li      t0, LIBP2P_ACTION_REFUSE
    beq     s7, t0, 24f
    mv      a0, s1
    ld      a1, LIBP2P_ACT_ADOPT_CONN(s3)
    call    libp2p_shell_entry
    beqz    a0, 24f
    mv      s5, a0
    ld      t0, LIBP2P_SE_STATE(s5)
    beqz    t0, 25f
    ld      a0, LIBP2P_SE_SOCKET(s5)
    OS_CLOSE
25: sd      s6, LIBP2P_SE_SOCKET(s5)
    ld      t0, LIBP2P_ACT_ADOPT_CONN(s3)
    sd      t0, LIBP2P_SE_HANDLE(s5)
    li      t0, 2
    sd      t0, LIBP2P_SE_STATE(s5)
    sd      zero, LIBP2P_SE_LEN(s5)
    j       80f
24: mv      a0, s6
    OS_CLOSE
    j       80f

    /* SEND: into the send buffer, then write what the socket takes. */
30: li      t0, LIBP2P_ACTION_SEND
    bne     s7, t0, 40f
    mv      a0, s1
    ld      a1, LIBP2P_ACT_CONN(s3)
    call    libp2p_shell_entry
    beqz    a0, 80f
    mv      s5, a0
    ld      t0, LIBP2P_SE_STATE(s5)
    li      t1, 2
    bne     t0, t1, 80f
    ld      t0, LIBP2P_SE_HANDLE(s5)
    ld      t1, LIBP2P_ACT_CONN(s3)
    bne     t0, t1, 80f
    ld      s6, LIBP2P_ACT_SEND_COUNT(s3)
    ld      t0, LIBP2P_SE_LEN(s5)
    ld      t1, LIBP2P_SH_BUFFER(s1)
    sub     t1, t1, t0
    bgeu    t1, s6, 31f
    mv      a0, s5                          # more than the buffer holds: the connection ends
    mv      a1, s2
    li      a2, OS_EINVAL
    call    libp2p_shell_drop
    j       80f
31: addi    a0, s5, LIBP2P_SE_DATA
    add     a0, a0, t0
    addi    a1, s3, LIBP2P_ACT_SEND_DATA
    mv      a2, s6
    call    libp2p_shell_move_any
    ld      t0, LIBP2P_SE_LEN(s5)
    add     t0, t0, s6
    sd      t0, LIBP2P_SE_LEN(s5)
    mv      a0, s5
    mv      a1, s2
    call    libp2p_shell_flush
    j       80f

    /* CLOSE */
40: li      t0, LIBP2P_ACTION_CLOSE
    bne     s7, t0, 80f
    mv      a0, s1
    ld      a1, LIBP2P_ACT_CONN(s3)
    call    libp2p_shell_entry
    beqz    a0, 80f
    mv      s5, a0
    ld      t0, LIBP2P_SE_STATE(s5)
    beqz    t0, 41f
    ld      t0, LIBP2P_SE_HANDLE(s5)
    ld      t1, LIBP2P_ACT_CONN(s3)
    bne     t0, t1, 41f
    mv      a0, s5
    mv      a1, s2
    li      a2, 0
    call    libp2p_shell_drop
    j       80f
41: mv      a0, s2                          # no socket: CLOSED all the same
    li      a1, LIBP2P_EVENT_CLOSED
    ld      a2, LIBP2P_ACT_CONN(s3)
    li      a3, 0
    call    libp2p_shell_conn_event
80: ld      t0, LIBP2P_ACT_SIZE(s3)
    add     s3, s3, t0
    j       1b
90: li      a0, LIBP2P_OK
    SLEAVE  160
END_FUNCTION libp2p_shell_perform

/*
 * libp2p_shell_move_any(dst, src, n): copies n bytes of regions that do not
 * overlap, 8 at a time when both are 8-byte aligned. A leaf.
 */
LOCAL_FUNCTION libp2p_shell_move_any
    UNWIND_END_PROLOGUE
    or      a3, a0, a1
    andi    a3, a3, 7
    bnez    a3, 2f
    li      a4, 8
1:  bltu    a2, a4, 2f
    ld      a3, 0(a1)
    sd      a3, 0(a0)
    addi    a0, a0, 8
    addi    a1, a1, 8
    addi    a2, a2, -8
    j       1b
2:  beqz    a2, 3f
    lbu     a3, 0(a1)
    sb      a3, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, 1
    addi    a2, a2, -1
    j       2b
3:  ret
END_FUNCTION libp2p_shell_move_any

/*
 * libp2p_shell_wait(context, timeout, events) -> status: waits up to
 * timeout ms (a u64) for socket activity, then gives events: ACCEPTED for
 * new connections (up to 16 waiting for ADOPT), CONNECTED or DIAL_FAILED
 * when a dial ends, SENT as buffered bytes go out, RECEIVED with what a
 * socket holds (at most 65536 bytes, while the event list has room), and
 * CLOSED when a socket ends.
 * s1 context, s2 events, s3 poll array, s4 poll count, s5 i, s6 entry,
 * s7 listeners, s8 timeout then revents, s9 bytes or the error, s10 event.
 */
FUNCTION libp2p_shell_wait
    SENTER  160
    mv      s1, a0
    mv      s2, a2
    ld      s8, 0(a1)                       # timeout
    ld      s3, LIBP2P_SH_POLL(s1)
    add     s3, s1, s3
    li      s4, 0
    li      s5, 0                           # listeners
1:  ld      t0, LIBP2P_SH_LISTENERS(s1)
    bgeu    s5, t0, 2f
    addi    t1, s1, LIBP2P_SH_LISTEN
    slli    t2, s5, 3
    add     t1, t1, t2
    ld      a0, 0(t1)
    li      a1, OS_POLLIN
    mv      a2, s4
    mv      a3, s3
    call    libp2p_shell_poll_set
    addi    s4, s4, 1
    addi    s5, s5, 1
    j       1b
2:  li      s5, 0                           # connections
3:  ld      t0, LIBP2P_SH_CAPACITY(s1)
    bgeu    s5, t0, 5f
    ld      t1, LIBP2P_SH_ENTRIES(s1)
    add     t1, s1, t1
    ld      t2, LIBP2P_SH_STRIDE(s1)
    mul     s6, s5, t2
    add     s6, s6, t1
    ld      t0, LIBP2P_SE_STATE(s6)
    li      a0, NONE_SOCKET                 # a free slot polls no socket
    li      a1, 0
    beqz    t0, 4f
    ld      a0, LIBP2P_SE_SOCKET(s6)
    li      a1, OS_POLLOUT
    li      t1, 1
    beq     t0, t1, 4f
    li      a1, OS_POLLIN
    ld      t1, LIBP2P_SE_LEN(s6)
    beqz    t1, 4f
    ori     a1, a1, OS_POLLOUT
4:  mv      a2, s4
    mv      a3, s3
    call    libp2p_shell_poll_set
    addi    s4, s4, 1
    addi    s5, s5, 1
    j       3b
5:  mv      a0, s3
    mv      a1, s4
    mv      a2, s8
    OS_POLL
    IF_ERROR_NEG 90f
    beqz    a0, 90f

    /* Listeners: accept while there is room. */
    li      s5, 0
6:  ld      t0, LIBP2P_SH_LISTENERS(s1)
    bgeu    s5, t0, 7f
    mv      a0, s5
    mv      a1, s3
    call    libp2p_shell_poll_events
    andi    a0, a0, OS_POLLIN
    beqz    a0, 61f
    mv      a0, s1
    mv      a1, s2
    addi    t0, s1, LIBP2P_SH_LISTEN
    slli    t1, s5, 3
    add     t0, t0, t1
    ld      a2, 0(t0)
    call    libp2p_shell_accept
61: addi    s5, s5, 1
    j       6b

    /* Connections. */
7:  ld      s7, LIBP2P_SH_LISTENERS(s1)
    li      s5, 0
8:  ld      t0, LIBP2P_SH_CAPACITY(s1)
    bgeu    s5, t0, 90f
    ld      t1, LIBP2P_SH_ENTRIES(s1)
    add     t1, s1, t1
    ld      t2, LIBP2P_SH_STRIDE(s1)
    mul     s6, s5, t2
    add     s6, s6, t1
    add     a0, s7, s5
    mv      a1, s3
    call    libp2p_shell_poll_events
    mv      s8, a0
    beqz    s8, 89f
    ld      t0, LIBP2P_SE_STATE(s6)
    beqz    t0, 89f
    li      t1, 1
    bne     t0, t1, 81f
    ld      a0, LIBP2P_SE_SOCKET(s6)        # a dial ended
    OS_SOCKET_ERROR
    bnez    a0, 80f
    li      t0, 2
    sd      t0, LIBP2P_SE_STATE(s6)
    mv      a0, s2
    li      a1, LIBP2P_EVENT_CONNECTED
    ld      a2, LIBP2P_SE_HANDLE(s6)
    li      a3, 0
    call    libp2p_shell_conn_event
    j       89f
80: mv      s9, a0
    ld      a0, LIBP2P_SE_SOCKET(s6)
    OS_CLOSE
    li      t0, NONE_SOCKET
    sd      t0, LIBP2P_SE_SOCKET(s6)
    sd      zero, LIBP2P_SE_STATE(s6)
    mv      a0, s2
    li      a1, LIBP2P_EVENT_DIAL_FAILED
    ld      a2, LIBP2P_SE_HANDLE(s6)
    mv      a3, s9
    call    libp2p_shell_conn_event
    j       89f
81: andi    t0, s8, OS_POLLOUT
    beqz    t0, 82f
    mv      a0, s6
    mv      a1, s2
    call    libp2p_shell_flush
    ld      t0, LIBP2P_SE_STATE(s6)
    beqz    t0, 89f
82: andi    t0, s8, (OS_POLLIN | OS_POLLHUP | OS_POLLERR)
    beqz    t0, 89f
    mv      a0, s2                          # read into a RECEIVED event
    call    libp2p_shell_room
    li      t0, (LIBP2P_EV_DATA + 8)
    bgeu    t0, a0, 89f
    sub     s9, a0, t0
    li      t0, LIBP2P_RECEIVE_MAX
    bltu    s9, t0, 821f
    mv      s9, t0
821: ld     t0, LIBP2P_BL_OFFSET(s2)
    ld      t1, LIBP2P_BL_COUNT(s2)
    add     s10, s2, t0
    add     s10, s10, t1                    # the event, not yet in the list
    ld      a0, LIBP2P_SE_SOCKET(s6)
    addi    a1, s10, LIBP2P_EV_DATA
    mv      a2, s9
    OS_RECV
    IF_WOULDBLOCK 89f
    IF_ERROR_NEG 83f
    beqz    a0, 84f
    addi    t1, a0, (LIBP2P_EV_DATA + 7)
    andi    t1, t1, -8
    sd      t1, LIBP2P_EV_SIZE(s10)
    li      t2, LIBP2P_EVENT_RECEIVED
    sd      t2, LIBP2P_EV_KIND(s10)
    ld      t2, LIBP2P_SE_HANDLE(s6)
    sd      t2, LIBP2P_EV_CONN(s10)
    sd      a0, LIBP2P_EV_COUNT(s10)
    ld      t2, LIBP2P_BL_COUNT(s2)
    add     t2, t2, t1
    sd      t2, LIBP2P_BL_COUNT(s2)
    j       89f
83: neg     a2, a0
    j       85f
84: li      a2, 0                           # the peer closed
85: mv      a0, s6
    mv      a1, s2
    call    libp2p_shell_drop
89: addi    s5, s5, 1
    j       8b
90: li      a0, LIBP2P_OK
    SLEAVE  160
END_FUNCTION libp2p_shell_wait

/*
 * libp2p_shell_accept(context, events, listener): one new connection: its
 * socket waits in the accepting table, and ACCEPTED has it as the token.
 * Without a free place or event room, the socket waits in the backlog.
 * s1 context, s2 events, s3 listener, s4 the table, s5 its place, s6 socket.
 * Locals: the socket address at sp + FL, its length at sp + FL + 128.
 */
LOCAL_FUNCTION libp2p_shell_accept
    SENTER  160
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    addi    s4, s1, LIBP2P_SH_FIXED
    li      s5, 0
1:  li      t0, LIBP2P_SHELL_ACCEPTING
    bgeu    s5, t0, 9f
    slli    t1, s5, 3
    add     t1, s4, t1
    ld      t0, 0(t1)
    li      t2, NONE_SOCKET
    beq     t0, t2, 2f
    addi    s5, s5, 1
    j       1b
2:  mv      a0, s2
    call    libp2p_shell_room
    li      t0, LIBP2P_EV_ACCEPTED_SIZE
    bltu    a0, t0, 9f
    li      t0, 128
    sd      t0, (FL + 128)(sp)
    mv      a0, s3
    addi    a1, sp, FL
    addi    a2, sp, (FL + 128)
    OS_ACCEPT
    IF_ERROR_NEG 9f
    slli    t1, s5, 3
    add     t1, s4, t1
    sd      a0, 0(t1)
    mv      s6, a0
    li      a1, OS_IPPROTO_TCP
    li      a2, OS_TCP_NODELAY
    OS_SETSOCKOPT_ONE
    mv      a0, s2
    li      a1, LIBP2P_EVENT_ACCEPTED
    li      a2, LIBP2P_EV_ACCEPTED_SIZE
    call    libp2p_shell_event
    sd      s6, LIBP2P_EV_TOKEN(a0)
    addi    a1, a0, LIBP2P_EV_ACCEPTED_ADDR
    addi    a0, sp, FL
    call    libp2p_shell_address
9:  SLEAVE  160
END_FUNCTION libp2p_shell_accept

/* libp2p_shell_close(context) -> status: closes every socket. s1 context, s2 i, s3 table or entry. */
FUNCTION libp2p_shell_close
    SENTER  0
    mv      s1, a0
    li      s2, 0
1:  ld      t0, LIBP2P_SH_LISTENERS(s1)
    bgeu    s2, t0, 2f
    addi    t1, s1, LIBP2P_SH_LISTEN
    slli    t2, s2, 3
    add     t1, t1, t2
    ld      a0, 0(t1)
    OS_CLOSE
    addi    s2, s2, 1
    j       1b
2:  sd      zero, LIBP2P_SH_LISTENERS(s1)
    addi    s3, s1, LIBP2P_SH_FIXED
    li      s2, 0
3:  li      t0, LIBP2P_SHELL_ACCEPTING
    bgeu    s2, t0, 4f
    slli    t1, s2, 3
    add     t1, s3, t1
    ld      a0, 0(t1)
    li      t2, NONE_SOCKET
    beq     a0, t2, 31f
    OS_CLOSE
    slli    t1, s2, 3
    add     t1, s3, t1
    li      t2, NONE_SOCKET
    sd      t2, 0(t1)
31: addi    s2, s2, 1
    j       3b
4:  li      s2, 0
5:  ld      t0, LIBP2P_SH_CAPACITY(s1)
    bgeu    s2, t0, 6f
    ld      t1, LIBP2P_SH_ENTRIES(s1)
    add     t1, s1, t1
    ld      t2, LIBP2P_SH_STRIDE(s1)
    mul     s3, s2, t2
    add     s3, s3, t1
    ld      t0, LIBP2P_SE_STATE(s3)
    beqz    t0, 51f
    ld      a0, LIBP2P_SE_SOCKET(s3)
    OS_CLOSE
    li      t0, NONE_SOCKET
    sd      t0, LIBP2P_SE_SOCKET(s3)
    sd      zero, LIBP2P_SE_STATE(s3)
51: addi    s2, s2, 1
    j       5b
6:  OS_CLEANUP s1
    li      a0, LIBP2P_OK
    SLEAVE  0
END_FUNCTION libp2p_shell_close

/* libp2p_shell_poll_set(socket, events, index, array): one struct pollfd. A leaf. */
LOCAL_FUNCTION libp2p_shell_poll_set
    UNWIND_END_PROLOGUE
    slli    a2, a2, POLL_SHIFT
    add     a3, a3, a2
    sw      a0, 0(a3)
    sh      a1, 4(a3)
    sh      zero, 6(a3)
    ret
END_FUNCTION libp2p_shell_poll_set

/* libp2p_shell_poll_events(index, array) -> the revents of slot index. A leaf. */
LOCAL_FUNCTION libp2p_shell_poll_events
    UNWIND_END_PROLOGUE
    slli    a0, a0, POLL_SHIFT
    add     a1, a1, a0
    lhu     a0, 6(a1)
    ret
END_FUNCTION libp2p_shell_poll_events

/*
 * libp2p_shell_clock(tick) -> status: the monotonic time in ms and 32 random
 * bytes (clock_gettime and getrandom); LIBP2P_OS_ERROR when either fails.
 * s1 tick, s2 random bytes so far. Locals: the timespec at sp + FL.
 */
FUNCTION libp2p_shell_clock
    SENTER  16
    mv      s1, a0
    li      a0, OS_CLOCK_MONOTONIC
    addi    a1, sp, FL
    SYSCALL SYS_CLOCK_GETTIME
    IF_ERROR_NEG 8f
    ld      t0, FL(sp)
    ld      t1, (FL + 8)(sp)
    li      t2, 1000
    mul     t0, t0, t2
    li      t2, 1000000
    divu    t1, t1, t2
    add     t0, t0, t1
    sd      t0, LIBP2P_TICK_NOW(s1)
    li      s2, 0
1:  li      t0, 32
    bgeu    s2, t0, 2f
    addi    a0, s1, LIBP2P_TICK_ENTROPY
    add     a0, a0, s2
    li      a1, 32
    sub     a1, a1, s2
    li      a2, 0
    SYSCALL SYS_GETRANDOM
    IF_ERROR_NEG 8f
    add     s2, s2, a0
    j       1b
2:  li      a0, LIBP2P_OK
    j       9f
8:  li      a0, LIBP2P_OS_ERROR
9:  SLEAVE  16
END_FUNCTION libp2p_shell_clock
