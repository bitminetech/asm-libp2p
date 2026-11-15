/*
 * asm-libp2p shell for Linux on x86-64: TCP and UDP sockets, the clock and random
 * bytes, through direct system calls. AT&T syntax.
 * Requirements: docs/reference/shell.md. Layouts: include/libp2p.inc.
 *
 * The functions use the System V AMD64 psABI like the core. System calls:
 * the number in rax, arguments in rdi, rsi, rdx, r10, r8, r9, "syscall";
 * rax holds the result, or minus the error number (-4095 to -1). Each OS
 * macro leaves the same in rax and may change rcx, rdx, rsi, rdi, r8-r11.
 *
 * Constants in macros are written $(n): in a macro without named
 * parameters, the Mach-O assembler reads $0 to $9 as positional arguments.
 */
.set ISA_X86_64, 1
.include "libp2p.inc"
.include "platform.inc"

/* Linux numbers: arch/x86/entry/syscalls/syscall_64.tbl and the uapi headers. */
.set SYS_CLOSE, 3
.set SYS_SOCKET, 41
.set SYS_CONNECT, 42
.set SYS_SENDTO, 44
.set SYS_RECVFROM, 45
.set SYS_BIND, 49
.set SYS_LISTEN, 50
.set SYS_GETSOCKNAME, 51
.set SYS_SETSOCKOPT, 54
.set SYS_GETSOCKOPT, 55
.set SYS_CLOCK_GETTIME, 228
.set SYS_PPOLL, 271
.set SYS_ACCEPT4, 288
.set SYS_GETRANDOM, 318
.set OS_AF_INET, 2
.set OS_AF_INET6, 10
.set OS_SOCK_STREAM, 1
.set OS_SOCK_NONBLOCK, 0x800        /* O_NONBLOCK */
.set OS_SOCK_CLOEXEC, 0x80000       /* O_CLOEXEC */
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
.set OS_CLOCK_REALTIME, 0
.set OS_SOCK_DGRAM, 2
.set OS_SO_SNDBUF, 7
.set OS_SO_RCVBUF, 8
.set POLL_STRIDE, 16                /* context bytes per poll entry: the largest of every OS (Windows) */
.set NONE_SOCKET, -1

.macro SYSCALL number
    mov     $\number, %eax
    syscall
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

/* The family of a socket address of len bytes. */
.macro SET_FAMILY family, base, len
    movw    $\family, (\base)
.endm

/* reg = the family of the socket address at base. */
.macro GET_FAMILY reg, base
    movzwl  (\base), \reg
.endm

/* rax = the status of starting the OS sockets: nothing to start. */
.macro OS_STARTUP context
    xor     %eax, %eax
.endm

.macro OS_CLEANUP context
.endm

/* rax = a non-blocking TCP socket of family rdi, or minus the error. */
.macro OS_SOCKET
    mov     $(OS_SOCK_STREAM | OS_SOCK_NONBLOCK | OS_SOCK_CLOEXEC), %esi
    xor     %edx, %edx
    SYSCALL SYS_SOCKET
.endm

/* setsockopt(rdi, rsi, rdx) to the int 1 (at L_ONE). */
.macro OS_SETSOCKOPT_ONE
    movl    $(1), L_ONE(%rsp)
    lea     L_ONE(%rsp), %r10
    mov     $(4), %r8d
    SYSCALL SYS_SETSOCKOPT
.endm

/* rax = a non-blocking UDP socket of family rdi, or minus the error. */
.macro OS_UDP_SOCKET
    mov     $(OS_SOCK_DGRAM | OS_SOCK_NONBLOCK | OS_SOCK_CLOEXEC), %esi
    xor     %edx, %edx
    SYSCALL SYS_SOCKET
.endm

/* setsockopt(rdi, rsi, rdx) to the int value (at L_ONE). */
.macro OS_SETSOCKOPT_INT value
    movl    $(\value), L_ONE(%rsp)
    lea     L_ONE(%rsp), %r10
    mov     $(4), %r8d
    SYSCALL SYS_SETSOCKOPT
.endm

/* sendto(rdi, rsi, rdx, sockaddr r8, its length r9) without SIGPIPE or blocking. */
.macro OS_SENDTO
    mov     $(OS_MSG_NOSIGNAL | OS_MSG_DONTWAIT), %r10d
    SYSCALL SYS_SENDTO
.endm

/* recvfrom(rdi, rsi, rdx, sockaddr r8, its length r9) without blocking. */
.macro OS_RECVFROM
    mov     $OS_MSG_DONTWAIT, %r10d
    SYSCALL SYS_RECVFROM
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

/* sendto(rdi, rsi, rdx) without SIGPIPE or blocking. */
.macro OS_SEND
    mov     $(OS_MSG_NOSIGNAL | OS_MSG_DONTWAIT), %r10d
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    SYSCALL SYS_SENDTO
.endm

/* recvfrom(rdi, rsi, rdx) without blocking. */
.macro OS_RECV
    mov     $OS_MSG_DONTWAIT, %r10d
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    SYSCALL SYS_RECVFROM
.endm

/* accept4(rdi, rsi, rdx): the new socket non-blocking. */
.macro OS_ACCEPT
    mov     $(OS_SOCK_NONBLOCK | OS_SOCK_CLOEXEC), %r10d
    SYSCALL SYS_ACCEPT4
.endm

.macro OS_CLOSE
    SYSCALL SYS_CLOSE
.endm

/* rax = the pending error of socket rdi (SO_ERROR), 0 when none. Uses L_ERRLEN and L_ERRVAL. */
.macro OS_SOCKET_ERROR
    movl    $(0), L_ERRVAL(%rsp)
    movl    $(4), L_ERRLEN(%rsp)
    mov     $OS_SOL_SOCKET, %esi
    mov     $OS_SO_ERROR, %edx
    lea     L_ERRVAL(%rsp), %r10
    lea     L_ERRLEN(%rsp), %r8
    SYSCALL SYS_GETSOCKOPT
    cmp     $-4095, %rax
    jae     1000f
    movl    L_ERRVAL(%rsp), %eax
    jmp     1001f
1000: neg   %rax
1001:
.endm

/* ppoll(rdi, rsi, timeout rdx ms) -> the ready count or minus the error. Uses L_SA for the timespec. */
.macro OS_POLL
    mov     %rdx, %rax
    xor     %edx, %edx
    mov     $(1000), %ecx
    div     %rcx
    imul    $(1000000), %rdx, %rdx
    mov     %rax, L_SA(%rsp)
    mov     %rdx, (L_SA + 8)(%rsp)
    lea     L_SA(%rsp), %rdx
    xor     %r10d, %r10d
    xor     %r8d, %r8d
    SYSCALL SYS_PPOLL
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
    lea     (LIBP2P_SH_MAX_LISTEN + LIBP2P_SH_MAX_UDP + LIBP2P_SHELL_ACCEPTING)(%rcx), %r11
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
    movq    $0, LIBP2P_SH_UDPS(%rbp)        /* UDP sockets */
    lea     LIBP2P_SH_UDP(%rbp), %rax
    mov     $LIBP2P_SH_MAX_UDP, %ecx
11: movq    $NONE_SOCKET, (%rax)
    add     $8, %rax
    dec     %rcx
    jnz     11b
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
 * libp2p_shell_bind(context, addr, result) -> status: a non-blocking UDP
 * socket bound to the address (port 0: any), IPv6 only for an IPv6
 * address, with send and receive buffers of LIBP2P_UDP_BUFFER bytes asked
 * for; result gets 0, its socket ID and the bound address, or the OS error.
 * rbx context, rbp addr, r12 result, r13 family, r14 socket, r15 error.
 */
FUNCTION libp2p_shell_bind
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
    mov     %rax, 40(%r12)
    mov     $OS_EINVAL, %r15d
    cmpq    $LIBP2P_SH_MAX_UDP, LIBP2P_SH_UDPS(%rbx)
    jae     80f
    mov     $OS_AF_INET, %edi
    mov     $OS_AF_INET6, %eax
    cmpq    $6, LIBP2P_ADDR_FAMILY(%rbp)
    cmove   %rax, %rdi
    mov     %rdi, %r13
    OS_UDP_SOCKET
    IF_ERROR_NEG 81f
    mov     %rax, %r14                      /* the socket */
    cmp     $OS_AF_INET6, %r13
    jne     2f
    mov     %r14, %rdi
    mov     $OS_IPPROTO_IPV6, %esi
    mov     $OS_IPV6_V6ONLY, %edx
    OS_SETSOCKOPT_ONE
2:  mov     %r14, %rdi                      /* the OS may give less: not an error */
    mov     $OS_SOL_SOCKET, %esi
    mov     $OS_SO_RCVBUF, %edx
    OS_SETSOCKOPT_INT LIBP2P_UDP_BUFFER
    mov     %r14, %rdi
    mov     $OS_SOL_SOCKET, %esi
    mov     $OS_SO_SNDBUF, %edx
    OS_SETSOCKOPT_INT LIBP2P_UDP_BUFFER
    mov     %rbp, %rdi
    lea     L_SA(%rsp), %rsi
    call    libp2p_shell_sockaddr
    mov     %rax, %rdx
    mov     %r14, %rdi
    lea     L_SA(%rsp), %rsi
    OS_BIND
    IF_ERROR_NEG 82f
    movq    $128, L_SALEN(%rsp)
    mov     %r14, %rdi
    lea     L_SA(%rsp), %rsi
    lea     L_SALEN(%rsp), %rdx
    OS_GETSOCKNAME
    IF_ERROR_NEG 82f
    lea     L_SA(%rsp), %rdi
    lea     LIBP2P_BR_ADDR(%r12), %rsi
    call    libp2p_shell_address
    mov     LIBP2P_SH_UDPS(%rbx), %rax
    mov     %rax, LIBP2P_BR_SOCKET(%r12)
    mov     %r14, LIBP2P_SH_UDP(%rbx,%rax,8)
    inc     %rax
    mov     %rax, LIBP2P_SH_UDPS(%rbx)
    jmp     90f
82: neg     %rax
    mov     %rax, %r15
    mov     %r14, %rdi
    OS_CLOSE
    jmp     80f
81: neg     %rax
    mov     %rax, %r15
80: mov     %r15, LIBP2P_BR_ERROR(%r12)
90: xor     %eax, %eax
    SLEAVE  FRAME_BIG
END_FUNCTION libp2p_shell_bind

/*
 * libp2p_shell_udp_read(context, events, index): the datagrams waiting on
 * UDP socket index become DATAGRAM events, each of at most
 * LIBP2P_UDP_RECEIVE bytes, while the event list has room for one; an error
 * or an empty socket ends it.
 * rbx context, rbp events, r12 socket ID, r13 native socket, r14 event, r15 bytes.
 */
LOCAL_FUNCTION libp2p_shell_udp_read
    SENTER  FRAME_BIG
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     LIBP2P_SH_UDP(%rbx,%r12,8), %r13
1:  mov     %rbp, %rdi
    call    libp2p_shell_room
    cmp     $(LIBP2P_EV_DG_DATA + LIBP2P_UDP_RECEIVE), %rax
    jb      9f
    mov     LIBP2P_BL_OFFSET(%rbp), %r14
    add     LIBP2P_BL_COUNT(%rbp), %r14
    add     %rbp, %r14                      /* the event, not yet in the list */
    movq    $128, L_SALEN(%rsp)
    mov     %r13, %rdi
    lea     LIBP2P_EV_DG_DATA(%r14), %rsi
    mov     $LIBP2P_UDP_RECEIVE, %edx
    lea     L_SA(%rsp), %r8
    lea     L_SALEN(%rsp), %r9
    OS_RECVFROM
    IF_ERROR_NEG 9f
    mov     %rax, %r15
    lea     (LIBP2P_EV_DG_DATA + 7)(%r15), %rax
    and     $-8, %rax
    mov     %rax, LIBP2P_EV_SIZE(%r14)
    movq    $LIBP2P_EVENT_DATAGRAM, LIBP2P_EV_KIND(%r14)
    mov     %r12, LIBP2P_EV_DG_SOCKET(%r14)
    mov     %r15, LIBP2P_EV_DG_COUNT(%r14)
    lea     L_SA(%rsp), %rdi
    lea     LIBP2P_EV_DG_ADDR(%r14), %rsi
    call    libp2p_shell_address
    mov     LIBP2P_EV_SIZE(%r14), %rax
    add     %rax, LIBP2P_BL_COUNT(%rbp)
    jmp     1b
9:  SLEAVE  FRAME_BIG
END_FUNCTION libp2p_shell_udp_read

/*
 * libp2p_shell_perform(context, actions, events) -> status: does the shell
 * actions of a step in order: DIAL, ADOPT, REFUSE, SEND, CLOSE and
 * SEND_DATAGRAM; results known at once go to events (CONNECTED, DIAL_FAILED,
 * SENT, CLOSED). Other kinds are the application's.
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
    jne     50f
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
    jmp     80f

    /* SEND_DATAGRAM: sendto on the UDP socket of its ID; a datagram the OS does not take is lost, as UDP allows. */
50: cmp     $LIBP2P_ACTION_SEND_DATAGRAM, %rax
    jne     80f
    mov     LIBP2P_ACT_DG_SOCKET(%r12), %rax
    cmp     LIBP2P_SH_UDPS(%rbx), %rax
    jae     80f
    mov     LIBP2P_SH_UDP(%rbx,%rax,8), %r15
    lea     LIBP2P_ACT_DG_ADDR(%r12), %rdi
    lea     L_SA(%rsp), %rsi
    call    libp2p_shell_sockaddr
    mov     %rax, %r9
    mov     %r15, %rdi
    lea     LIBP2P_ACT_DG_DATA(%r12), %rsi
    mov     LIBP2P_ACT_DG_COUNT(%r12), %rdx
    lea     L_SA(%rsp), %r8
    OS_SENDTO
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
 * socket holds (at most 65536 bytes, while the event list has room),
 * CLOSED when a socket ends, and DATAGRAM for each datagram of a UDP socket.
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
5:  xor     %r14d, %r14d                    /* UDP sockets */
51: cmp     LIBP2P_SH_UDPS(%rbx), %r14
    jae     52f
    mov     LIBP2P_SH_UDP(%rbx,%r14,8), %rdi
    mov     $OS_POLLIN, %esi
    mov     %r13, %rdx
    mov     %r12, %rcx
    call    libp2p_shell_poll_set
    inc     %r13
    inc     %r14
    jmp     51b
52: mov     %r12, %rdi
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
    jae     91f
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

    /* UDP sockets: their datagrams. */
91: xor     %r14d, %r14d
92: cmp     LIBP2P_SH_UDPS(%rbx), %r14
    jae     90f
    mov     L_S0(%rsp), %rdi
    add     LIBP2P_SH_CAPACITY(%rbx), %rdi
    add     %r14, %rdi
    mov     %r12, %rsi
    call    libp2p_shell_poll_events
    test    $(OS_POLLIN | OS_POLLHUP | OS_POLLERR), %eax
    jz      93f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    libp2p_shell_udp_read
93: inc     %r14
    jmp     92b
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
6:  xor     %ebp, %ebp                      /* UDP sockets */
61: cmp     LIBP2P_SH_UDPS(%rbx), %rbp
    jae     62f
    mov     LIBP2P_SH_UDP(%rbx,%rbp,8), %rdi
    OS_CLOSE
    inc     %rbp
    jmp     61b
62: movq    $0, LIBP2P_SH_UDPS(%rbx)
    OS_CLEANUP %rbx
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
 * libp2p_shell_clock(tick) -> status: the monotonic time in ms and in
 * microseconds, the Unix time in seconds, and 32 random bytes
 * (clock_gettime and getrandom); LIBP2P_OS_ERROR when one fails.
 * rbx tick, rbp bytes so far.
 */
FUNCTION libp2p_shell_clock
    SENTER  FRAME_BIG
    mov     %rdi, %rbx
    mov     $OS_CLOCK_MONOTONIC, %edi
    lea     L_SA(%rsp), %rsi
    SYSCALL SYS_CLOCK_GETTIME
    IF_ERROR_NEG 8f
    imul    $1000000, L_SA(%rsp), %rcx
    mov     (L_SA + 8)(%rsp), %rax
    xor     %edx, %edx
    mov     $1000, %r8d
    div     %r8
    add     %rcx, %rax
    mov     %rax, LIBP2P_TICK_US(%rbx)
    xor     %edx, %edx
    div     %r8
    mov     %rax, LIBP2P_TICK_NOW(%rbx)
    mov     $OS_CLOCK_REALTIME, %edi
    lea     L_SA(%rsp), %rsi
    SYSCALL SYS_CLOCK_GETTIME
    IF_ERROR_NEG 8f
    mov     L_SA(%rsp), %rax
    mov     %rax, LIBP2P_TICK_UNIX(%rbx)
    xor     %ebp, %ebp
1:  cmp     $32, %rbp
    jae     2f
    lea     LIBP2P_TICK_ENTROPY(%rbx,%rbp), %rdi
    mov     $32, %esi
    sub     %rbp, %rsi
    xor     %edx, %edx
    SYSCALL SYS_GETRANDOM
    IF_ERROR_NEG 8f
    add     %rax, %rbp
    jmp     1b
2:  xor     %eax, %eax
    jmp     9f
8:  mov     $LIBP2P_OS_ERROR, %eax
9:  SLEAVE  FRAME_BIG
END_FUNCTION libp2p_shell_clock
