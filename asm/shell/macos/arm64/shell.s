/*
 * asm-libp2p shell for macOS on ARM64: TCP sockets, the clock and random
 * bytes, through libSystem. Requirements: docs/reference/shell.md.
 * Layouts: include/libp2p.inc.
 *
 * The functions use AAPCS64 and call libSystem with the same convention.
 * Each OS macro leaves in x0 the result, or minus errno (from __error()).
 */
.set ISA_ARM64, 1
.include "libp2p.inc"
.include "platform.inc"

/* libSystem numbers: the macOS SDK headers. */
.set OS_AF_INET, 2                  /* sys/socket.h */
.set OS_AF_INET6, 30                /* sys/socket.h */
.set OS_SOCK_STREAM, 1              /* sys/socket.h */
.set OS_SOL_SOCKET, 0xFFFF          /* sys/socket.h */
.set OS_SO_LISTEN, 4                /* the option of a listener: SO_REUSEADDR, sys/socket.h */
.set OS_SO_ERROR, 0x1007            /* sys/socket.h */
.set OS_SO_NOSIGPIPE, 0x1022        /* sys/socket.h */
.set OS_MSG_DONTWAIT, 0x80          /* sys/socket.h */
.set OS_IPPROTO_TCP, 6              /* netinet/in.h */
.set OS_TCP_NODELAY, 1              /* netinet/tcp.h */
.set OS_IPPROTO_IPV6, 41            /* netinet/in.h */
.set OS_IPV6_V6ONLY, 27             /* netinet6/in6.h */
.set OS_POLLIN, 1                   /* sys/poll.h */
.set OS_POLLOUT, 4                  /* sys/poll.h */
.set OS_POLLERR, 8                  /* sys/poll.h */
.set OS_POLLHUP, 16                 /* sys/poll.h */
.set OS_EAGAIN, 35                  /* sys/errno.h */
.set OS_EINVAL, 22                  /* sys/errno.h */
.set OS_EINPROGRESS, 36             /* sys/errno.h */
.set OS_F_SETFD, 2                  /* sys/fcntl.h */
.set OS_F_SETFL, 4                  /* sys/fcntl.h */
.set OS_FD_CLOEXEC, 1               /* sys/fcntl.h */
.set OS_O_NONBLOCK, 4               /* sys/fcntl.h */
.set OS_CLOCK_MONOTONIC, 6          /* time.h */
.set POLL_STRIDE, 16                /* context bytes per poll entry: the largest of every OS (Windows) */
.set POLL_SHIFT, 3                  /* struct pollfd: 8 bytes, fd at 0, events at 4, revents at 6 */
.set NONE_SOCKET, -1

/* reg = a constant of up to 32 bits. */
.macro MOV32 reg, v
    movz    \reg, #((\v) & 0xFFFF)
    movk    \reg, #(((\v) >> 16) & 0xFFFF), lsl #16
.endm

/* x0 = the int result in w0, or minus errno when it is negative. */
.macro OS_RET_INT
    sxtw    x0, w0
    tbz     x0, #63, 1100f
    CALL_GLOBAL __error
    ldr     w0, [x0]
    neg     x0, x0
1100:
.endm

/* x0 = the ssize_t result, or minus errno when it is negative. */
.macro OS_RET_SIZE
    tbz     x0, #63, 1101f
    CALL_GLOBAL __error
    ldr     w0, [x0]
    neg     x0, x0
1101:
.endm

/* Branch to label when x0 is minus an error number (-4095 to -1). */
.macro IF_ERROR_NEG label
    cmn     x0, #4095
    b.hs    \label
.endm

/* Branch to label when the call would block. */
.macro IF_WOULDBLOCK label
    cmn     x0, #OS_EAGAIN
    b.eq    \label
.endm

/* Branch to label when a connect is in progress. */
.macro IF_INPROGRESS label
    cmn     x0, #OS_EINPROGRESS
    b.eq    \label
.endm

/* The length and family of a socket address of len bytes (sin_len, sin_family). */
.macro SET_FAMILY reg, base, len
    strb    \reg, [\base, #1]
    mov     w12, #\len
    strb    w12, [\base]
.endm

.macro GET_FAMILY reg, base
    ldrb    \reg, [\base, #1]
.endm

/* x0 = the status of starting the OS sockets: nothing to start. */
.macro OS_STARTUP context
    mov     x0, #LIBP2P_OK
.endm

.macro OS_CLEANUP context
.endm

/* x0 = a non-blocking TCP socket of family x0, or minus the error. */
.macro OS_SOCKET
    bl      libp2p_shell_socket
.endm

/* setsockopt(x0, x1, x2) to the int 1 (at sp + 248). */
.macro OS_SETSOCKOPT_ONE
    mov     w9, #1
    str     w9, [sp, #248]
    add     x3, sp, #248
    mov     w4, #4
    CALL_GLOBAL setsockopt
    OS_RET_INT
.endm

.macro OS_BIND
    CALL_GLOBAL bind
    OS_RET_INT
.endm

.macro OS_LISTEN
    CALL_GLOBAL listen
    OS_RET_INT
.endm

.macro OS_GETSOCKNAME
    CALL_GLOBAL getsockname
    OS_RET_INT
.endm

.macro OS_CONNECT
    CALL_GLOBAL connect
    OS_RET_INT
.endm

/* send(x0, x1, x2) without blocking; SO_NOSIGPIPE keeps SIGPIPE away. */
.macro OS_SEND
    mov     w3, #OS_MSG_DONTWAIT
    CALL_GLOBAL send
    OS_RET_SIZE
.endm

/* recv(x0, x1, x2) without blocking. */
.macro OS_RECV
    mov     w3, #OS_MSG_DONTWAIT
    CALL_GLOBAL recv
    OS_RET_SIZE
.endm

/* accept(x0, x1, x2): the new socket non-blocking. */
.macro OS_ACCEPT
    bl      libp2p_shell_accept_one
.endm

.macro OS_CLOSE
    CALL_GLOBAL close
    OS_RET_INT
.endm

/* x0 = the pending error of socket x0 (SO_ERROR), 0 when none. Uses sp + 232 and sp + 240. */
.macro OS_SOCKET_ERROR
    str     wzr, [sp, #240]
    mov     w9, #4
    str     w9, [sp, #232]
    mov     w1, #OS_SOL_SOCKET
    mov     w2, #OS_SO_ERROR
    add     x3, sp, #240
    add     x4, sp, #232
    CALL_GLOBAL getsockopt
    OS_RET_INT
    tbnz    x0, #63, 1000f
    ldr     w0, [sp, #240]
    b       1001f
1000: neg   x0, x0
1001:
.endm

/* poll(x0, x1, timeout x2 ms) -> ready count or minus the error. */
.macro OS_POLL
    mov     x9, #0x7FFFFFFF
    cmp     x2, x9
    csel    x2, x2, x9, lo
    CALL_GLOBAL poll
    OS_RET_INT
.endm

/* Frame: x29, x30, x19-x28, then locals. */
.macro SENTER locals
    stp     x29, x30, [sp, #-(96 + \locals)]!
    UNWIND_SAVE_FPLR_X (96 + \locals)
    mov     x29, sp
    UNWIND_SET_FP
    stp     x19, x20, [sp, #16]
    UNWIND_SAVE_REGP x19, x20, 16, (96 + \locals)
    stp     x21, x22, [sp, #32]
    UNWIND_SAVE_REGP x21, x22, 32, (96 + \locals)
    stp     x23, x24, [sp, #48]
    UNWIND_SAVE_REGP x23, x24, 48, (96 + \locals)
    stp     x25, x26, [sp, #64]
    UNWIND_SAVE_REGP x25, x26, 64, (96 + \locals)
    stp     x27, x28, [sp, #80]
    UNWIND_SAVE_REGP x27, x28, 80, (96 + \locals)
    UNWIND_END_PROLOGUE
.endm

.macro SLEAVE locals
    UNWIND_BEGIN_EPILOGUE
    ldp     x27, x28, [sp, #80]
    UNWIND_RESTORE_REGP x27, x28, 80
    ldp     x25, x26, [sp, #64]
    UNWIND_RESTORE_REGP x25, x26, 64
    ldp     x23, x24, [sp, #48]
    UNWIND_RESTORE_REGP x23, x24, 48
    ldp     x21, x22, [sp, #32]
    UNWIND_RESTORE_REGP x21, x22, 32
    ldp     x19, x20, [sp, #16]
    UNWIND_RESTORE_REGP x19, x20, 16
    ldp     x29, x30, [sp], #(96 + \locals)
    UNWIND_RESTORE_FPLR_X (96 + \locals)
    UNWIND_END_EPILOGUE
    ret
.endm

/* ---------------------------------------------------------------- libSystem */

/*
 * libp2p_shell_fcntl(socket, command, value) -> the result, or minus errno.
 * Darwin passes the variadic third argument of fcntl on the stack.
 */
LOCAL_FUNCTION libp2p_shell_fcntl
    stp     x29, x30, [sp, #-16]!
    UNWIND_SAVE_FPLR_X 16
    mov     x29, sp
    UNWIND_SET_FP
    sub     sp, sp, #16
    UNWIND_ALLOC 16
    UNWIND_END_PROLOGUE
    str     x2, [sp]
    CALL_GLOBAL fcntl
    OS_RET_INT
    UNWIND_BEGIN_EPILOGUE
    add     sp, sp, #16
    UNWIND_FREE 16
    ldp     x29, x30, [sp], #16
    UNWIND_RESTORE_FPLR_X 16
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION libp2p_shell_fcntl

/*
 * libp2p_shell_prepare(socket) -> 0, or minus errno: the socket becomes
 * non-blocking and close-on-exec, without SIGPIPE.
 */
LOCAL_FUNCTION libp2p_shell_prepare
    SENTER  160
    mov     x19, x0
    mov     x1, #OS_F_SETFL
    mov     x2, #OS_O_NONBLOCK
    bl      libp2p_shell_fcntl
    IF_ERROR_NEG 9f
    mov     x0, x19
    mov     x1, #OS_F_SETFD
    mov     x2, #OS_FD_CLOEXEC
    bl      libp2p_shell_fcntl
    IF_ERROR_NEG 9f
    mov     x0, x19
    mov     w1, #OS_SOL_SOCKET
    MOV32   x2, OS_SO_NOSIGPIPE
    OS_SETSOCKOPT_ONE
    IF_ERROR_NEG 9f
    mov     x0, #0
9:  SLEAVE  160
END_FUNCTION libp2p_shell_prepare

/* libp2p_shell_socket(family) -> a prepared TCP socket, or minus errno. */
LOCAL_FUNCTION libp2p_shell_socket
    SENTER  0
    mov     w1, #OS_SOCK_STREAM
    mov     w2, #0
    CALL_GLOBAL socket
    OS_RET_INT
    IF_ERROR_NEG 9f
    mov     x19, x0
    bl      libp2p_shell_prepare
    IF_ERROR_NEG 8f
    mov     x0, x19
    b       9f
8:  mov     x20, x0
    mov     x0, x19
    CALL_GLOBAL close
    mov     x0, x20
9:  SLEAVE  0
END_FUNCTION libp2p_shell_socket

/* libp2p_shell_accept_one(listener, sockaddr, length) -> a prepared new socket, or minus errno. */
LOCAL_FUNCTION libp2p_shell_accept_one
    SENTER  0
    CALL_GLOBAL accept
    OS_RET_INT
    IF_ERROR_NEG 9f
    mov     x19, x0
    bl      libp2p_shell_prepare
    IF_ERROR_NEG 8f
    mov     x0, x19
    b       9f
8:  mov     x20, x0
    mov     x0, x19
    CALL_GLOBAL close
    mov     x0, x20
9:  SLEAVE  0
END_FUNCTION libp2p_shell_accept_one

/* ---------------------------------------------------------------- Addresses */

/* libp2p_shell_sockaddr(addr, sockaddr) -> its length: 16 for IPv4, 28 for IPv6. A leaf. */
LOCAL_FUNCTION libp2p_shell_sockaddr
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #LIBP2P_ADDR_FAMILY]
    ldr     x10, [x0, #LIBP2P_ADDR_PORT]
    rev16   w10, w10
    stp     xzr, xzr, [x1]
    stp     xzr, xzr, [x1, #16]
    cmp     x9, #6
    b.eq    1f
    mov     w11, #OS_AF_INET
    SET_FAMILY w11, x1, 16
    strh    w10, [x1, #2]
    ldr     w11, [x0, #LIBP2P_ADDR_IP]
    str     w11, [x1, #4]
    mov     x0, #16
    ret
1:  mov     w11, #OS_AF_INET6
    SET_FAMILY w11, x1, 28
    strh    w10, [x1, #2]
    ldp     x11, x12, [x0, #LIBP2P_ADDR_IP]
    stp     x11, x12, [x1, #8]
    mov     x0, #28
    ret
END_FUNCTION libp2p_shell_sockaddr

/* libp2p_shell_address(sockaddr, addr): an Address of an IPv4 or IPv6 socket address; an IPv4-mapped IPv6 address becomes IPv4. A leaf. */
LOCAL_FUNCTION libp2p_shell_address
    UNWIND_END_PROLOGUE
    stp     xzr, xzr, [x1]
    stp     xzr, xzr, [x1, #16]
    ldrh    w10, [x0, #2]
    rev16   w10, w10
    str     x10, [x1, #LIBP2P_ADDR_PORT]
    GET_FAMILY w9, x0
    cmp     w9, #OS_AF_INET
    b.ne    1f
    mov     x9, #4
    str     x9, [x1, #LIBP2P_ADDR_FAMILY]
    ldr     w11, [x0, #4]
    str     w11, [x1, #LIBP2P_ADDR_IP]
    ret
1:  ldp     x11, x12, [x0, #8]
    lsr     x13, x12, #32                   /* ::ffff:a.b.c.d */
    cbnz    x11, 2f
    and     x14, x12, #0xFFFFFFFF
    mov     x15, #0xFFFF0000
    cmp     x14, x15
    b.ne    2f
    mov     x9, #4
    str     x9, [x1, #LIBP2P_ADDR_FAMILY]
    str     w13, [x1, #LIBP2P_ADDR_IP]
    ret
2:  mov     x9, #6
    str     x9, [x1, #LIBP2P_ADDR_FAMILY]
    stp     x11, x12, [x1, #LIBP2P_ADDR_IP]
    ret
END_FUNCTION libp2p_shell_address

/* ---------------------------------------------------------------- Layout */

/*
 * libp2p_shell_layout(params, context or 0) -> x0 status, x1 the context
 * size. With a context, writes its fixed fields.
 */
LOCAL_FUNCTION libp2p_shell_layout
    UNWIND_END_PROLOGUE
    ldr     x2, [x0, #LIBP2P_SP_CAPACITY]
    ldr     x3, [x0, #LIBP2P_SP_BUFFER]
    cbz     x2, 8f
    mov     x9, #65536
    cmp     x2, x9
    b.hi    8f
    mov     x9, #4096
    cmp     x3, x9
    b.lo    8f
    mov     x9, #0x40000000
    cmp     x3, x9
    b.hi    8f
    add     x3, x3, #7
    and     x3, x3, #~7
    add     x4, x3, #LIBP2P_SE_FIXED        /* stride */
    mov     x5, #(LIBP2P_SH_FIXED + 8 * LIBP2P_SHELL_ACCEPTING)   /* poll array */
    add     x6, x2, #(LIBP2P_SH_MAX_LISTEN + LIBP2P_SHELL_ACCEPTING)
    mov     x9, #POLL_STRIDE
    madd    x6, x6, x9, x5                  /* entries */
    madd    x7, x2, x4, x6                  /* total */
    cbz     x1, 1f
    str     x2, [x1, #LIBP2P_SH_CAPACITY]
    str     x3, [x1, #LIBP2P_SH_BUFFER]
    str     x4, [x1, #LIBP2P_SH_STRIDE]
    str     x5, [x1, #LIBP2P_SH_POLL]
    str     x6, [x1, #LIBP2P_SH_ENTRIES]
1:  mov     x0, #LIBP2P_OK
    mov     x1, x7
    ret
8:  mov     x0, #LIBP2P_INVALID_CONFIG
    mov     x1, #0
    ret
END_FUNCTION libp2p_shell_layout

/* libp2p_shell_size(params, size) -> status: the bytes of a ShellContext for the params. */
FUNCTION libp2p_shell_size
    SENTER  0
    mov     x19, x1
    mov     x1, #0
    bl      libp2p_shell_layout
    cbnz    x0, 9f
    str     x1, [x19]
9:  SLEAVE  0
END_FUNCTION libp2p_shell_size

/*
 * libp2p_shell_init(params, context) -> status: a context with no sockets.
 * The size field of the context gives its bytes.
 */
FUNCTION libp2p_shell_init
    SENTER  0
    mov     x19, x0
    mov     x20, x1
    mov     x1, #0
    bl      libp2p_shell_layout
    cbnz    x0, 9f
    mov     x0, #LIBP2P_BUFFER_TOO_SMALL
    ldr     x9, [x20, #LIBP2P_SH_SIZE]
    cmp     x9, x1
    b.lo    9f
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_shell_layout
    mov     x9, #NONE_SOCKET
    str     xzr, [x20, #LIBP2P_SH_LISTENERS]
    add     x10, x20, #LIBP2P_SH_LISTEN
    mov     x11, #LIBP2P_SH_MAX_LISTEN
1:  str     x9, [x10], #8
    subs    x11, x11, #1
    b.ne    1b
    add     x10, x20, #LIBP2P_SH_FIXED      /* accepted sockets */
    mov     x11, #LIBP2P_SHELL_ACCEPTING
2:  str     x9, [x10], #8
    subs    x11, x11, #1
    b.ne    2b
    ldr     x10, [x20, #LIBP2P_SH_ENTRIES]
    add     x10, x20, x10
    ldr     x11, [x20, #LIBP2P_SH_CAPACITY]
    ldr     x12, [x20, #LIBP2P_SH_STRIDE]
3:  str     x9, [x10, #LIBP2P_SE_SOCKET]
    str     xzr, [x10, #LIBP2P_SE_STATE]
    str     xzr, [x10, #LIBP2P_SE_LEN]
    add     x10, x10, x12
    subs    x11, x11, #1
    b.ne    3b
    OS_STARTUP x20                  /* x0 = status */
9:  SLEAVE  0
END_FUNCTION libp2p_shell_init

/* libp2p_shell_entry(context, handle) -> the entry of the connection slot of the handle, or 0 past the capacity. A leaf. */
LOCAL_FUNCTION libp2p_shell_entry
    UNWIND_END_PROLOGUE
    mov     w1, w1
    ldr     x2, [x0, #LIBP2P_SH_CAPACITY]
    cmp     x1, x2
    b.hs    8f
    ldr     x2, [x0, #LIBP2P_SH_ENTRIES]
    add     x2, x0, x2
    ldr     x3, [x0, #LIBP2P_SH_STRIDE]
    madd    x0, x1, x3, x2
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_shell_entry

/* ---------------------------------------------------------------- Event list */

/*
 * libp2p_shell_event(events, kind, size) -> the new event, zeroed, with
 * size and kind set; 0 when the list has no room.
 */
LOCAL_FUNCTION libp2p_shell_event
    SENTER  0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x19, #LIBP2P_BL_SIZE]
    ldr     x10, [x19, #LIBP2P_BL_OFFSET]
    ldr     x11, [x19, #LIBP2P_BL_COUNT]
    sub     x9, x9, x10
    sub     x9, x9, x11
    mov     x0, #0
    cmp     x9, x21
    b.lo    9f
    add     x22, x19, x10
    add     x22, x22, x11
    add     x11, x11, x21
    str     x11, [x19, #LIBP2P_BL_COUNT]
    mov     x0, #0
1:  cmp     x0, x21
    b.hs    2f
    str     xzr, [x22, x0]
    add     x0, x0, #8
    b       1b
2:  str     x21, [x22, #LIBP2P_EV_SIZE]
    str     x20, [x22, #LIBP2P_EV_KIND]
    mov     x0, x22
9:  SLEAVE  0
END_FUNCTION libp2p_shell_event

/* libp2p_shell_room(events) -> the bytes left in the event list. A leaf. */
LOCAL_FUNCTION libp2p_shell_room
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #LIBP2P_BL_SIZE]
    ldr     x10, [x0, #LIBP2P_BL_OFFSET]
    ldr     x11, [x0, #LIBP2P_BL_COUNT]
    sub     x9, x9, x10
    subs    x0, x9, x11
    csel    x0, xzr, x0, lo
    ret
END_FUNCTION libp2p_shell_room

/* libp2p_shell_conn_event(events, kind, handle, value): an event with a connection handle and a value (error or count). */
LOCAL_FUNCTION libp2p_shell_conn_event
    SENTER  0
    mov     x19, x2
    mov     x20, x3
    mov     x2, #LIBP2P_EV_CONN_SIZE
    bl      libp2p_shell_event
    cbz     x0, 9f
    str     x19, [x0, #LIBP2P_EV_CONN]
    str     x20, [x0, #LIBP2P_EV_ERROR]
9:  SLEAVE  0
END_FUNCTION libp2p_shell_conn_event

/* ---------------------------------------------------------------- Sockets */

/*
 * libp2p_shell_drop(entry, events, error): closes the socket of a
 * connection and gives CLOSED with the error.
 */
LOCAL_FUNCTION libp2p_shell_drop
    SENTER  0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x0, [x19, #LIBP2P_SE_SOCKET]
    OS_CLOSE
    mov     x9, #NONE_SOCKET
    str     x9, [x19, #LIBP2P_SE_SOCKET]
    str     xzr, [x19, #LIBP2P_SE_STATE]
    str     xzr, [x19, #LIBP2P_SE_LEN]
    mov     x0, x20
    mov     x1, #LIBP2P_EVENT_CLOSED
    ldr     x2, [x19, #LIBP2P_SE_HANDLE]
    mov     x3, x21
    bl      libp2p_shell_conn_event
    SLEAVE  0
END_FUNCTION libp2p_shell_drop

/*
 * libp2p_shell_flush(entry, events): writes what the send buffer holds,
 * until the socket would block; SENT with the bytes written; an error
 * closes the connection (CLOSED).
 */
LOCAL_FUNCTION libp2p_shell_flush
    SENTER  0
    mov     x19, x0
    mov     x20, x1
    mov     x21, #0                         /* written */
1:  ldr     x22, [x19, #LIBP2P_SE_LEN]
    cmp     x21, x22
    b.hs    3f
    ldr     x0, [x19, #LIBP2P_SE_SOCKET]
    add     x1, x19, #LIBP2P_SE_DATA
    add     x1, x1, x21
    sub     x2, x22, x21
    OS_SEND
    IF_WOULDBLOCK 3f
    IF_ERROR_NEG 8f
    add     x21, x21, x0
    b       1b
3:  cbz     x21, 9f
    add     x0, x19, #LIBP2P_SE_DATA        /* keep the rest at the front */
    add     x1, x0, x21
    sub     x2, x22, x21
    str     x2, [x19, #LIBP2P_SE_LEN]
    bl      libp2p_shell_move
    mov     x0, x20
    mov     x1, #LIBP2P_EVENT_SENT
    ldr     x2, [x19, #LIBP2P_SE_HANDLE]
    mov     x3, x21
    bl      libp2p_shell_conn_event
    b       9f
8:  neg     x2, x0
    cbz     x21, 81f
    mov     x23, x2
    mov     x0, x20
    mov     x1, #LIBP2P_EVENT_SENT
    ldr     x2, [x19, #LIBP2P_SE_HANDLE]
    mov     x3, x21
    bl      libp2p_shell_conn_event
    mov     x2, x23
81: mov     x0, x19
    mov     x1, x20
    bl      libp2p_shell_drop
9:  SLEAVE  0
END_FUNCTION libp2p_shell_flush

/* libp2p_shell_move(dst, src, n): copies n bytes forward; dst is below src. A leaf. */
LOCAL_FUNCTION libp2p_shell_move
    UNWIND_END_PROLOGUE
1:  cbz     x2, 2f
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     x2, x2, #1
    b       1b
2:  ret
END_FUNCTION libp2p_shell_move

/*
 * libp2p_shell_listen(context, addr, result) -> status: a listening TCP
 * socket bound to the address (port 0: any); result gets 0 and the bound
 * address, or the OS error.
 */
FUNCTION libp2p_shell_listen
    SENTER  160
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, x21
    mov     x9, #0
1:  str     xzr, [x21, x9]
    add     x9, x9, #8
    cmp     x9, #LIBP2P_LR_SIZE
    b.lo    1b
    ldr     x9, [x19, #LIBP2P_SH_LISTENERS]
    cmp     x9, #LIBP2P_SH_MAX_LISTEN
    mov     x23, #OS_EINVAL
    b.hs    80f
    ldr     x9, [x20, #LIBP2P_ADDR_FAMILY]
    cmp     x9, #6
    mov     x0, #OS_AF_INET
    mov     x10, #OS_AF_INET6
    csel    x0, x10, x0, eq
    mov     x22, x0
    OS_SOCKET
    IF_ERROR_NEG 81f
    mov     x24, x0                         /* the socket */
    mov     x0, x24
    mov     x1, #OS_SOL_SOCKET
    mov     x2, #OS_SO_LISTEN
    OS_SETSOCKOPT_ONE
    cmp     x22, #OS_AF_INET6
    b.ne    2f
    mov     x0, x24
    mov     x1, #OS_IPPROTO_IPV6
    mov     x2, #OS_IPV6_V6ONLY
    OS_SETSOCKOPT_ONE
2:  mov     x0, x20
    add     x1, sp, #96
    bl      libp2p_shell_sockaddr
    mov     x2, x0
    mov     x0, x24
    add     x1, sp, #96
    OS_BIND
    IF_ERROR_NEG 82f
    mov     x0, x24
    mov     x1, #1024
    OS_LISTEN
    IF_ERROR_NEG 82f
    mov     x9, #128
    str     x9, [sp, #224]
    mov     x0, x24
    add     x1, sp, #96
    add     x2, sp, #224
    OS_GETSOCKNAME
    IF_ERROR_NEG 82f
    add     x0, sp, #96
    add     x1, x21, #LIBP2P_LR_ADDR
    bl      libp2p_shell_address
    ldr     x9, [x19, #LIBP2P_SH_LISTENERS]
    add     x10, x19, #LIBP2P_SH_LISTEN
    str     x24, [x10, x9, lsl #3]
    add     x9, x9, #1
    str     x9, [x19, #LIBP2P_SH_LISTENERS]
    b       90f
82: neg     x23, x0
    mov     x0, x24
    OS_CLOSE
    b       80f
81: neg     x23, x0
80: str     x23, [x21, #LIBP2P_LR_ERROR]
90: mov     x0, #LIBP2P_OK
    SLEAVE  160
END_FUNCTION libp2p_shell_listen

/*
 * libp2p_shell_perform(context, actions, events) -> status: does the shell
 * actions of a step in order: DIAL, ADOPT, REFUSE, SEND and CLOSE; results
 * known at once go to events (CONNECTED, DIAL_FAILED, SENT, CLOSED). Other
 * kinds are the application's.
 * x19 context, x20 events, x21 action, x22 end.
 */
FUNCTION libp2p_shell_perform
    SENTER  160
    mov     x19, x0
    mov     x20, x2
    ldr     x9, [x1, #LIBP2P_BL_OFFSET]
    add     x21, x1, x9
    ldr     x9, [x1, #LIBP2P_BL_COUNT]
    add     x22, x21, x9
1:  cmp     x21, x22
    b.hs    90f
    ldr     x9, [x21, #LIBP2P_ACT_KIND]
    cmp     x9, #LIBP2P_ACTION_DIAL
    b.ne    20f

    /* DIAL */
    mov     x0, x19
    ldr     x1, [x21, #LIBP2P_ACT_CONN]
    bl      libp2p_shell_entry
    cbz     x0, 80f
    mov     x23, x0
    ldr     x9, [x23, #LIBP2P_SE_STATE]
    cbz     x9, 11f
    ldr     x0, [x23, #LIBP2P_SE_SOCKET]    /* a stale socket in the slot */
    OS_CLOSE
11: ldr     x9, [x21, #LIBP2P_ACT_CONN]
    str     x9, [x23, #LIBP2P_SE_HANDLE]
    str     xzr, [x23, #LIBP2P_SE_LEN]
    str     xzr, [x23, #LIBP2P_SE_STATE]
    mov     x9, #NONE_SOCKET
    str     x9, [x23, #LIBP2P_SE_SOCKET]
    ldr     x9, [x21, #(LIBP2P_ACT_DIAL_ADDR + LIBP2P_ADDR_FAMILY)]
    cmp     x9, #6
    mov     x0, #OS_AF_INET
    mov     x10, #OS_AF_INET6
    csel    x0, x10, x0, eq
    OS_SOCKET
    IF_ERROR_NEG 15f
    str     x0, [x23, #LIBP2P_SE_SOCKET]
    mov     x0, x0
    mov     x1, #OS_IPPROTO_TCP
    mov     x2, #OS_TCP_NODELAY
    OS_SETSOCKOPT_ONE
    add     x0, x21, #LIBP2P_ACT_DIAL_ADDR
    add     x1, sp, #96
    bl      libp2p_shell_sockaddr
    mov     x2, x0
    ldr     x0, [x23, #LIBP2P_SE_SOCKET]
    add     x1, sp, #96
    OS_CONNECT
    IF_INPROGRESS 13f
    IF_ERROR_NEG 14f
    mov     x9, #2                          /* connected at once */
    str     x9, [x23, #LIBP2P_SE_STATE]
    mov     x0, x20
    mov     x1, #LIBP2P_EVENT_CONNECTED
    ldr     x2, [x23, #LIBP2P_SE_HANDLE]
    mov     x3, #0
    bl      libp2p_shell_conn_event
    b       80f
13: mov     x9, #1
    str     x9, [x23, #LIBP2P_SE_STATE]
    b       80f
14: neg     x24, x0
    ldr     x0, [x23, #LIBP2P_SE_SOCKET]
    OS_CLOSE
    mov     x9, #NONE_SOCKET
    str     x9, [x23, #LIBP2P_SE_SOCKET]
    mov     x0, x24
    neg     x0, x0
15: neg     x3, x0
    mov     x0, x20
    mov     x1, #LIBP2P_EVENT_DIAL_FAILED
    ldr     x2, [x21, #LIBP2P_ACT_CONN]
    bl      libp2p_shell_conn_event
    b       80f

    /* ADOPT and REFUSE: the accepted socket of the token. */
20: cmp     x9, #LIBP2P_ACTION_ADOPT
    b.eq    21f
    cmp     x9, #LIBP2P_ACTION_REFUSE
    b.ne    30f
21: ldr     x10, [x21, #LIBP2P_ACT_TOKEN]
    add     x11, x19, #LIBP2P_SH_FIXED
    mov     x12, #0
22: cmp     x12, #LIBP2P_SHELL_ACCEPTING
    b.hs    80f
    ldr     x13, [x11, x12, lsl #3]
    cmp     x13, x10
    b.eq    23f
    add     x12, x12, #1
    b       22b
23: mov     x14, #NONE_SOCKET
    str     x14, [x11, x12, lsl #3]
    mov     x24, x13
    cmp     x9, #LIBP2P_ACTION_REFUSE
    b.eq    24f
    mov     x0, x19
    ldr     x1, [x21, #LIBP2P_ACT_ADOPT_CONN]
    bl      libp2p_shell_entry
    cbz     x0, 24f
    mov     x23, x0
    ldr     x9, [x23, #LIBP2P_SE_STATE]
    cbz     x9, 25f
    ldr     x0, [x23, #LIBP2P_SE_SOCKET]
    OS_CLOSE
25: str     x24, [x23, #LIBP2P_SE_SOCKET]
    ldr     x9, [x21, #LIBP2P_ACT_ADOPT_CONN]
    str     x9, [x23, #LIBP2P_SE_HANDLE]
    mov     x9, #2
    str     x9, [x23, #LIBP2P_SE_STATE]
    str     xzr, [x23, #LIBP2P_SE_LEN]
    b       80f
24: mov     x0, x24
    OS_CLOSE
    b       80f

    /* SEND: into the send buffer, then write what the socket takes. */
30: cmp     x9, #LIBP2P_ACTION_SEND
    b.ne    40f
    mov     x0, x19
    ldr     x1, [x21, #LIBP2P_ACT_CONN]
    bl      libp2p_shell_entry
    cbz     x0, 80f
    mov     x23, x0
    ldr     x9, [x23, #LIBP2P_SE_STATE]
    cmp     x9, #2
    b.ne    80f
    ldr     x9, [x23, #LIBP2P_SE_HANDLE]
    ldr     x10, [x21, #LIBP2P_ACT_CONN]
    cmp     x9, x10
    b.ne    80f
    ldr     x24, [x21, #LIBP2P_ACT_SEND_COUNT]
    ldr     x9, [x23, #LIBP2P_SE_LEN]
    ldr     x10, [x19, #LIBP2P_SH_BUFFER]
    sub     x10, x10, x9
    cmp     x24, x10
    b.ls    31f
    mov     x0, x23                         /* more than the buffer holds: the connection ends */
    mov     x1, x20
    mov     x2, #OS_EINVAL
    bl      libp2p_shell_drop
    b       80f
31: add     x0, x23, #LIBP2P_SE_DATA
    add     x0, x0, x9
    add     x1, x21, #LIBP2P_ACT_SEND_DATA
    mov     x2, x24
    bl      libp2p_shell_move_any
    ldr     x9, [x23, #LIBP2P_SE_LEN]
    add     x9, x9, x24
    str     x9, [x23, #LIBP2P_SE_LEN]
    mov     x0, x23
    mov     x1, x20
    bl      libp2p_shell_flush
    b       80f

    /* CLOSE */
40: cmp     x9, #LIBP2P_ACTION_CLOSE
    b.ne    80f
    mov     x0, x19
    ldr     x1, [x21, #LIBP2P_ACT_CONN]
    bl      libp2p_shell_entry
    cbz     x0, 80f
    mov     x23, x0
    ldr     x9, [x23, #LIBP2P_SE_STATE]
    cbz     x9, 41f
    ldr     x9, [x23, #LIBP2P_SE_HANDLE]
    ldr     x10, [x21, #LIBP2P_ACT_CONN]
    cmp     x9, x10
    b.ne    41f
    mov     x0, x23
    mov     x1, x20
    mov     x2, #0
    bl      libp2p_shell_drop
    b       80f
41: mov     x0, x20                         /* no socket: CLOSED all the same */
    mov     x1, #LIBP2P_EVENT_CLOSED
    ldr     x2, [x21, #LIBP2P_ACT_CONN]
    mov     x3, #0
    bl      libp2p_shell_conn_event
80: ldr     x9, [x21, #LIBP2P_ACT_SIZE]
    add     x21, x21, x9
    b       1b
90: mov     x0, #LIBP2P_OK
    SLEAVE  160
END_FUNCTION libp2p_shell_perform

/* libp2p_shell_move_any(dst, src, n): copies n bytes of regions that do not overlap, 8 at a time. A leaf. */
LOCAL_FUNCTION libp2p_shell_move_any
    UNWIND_END_PROLOGUE
1:  cmp     x2, #8
    b.lo    2f
    ldr     x3, [x1], #8
    str     x3, [x0], #8
    sub     x2, x2, #8
    b       1b
2:  cbz     x2, 3f
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     x2, x2, #1
    b       2b
3:  ret
END_FUNCTION libp2p_shell_move_any

/*
 * libp2p_shell_wait(context, timeout, events) -> status: waits up to
 * timeout ms (a u64) for socket activity, then gives events: ACCEPTED for
 * new connections (up to 16 waiting for ADOPT), CONNECTED or DIAL_FAILED
 * when a dial ends, SENT as buffered bytes go out, RECEIVED with what a
 * socket holds (at most 65536 bytes, while the event list has room), and
 * CLOSED when a socket ends.
 * x19 context, x20 events, x21 poll array, x22 poll count, x23 i, x24 entry,
 * x25 kind of the poll slot.
 */
FUNCTION libp2p_shell_wait
    SENTER  160
    mov     x19, x0
    mov     x20, x2
    ldr     x26, [x1]                       /* timeout */
    ldr     x21, [x19, #LIBP2P_SH_POLL]
    add     x21, x19, x21
    mov     x22, #0
    mov     x23, #0                         /* listeners */
1:  ldr     x9, [x19, #LIBP2P_SH_LISTENERS]
    cmp     x23, x9
    b.hs    2f
    add     x10, x19, #LIBP2P_SH_LISTEN
    ldr     x0, [x10, x23, lsl #3]
    mov     x1, #OS_POLLIN
    mov     x2, x22
    mov     x3, x21
    bl      libp2p_shell_poll_set
    add     x22, x22, #1
    add     x23, x23, #1
    b       1b
2:  mov     x23, #0                         /* connections */
3:  ldr     x9, [x19, #LIBP2P_SH_CAPACITY]
    cmp     x23, x9
    b.hs    5f
    ldr     x10, [x19, #LIBP2P_SH_ENTRIES]
    add     x10, x19, x10
    ldr     x11, [x19, #LIBP2P_SH_STRIDE]
    madd    x24, x23, x11, x10
    ldr     x9, [x24, #LIBP2P_SE_STATE]
    mov     x1, #NONE_SOCKET               /* a free slot polls no socket */
    mov     x0, x1
    mov     x1, #0
    cbz     x9, 4f
    ldr     x0, [x24, #LIBP2P_SE_SOCKET]
    mov     x1, #OS_POLLOUT
    cmp     x9, #1
    b.eq    4f
    mov     x1, #OS_POLLIN
    ldr     x10, [x24, #LIBP2P_SE_LEN]
    cbz     x10, 4f
    orr     x1, x1, #OS_POLLOUT
4:  mov     x2, x22
    mov     x3, x21
    bl      libp2p_shell_poll_set
    add     x22, x22, #1
    add     x23, x23, #1
    b       3b
5:  mov     x0, x21
    mov     x1, x22
    mov     x2, x26
    OS_POLL
    IF_ERROR_NEG 90f
    cbz     x0, 90f

    /* Listeners: accept while there is room. */
    mov     x23, #0
6:  ldr     x9, [x19, #LIBP2P_SH_LISTENERS]
    cmp     x23, x9
    b.hs    7f
    mov     x0, x23
    mov     x1, x21
    bl      libp2p_shell_poll_events
    tst     x0, #OS_POLLIN
    b.eq    61f
    mov     x0, x19
    mov     x1, x20
    add     x9, x19, #LIBP2P_SH_LISTEN
    ldr     x2, [x9, x23, lsl #3]
    bl      libp2p_shell_accept
61: add     x23, x23, #1
    b       6b

    /* Connections. */
7:  ldr     x25, [x19, #LIBP2P_SH_LISTENERS]
    mov     x23, #0
8:  ldr     x9, [x19, #LIBP2P_SH_CAPACITY]
    cmp     x23, x9
    b.hs    90f
    ldr     x10, [x19, #LIBP2P_SH_ENTRIES]
    add     x10, x19, x10
    ldr     x11, [x19, #LIBP2P_SH_STRIDE]
    madd    x24, x23, x11, x10
    add     x0, x25, x23
    mov     x1, x21
    bl      libp2p_shell_poll_events
    mov     x26, x0
    cbz     x26, 89f
    ldr     x9, [x24, #LIBP2P_SE_STATE]
    cbz     x9, 89f
    cmp     x9, #1
    b.ne    81f
    ldr     x0, [x24, #LIBP2P_SE_SOCKET]    /* a dial ended */
    OS_SOCKET_ERROR
    cbnz    x0, 80f
    mov     x9, #2
    str     x9, [x24, #LIBP2P_SE_STATE]
    mov     x0, x20
    mov     x1, #LIBP2P_EVENT_CONNECTED
    ldr     x2, [x24, #LIBP2P_SE_HANDLE]
    mov     x3, #0
    bl      libp2p_shell_conn_event
    b       89f
80: mov     x27, x0
    ldr     x0, [x24, #LIBP2P_SE_SOCKET]
    OS_CLOSE
    mov     x9, #NONE_SOCKET
    str     x9, [x24, #LIBP2P_SE_SOCKET]
    str     xzr, [x24, #LIBP2P_SE_STATE]
    mov     x0, x20
    mov     x1, #LIBP2P_EVENT_DIAL_FAILED
    ldr     x2, [x24, #LIBP2P_SE_HANDLE]
    mov     x3, x27
    bl      libp2p_shell_conn_event
    b       89f
81: tst     x26, #OS_POLLOUT
    b.eq    82f
    mov     x0, x24
    mov     x1, x20
    bl      libp2p_shell_flush
    ldr     x9, [x24, #LIBP2P_SE_STATE]
    cbz     x9, 89f
82: mov     x9, #(OS_POLLIN | OS_POLLHUP | OS_POLLERR)
    tst     x26, x9
    b.eq    89f
    mov     x0, x20                         /* read into a RECEIVED event */
    bl      libp2p_shell_room
    subs    x27, x0, #(LIBP2P_EV_DATA + 8)
    b.ls    89f
    mov     x9, #LIBP2P_RECEIVE_MAX
    cmp     x27, x9
    csel    x27, x27, x9, lo
    ldr     x9, [x20, #LIBP2P_BL_OFFSET]
    ldr     x10, [x20, #LIBP2P_BL_COUNT]
    add     x28, x20, x9
    add     x28, x28, x10                   /* the event, not yet in the list */
    ldr     x0, [x24, #LIBP2P_SE_SOCKET]
    add     x1, x28, #LIBP2P_EV_DATA
    mov     x2, x27
    OS_RECV
    IF_WOULDBLOCK 89f
    IF_ERROR_NEG 83f
    cbz     x0, 84f
    mov     x9, x0
    add     x10, x9, #(LIBP2P_EV_DATA + 7)
    and     x10, x10, #~7
    str     x10, [x28, #LIBP2P_EV_SIZE]
    mov     x11, #LIBP2P_EVENT_RECEIVED
    str     x11, [x28, #LIBP2P_EV_KIND]
    ldr     x11, [x24, #LIBP2P_SE_HANDLE]
    str     x11, [x28, #LIBP2P_EV_CONN]
    str     x9, [x28, #LIBP2P_EV_COUNT]
    ldr     x11, [x20, #LIBP2P_BL_COUNT]
    add     x11, x11, x10
    str     x11, [x20, #LIBP2P_BL_COUNT]
    b       89f
83: neg     x2, x0
    b       85f
84: mov     x2, #0                          /* the peer closed */
85: mov     x0, x24
    mov     x1, x20
    bl      libp2p_shell_drop
89: add     x23, x23, #1
    b       8b
90: mov     x0, #LIBP2P_OK
    SLEAVE  160
END_FUNCTION libp2p_shell_wait

/*
 * libp2p_shell_accept(context, events, listener): one new connection: its
 * socket waits in the accepting table, and ACCEPTED has it as the token.
 * Without a free place or event room, the socket waits in the backlog.
 */
LOCAL_FUNCTION libp2p_shell_accept
    SENTER  160
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    add     x22, x19, #LIBP2P_SH_FIXED
    mov     x23, #0
1:  cmp     x23, #LIBP2P_SHELL_ACCEPTING
    b.hs    9f
    ldr     x9, [x22, x23, lsl #3]
    cmn     x9, #1
    b.eq    2f
    add     x23, x23, #1
    b       1b
2:  mov     x0, x20
    bl      libp2p_shell_room
    cmp     x0, #LIBP2P_EV_ACCEPTED_SIZE
    b.lo    9f
    mov     x9, #128
    str     x9, [sp, #224]
    mov     x0, x21
    add     x1, sp, #96
    add     x2, sp, #224
    OS_ACCEPT
    IF_ERROR_NEG 9f
    str     x0, [x22, x23, lsl #3]
    mov     x24, x0
    mov     x1, #OS_IPPROTO_TCP
    mov     x2, #OS_TCP_NODELAY
    OS_SETSOCKOPT_ONE
    mov     x0, x20
    mov     x1, #LIBP2P_EVENT_ACCEPTED
    mov     x2, #LIBP2P_EV_ACCEPTED_SIZE
    bl      libp2p_shell_event
    str     x24, [x0, #LIBP2P_EV_TOKEN]
    add     x1, x0, #LIBP2P_EV_ACCEPTED_ADDR
    add     x0, sp, #96
    bl      libp2p_shell_address
9:  SLEAVE  160
END_FUNCTION libp2p_shell_accept

/* libp2p_shell_close(context) -> status: closes every socket. */
FUNCTION libp2p_shell_close
    SENTER  0
    mov     x19, x0
    mov     x20, #0
1:  ldr     x9, [x19, #LIBP2P_SH_LISTENERS]
    cmp     x20, x9
    b.hs    2f
    add     x10, x19, #LIBP2P_SH_LISTEN
    ldr     x0, [x10, x20, lsl #3]
    OS_CLOSE
    add     x20, x20, #1
    b       1b
2:  str     xzr, [x19, #LIBP2P_SH_LISTENERS]
    add     x21, x19, #LIBP2P_SH_FIXED
    mov     x20, #0
3:  cmp     x20, #LIBP2P_SHELL_ACCEPTING
    b.hs    4f
    ldr     x0, [x21, x20, lsl #3]
    cmn     x0, #1
    b.eq    31f
    OS_CLOSE
    mov     x9, #NONE_SOCKET
    str     x9, [x21, x20, lsl #3]
31: add     x20, x20, #1
    b       3b
4:  mov     x20, #0
5:  ldr     x9, [x19, #LIBP2P_SH_CAPACITY]
    cmp     x20, x9
    b.hs    6f
    ldr     x10, [x19, #LIBP2P_SH_ENTRIES]
    add     x10, x19, x10
    ldr     x11, [x19, #LIBP2P_SH_STRIDE]
    madd    x21, x20, x11, x10
    ldr     x9, [x21, #LIBP2P_SE_STATE]
    cbz     x9, 51f
    ldr     x0, [x21, #LIBP2P_SE_SOCKET]
    OS_CLOSE
    mov     x9, #NONE_SOCKET
    str     x9, [x21, #LIBP2P_SE_SOCKET]
    str     xzr, [x21, #LIBP2P_SE_STATE]
51: add     x20, x20, #1
    b       5b
6:  OS_CLEANUP x19
    mov     x0, #LIBP2P_OK
    SLEAVE  0
END_FUNCTION libp2p_shell_close

/* libp2p_shell_poll_set(socket, events, index, array): one struct pollfd. A leaf. */
LOCAL_FUNCTION libp2p_shell_poll_set
    UNWIND_END_PROLOGUE
    add     x3, x3, x2, lsl #POLL_SHIFT
    str     w0, [x3]
    strh    w1, [x3, #4]
    strh    wzr, [x3, #6]
    ret
END_FUNCTION libp2p_shell_poll_set

/* libp2p_shell_poll_events(index, array) -> the revents of slot index. A leaf. */
LOCAL_FUNCTION libp2p_shell_poll_events
    UNWIND_END_PROLOGUE
    add     x1, x1, x0, lsl #POLL_SHIFT
    ldrh    w0, [x1, #6]
    ret
END_FUNCTION libp2p_shell_poll_events

/*
 * libp2p_shell_clock(tick) -> status: the monotonic time in ms
 * (clock_gettime_nsec_np) and 32 random bytes (getentropy); LIBP2P_OS_ERROR
 * when either fails.
 */
FUNCTION libp2p_shell_clock
    SENTER  0
    mov     x19, x0
    mov     x20, #LIBP2P_OS_ERROR
    mov     w0, #OS_CLOCK_MONOTONIC
    CALL_GLOBAL clock_gettime_nsec_np
    cbz     x0, 9f
    MOV32   x9, 1000000
    udiv    x0, x0, x9
    str     x0, [x19, #LIBP2P_TICK_NOW]
    add     x0, x19, #LIBP2P_TICK_ENTROPY
    mov     x1, #32
    CALL_GLOBAL getentropy
    cbnz    w0, 9f
    mov     x20, #LIBP2P_OK
9:  mov     x0, x20
    SLEAVE  0
END_FUNCTION libp2p_shell_clock
