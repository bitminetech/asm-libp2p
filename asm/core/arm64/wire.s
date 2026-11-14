/*
 * Wire helpers of the ARM64 core: unsigned varints (multiformats
 * unsigned-varint), protobuf fields, public keys and peer IDs (libp2p
 * peer-ids), DER signatures, identity signatures. Included by libp2p.s.
 */

/* ---------------------------------------------------------------- Varints */

/* libp2p_varint_put(dst, value) -> dst after the varint. A leaf. */
LOCAL_FUNCTION libp2p_varint_put
    UNWIND_END_PROLOGUE
1:  cmp     x1, #0x80
    b.lo    2f
    orr     x2, x1, #0x80
    strb    w2, [x0], #1
    lsr     x1, x1, #7
    b       1b
2:  strb    w1, [x0], #1
    ret
END_FUNCTION libp2p_varint_put

/* libp2p_varint_len(value) -> the bytes of its varint. A leaf. */
LOCAL_FUNCTION libp2p_varint_len
    UNWIND_END_PROLOGUE
    mov     x1, #1
1:  cmp     x0, #0x80
    b.lo    2f
    lsr     x0, x0, #7
    add     x1, x1, #1
    b       1b
2:  mov     x0, x1
    ret
END_FUNCTION libp2p_varint_len

/*
 * libp2p_varint_get(src, end) -> x0 the value, x1 the bytes it takes: 0 when
 * the bytes end first, NONE when it is longer than 10 bytes or 2^63 or more.
 * A leaf.
 */
LOCAL_FUNCTION libp2p_varint_get
    UNWIND_END_PROLOGUE
    mov     x2, #0                          /* value */
    mov     x3, #0                          /* shift */
    mov     x4, x0
1:  cmp     x4, x1
    b.hs    8f
    ldrb    w5, [x4], #1
    cmp     x3, #64
    b.hs    7f
    and     x6, x5, #0x7F
    lsl     x7, x6, x3
    lsr     x9, x7, x3
    cmp     x9, x6
    b.ne    7f                              /* bits lost above 2^64 */
    orr     x2, x2, x7
    add     x3, x3, #7
    tbnz    w5, #7, 1b
    tbnz    x2, #63, 7f
    sub     x1, x4, x0
    mov     x0, x2
    ret
7:  mov     x0, #0
    mov     x1, #NONE
    ret
8:  mov     x0, #0
    mov     x1, #0
    ret
END_FUNCTION libp2p_varint_get

/* ---------------------------------------------------------------- Protobuf */

/*
 * libp2p_pb_next(p, end) -> x0: 1 for a field, 0 at the end, NONE when the bytes
 * are not well formed; x1 the field number, x2 the wire type, x3 the value
 * (varint, 32- or 64-bit) or the start of the bytes (type 2), x4 the length
 * of the bytes, x5 the position after the field.
 */
LOCAL_FUNCTION libp2p_pb_next
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    cmp     x19, x20
    b.hs    80f
    bl      libp2p_varint_get                   /* the key */
    cbz     x1, 90f
    cmn     x1, #1
    b.eq    90f
    add     x19, x19, x1
    lsr     x21, x0, #3
    and     x22, x0, #7
    cbz     x21, 90f
    cmp     x22, #0
    b.ne    1f
    mov     x0, x19                         /* varint */
    mov     x1, x20
    bl      libp2p_varint_get
    cbz     x1, 90f
    cmn     x1, #1
    b.eq    90f
    mov     x3, x0
    mov     x4, #0
    add     x5, x19, x1
    b       70f
1:  cmp     x22, #1
    b.ne    2f
    sub     x9, x20, x19                    /* 64-bit */
    cmp     x9, #8
    b.lo    90f
    ldr     x3, [x19]
    mov     x4, #0
    add     x5, x19, #8
    b       70f
2:  cmp     x22, #5
    b.ne    3f
    sub     x9, x20, x19                    /* 32-bit */
    cmp     x9, #4
    b.lo    90f
    ldr     w3, [x19]
    mov     x4, #0
    add     x5, x19, #4
    b       70f
3:  cmp     x22, #2
    b.ne    90f
    mov     x0, x19                         /* length-delimited */
    mov     x1, x20
    bl      libp2p_varint_get
    cbz     x1, 90f
    cmn     x1, #1
    b.eq    90f
    add     x3, x19, x1
    sub     x9, x20, x3
    cmp     x0, x9
    b.hi    90f
    mov     x4, x0
    add     x5, x3, x0
70: mov     x0, #1
    mov     x1, x21
    mov     x2, x22
    b       99f
80: mov     x0, #0
    mov     x5, x19
    b       99f
90: mov     x0, #NONE
99: LEAVE   0
END_FUNCTION libp2p_pb_next

/* libp2p_pb_bytes(dst, field, src, n) -> dst after: the key of field with type 2, the length, the bytes. */
LOCAL_FUNCTION libp2p_pb_bytes
    ENTER   0
    mov     x19, x2
    mov     x20, x3
    lsl     x1, x1, #3
    orr     x1, x1, #2
    bl      libp2p_varint_put
    mov     x1, x20
    bl      libp2p_varint_put
    mov     x1, x19
    mov     x2, x20
    bl      libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_pb_bytes

/* libp2p_pb_varint(dst, field, value) -> dst after: the key of field with type 0, then the value. */
LOCAL_FUNCTION libp2p_pb_varint
    ENTER   0
    mov     x19, x2
    lsl     x1, x1, #3
    bl      libp2p_varint_put
    mov     x1, x19
    bl      libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_pb_varint

/* libp2p_pb_size(field, n) -> the bytes of a type 2 field of n bytes: key, length and bytes. */
LOCAL_FUNCTION libp2p_pb_size
    ENTER   0
    mov     x19, x1
    lsl     x0, x0, #3
    bl      libp2p_varint_len
    mov     x20, x0
    mov     x0, x19
    bl      libp2p_varint_len
    add     x0, x0, x20
    add     x0, x0, x19
    LEAVE   0
END_FUNCTION libp2p_pb_size

/* ---------------------------------------------------------------- Keys and peer IDs */

/*
 * libp2p_key_proto(dst, type, key, n) -> dst after the PublicKey protobuf of
 * peer-ids: Type (field 1), then Data (field 2).
 */
LOCAL_FUNCTION libp2p_key_proto
    ENTER   0
    mov     x19, x2
    mov     x20, x3
    mov     x2, x1
    mov     x1, #1
    bl      libp2p_pb_varint
    mov     x1, #2
    mov     x2, x19
    mov     x3, x20
    bl      libp2p_pb_bytes
    LEAVE   0
END_FUNCTION libp2p_key_proto

/*
 * libp2p_peer_id(dst, type, key, n) -> the length of the peer ID written at dst:
 * the identity multihash (0x00, length, the PublicKey protobuf). The
 * protobuf of a secp256k1 or Ed25519 key is at most 42 bytes.
 */
LOCAL_FUNCTION libp2p_peer_id
    ENTER   0
    mov     x19, x0
    add     x0, x0, #2
    bl      libp2p_key_proto
    sub     x9, x0, x19
    sub     x9, x9, #2
    strb    wzr, [x19]
    strb    w9, [x19, #1]
    sub     x0, x0, x19
    LEAVE   0
END_FUNCTION libp2p_peer_id

/* ---------------------------------------------------------------- DER signatures (secp256k1) */

/* libp2p_der_int(dst, src) -> dst after a DER INTEGER of the 32-byte big-endian number at src. */
LOCAL_FUNCTION libp2p_der_int
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, #32
1:  cmp     x21, #1                         /* drop leading zero bytes, keep one */
    b.ls    2f
    ldrb    w9, [x20]
    cbnz    w9, 2f
    add     x20, x20, #1
    sub     x21, x21, #1
    b       1b
2:  ldrb    w9, [x20]
    lsr     w10, w9, #7                     /* a 0x00 byte keeps the number positive */
    mov     w11, #2
    strb    w11, [x19]
    add     w12, w21, w10
    strb    w12, [x19, #1]
    add     x0, x19, #2
    cbz     w10, 3f
    strb    wzr, [x0], #1
3:  mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_der_int

/* libp2p_der_encode(dst, sig) -> the length of the DER SEQUENCE of r and s (64 bytes big endian at sig). */
LOCAL_FUNCTION libp2p_der_encode
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    add     x0, x19, #2
    bl      libp2p_der_int
    add     x1, x20, #32
    bl      libp2p_der_int
    sub     x9, x0, x19
    mov     w10, #0x30
    strb    w10, [x19]
    sub     w11, w9, #2
    strb    w11, [x19, #1]
    mov     x0, x9
    LEAVE   0
END_FUNCTION libp2p_der_encode

/*
 * libp2p_der_get(dst, p, end) -> the position after a DER INTEGER at p, its
 * value written as 32 bytes big endian at dst; 0 when it is not a positive
 * INTEGER of at most 32 bytes of value.
 */
LOCAL_FUNCTION libp2p_der_get
    ENTER   0
    mov     x19, x0
    sub     x9, x2, x1
    cmp     x9, #2
    b.lo    8f
    ldrb    w10, [x1]
    cmp     w10, #2
    b.ne    8f
    ldrb    w11, [x1, #1]
    add     x20, x1, #2
    sub     x9, x9, #2
    cmp     x11, x9
    b.hi    8f
    cbz     x11, 8f
    ldrb    w12, [x20]
    tbnz    w12, #7, 8f                     /* negative */
    add     x21, x20, x11                   /* the end of the integer */
1:  cmp     x11, #32                        /* leading zero bytes beyond 32 */
    b.ls    2f
    ldrb    w12, [x20]
    cbnz    w12, 8f
    add     x20, x20, #1
    sub     x11, x11, #1
    b       1b
2:  mov     x22, x11
    mov     x0, x19
    mov     x1, #32
    bl      libp2p_zero
    mov     x9, #32
    sub     x9, x9, x22
    add     x0, x19, x9
    mov     x1, x20
    mov     x2, x22
    bl      libp2p_copy
    mov     x0, x21
    b       9f
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_der_get

/*
 * libp2p_der_decode(sig, p, n) -> 1 when the n bytes at p are a DER SEQUENCE of
 * two positive INTEGERs r and s, written as 64 bytes big endian at sig;
 * else 0.
 */
LOCAL_FUNCTION libp2p_der_decode
    ENTER   0
    mov     x19, x0
    add     x20, x1, x2                     /* end */
    cmp     x2, #8
    b.lo    8f
    ldrb    w9, [x1]
    cmp     w9, #0x30
    b.ne    8f
    ldrb    w10, [x1, #1]
    sub     x11, x2, #2
    cmp     x10, x11
    b.ne    8f
    add     x1, x1, #2
    mov     x0, x19
    mov     x2, x20
    bl      libp2p_der_get
    cbz     x0, 8f
    mov     x1, x0
    add     x0, x19, #32
    mov     x2, x20
    bl      libp2p_der_get
    cmp     x0, x20
    b.ne    8f
    mov     x0, #1
    b       9f
8:  mov     x0, #0
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
 * Work: the scratch work area at x19.
 */
.set SS_MSG, 0                          /* ByteList: 24 + 56 bytes */
.set SS_HASH, 80                        /* 32 bytes */
.set SS_SIG, 112                        /* 64 bytes */
LOCAL_FUNCTION libp2p_sign_static
    ENTER   0, 192
    mov     x19, sp
    mov     x9, #80
    mov     x10, #56
    str     x9, [x19, #SS_MSG]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x19, #SS_MSG + 8]
    str     x10, [x19, #SS_MSG + 16]
    add     x0, x19, #SS_MSG + 24
    adr     x1, 400b
    mov     x2, #NOISE_SIG_PREFIX
    bl      libp2p_copy
    add     x1, x27, #ST_NOISE_PUB
    mov     x2, #32
    bl      libp2p_copy
    ldr     x9, [x27, #ST_KEY_TYPE]
    cmp     x9, #LIBP2P_KEY_ED25519
    b.ne    1f
    add     x0, x27, #ST_PRIVATE_KEY
    add     x1, x19, #SS_MSG
    add     x2, x27, #ST_NOISE_SIG
    CALL_GLOBAL crypto_ed25519_sign
    mov     x9, #64
    str     x9, [x27, #ST_NOISE_SIG_LEN]
    b       2f
1:  add     x0, x19, #SS_MSG
    add     x1, x19, #SS_HASH
    CALL_GLOBAL crypto_sha256
    add     x0, x27, #ST_PRIVATE_KEY
    add     x1, x19, #SS_HASH
    add     x2, x19, #SS_SIG
    CALL_GLOBAL crypto_secp256k1_sign
    add     x0, x27, #ST_NOISE_SIG
    add     x1, x19, #SS_SIG
    bl      libp2p_der_encode
    str     x0, [x27, #ST_NOISE_SIG_LEN]
2:  add     x0, x27, #ST_PAYLOAD            /* NoiseHandshakePayload: identity_key, identity_sig */
    mov     x20, x0
    add     x0, x0, #2                      /* the PublicKey protobuf at payload + 2 */
    ldr     x1, [x27, #ST_KEY_TYPE]
    add     x2, x27, #ST_PUBLIC_KEY
    ldr     x3, [x27, #ST_PUBLIC_LEN]
    bl      libp2p_key_proto
    sub     x9, x0, x20
    sub     x9, x9, #2
    mov     w10, #0x0A
    strb    w10, [x20]
    strb    w9, [x20, #1]
    mov     x1, #2
    add     x2, x27, #ST_NOISE_SIG
    ldr     x3, [x27, #ST_NOISE_SIG_LEN]
    bl      libp2p_pb_bytes
    sub     x0, x0, x20
    str     x0, [x27, #ST_PAYLOAD_LEN]
    LEAVE   0, 192
END_FUNCTION libp2p_sign_static

/*
 * libp2p_verify_static(type, key, key length, sig, sig length, static key)
 * -> 1 when sig is a valid identity signature of
 * "noise-libp2p-static-key:" || the 32-byte static key, by the key of the
 * type; else 0. A secp256k1 s above n / 2 is taken as n - s.
 */
.set VS_MSG, 0                          /* ByteList: 24 + 56 bytes */
.set VS_HASH, 80
.set VS_SIG, 112                        /* 64 bytes */
.set VS_VALID, 176
.set VS_KEY, 184                        /* 40 bytes */
LOCAL_FUNCTION libp2p_verify_static
    ENTER   0, 224
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x9, #80
    str     x9, [sp, #VS_MSG]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [sp, #VS_MSG + 8]
    mov     x9, #56
    str     x9, [sp, #VS_MSG + 16]
    add     x0, sp, #VS_MSG + 24
    adr     x1, 400b
    mov     x2, #NOISE_SIG_PREFIX
    bl      libp2p_copy
    mov     x1, x24
    mov     x2, #32
    bl      libp2p_copy
    add     x0, sp, #VS_KEY                 /* the key, aligned */
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    cmp     x19, #LIBP2P_KEY_ED25519
    b.ne    1f
    cmp     x21, #32
    b.ne    8f
    cmp     x23, #64
    b.ne    8f
    add     x0, sp, #VS_SIG
    mov     x1, x22
    mov     x2, #64
    bl      libp2p_copy
    add     x0, sp, #VS_KEY
    add     x1, sp, #VS_MSG
    add     x2, sp, #VS_SIG
    add     x3, sp, #VS_VALID
    CALL_GLOBAL crypto_ed25519_verify
    cbnz    x0, 8f
    ldr     x0, [sp, #VS_VALID]
    b       9f
1:  cmp     x19, #LIBP2P_KEY_SECP256K1
    b.ne    8f
    cmp     x21, #33
    b.ne    8f
    add     x0, sp, #VS_SIG
    mov     x1, x22
    mov     x2, x23
    bl      libp2p_der_decode
    cbz     x0, 8f
    add     x0, sp, #VS_SIG + 32
    bl      libp2p_low_s
    add     x0, sp, #VS_MSG
    add     x1, sp, #VS_HASH
    CALL_GLOBAL crypto_sha256
    add     x0, sp, #VS_KEY
    add     x1, sp, #VS_HASH
    add     x2, sp, #VS_SIG
    add     x3, sp, #VS_VALID
    CALL_GLOBAL crypto_secp256k1_verify
    cbnz    x0, 8f
    ldr     x0, [sp, #VS_VALID]
    b       9f
8:  mov     x0, #0
9:  LEAVE   0, 224
END_FUNCTION libp2p_verify_static

/*
 * libp2p_low_s(s): when the 32-byte big-endian s is above n / 2 of secp256k1,
 * replaces it with n - s. A leaf. x2 to x5 s as big-endian limbs, most
 * significant first.
 */
LOCAL_FUNCTION libp2p_low_s
    UNWIND_END_PROLOGUE
    ldp     x2, x3, [x0]
    ldp     x4, x5, [x0, #16]
    rev     x2, x2
    rev     x3, x3
    rev     x4, x4
    rev     x5, x5
    adr     x6, 410f                        /* n / 2 */
    ldp     x7, x8, [x6]
    ldp     x9, x10, [x6, #16]
    cmp     x2, x7                          /* s > n / 2, most significant limb first */
    b.hi    1f
    b.lo    9f
    cmp     x3, x8
    b.hi    1f
    b.lo    9f
    cmp     x4, x9
    b.hi    1f
    b.lo    9f
    cmp     x5, x10
    b.ls    9f
1:  ldp     x7, x8, [x6, #32]               /* n */
    ldp     x9, x10, [x6, #48]
    subs    x10, x10, x5
    sbcs    x9, x9, x4
    sbcs    x8, x8, x3
    sbc     x7, x7, x2
    rev     x7, x7
    rev     x8, x8
    rev     x9, x9
    rev     x10, x10
    stp     x7, x8, [x0]
    stp     x9, x10, [x0, #16]
9:  ret
END_FUNCTION libp2p_low_s

    .p2align 3
/* n / 2, then n, of secp256k1: big-endian limbs, most significant first. */
410:
    .quad   0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0x5D576E7357A4501D, 0xDFE92F46681B20A0
    .quad   0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFE, 0xBAAEDCE6AF48A03B, 0xBFD25E8CD0364141
