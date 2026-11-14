/*
 * Wire helpers of the x86-64 core: unsigned varints (multiformats
 * unsigned-varint), protobuf fields, public keys and peer IDs (libp2p
 * peer-ids), DER signatures, identity signatures. Included by libp2p.s.
 */

/* ---------------------------------------------------------------- Varints */

/* libp2p_varint_put(dst, value) -> dst after the varint. A leaf. */
LOCAL_FUNCTION libp2p_varint_put
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
1:  cmp     $0x80, %rsi
    jb      2f
    mov     %esi, %ecx
    or      $0x80, %ecx
    movb    %cl, (%rax)
    inc     %rax
    shr     $7, %rsi
    jmp     1b
2:  movb    %sil, (%rax)
    inc     %rax
    ret
END_FUNCTION libp2p_varint_put

/* libp2p_varint_len(value) -> the bytes of its varint. A leaf. */
LOCAL_FUNCTION libp2p_varint_len
    UNWIND_END_PROLOGUE
    mov     $1, %eax
1:  cmp     $0x80, %rdi
    jb      2f
    shr     $7, %rdi
    inc     %rax
    jmp     1b
2:  ret
END_FUNCTION libp2p_varint_len

/*
 * libp2p_varint_get(src, end) -> rax the value, rdx the bytes it takes: 0 when
 * the bytes end first, NONE when it is longer than 10 bytes or 2^63 or more.
 * A leaf.
 */
LOCAL_FUNCTION libp2p_varint_get
    UNWIND_END_PROLOGUE
    xor     %r8d, %r8d                      /* value */
    xor     %ecx, %ecx                      /* shift */
    mov     %rdi, %r9
1:  cmp     %rsi, %r9
    jae     8f
    movzbl  (%r9), %r10d
    inc     %r9
    cmp     $64, %rcx
    jae     7f
    mov     %r10, %r11
    and     $0x7F, %r11
    mov     %r11, %rdx
    shl     %cl, %rdx
    mov     %rdx, %rax
    shr     %cl, %rax
    cmp     %r11, %rax
    jne     7f                              /* bits lost above 2^64 */
    or      %rdx, %r8
    add     $7, %rcx
    test    $0x80, %r10d
    jnz     1b
    test    %r8, %r8
    js      7f
    mov     %r9, %rdx
    sub     %rdi, %rdx
    mov     %r8, %rax
    ret
7:  xor     %eax, %eax
    mov     $NONE, %rdx
    ret
8:  xor     %eax, %eax
    xor     %edx, %edx
    ret
END_FUNCTION libp2p_varint_get

/* ---------------------------------------------------------------- Protobuf */

/*
 * libp2p_pb_next(p, end) -> rax: 1 for a field, 0 at the end, NONE when the
 * bytes are not well formed; rdx the field number, rcx the wire type, rsi
 * the value (varint, 32- or 64-bit) or the start of the bytes (type 2), rdi
 * the length of the bytes, r8 the position after the field.
 */
LOCAL_FUNCTION libp2p_pb_next
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    cmp     %rbp, %rbx
    jae     80f
    call    libp2p_varint_get                   /* the key */
    test    %rdx, %rdx
    jz      90f
    cmp     $NONE, %rdx
    je      90f
    add     %rdx, %rbx
    mov     %rax, %r12
    shr     $3, %r12
    mov     %rax, %r13
    and     $7, %r13
    test    %r12, %r12
    jz      90f
    test    %r13, %r13
    jnz     1f
    mov     %rbx, %rdi                      /* varint */
    mov     %rbp, %rsi
    call    libp2p_varint_get
    test    %rdx, %rdx
    jz      90f
    cmp     $NONE, %rdx
    je      90f
    mov     %rax, %rsi
    xor     %edi, %edi
    lea     (%rbx,%rdx), %r8
    jmp     70f
1:  cmp     $1, %r13
    jne     2f
    mov     %rbp, %rax                      /* 64-bit */
    sub     %rbx, %rax
    cmp     $8, %rax
    jb      90f
    mov     (%rbx), %rsi
    xor     %edi, %edi
    lea     8(%rbx), %r8
    jmp     70f
2:  cmp     $5, %r13
    jne     3f
    mov     %rbp, %rax                      /* 32-bit */
    sub     %rbx, %rax
    cmp     $4, %rax
    jb      90f
    movl    (%rbx), %esi
    xor     %edi, %edi
    lea     4(%rbx), %r8
    jmp     70f
3:  cmp     $2, %r13
    jne     90f
    mov     %rbx, %rdi                      /* length-delimited */
    mov     %rbp, %rsi
    call    libp2p_varint_get
    test    %rdx, %rdx
    jz      90f
    cmp     $NONE, %rdx
    je      90f
    lea     (%rbx,%rdx), %rsi
    mov     %rbp, %rcx
    sub     %rsi, %rcx
    cmp     %rcx, %rax
    ja      90f
    mov     %rax, %rdi
    lea     (%rsi,%rax), %r8
70: mov     $1, %eax
    mov     %r12, %rdx
    mov     %r13, %rcx
    jmp     99f
80: xor     %eax, %eax
    mov     %rbx, %r8
    jmp     99f
90: mov     $NONE, %rax
99: LEAVE   0
END_FUNCTION libp2p_pb_next

/* libp2p_pb_bytes(dst, field, src, n) -> dst after: the key of field with type 2, the length, the bytes. */
LOCAL_FUNCTION libp2p_pb_bytes
    ENTER   0
    mov     %rdx, %rbx
    mov     %rcx, %rbp
    shl     $3, %rsi
    or      $2, %rsi
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     %rbp, %rsi
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_pb_bytes

/* libp2p_pb_varint(dst, field, value) -> dst after: the key of field with type 0, then the value. */
LOCAL_FUNCTION libp2p_pb_varint
    ENTER   0
    mov     %rdx, %rbx
    shl     $3, %rsi
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     %rbx, %rsi
    call    libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_pb_varint

/* libp2p_pb_size(field, n) -> the bytes of a type 2 field of n bytes: key, length and bytes. */
LOCAL_FUNCTION libp2p_pb_size
    ENTER   0
    mov     %rsi, %rbx
    shl     $3, %rdi
    call    libp2p_varint_len
    mov     %rax, %rbp
    mov     %rbx, %rdi
    call    libp2p_varint_len
    add     %rbp, %rax
    add     %rbx, %rax
    LEAVE   0
END_FUNCTION libp2p_pb_size

/* ---------------------------------------------------------------- Keys and peer IDs */

/*
 * libp2p_key_proto(dst, type, key, n) -> dst after the PublicKey protobuf of
 * peer-ids: Type (field 1), then Data (field 2).
 */
LOCAL_FUNCTION libp2p_key_proto
    ENTER   0
    mov     %rdx, %rbx
    mov     %rcx, %rbp
    mov     %rsi, %rdx
    mov     $1, %esi
    call    libp2p_pb_varint
    mov     %rax, %rdi
    mov     $2, %esi
    mov     %rbx, %rdx
    mov     %rbp, %rcx
    call    libp2p_pb_bytes
    LEAVE   0
END_FUNCTION libp2p_key_proto

/*
 * libp2p_peer_id(dst, type, key, n) -> the length of the peer ID written at dst:
 * the identity multihash (0x00, length, the PublicKey protobuf). The
 * protobuf of a secp256k1 or Ed25519 key is at most 42 bytes.
 */
LOCAL_FUNCTION libp2p_peer_id
    ENTER   0
    mov     %rdi, %rbx
    add     $2, %rdi
    call    libp2p_key_proto
    mov     %rax, %rcx
    sub     %rbx, %rcx
    sub     $2, %rcx
    movb    $0, (%rbx)
    movb    %cl, 1(%rbx)
    sub     %rbx, %rax
    LEAVE   0
END_FUNCTION libp2p_peer_id

/* ---------------------------------------------------------------- DER signatures (secp256k1) */

/* libp2p_der_int(dst, src) -> dst after a DER INTEGER of the 32-byte big-endian number at src. */
LOCAL_FUNCTION libp2p_der_int
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     $32, %r12d
1:  cmp     $1, %r12                        /* drop leading zero bytes, keep one */
    jbe     2f
    cmpb    $0, (%rbp)
    jne     2f
    inc     %rbp
    dec     %r12
    jmp     1b
2:  movzbl  (%rbp), %eax
    shr     $7, %eax                        /* a 0x00 byte keeps the number positive */
    movb    $2, (%rbx)
    lea     (%r12,%rax), %rcx
    movb    %cl, 1(%rbx)
    lea     2(%rbx), %rdi
    test    %eax, %eax
    jz      3f
    movb    $0, (%rdi)
    inc     %rdi
3:  mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_der_int

/* libp2p_der_encode(dst, sig) -> the length of the DER SEQUENCE of r and s (64 bytes big endian at sig). */
LOCAL_FUNCTION libp2p_der_encode
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     2(%rbx), %rdi
    call    libp2p_der_int
    mov     %rax, %rdi
    lea     32(%rbp), %rsi
    call    libp2p_der_int
    mov     %rax, %rcx
    sub     %rbx, %rcx
    movb    $0x30, (%rbx)
    lea     -2(%rcx), %rdx
    movb    %dl, 1(%rbx)
    mov     %rcx, %rax
    LEAVE   0
END_FUNCTION libp2p_der_encode

/*
 * libp2p_der_get(dst, p, end) -> the position after a DER INTEGER at p, its
 * value written as 32 bytes big endian at dst; 0 when it is not a positive
 * INTEGER of at most 32 bytes of value.
 */
LOCAL_FUNCTION libp2p_der_get
    ENTER   0
    mov     %rdi, %rbx
    mov     %rdx, %rax
    sub     %rsi, %rax
    cmp     $2, %rax
    jb      8f
    cmpb    $2, (%rsi)
    jne     8f
    movzbl  1(%rsi), %ecx
    lea     2(%rsi), %rbp
    sub     $2, %rax
    cmp     %rax, %rcx
    ja      8f
    test    %rcx, %rcx
    jz      8f
    testb   $0x80, (%rbp)
    jnz     8f                              /* negative */
    lea     (%rbp,%rcx), %r12               /* the end of the integer */
1:  cmp     $32, %rcx                       /* leading zero bytes beyond 32 */
    jbe     2f
    cmpb    $0, (%rbp)
    jne     8f
    inc     %rbp
    dec     %rcx
    jmp     1b
2:  mov     %rcx, %r13
    mov     %rbx, %rdi
    mov     $32, %esi
    call    libp2p_zero
    mov     $32, %edi
    sub     %r13, %rdi
    add     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r13, %rdx
    call    libp2p_copy
    mov     %r12, %rax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_der_get

/*
 * libp2p_der_decode(sig, p, n) -> 1 when the n bytes at p are a DER SEQUENCE of
 * two positive INTEGERs r and s, written as 64 bytes big endian at sig;
 * else 0.
 */
LOCAL_FUNCTION libp2p_der_decode
    ENTER   0
    mov     %rdi, %rbx
    lea     (%rsi,%rdx), %rbp               /* end */
    cmp     $8, %rdx
    jb      8f
    cmpb    $0x30, (%rsi)
    jne     8f
    movzbl  1(%rsi), %eax
    lea     -2(%rdx), %rcx
    cmp     %rcx, %rax
    jne     8f
    add     $2, %rsi
    mov     %rbx, %rdi
    mov     %rbp, %rdx
    call    libp2p_der_get
    test    %rax, %rax
    jz      8f
    mov     %rax, %rsi
    lea     32(%rbx), %rdi
    mov     %rbp, %rdx
    call    libp2p_der_get
    cmp     %rbp, %rax
    jne     8f
    mov     $1, %eax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_der_decode

/* ---------------------------------------------------------------- Identity signatures */

/* "noise-libp2p-static-key:": the prefix of the message an identity key signs in Noise. */
    .p2align 3
400:
    .ascii  "noise-libp2p-static-key:"
.set NOISE_SIG_PREFIX, 24

/*
 * libp2p_sign_static(): signs "noise-libp2p-static-key:" || the static X25519
 * key with the identity key, and stores the signature and the handshake
 * payload in the state: an Ed25519 signature, or the DER form of a
 * low-s ECDSA secp256k1 signature of the SHA-256 of the message.
 * Work: the extra area at rbx.
 */
.set SS_MSG, 0                          /* ByteList: 24 + 56 bytes */
.set SS_HASH, 80                        /* 32 bytes */
.set SS_SIG, 112                        /* 64 bytes */
LOCAL_FUNCTION libp2p_sign_static
    ENTER   0, 192
    lea     32(%rsp), %rbx
    movq    $80, SS_MSG(%rbx)
    movq    $LIBP2P_BL_FIXED, (SS_MSG + 8)(%rbx)
    movq    $56, (SS_MSG + 16)(%rbx)
    lea     (SS_MSG + 24)(%rbx), %rdi
    lea     400b(%rip), %rsi
    mov     $NOISE_SIG_PREFIX, %edx
    call    libp2p_copy
    mov     %rax, %rdi
    lea     ST_NOISE_PUB(%r15), %rsi
    mov     $32, %edx
    call    libp2p_copy
    cmpq    $LIBP2P_KEY_ED25519, ST_KEY_TYPE(%r15)
    jne     1f
    lea     ST_PRIVATE_KEY(%r15), %rdi
    lea     SS_MSG(%rbx), %rsi
    lea     ST_NOISE_SIG(%r15), %rdx
    CALL_GLOBAL crypto_ed25519_sign
    movq    $64, ST_NOISE_SIG_LEN(%r15)
    jmp     2f
1:  lea     SS_MSG(%rbx), %rdi
    lea     SS_HASH(%rbx), %rsi
    CALL_GLOBAL crypto_sha256
    lea     ST_PRIVATE_KEY(%r15), %rdi
    lea     SS_HASH(%rbx), %rsi
    lea     SS_SIG(%rbx), %rdx
    CALL_GLOBAL crypto_secp256k1_sign
    lea     ST_NOISE_SIG(%r15), %rdi
    lea     SS_SIG(%rbx), %rsi
    call    libp2p_der_encode
    mov     %rax, ST_NOISE_SIG_LEN(%r15)
2:  lea     ST_PAYLOAD(%r15), %rbp          /* NoiseHandshakePayload: identity_key, identity_sig */
    lea     2(%rbp), %rdi                   /* the PublicKey protobuf at payload + 2 */
    mov     ST_KEY_TYPE(%r15), %rsi
    lea     ST_PUBLIC_KEY(%r15), %rdx
    mov     ST_PUBLIC_LEN(%r15), %rcx
    call    libp2p_key_proto
    mov     %rax, %rcx
    sub     %rbp, %rcx
    sub     $2, %rcx
    movb    $0x0A, (%rbp)
    movb    %cl, 1(%rbp)
    mov     %rax, %rdi
    mov     $2, %esi
    lea     ST_NOISE_SIG(%r15), %rdx
    mov     ST_NOISE_SIG_LEN(%r15), %rcx
    call    libp2p_pb_bytes
    sub     %rbp, %rax
    mov     %rax, ST_PAYLOAD_LEN(%r15)
    LEAVE   0, 192
END_FUNCTION libp2p_sign_static

/*
 * libp2p_verify_static(type, key, key length, sig, sig length, static key)
 * -> 1 when sig is a valid identity signature of
 * "noise-libp2p-static-key:" || the 32-byte static key, by the key of the
 * type; else 0. A secp256k1 s above n / 2 is taken as n - s.
 * rbx type, rbp key, r12 key length, r13 sig; X23 sig length, X24 static key.
 * Work: the extra area at 32(%rsp), VS offsets.
 */
.set VS_MSG, 0                          /* ByteList: 24 + 56 bytes */
.set VS_HASH, 80
.set VS_SIG, 112                        /* 64 bytes */
.set VS_VALID, 176
.set VS_KEY, 184                        /* 40 bytes */
LOCAL_FUNCTION libp2p_verify_static
    ENTER   0, 224
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, X23(%rsp)
    mov     %r9, X24(%rsp)
    movq    $80, (32 + VS_MSG)(%rsp)
    movq    $LIBP2P_BL_FIXED, (32 + VS_MSG + 8)(%rsp)
    movq    $56, (32 + VS_MSG + 16)(%rsp)
    lea     (32 + VS_MSG + 24)(%rsp), %rdi
    lea     400b(%rip), %rsi
    mov     $NOISE_SIG_PREFIX, %edx
    call    libp2p_copy
    mov     %rax, %rdi
    mov     X24(%rsp), %rsi
    mov     $32, %edx
    call    libp2p_copy
    lea     (32 + VS_KEY)(%rsp), %rdi       /* the key, aligned */
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    cmp     $LIBP2P_KEY_ED25519, %rbx
    jne     1f
    cmp     $32, %r12
    jne     8f
    cmpq    $64, X23(%rsp)
    jne     8f
    lea     (32 + VS_SIG)(%rsp), %rdi
    mov     %r13, %rsi
    mov     $64, %edx
    call    libp2p_copy
    lea     (32 + VS_KEY)(%rsp), %rdi
    lea     (32 + VS_MSG)(%rsp), %rsi
    lea     (32 + VS_SIG)(%rsp), %rdx
    lea     (32 + VS_VALID)(%rsp), %rcx
    CALL_GLOBAL crypto_ed25519_verify
    test    %rax, %rax
    jnz     8f
    mov     (32 + VS_VALID)(%rsp), %rax
    jmp     9f
1:  cmp     $LIBP2P_KEY_SECP256K1, %rbx
    jne     8f
    cmp     $33, %r12
    jne     8f
    lea     (32 + VS_SIG)(%rsp), %rdi
    mov     %r13, %rsi
    mov     X23(%rsp), %rdx
    call    libp2p_der_decode
    test    %rax, %rax
    jz      8f
    lea     (32 + VS_SIG + 32)(%rsp), %rdi
    call    libp2p_low_s
    lea     (32 + VS_MSG)(%rsp), %rdi
    lea     (32 + VS_HASH)(%rsp), %rsi
    CALL_GLOBAL crypto_sha256
    lea     (32 + VS_KEY)(%rsp), %rdi
    lea     (32 + VS_HASH)(%rsp), %rsi
    lea     (32 + VS_SIG)(%rsp), %rdx
    lea     (32 + VS_VALID)(%rsp), %rcx
    CALL_GLOBAL crypto_secp256k1_verify
    test    %rax, %rax
    jnz     8f
    mov     (32 + VS_VALID)(%rsp), %rax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0, 224
END_FUNCTION libp2p_verify_static

/*
 * libp2p_low_s(s): when the 32-byte big-endian s is above n / 2 of secp256k1,
 * replaces it with n - s. A leaf. rax, rcx, rdx, rsi: s as big-endian limbs,
 * most significant first.
 */
LOCAL_FUNCTION libp2p_low_s
    UNWIND_END_PROLOGUE
    mov     (%rdi), %rax
    bswap   %rax
    mov     8(%rdi), %rcx
    bswap   %rcx
    mov     16(%rdi), %rdx
    bswap   %rdx
    mov     24(%rdi), %rsi
    bswap   %rsi
    lea     410f(%rip), %r8                 /* n / 2 */
    cmp     (%r8), %rax                     /* s > n / 2, most significant limb first */
    ja      1f
    jb      9f
    cmp     8(%r8), %rcx
    ja      1f
    jb      9f
    cmp     16(%r8), %rdx
    ja      1f
    jb      9f
    cmp     24(%r8), %rsi
    jbe     9f
1:  mov     56(%r8), %r11                   /* n - s */
    sub     %rsi, %r11
    mov     48(%r8), %r10
    sbb     %rdx, %r10
    mov     40(%r8), %r9
    sbb     %rcx, %r9
    mov     32(%r8), %r8
    sbb     %rax, %r8
    bswap   %r8
    bswap   %r9
    bswap   %r10
    bswap   %r11
    mov     %r8, (%rdi)
    mov     %r9, 8(%rdi)
    mov     %r10, 16(%rdi)
    mov     %r11, 24(%rdi)
9:  ret
END_FUNCTION libp2p_low_s

    .p2align 3
/* n / 2, then n, of secp256k1: big-endian limbs, most significant first. */
410:
    .quad   0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0x5D576E7357A4501D, 0xDFE92F46681B20A0
    .quad   0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFE, 0xBAAEDCE6AF48A03B, 0xBFD25E8CD0364141
