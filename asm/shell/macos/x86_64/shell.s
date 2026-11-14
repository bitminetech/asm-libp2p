/*
 * asm-libp2p shell for macOS on x86-64: TCP sockets, the clock and random
 * bytes, through libSystem. AT&T syntax.
 * Requirements: docs/reference/shell.md. Layouts: include/libp2p.inc.
 *
 * The functions use the System V AMD64 psABI like the core, and call
 * libSystem with it. Each OS macro leaves in rax the result, or minus errno
 * (from __error()), and may change rcx, rdx, rsi, rdi, r8-r11.
 *
 * Constants in macros are written $(n): in a macro without named
 * parameters, the Mach-O assembler reads $0 to $9 as positional arguments.
 */
.set ISA_X86_64, 1
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
.set NONE_SOCKET, -1

/* rax = the int result in eax, or minus errno when it is negative. */
.macro OS_RET_INT
    movslq  %eax, %rax
    test    %rax, %rax
    jns     1100f
    CALL_GLOBAL __error
    movslq  (%rax), %rax
    neg     %rax
1100:
.endm

/* rax = the ssize_t result, or minus errno when it is negative. */
.macro OS_RET_SIZE
    test    %rax, %rax
    jns     1101f
    CALL_GLOBAL __error
    movslq  (%rax), %rax
    neg     %rax
1101:
.endm

/* Branch to label when rax is minus an error number (-4095 to -1). */
.macro IF_ERROR_NEG label
    cmp     $-4095, %rax
    jae     \label
.endm

/* Branch to label when the call would block. */
.macro IF_WOULDBLOCK label
    cmp     $-OS_EAGAIN, %rax
    je      \label
.endm

/* Branch to label when a connect is in progress. */
.macro IF_INPROGRESS label
    cmp     $-OS_EINPROGRESS, %rax
    je      \label
.endm

/* The length and family of a socket address of len bytes (sin_len, sin_family). */
.macro SET_FAMILY family, base, len
    movb    $\len, (\base)
    movb    $\family, 1(\base)
.endm

/* reg = the family of the socket address at base. */
.macro GET_FAMILY reg, base
    movzbl  1(\base), \reg
.endm

/* rax = the status of starting the OS sockets: nothing to start. */
.macro OS_STARTUP context
    xor     %eax, %eax
.endm

.macro OS_CLEANUP context
.endm

/* rax = a non-blocking TCP socket of family rdi, or minus the error. */
.macro OS_SOCKET
    call    libp2p_shell_socket
.endm

/* setsockopt(rdi, rsi, rdx) to the int 1 (at L_ONE). */
.macro OS_SETSOCKOPT_ONE
    movl    $(1), L_ONE(%rsp)
    lea     L_ONE(%rsp), %rcx
    mov     $(4), %r8d
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

/* send(rdi, rsi, rdx) without blocking; SO_NOSIGPIPE keeps SIGPIPE away. */
.macro OS_SEND
    mov     $OS_MSG_DONTWAIT, %ecx
    CALL_GLOBAL send
    OS_RET_SIZE
.endm

/* recv(rdi, rsi, rdx) without blocking. */
.macro OS_RECV
    mov     $OS_MSG_DONTWAIT, %ecx
    CALL_GLOBAL recv
    OS_RET_SIZE
.endm

/* accept(rdi, rsi, rdx): the new socket non-blocking. */
.macro OS_ACCEPT
    call    libp2p_shell_accept_one
.endm

.macro OS_CLOSE
    CALL_GLOBAL close
    OS_RET_INT
.endm

/* rax = the pending error of socket rdi (SO_ERROR), 0 when none. Uses L_ERRLEN and L_ERRVAL. */
.macro OS_SOCKET_ERROR
    movl    $(0), L_ERRVAL(%rsp)
    movl    $(4), L_ERRLEN(%rsp)
    mov     $OS_SOL_SOCKET, %esi
    mov     $OS_SO_ERROR, %edx
    lea     L_ERRVAL(%rsp), %rcx
    lea     L_ERRLEN(%rsp), %r8
    CALL_GLOBAL getsockopt
    OS_RET_INT
    test    %rax, %rax
    js      1000f
    movl    L_ERRVAL(%rsp), %eax
    jmp     1001f
1000: neg   %rax
1001:
.endm

/* poll(rdi, rsi, timeout rdx ms) -> the ready count or minus the error. */
.macro OS_POLL
    mov     $(0x7FFFFFFF), %ecx
    cmp     %rcx, %rdx
    cmovae  %rcx, %rdx
    CALL_GLOBAL poll
    OS_RET_INT
.endm

/* Frame locals, from rsp: room for native stack arguments, then: */
.set LOC, 48
.set L_SA, LOC                      /* a socket address: 128 bytes */
.set L_SALEN, LOC + 128             /* its length */
.set L_ERRLEN, LOC + 136
.set L_ERRVAL, LOC + 144
.set L_ONE, LOC + 152               /* the int 1 of setsockopt */
.set L_S0, LOC + 160                /* four saved values */
.set L_S1, LOC + 168
.set L_S2, LOC + 176
.set L_S3, LOC + 184
.set FRAME_BIG, LOC + 200           /* 8 more than a multiple of 16 */
.set FRAME_SMALL, LOC + 8

/* Frame: rbx, rbp, r12-r15, then bytes of locals at rsp. bytes is 8 more than a multiple of 16. */
.macro SENTER bytes
    push    %rbx
    UNWIND_PUSH %rbx
    push    %rbp
    UNWIND_PUSH %rbp
    push    %r12
    UNWIND_PUSH %r12
    push    %r13
    UNWIND_PUSH %r13
    push    %r14
    UNWIND_PUSH %r14
    push    %r15
    UNWIND_PUSH %r15
    sub     $\bytes, %rsp
    UNWIND_ALLOC \bytes
    UNWIND_END_PROLOGUE
.endm

.macro SLEAVE bytes
    UNWIND_BEGIN_EPILOGUE
    add     $\bytes, %rsp
    UNWIND_FREE \bytes
    pop     %r15
    UNWIND_POP %r15
    pop     %r14
    UNWIND_POP %r14
    pop     %r13
    UNWIND_POP %r13
    pop     %r12
    UNWIND_POP %r12
    pop     %rbp
    UNWIND_POP %rbp
    pop     %rbx
    UNWIND_POP %rbx
    UNWIND_END_EPILOGUE
    ret
.endm

/* ---------------------------------------------------------------- libSystem */

/*
 * libp2p_shell_fcntl(socket, command, value) -> the result, or minus errno.
 * fcntl is variadic: al holds the vector registers used, 0.
 */
LOCAL_FUNCTION libp2p_shell_fcntl
    SENTER  FRAME_SMALL
    xor     %eax, %eax
    CALL_GLOBAL fcntl
    OS_RET_INT
    SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_fcntl

/*
 * libp2p_shell_prepare(socket) -> 0, or minus errno: the socket becomes
 * non-blocking and close-on-exec, without SIGPIPE. rbx socket.
 */
LOCAL_FUNCTION libp2p_shell_prepare
    SENTER  FRAME_BIG
    mov     %rdi, %rbx
    mov     $OS_F_SETFL, %esi
    mov     $OS_O_NONBLOCK, %edx
    call    libp2p_shell_fcntl
    IF_ERROR_NEG 9f
    mov     %rbx, %rdi
    mov     $OS_F_SETFD, %esi
    mov     $OS_FD_CLOEXEC, %edx
    call    libp2p_shell_fcntl
    IF_ERROR_NEG 9f
    mov     %rbx, %rdi
    mov     $OS_SOL_SOCKET, %esi
    mov     $OS_SO_NOSIGPIPE, %edx
    OS_SETSOCKOPT_ONE
    IF_ERROR_NEG 9f
    xor     %eax, %eax
9:  SLEAVE  FRAME_BIG
END_FUNCTION libp2p_shell_prepare

/* libp2p_shell_socket(family) -> a prepared TCP socket, or minus errno. rbx socket, rbp error. */
LOCAL_FUNCTION libp2p_shell_socket
    SENTER  FRAME_SMALL
    mov     $OS_SOCK_STREAM, %esi
    xor     %edx, %edx
    CALL_GLOBAL socket
    OS_RET_INT
    IF_ERROR_NEG 9f
    mov     %rax, %rbx
    mov     %rax, %rdi
    call    libp2p_shell_prepare
    IF_ERROR_NEG 8f
    mov     %rbx, %rax
    jmp     9f
8:  mov     %rax, %rbp
    mov     %rbx, %rdi
    CALL_GLOBAL close
    mov     %rbp, %rax
9:  SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_socket

/* libp2p_shell_accept_one(listener, sockaddr, length) -> a prepared new socket, or minus errno. rbx socket, rbp error. */
LOCAL_FUNCTION libp2p_shell_accept_one
    SENTER  FRAME_SMALL
    CALL_GLOBAL accept
    OS_RET_INT
    IF_ERROR_NEG 9f
    mov     %rax, %rbx
    mov     %rax, %rdi
    call    libp2p_shell_prepare
    IF_ERROR_NEG 8f
    mov     %rbx, %rax
    jmp     9f
8:  mov     %rax, %rbp
    mov     %rbx, %rdi
    CALL_GLOBAL close
    mov     %rbp, %rax
9:  SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_accept_one

/* ---------------------------------------------------------------- Addresses */

/* libp2p_shell_sockaddr(addr, sockaddr) -> its length: 16 for IPv4, 28 for IPv6. A leaf. */
LOCAL_FUNCTION libp2p_shell_sockaddr
    UNWIND_END_PROLOGUE
    mov     LIBP2P_ADDR_FAMILY(%rdi), %rcx
    mov     LIBP2P_ADDR_PORT(%rdi), %rdx
    rolw    $8, %dx
    xor     %eax, %eax
    mov     %rax, (%rsi)
    mov     %rax, 8(%rsi)
    mov     %rax, 16(%rsi)
    mov     %rax, 24(%rsi)
    cmp     $6, %rcx
    je      1f
    SET_FAMILY OS_AF_INET, %rsi, 16
    movw    %dx, 2(%rsi)
    movl    LIBP2P_ADDR_IP(%rdi), %eax
    movl    %eax, 4(%rsi)
    mov     $16, %eax
    ret
1:  SET_FAMILY OS_AF_INET6, %rsi, 28
    movw    %dx, 2(%rsi)
    mov     LIBP2P_ADDR_IP(%rdi), %rax
    mov     %rax, 8(%rsi)
    mov     (LIBP2P_ADDR_IP + 8)(%rdi), %rax
    mov     %rax, 16(%rsi)
    mov     $28, %eax
    ret
END_FUNCTION libp2p_shell_sockaddr

/* libp2p_shell_address(sockaddr, addr): an Address of an IPv4 or IPv6 socket address; an IPv4-mapped IPv6 address becomes IPv4. A leaf. */
LOCAL_FUNCTION libp2p_shell_address
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    mov     %rax, (%rsi)
    mov     %rax, 8(%rsi)
    mov     %rax, 16(%rsi)
    mov     %rax, 24(%rsi)
    movzwl  2(%rdi), %eax
    rolw    $8, %ax
    mov     %rax, LIBP2P_ADDR_PORT(%rsi)
    GET_FAMILY %ecx, %rdi
    cmp     $OS_AF_INET, %ecx
    jne     1f
    movq    $4, LIBP2P_ADDR_FAMILY(%rsi)
    movl    4(%rdi), %eax
    movl    %eax, LIBP2P_ADDR_IP(%rsi)
    ret
1:  mov     8(%rdi), %rcx
    mov     16(%rdi), %rdx
    test    %rcx, %rcx                      /* ::ffff:a.b.c.d */
    jnz     2f
    cmp     $0xFFFF0000, %edx
    jne     2f
    movq    $4, LIBP2P_ADDR_FAMILY(%rsi)
    shr     $32, %rdx
    movl    %edx, LIBP2P_ADDR_IP(%rsi)
    ret
2:  movq    $6, LIBP2P_ADDR_FAMILY(%rsi)
    mov     %rcx, LIBP2P_ADDR_IP(%rsi)
    mov     %rdx, (LIBP2P_ADDR_IP + 8)(%rsi)
    ret
END_FUNCTION libp2p_shell_address

/* ---------------------------------------------------------------- Layout */

/*
 * libp2p_shell_layout(params, context or 0) -> rax status, rdx the context
 * size. With a context, writes its fixed fields. A leaf.
 */
LOCAL_FUNCTION libp2p_shell_layout
    UNWIND_END_PROLOGUE
    mov     LIBP2P_SP_CAPACITY(%rdi), %rcx
    mov     LIBP2P_SP_BUFFER(%rdi), %r8
    test    %rcx, %rcx
    jz      8f
    cmp     $65536, %rcx
    ja      8f
    cmp     $4096, %r8
    jb      8f
    cmp     $0x40000000, %r8
    ja      8f
    add     $7, %r8
    and     $-8, %r8
    lea     LIBP2P_SE_FIXED(%r8), %r9       /* stride */
    mov     $(LIBP2P_SH_FIXED + 8 * LIBP2P_SHELL_ACCEPTING), %r10  /* poll array */
    lea     (LIBP2P_SH_MAX_LISTEN + LIBP2P_SHELL_ACCEPTING)(%rcx), %r11
    imul    $POLL_STRIDE, %r11, %r11
    add     %r10, %r11                      /* entries */
    mov     %rcx, %rax
    imul    %r9, %rax
    add     %r11, %rax                      /* total */
    test    %rsi, %rsi
    jz      1f
    mov     %rcx, LIBP2P_SH_CAPACITY(%rsi)
    mov     %r8, LIBP2P_SH_BUFFER(%rsi)
    mov     %r9, LIBP2P_SH_STRIDE(%rsi)
    mov     %r10, LIBP2P_SH_POLL(%rsi)
    mov     %r11, LIBP2P_SH_ENTRIES(%rsi)
1:  mov     %rax, %rdx
    mov     $LIBP2P_OK, %eax
    ret
8:  mov     $LIBP2P_INVALID_CONFIG, %eax
    xor     %edx, %edx
    ret
END_FUNCTION libp2p_shell_layout

/* libp2p_shell_size(params, size) -> status: the bytes of a ShellContext for the params. */
FUNCTION libp2p_shell_size
    SENTER  FRAME_SMALL
    mov     %rsi, %rbx
    xor     %esi, %esi
    call    libp2p_shell_layout
    test    %rax, %rax
    jnz     9f
    mov     %rdx, (%rbx)
9:  SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_size

/*
 * libp2p_shell_init(params, context) -> status: a context with no sockets.
 * The size field of the context gives its bytes.
 */
FUNCTION libp2p_shell_init
    SENTER  FRAME_SMALL
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    xor     %esi, %esi
    call    libp2p_shell_layout
    test    %rax, %rax
    jnz     9f
    mov     $LIBP2P_BUFFER_TOO_SMALL, %eax
    cmp     %rdx, LIBP2P_SH_SIZE(%rbp)
    jb      9f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_shell_layout
    movq    $0, LIBP2P_SH_LISTENERS(%rbp)
    lea     LIBP2P_SH_LISTEN(%rbp), %rax
    mov     $LIBP2P_SH_MAX_LISTEN, %ecx
1:  movq    $NONE_SOCKET, (%rax)
    add     $8, %rax
    dec     %rcx
    jnz     1b
    lea     LIBP2P_SH_FIXED(%rbp), %rax     /* accepted sockets */
    mov     $LIBP2P_SHELL_ACCEPTING, %ecx
2:  movq    $NONE_SOCKET, (%rax)
    add     $8, %rax
    dec     %rcx
    jnz     2b
    mov     LIBP2P_SH_ENTRIES(%rbp), %rax
    add     %rbp, %rax
    mov     LIBP2P_SH_CAPACITY(%rbp), %rcx
    mov     LIBP2P_SH_STRIDE(%rbp), %rdx
3:  movq    $NONE_SOCKET, LIBP2P_SE_SOCKET(%rax)
    movq    $0, LIBP2P_SE_STATE(%rax)
    movq    $0, LIBP2P_SE_LEN(%rax)
    add     %rdx, %rax
    dec     %rcx
    jnz     3b
    OS_STARTUP %rbp                         /* rax = status */
9:  SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_init

/* libp2p_shell_entry(context, handle) -> the entry of the connection slot of the handle, or 0 past the capacity. A leaf. */
LOCAL_FUNCTION libp2p_shell_entry
    UNWIND_END_PROLOGUE
    mov     %esi, %esi
    cmp     LIBP2P_SH_CAPACITY(%rdi), %rsi
    jae     8f
    mov     LIBP2P_SH_STRIDE(%rdi), %rax
    imul    %rsi, %rax
    add     LIBP2P_SH_ENTRIES(%rdi), %rax
    add     %rdi, %rax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_shell_entry

/* ---------------------------------------------------------------- Event list */

/*
 * libp2p_shell_event(events, kind, size) -> the new event, zeroed, with
 * size and kind set; 0 when the list has no room. A leaf.
 */
LOCAL_FUNCTION libp2p_shell_event
    UNWIND_END_PROLOGUE
    mov     LIBP2P_BL_SIZE(%rdi), %rax
    sub     LIBP2P_BL_OFFSET(%rdi), %rax
    sub     LIBP2P_BL_COUNT(%rdi), %rax
    cmp     %rdx, %rax
    jb      8f
    mov     LIBP2P_BL_OFFSET(%rdi), %r8
    add     LIBP2P_BL_COUNT(%rdi), %r8
    add     %rdi, %r8
    add     %rdx, LIBP2P_BL_COUNT(%rdi)
    xor     %eax, %eax
    xor     %ecx, %ecx
1:  cmp     %rdx, %rcx
    jae     2f
    mov     %rax, (%r8,%rcx)
    add     $8, %rcx
    jmp     1b
2:  mov     %rdx, LIBP2P_EV_SIZE(%r8)
    mov     %rsi, LIBP2P_EV_KIND(%r8)
    mov     %r8, %rax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_shell_event

/* libp2p_shell_room(events) -> the bytes left in the event list. A leaf. */
LOCAL_FUNCTION libp2p_shell_room
    UNWIND_END_PROLOGUE
    mov     LIBP2P_BL_SIZE(%rdi), %rax
    sub     LIBP2P_BL_OFFSET(%rdi), %rax
    xor     %ecx, %ecx
    sub     LIBP2P_BL_COUNT(%rdi), %rax
    cmovb   %rcx, %rax
    ret
END_FUNCTION libp2p_shell_room

/* libp2p_shell_conn_event(events, kind, handle, value): an event with a connection handle and a value (error or count). */
LOCAL_FUNCTION libp2p_shell_conn_event
    SENTER  FRAME_SMALL
    mov     %rdx, %rbx
    mov     %rcx, %rbp
    mov     $LIBP2P_EV_CONN_SIZE, %edx
    call    libp2p_shell_event
    test    %rax, %rax
    jz      9f
    mov     %rbx, LIBP2P_EV_CONN(%rax)
    mov     %rbp, LIBP2P_EV_ERROR(%rax)
9:  SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_conn_event

/* ---------------------------------------------------------------- Sockets */

/*
 * libp2p_shell_drop(entry, events, error): closes the socket of a
 * connection and gives CLOSED with the error.
 */
LOCAL_FUNCTION libp2p_shell_drop
    SENTER  FRAME_SMALL
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     LIBP2P_SE_SOCKET(%rbx), %rdi
    OS_CLOSE
    movq    $NONE_SOCKET, LIBP2P_SE_SOCKET(%rbx)
    movq    $0, LIBP2P_SE_STATE(%rbx)
    movq    $0, LIBP2P_SE_LEN(%rbx)
    mov     %rbp, %rdi
    mov     $LIBP2P_EVENT_CLOSED, %esi
    mov     LIBP2P_SE_HANDLE(%rbx), %rdx
    mov     %r12, %rcx
    call    libp2p_shell_conn_event
    SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_drop

/*
 * libp2p_shell_flush(entry, events): writes what the send buffer holds,
 * until the socket would block; SENT with the bytes written; an error
 * closes the connection (CLOSED).
 * rbx entry, rbp events, r12 written, r13 bytes buffered, then the error.
 */
LOCAL_FUNCTION libp2p_shell_flush
    SENTER  FRAME_SMALL
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    xor     %r12d, %r12d
1:  mov     LIBP2P_SE_LEN(%rbx), %r13
    cmp     %r13, %r12
    jae     3f
    mov     LIBP2P_SE_SOCKET(%rbx), %rdi
    lea     LIBP2P_SE_DATA(%rbx,%r12), %rsi
    mov     %r13, %rdx
    sub     %r12, %rdx
    OS_SEND
    IF_WOULDBLOCK 3f
    IF_ERROR_NEG 8f
    add     %rax, %r12
    jmp     1b
3:  test    %r12, %r12
    jz      9f
    lea     LIBP2P_SE_DATA(%rbx), %rdi      /* keep the rest at the front */
    lea     (%rdi,%r12), %rsi
    mov     %r13, %rdx
    sub     %r12, %rdx
    mov     %rdx, LIBP2P_SE_LEN(%rbx)
    call    libp2p_shell_move
    mov     %rbp, %rdi
    mov     $LIBP2P_EVENT_SENT, %esi
    mov     LIBP2P_SE_HANDLE(%rbx), %rdx
    mov     %r12, %rcx
    call    libp2p_shell_conn_event
    jmp     9f
8:  neg     %rax
    mov     %rax, %r13
    test    %r12, %r12
    jz      81f
    mov     %rbp, %rdi
    mov     $LIBP2P_EVENT_SENT, %esi
    mov     LIBP2P_SE_HANDLE(%rbx), %rdx
    mov     %r12, %rcx
    call    libp2p_shell_conn_event
81: mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r13, %rdx
    call    libp2p_shell_drop
9:  SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_flush

/* libp2p_shell_move(dst, src, n): copies n bytes forward; dst is below src. A leaf. */
LOCAL_FUNCTION libp2p_shell_move
    UNWIND_END_PROLOGUE
    mov     %rdx, %rcx
    rep movsb
    ret
END_FUNCTION libp2p_shell_move

/* libp2p_shell_move_any(dst, src, n): copies n bytes of regions that do not overlap. A leaf. */
LOCAL_FUNCTION libp2p_shell_move_any
    UNWIND_END_PROLOGUE
    mov     %rdx, %rcx
    rep movsb
    ret
END_FUNCTION libp2p_shell_move_any

/*
 * libp2p_shell_listen(context, addr, result) -> status: a listening TCP
 * socket bound to the address (port 0: any); result gets 0 and the bound
 * address, or the OS error.
 * rbx context, rbp addr, r12 result, r13 family, r14 socket, r15 error.
 */
FUNCTION libp2p_shell_listen
    SENTER  FRAME_BIG
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    xor     %eax, %eax
    mov     %rax, (%r12)
    mov     %rax, 8(%r12)
    mov     %rax, 16(%r12)
    mov     %rax, 24(%r12)
    mov     %rax, 32(%r12)
    mov     $OS_EINVAL, %r15d
    cmpq    $LIBP2P_SH_MAX_LISTEN, LIBP2P_SH_LISTENERS(%rbx)
    jae     80f
    mov     $OS_AF_INET, %edi
    mov     $OS_AF_INET6, %eax
    cmpq    $6, LIBP2P_ADDR_FAMILY(%rbp)
    cmove   %rax, %rdi
    mov     %rdi, %r13
    OS_SOCKET
    IF_ERROR_NEG 81f
    mov     %rax, %r14                      /* the socket */
    mov     %r14, %rdi
    mov     $OS_SOL_SOCKET, %esi
    mov     $OS_SO_LISTEN, %edx
    OS_SETSOCKOPT_ONE
    cmp     $OS_AF_INET6, %r13
    jne     2f
    mov     %r14, %rdi
    mov     $OS_IPPROTO_IPV6, %esi
    mov     $OS_IPV6_V6ONLY, %edx
    OS_SETSOCKOPT_ONE
2:  mov     %rbp, %rdi
    lea     L_SA(%rsp), %rsi
    call    libp2p_shell_sockaddr
    mov     %rax, %rdx
    mov     %r14, %rdi
    lea     L_SA(%rsp), %rsi
    OS_BIND
    IF_ERROR_NEG 82f
    mov     %r14, %rdi
    mov     $1024, %esi
    OS_LISTEN
    IF_ERROR_NEG 82f
    movq    $128, L_SALEN(%rsp)
    mov     %r14, %rdi
    lea     L_SA(%rsp), %rsi
    lea     L_SALEN(%rsp), %rdx
    OS_GETSOCKNAME
    IF_ERROR_NEG 82f
    lea     L_SA(%rsp), %rdi
    lea     LIBP2P_LR_ADDR(%r12), %rsi
    call    libp2p_shell_address
    mov     LIBP2P_SH_LISTENERS(%rbx), %rax
    mov     %r14, LIBP2P_SH_LISTEN(%rbx,%rax,8)
    inc     %rax
    mov     %rax, LIBP2P_SH_LISTENERS(%rbx)
    jmp     90f
82: neg     %rax
    mov     %rax, %r15
    mov     %r14, %rdi
    OS_CLOSE
    jmp     80f
81: neg     %rax
    mov     %rax, %r15
80: mov     %r15, LIBP2P_LR_ERROR(%r12)
90: xor     %eax, %eax
    SLEAVE  FRAME_BIG
END_FUNCTION libp2p_shell_listen

/*
 * libp2p_shell_perform(context, actions, events) -> status: does the shell
 * actions of a step in order: DIAL, ADOPT, REFUSE, SEND and CLOSE; results
 * known at once go to events (CONNECTED, DIAL_FAILED, SENT, CLOSED). Other
 * kinds are the application's.
 * rbx context, rbp events, r12 action, r13 end, r14 entry, r15 a socket, a
 * count or an error.
 */
FUNCTION libp2p_shell_perform
    SENTER  FRAME_BIG
    mov     %rdi, %rbx
    mov     %rdx, %rbp
    mov     LIBP2P_BL_OFFSET(%rsi), %r12
    add     %rsi, %r12
    mov     LIBP2P_BL_COUNT(%rsi), %r13
    add     %r12, %r13
1:  cmp     %r13, %r12
    jae     90f
    mov     LIBP2P_ACT_KIND(%r12), %rax
    cmp     $LIBP2P_ACTION_DIAL, %rax
    jne     20f

    /* DIAL */
    mov     %rbx, %rdi
    mov     LIBP2P_ACT_CONN(%r12), %rsi
    call    libp2p_shell_entry
    test    %rax, %rax
    jz      80f
    mov     %rax, %r14
    cmpq    $0, LIBP2P_SE_STATE(%r14)
    je      11f
    mov     LIBP2P_SE_SOCKET(%r14), %rdi    /* a stale socket in the slot */
    OS_CLOSE
11: mov     LIBP2P_ACT_CONN(%r12), %rax
    mov     %rax, LIBP2P_SE_HANDLE(%r14)
    movq    $0, LIBP2P_SE_LEN(%r14)
    movq    $0, LIBP2P_SE_STATE(%r14)
    movq    $NONE_SOCKET, LIBP2P_SE_SOCKET(%r14)
    mov     $OS_AF_INET, %edi
    mov     $OS_AF_INET6, %eax
    cmpq    $6, (LIBP2P_ACT_DIAL_ADDR + LIBP2P_ADDR_FAMILY)(%r12)
    cmove   %rax, %rdi
    OS_SOCKET
    IF_ERROR_NEG 15f
    mov     %rax, LIBP2P_SE_SOCKET(%r14)
    mov     %rax, %rdi
    mov     $OS_IPPROTO_TCP, %esi
    mov     $OS_TCP_NODELAY, %edx
    OS_SETSOCKOPT_ONE
    lea     LIBP2P_ACT_DIAL_ADDR(%r12), %rdi
    lea     L_SA(%rsp), %rsi
    call    libp2p_shell_sockaddr
    mov     %rax, %rdx
    mov     LIBP2P_SE_SOCKET(%r14), %rdi
    lea     L_SA(%rsp), %rsi
    OS_CONNECT
    IF_INPROGRESS 13f
    IF_ERROR_NEG 14f
    movq    $2, LIBP2P_SE_STATE(%r14)       /* connected at once */
    mov     %rbp, %rdi
    mov     $LIBP2P_EVENT_CONNECTED, %esi
    mov     LIBP2P_SE_HANDLE(%r14), %rdx
    xor     %ecx, %ecx
    call    libp2p_shell_conn_event
    jmp     80f
13: movq    $1, LIBP2P_SE_STATE(%r14)
    jmp     80f
14: mov     %rax, %r15
    mov     LIBP2P_SE_SOCKET(%r14), %rdi
    OS_CLOSE
    movq    $NONE_SOCKET, LIBP2P_SE_SOCKET(%r14)
    mov     %r15, %rax
15: neg     %rax
    mov     %rax, %rcx
    mov     %rbp, %rdi
    mov     $LIBP2P_EVENT_DIAL_FAILED, %esi
    mov     LIBP2P_ACT_CONN(%r12), %rdx
    call    libp2p_shell_conn_event
    jmp     80f

    /* ADOPT and REFUSE: the accepted socket of the token. */
20: cmp     $LIBP2P_ACTION_ADOPT, %rax
    je      21f
    cmp     $LIBP2P_ACTION_REFUSE, %rax
    jne     30f
21: mov     LIBP2P_ACT_TOKEN(%r12), %rcx
    lea     LIBP2P_SH_FIXED(%rbx), %rdx
    xor     %r8d, %r8d
22: cmp     $LIBP2P_SHELL_ACCEPTING, %r8
    jae     80f
    cmp     (%rdx,%r8,8), %rcx
    je      23f
    inc     %r8
    jmp     22b
23: movq    $NONE_SOCKET, (%rdx,%r8,8)
    mov     %rcx, %r15
    cmpq    $LIBP2P_ACTION_REFUSE, LIBP2P_ACT_KIND(%r12)
    je      24f
    mov     %rbx, %rdi
    mov     LIBP2P_ACT_ADOPT_CONN(%r12), %rsi
    call    libp2p_shell_entry
    test    %rax, %rax
    jz      24f
    mov     %rax, %r14
    cmpq    $0, LIBP2P_SE_STATE(%r14)
    je      25f
    mov     LIBP2P_SE_SOCKET(%r14), %rdi
    OS_CLOSE
25: mov     %r15, LIBP2P_SE_SOCKET(%r14)
    mov     LIBP2P_ACT_ADOPT_CONN(%r12), %rax
    mov     %rax, LIBP2P_SE_HANDLE(%r14)
    movq    $2, LIBP2P_SE_STATE(%r14)
    movq    $0, LIBP2P_SE_LEN(%r14)
    jmp     80f
24: mov     %r15, %rdi
    OS_CLOSE
    jmp     80f

    /* SEND: into the send buffer, then write what the socket takes. */
30: cmp     $LIBP2P_ACTION_SEND, %rax
    jne     40f
    mov     %rbx, %rdi
    mov     LIBP2P_ACT_CONN(%r12), %rsi
    call    libp2p_shell_entry
    test    %rax, %rax
    jz      80f
    mov     %rax, %r14
    cmpq    $2, LIBP2P_SE_STATE(%r14)
    jne     80f
    mov     LIBP2P_SE_HANDLE(%r14), %rax
    cmp     LIBP2P_ACT_CONN(%r12), %rax
    jne     80f
    mov     LIBP2P_ACT_SEND_COUNT(%r12), %r15
    mov     LIBP2P_SH_BUFFER(%rbx), %rax
    sub     LIBP2P_SE_LEN(%r14), %rax
    cmp     %rax, %r15
    jbe     31f
    mov     %r14, %rdi                      /* more than the buffer holds: the connection ends */
    mov     %rbp, %rsi
    mov     $OS_EINVAL, %edx
    call    libp2p_shell_drop
    jmp     80f
31: lea     LIBP2P_SE_DATA(%r14), %rdi
    add     LIBP2P_SE_LEN(%r14), %rdi
    lea     LIBP2P_ACT_SEND_DATA(%r12), %rsi
    mov     %r15, %rdx
    call    libp2p_shell_move_any
    add     %r15, LIBP2P_SE_LEN(%r14)
    mov     %r14, %rdi
    mov     %rbp, %rsi
    call    libp2p_shell_flush
    jmp     80f

    /* CLOSE */
40: cmp     $LIBP2P_ACTION_CLOSE, %rax
    jne     80f
    mov     %rbx, %rdi
    mov     LIBP2P_ACT_CONN(%r12), %rsi
    call    libp2p_shell_entry
    test    %rax, %rax
    jz      80f
    mov     %rax, %r14
    cmpq    $0, LIBP2P_SE_STATE(%r14)
    je      41f
    mov     LIBP2P_SE_HANDLE(%r14), %rax
    cmp     LIBP2P_ACT_CONN(%r12), %rax
    jne     41f
    mov     %r14, %rdi
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    libp2p_shell_drop
    jmp     80f
41: mov     %rbp, %rdi                      /* no socket: CLOSED all the same */
    mov     $LIBP2P_EVENT_CLOSED, %esi
    mov     LIBP2P_ACT_CONN(%r12), %rdx
    xor     %ecx, %ecx
    call    libp2p_shell_conn_event
80: add     LIBP2P_ACT_SIZE(%r12), %r12
    jmp     1b
90: xor     %eax, %eax
    SLEAVE  FRAME_BIG
END_FUNCTION libp2p_shell_perform

/*
 * libp2p_shell_wait(context, timeout, events) -> status: waits up to
 * timeout ms (a u64) for socket activity, then gives events: ACCEPTED for
 * new connections (up to 16 waiting for ADOPT), CONNECTED or DIAL_FAILED
 * when a dial ends, SENT as buffered bytes go out, RECEIVED with what a
 * socket holds (at most 65536 bytes, while the event list has room), and
 * CLOSED when a socket ends.
 * rbx context, rbp events, r12 poll array, r13 poll count, r14 i, r15
 * entry; L_S0 listeners, L_S1 the timeout then the revents, L_S2 a size or
 * an error, L_S3 the event.
 */
FUNCTION libp2p_shell_wait
    SENTER  FRAME_BIG
    mov     %rdi, %rbx
    mov     %rdx, %rbp
    mov     (%rsi), %rax                    /* timeout */
    mov     %rax, L_S1(%rsp)
    mov     LIBP2P_SH_POLL(%rbx), %r12
    add     %rbx, %r12
    xor     %r13d, %r13d
    xor     %r14d, %r14d                    /* listeners */
1:  cmp     LIBP2P_SH_LISTENERS(%rbx), %r14
    jae     2f
    mov     LIBP2P_SH_LISTEN(%rbx,%r14,8), %rdi
    mov     $OS_POLLIN, %esi
    mov     %r13, %rdx
    mov     %r12, %rcx
    call    libp2p_shell_poll_set
    inc     %r13
    inc     %r14
    jmp     1b
2:  xor     %r14d, %r14d                    /* connections */
3:  cmp     LIBP2P_SH_CAPACITY(%rbx), %r14
    jae     5f
    mov     LIBP2P_SH_STRIDE(%rbx), %r15
    imul    %r14, %r15
    add     LIBP2P_SH_ENTRIES(%rbx), %r15
    add     %rbx, %r15
    mov     LIBP2P_SE_STATE(%r15), %rax
    mov     $NONE_SOCKET, %rdi              /* a free slot polls no socket */
    xor     %esi, %esi
    test    %rax, %rax
    jz      4f
    mov     LIBP2P_SE_SOCKET(%r15), %rdi
    mov     $OS_POLLOUT, %esi
    cmp     $1, %rax
    je      4f
    mov     $OS_POLLIN, %esi
    cmpq    $0, LIBP2P_SE_LEN(%r15)
    je      4f
    or      $OS_POLLOUT, %esi
4:  mov     %r13, %rdx
    mov     %r12, %rcx
    call    libp2p_shell_poll_set
    inc     %r13
    inc     %r14
    jmp     3b
5:  mov     %r12, %rdi
    mov     %r13, %rsi
    mov     L_S1(%rsp), %rdx
    OS_POLL
    IF_ERROR_NEG 90f
    test    %rax, %rax
    jz      90f

    /* Listeners: accept while there is room. */
    xor     %r14d, %r14d
6:  cmp     LIBP2P_SH_LISTENERS(%rbx), %r14
    jae     7f
    mov     %r14, %rdi
    mov     %r12, %rsi
    call    libp2p_shell_poll_events
    test    $OS_POLLIN, %eax
    jz      61f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     LIBP2P_SH_LISTEN(%rbx,%r14,8), %rdx
    call    libp2p_shell_accept
61: inc     %r14
    jmp     6b

    /* Connections. */
7:  mov     LIBP2P_SH_LISTENERS(%rbx), %rax
    mov     %rax, L_S0(%rsp)
    xor     %r14d, %r14d
8:  cmp     LIBP2P_SH_CAPACITY(%rbx), %r14
    jae     90f
    mov     LIBP2P_SH_STRIDE(%rbx), %r15
    imul    %r14, %r15
    add     LIBP2P_SH_ENTRIES(%rbx), %r15
    add     %rbx, %r15
    mov     L_S0(%rsp), %rdi
    add     %r14, %rdi
    mov     %r12, %rsi
    call    libp2p_shell_poll_events
    mov     %rax, L_S1(%rsp)
    test    %rax, %rax
    jz      89f
    mov     LIBP2P_SE_STATE(%r15), %rcx
    test    %rcx, %rcx
    jz      89f
    cmp     $1, %rcx
    jne     81f
    mov     LIBP2P_SE_SOCKET(%r15), %rdi    /* a dial ended */
    OS_SOCKET_ERROR
    test    %rax, %rax
    jnz     80f
    movq    $2, LIBP2P_SE_STATE(%r15)
    mov     %rbp, %rdi
    mov     $LIBP2P_EVENT_CONNECTED, %esi
    mov     LIBP2P_SE_HANDLE(%r15), %rdx
    xor     %ecx, %ecx
    call    libp2p_shell_conn_event
    jmp     89f
80: mov     %rax, L_S2(%rsp)
    mov     LIBP2P_SE_SOCKET(%r15), %rdi
    OS_CLOSE
    movq    $NONE_SOCKET, LIBP2P_SE_SOCKET(%r15)
    movq    $0, LIBP2P_SE_STATE(%r15)
    mov     %rbp, %rdi
    mov     $LIBP2P_EVENT_DIAL_FAILED, %esi
    mov     LIBP2P_SE_HANDLE(%r15), %rdx
    mov     L_S2(%rsp), %rcx
    call    libp2p_shell_conn_event
    jmp     89f
81: testq   $OS_POLLOUT, L_S1(%rsp)
    jz      82f
    mov     %r15, %rdi
    mov     %rbp, %rsi
    call    libp2p_shell_flush
    cmpq    $0, LIBP2P_SE_STATE(%r15)
    je      89f
82: testq   $(OS_POLLIN | OS_POLLHUP | OS_POLLERR), L_S1(%rsp)
    jz      89f
    mov     %rbp, %rdi                      /* read into a RECEIVED event */
    call    libp2p_shell_room
    sub     $(LIBP2P_EV_DATA + 8), %rax
    jbe     89f
    mov     $LIBP2P_RECEIVE_MAX, %ecx
    cmp     %rcx, %rax
    cmovae  %rcx, %rax
    mov     %rax, L_S2(%rsp)
    mov     LIBP2P_BL_OFFSET(%rbp), %rcx
    add     LIBP2P_BL_COUNT(%rbp), %rcx
    add     %rbp, %rcx                      /* the event, not yet in the list */
    mov     %rcx, L_S3(%rsp)
    mov     LIBP2P_SE_SOCKET(%r15), %rdi
    lea     LIBP2P_EV_DATA(%rcx), %rsi
    mov     %rax, %rdx
    OS_RECV
    IF_WOULDBLOCK 89f
    IF_ERROR_NEG 83f
    test    %rax, %rax
    jz      84f
    mov     L_S3(%rsp), %rcx
    lea     (LIBP2P_EV_DATA + 7)(%rax), %rdx
    and     $-8, %rdx
    mov     %rdx, LIBP2P_EV_SIZE(%rcx)
    movq    $LIBP2P_EVENT_RECEIVED, LIBP2P_EV_KIND(%rcx)
    mov     LIBP2P_SE_HANDLE(%r15), %r8
    mov     %r8, LIBP2P_EV_CONN(%rcx)
    mov     %rax, LIBP2P_EV_COUNT(%rcx)
    add     %rdx, LIBP2P_BL_COUNT(%rbp)
    jmp     89f
83: neg     %rax
    mov     %rax, %rdx
    jmp     85f
84: xor     %edx, %edx                      /* the peer closed */
85: mov     %r15, %rdi
    mov     %rbp, %rsi
    call    libp2p_shell_drop
89: inc     %r14
    jmp     8b
90: xor     %eax, %eax
    SLEAVE  FRAME_BIG
END_FUNCTION libp2p_shell_wait

/*
 * libp2p_shell_accept(context, events, listener): one new connection: its
 * socket waits in the accepting table, and ACCEPTED has it as the token.
 * Without a free place or event room, the socket waits in the backlog.
 * rbx context, rbp events, r12 listener, r13 table, r14 place, r15 socket.
 */
LOCAL_FUNCTION libp2p_shell_accept
    SENTER  FRAME_BIG
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    lea     LIBP2P_SH_FIXED(%rbx), %r13
    xor     %r14d, %r14d
1:  cmp     $LIBP2P_SHELL_ACCEPTING, %r14
    jae     9f
    cmpq    $NONE_SOCKET, (%r13,%r14,8)
    je      2f
    inc     %r14
    jmp     1b
2:  mov     %rbp, %rdi
    call    libp2p_shell_room
    cmp     $LIBP2P_EV_ACCEPTED_SIZE, %rax
    jb      9f
    movq    $128, L_SALEN(%rsp)
    mov     %r12, %rdi
    lea     L_SA(%rsp), %rsi
    lea     L_SALEN(%rsp), %rdx
    OS_ACCEPT
    IF_ERROR_NEG 9f
    mov     %rax, (%r13,%r14,8)
    mov     %rax, %r15
    mov     %rax, %rdi
    mov     $OS_IPPROTO_TCP, %esi
    mov     $OS_TCP_NODELAY, %edx
    OS_SETSOCKOPT_ONE
    mov     %rbp, %rdi
    mov     $LIBP2P_EVENT_ACCEPTED, %esi
    mov     $LIBP2P_EV_ACCEPTED_SIZE, %edx
    call    libp2p_shell_event
    mov     %r15, LIBP2P_EV_TOKEN(%rax)
    lea     LIBP2P_EV_ACCEPTED_ADDR(%rax), %rsi
    lea     L_SA(%rsp), %rdi
    call    libp2p_shell_address
9:  SLEAVE  FRAME_BIG
END_FUNCTION libp2p_shell_accept

/* libp2p_shell_close(context) -> status: closes every socket. rbx context, rbp i, r12 entry. */
FUNCTION libp2p_shell_close
    SENTER  FRAME_SMALL
    mov     %rdi, %rbx
    xor     %ebp, %ebp
1:  cmp     LIBP2P_SH_LISTENERS(%rbx), %rbp
    jae     2f
    mov     LIBP2P_SH_LISTEN(%rbx,%rbp,8), %rdi
    OS_CLOSE
    inc     %rbp
    jmp     1b
2:  movq    $0, LIBP2P_SH_LISTENERS(%rbx)
    xor     %ebp, %ebp
3:  cmp     $LIBP2P_SHELL_ACCEPTING, %rbp
    jae     4f
    mov     LIBP2P_SH_FIXED(%rbx,%rbp,8), %rdi
    cmp     $NONE_SOCKET, %rdi
    je      31f
    OS_CLOSE
    movq    $NONE_SOCKET, LIBP2P_SH_FIXED(%rbx,%rbp,8)
31: inc     %rbp
    jmp     3b
4:  xor     %ebp, %ebp
5:  cmp     LIBP2P_SH_CAPACITY(%rbx), %rbp
    jae     6f
    mov     LIBP2P_SH_STRIDE(%rbx), %r12
    imul    %rbp, %r12
    add     LIBP2P_SH_ENTRIES(%rbx), %r12
    add     %rbx, %r12
    cmpq    $0, LIBP2P_SE_STATE(%r12)
    je      51f
    mov     LIBP2P_SE_SOCKET(%r12), %rdi
    OS_CLOSE
    movq    $NONE_SOCKET, LIBP2P_SE_SOCKET(%r12)
    movq    $0, LIBP2P_SE_STATE(%r12)
51: inc     %rbp
    jmp     5b
6:  OS_CLEANUP %rbx
    xor     %eax, %eax
    SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_close

/* ---------------------------------------------------------------- Poll entries, clock */

/* libp2p_shell_poll_set(socket, events, index, array): one struct pollfd (8 bytes: fd, events, revents). A leaf. */
LOCAL_FUNCTION libp2p_shell_poll_set
    UNWIND_END_PROLOGUE
    lea     (%rcx,%rdx,8), %rax
    movl    %edi, (%rax)
    movw    %si, 4(%rax)
    movw    $0, 6(%rax)
    ret
END_FUNCTION libp2p_shell_poll_set

/* libp2p_shell_poll_events(index, array) -> the revents of slot index. A leaf. */
LOCAL_FUNCTION libp2p_shell_poll_events
    UNWIND_END_PROLOGUE
    movzwl  6(%rsi,%rdi,8), %eax
    ret
END_FUNCTION libp2p_shell_poll_events

/*
 * libp2p_shell_clock(tick) -> status: the monotonic time in ms
 * (clock_gettime_nsec_np) and 32 random bytes (getentropy); LIBP2P_OS_ERROR
 * when either fails. rbx tick, rbp status.
 */
FUNCTION libp2p_shell_clock
    SENTER  FRAME_SMALL
    mov     %rdi, %rbx
    mov     $LIBP2P_OS_ERROR, %ebp
    mov     $OS_CLOCK_MONOTONIC, %edi
    CALL_GLOBAL clock_gettime_nsec_np
    test    %rax, %rax
    jz      9f
    xor     %edx, %edx
    mov     $1000000, %ecx
    div     %rcx
    mov     %rax, LIBP2P_TICK_NOW(%rbx)
    lea     LIBP2P_TICK_ENTROPY(%rbx), %rdi
    mov     $32, %esi
    CALL_GLOBAL getentropy
    test    %eax, %eax
    jnz     9f
    xor     %ebp, %ebp
9:  mov     %rbp, %rax
    SLEAVE  FRAME_SMALL
END_FUNCTION libp2p_shell_clock
