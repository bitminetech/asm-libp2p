/*
 * Wire helpers of the RISC-V core: unsigned varints (multiformats
 * unsigned-varint), protobuf fields, public keys and peer IDs (libp2p
 * peer-ids), DER signatures, identity signatures. Included by libp2p.s.
 */

/* rd = the 8 bytes at base + off, big endian. Uses tmp. */
.macro BE64 rd, base, off, tmp
    li      \rd, 0
    .irp i, 0, 1, 2, 3, 4, 5, 6, 7
    lbu     \tmp, (\off + \i)(\base)
    slli    \rd, \rd, 8
    or      \rd, \rd, \tmp
    .endr
.endm

/* The 8 bytes at base + off = rs, big endian. Uses tmp. */
.macro STBE rs, base, off, tmp
    .irp i, 0, 1, 2, 3, 4, 5, 6, 7
    srli    \tmp, \rs, (56 - 8 * \i)
    sb      \tmp, (\off + \i)(\base)
    .endr
.endm

/* rd = the n (1 to 8) bytes at base, little endian. Uses tmp and idx. */
.macro LE64 rd, base, n, tmp, idx
    li      \rd, 0
    li      \idx, (\n - 1)
1000:
    add     \tmp, \base, \idx
    lbu     \tmp, 0(\tmp)
    slli    \rd, \rd, 8
    or      \rd, \rd, \tmp
    addi    \idx, \idx, -1
    bgez    \idx, 1000b
.endm

/* ---------------------------------------------------------------- Varints */

/* libp2p_varint_put(dst, value) -> dst after the varint. A leaf. */
LOCAL_FUNCTION libp2p_varint_put
    UNWIND_END_PROLOGUE
    li      a2, 0x80
1:  bltu    a1, a2, 2f
    ori     a3, a1, 0x80
    sb      a3, 0(a0)
    addi    a0, a0, 1
    srli    a1, a1, 7
    j       1b
2:  sb      a1, 0(a0)
    addi    a0, a0, 1
    ret
END_FUNCTION libp2p_varint_put

/* libp2p_varint_len(value) -> the bytes of its varint. A leaf. */
LOCAL_FUNCTION libp2p_varint_len
    UNWIND_END_PROLOGUE
    li      a1, 1
    li      a2, 0x80
1:  bltu    a0, a2, 2f
    srli    a0, a0, 7
    addi    a1, a1, 1
    j       1b
2:  mv      a0, a1
    ret
END_FUNCTION libp2p_varint_len

/*
 * libp2p_varint_get(src, end) -> a0 the value, a1 the bytes it takes: 0 when
 * the bytes end first, NONE when it is longer than 10 bytes or 2^63 or more.
 * A leaf.
 */
LOCAL_FUNCTION libp2p_varint_get
    UNWIND_END_PROLOGUE
    li      a2, 0                           # value
    li      a3, 0                           # shift
    mv      a4, a0
1:  bgeu    a4, a1, 8f
    lbu     a5, 0(a4)
    addi    a4, a4, 1
    li      a6, 64
    bgeu    a3, a6, 7f
    andi    a6, a5, 0x7F
    sll     a7, a6, a3
    srl     t0, a7, a3
    bne     t0, a6, 7f                      # bits lost above 2^64
    or      a2, a2, a7
    addi    a3, a3, 7
    andi    t0, a5, 0x80
    bnez    t0, 1b
    bltz    a2, 7f
    sub     a1, a4, a0
    mv      a0, a2
    ret
7:  li      a0, 0
    li      a1, NONE
    ret
8:  li      a0, 0
    li      a1, 0
    ret
END_FUNCTION libp2p_varint_get

/* ---------------------------------------------------------------- Protobuf */

/*
 * libp2p_pb_next(p, end) -> a0: 1 for a field, 0 at the end, NONE when the bytes
 * are not well formed; a1 the field number, a2 the wire type, a3 the value
 * (varint, 32- or 64-bit) or the start of the bytes (type 2), a4 the length
 * of the bytes, a5 the position after the field.
 */
LOCAL_FUNCTION libp2p_pb_next
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    bgeu    s1, s2, 80f
    call    libp2p_varint_get                   # the key
    beqz    a1, 90f
    li      t0, NONE
    beq     a1, t0, 90f
    add     s1, s1, a1
    srli    s3, a0, 3
    andi    s4, a0, 7
    beqz    s3, 90f
    bnez    s4, 1f
    mv      a0, s1                          # varint
    mv      a1, s2
    call    libp2p_varint_get
    beqz    a1, 90f
    li      t0, NONE
    beq     a1, t0, 90f
    mv      a3, a0
    li      a4, 0
    add     a5, s1, a1
    j       70f
1:  li      t0, 1
    bne     s4, t0, 2f
    sub     t0, s2, s1                      # 64-bit
    li      t1, 8
    bltu    t0, t1, 90f
    LE64    a3, s1, 8, t2, t1
    li      a4, 0
    addi    a5, s1, 8
    j       70f
2:  li      t0, 5
    bne     s4, t0, 3f
    sub     t0, s2, s1                      # 32-bit
    li      t1, 4
    bltu    t0, t1, 90f
    LE64    a3, s1, 4, t2, t1
    li      a4, 0
    addi    a5, s1, 4
    j       70f
3:  li      t0, 2
    bne     s4, t0, 90f
    mv      a0, s1                          # length-delimited
    mv      a1, s2
    call    libp2p_varint_get
    beqz    a1, 90f
    li      t0, NONE
    beq     a1, t0, 90f
    add     a3, s1, a1
    sub     t0, s2, a3
    bltu    t0, a0, 90f
    mv      a4, a0
    add     a5, a3, a0
70: li      a0, 1
    mv      a1, s3
    mv      a2, s4
    j       99f
80: li      a0, 0
    mv      a5, s1
    j       99f
90: li      a0, NONE
99: LEAVE   0
END_FUNCTION libp2p_pb_next

/* libp2p_pb_bytes(dst, field, src, n) -> dst after: the key of field with type 2, the length, the bytes. */
LOCAL_FUNCTION libp2p_pb_bytes
    ENTER   0
    mv      s1, a2
    mv      s2, a3
    slli    a1, a1, 3
    ori     a1, a1, 2
    call    libp2p_varint_put
    mv      a1, s2
    call    libp2p_varint_put
    mv      a1, s1
    mv      a2, s2
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_pb_bytes

/* libp2p_pb_varint(dst, field, value) -> dst after: the key of field with type 0, then the value. */
LOCAL_FUNCTION libp2p_pb_varint
    ENTER   0
    mv      s1, a2
    slli    a1, a1, 3
    call    libp2p_varint_put
    mv      a1, s1
    call    libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_pb_varint

/* libp2p_pb_size(field, n) -> the bytes of a type 2 field of n bytes: key, length and bytes. */
LOCAL_FUNCTION libp2p_pb_size
    ENTER   0
    mv      s1, a1
    slli    a0, a0, 3
    call    libp2p_varint_len
    mv      s2, a0
    mv      a0, s1
    call    libp2p_varint_len
    add     a0, a0, s2
    add     a0, a0, s1
    LEAVE   0
END_FUNCTION libp2p_pb_size

/* ---------------------------------------------------------------- Keys and peer IDs */

/*
 * libp2p_key_proto(dst, type, key, n) -> dst after the PublicKey protobuf of
 * peer-ids: Type (field 1), then Data (field 2).
 */
LOCAL_FUNCTION libp2p_key_proto
    ENTER   0
    mv      s1, a2
    mv      s2, a3
    mv      a2, a1
    li      a1, 1
    call    libp2p_pb_varint
    li      a1, 2
    mv      a2, s1
    mv      a3, s2
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
    mv      s1, a0
    addi    a0, a0, 2
    call    libp2p_key_proto
    sub     t0, a0, s1
    addi    t0, t0, -2
    sb      zero, 0(s1)
    sb      t0, 1(s1)
    sub     a0, a0, s1
    LEAVE   0
END_FUNCTION libp2p_peer_id

/* ---------------------------------------------------------------- DER signatures (secp256k1) */

/* libp2p_der_int(dst, src) -> dst after a DER INTEGER of the 32-byte big-endian number at src. */
LOCAL_FUNCTION libp2p_der_int
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    li      s3, 32
1:  li      t0, 1                           # drop leading zero bytes, keep one
    bgeu    t0, s3, 2f
    lbu     t0, 0(s2)
    bnez    t0, 2f
    addi    s2, s2, 1
    addi    s3, s3, -1
    j       1b
2:  lbu     t0, 0(s2)
    srli    t1, t0, 7                       # a 0x00 byte keeps the number positive
    li      t2, 2
    sb      t2, 0(s1)
    add     t2, s3, t1
    sb      t2, 1(s1)
    addi    a0, s1, 2
    beqz    t1, 3f
    sb      zero, 0(a0)
    addi    a0, a0, 1
3:  mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_der_int

/* libp2p_der_encode(dst, sig) -> the length of the DER SEQUENCE of r and s (64 bytes big endian at sig). */
LOCAL_FUNCTION libp2p_der_encode
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    addi    a0, s1, 2
    call    libp2p_der_int
    addi    a1, s2, 32
    call    libp2p_der_int
    sub     t0, a0, s1
    li      t1, 0x30
    sb      t1, 0(s1)
    addi    t2, t0, -2
    sb      t2, 1(s1)
    mv      a0, t0
    LEAVE   0
END_FUNCTION libp2p_der_encode

/*
 * libp2p_der_get(dst, p, end) -> the position after a DER INTEGER at p, its
 * value written as 32 bytes big endian at dst; 0 when it is not a positive
 * INTEGER of at most 32 bytes of value.
 */
LOCAL_FUNCTION libp2p_der_get
    ENTER   0
    mv      s1, a0
    sub     t0, a2, a1
    li      t1, 2
    bltu    t0, t1, 8f
    lbu     t1, 0(a1)
    li      t2, 2
    bne     t1, t2, 8f
    lbu     t3, 1(a1)
    addi    s2, a1, 2
    addi    t0, t0, -2
    bltu    t0, t3, 8f
    beqz    t3, 8f
    lbu     t4, 0(s2)
    andi    t4, t4, 0x80
    bnez    t4, 8f                          # negative
    add     s3, s2, t3                      # the end of the integer
1:  li      t4, 32                          # leading zero bytes beyond 32
    bgeu    t4, t3, 2f
    lbu     t4, 0(s2)
    bnez    t4, 8f
    addi    s2, s2, 1
    addi    t3, t3, -1
    j       1b
2:  mv      s4, t3
    mv      a0, s1
    li      a1, 32
    call    libp2p_zero
    li      t0, 32
    sub     t0, t0, s4
    add     a0, s1, t0
    mv      a1, s2
    mv      a2, s4
    call    libp2p_copy
    mv      a0, s3
    j       9f
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_der_get

/*
 * libp2p_der_decode(sig, p, n) -> 1 when the n bytes at p are a DER SEQUENCE of
 * two positive INTEGERs r and s, written as 64 bytes big endian at sig;
 * else 0.
 */
LOCAL_FUNCTION libp2p_der_decode
    ENTER   0
    mv      s1, a0
    add     s2, a1, a2                      # end
    li      t0, 8
    bltu    a2, t0, 8f
    lbu     t0, 0(a1)
    li      t1, 0x30
    bne     t0, t1, 8f
    lbu     t0, 1(a1)
    addi    t1, a2, -2
    bne     t0, t1, 8f
    addi    a1, a1, 2
    mv      a0, s1
    mv      a2, s2
    call    libp2p_der_get
    beqz    a0, 8f
    mv      a1, a0
    addi    a0, s1, 32
    mv      a2, s2
    call    libp2p_der_get
    bne     a0, s2, 8f
    li      a0, 1
    j       9f
8:  li      a0, 0
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
 * Work: the extra area at s1.
 */
.set SS_MSG, 0                          /* ByteList: 24 + 56 bytes */
.set SS_HASH, 80                        /* 32 bytes */
.set SS_SIG, 112                        /* 64 bytes */
LOCAL_FUNCTION libp2p_sign_static
    ENTER   0, 192
    addi    s1, sp, FL
    li      t0, 80
    sd      t0, SS_MSG(s1)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (SS_MSG + 8)(s1)
    li      t0, 56
    sd      t0, (SS_MSG + 16)(s1)
    addi    a0, s1, (SS_MSG + 24)
    lla     a1, 400b
    li      a2, NOISE_SIG_PREFIX
    call    libp2p_copy
    addi    a1, s9, ST_NOISE_PUB
    li      a2, 32
    call    libp2p_copy
    ld      t0, ST_KEY_TYPE(s9)
    li      t1, LIBP2P_KEY_ED25519
    bne     t0, t1, 1f
    addi    a0, s9, ST_PRIVATE_KEY
    addi    a1, s1, SS_MSG
    addi    a2, s9, ST_NOISE_SIG
    CALL_GLOBAL crypto_ed25519_sign
    li      t0, 64
    sd      t0, ST_NOISE_SIG_LEN(s9)
    j       2f
1:  addi    a0, s1, SS_MSG
    addi    a1, s1, SS_HASH
    CALL_GLOBAL crypto_sha256
    addi    a0, s9, ST_PRIVATE_KEY
    addi    a1, s1, SS_HASH
    addi    a2, s1, SS_SIG
    CALL_GLOBAL crypto_secp256k1_sign
    addi    a0, s9, ST_NOISE_SIG
    addi    a1, s1, SS_SIG
    call    libp2p_der_encode
    sd      a0, ST_NOISE_SIG_LEN(s9)
2:  addi    s2, s9, ST_PAYLOAD              # NoiseHandshakePayload: identity_key, identity_sig
    addi    a0, s2, 2                       # the PublicKey protobuf at payload + 2
    ld      a1, ST_KEY_TYPE(s9)
    addi    a2, s9, ST_PUBLIC_KEY
    ld      a3, ST_PUBLIC_LEN(s9)
    call    libp2p_key_proto
    sub     t0, a0, s2
    addi    t0, t0, -2
    li      t1, 0x0A
    sb      t1, 0(s2)
    sb      t0, 1(s2)
    li      a1, 2
    addi    a2, s9, ST_NOISE_SIG
    ld      a3, ST_NOISE_SIG_LEN(s9)
    call    libp2p_pb_bytes
    sub     a0, a0, s2
    sd      a0, ST_PAYLOAD_LEN(s9)
    LEAVE   0, 192
END_FUNCTION libp2p_sign_static

/*
 * libp2p_verify_static(type, key, key length, sig, sig length, static key)
 * -> 1 when sig is a valid identity signature of
 * "noise-libp2p-static-key:" || the 32-byte static key, by the key of the
 * type; else 0. A secp256k1 s above n / 2 is taken as n - s.
 * s1-s6 the arguments. Work: the extra area at sp + FL, VS offsets.
 */
.set VS_MSG, 0                          /* ByteList: 24 + 56 bytes */
.set VS_HASH, 80
.set VS_SIG, 112                        /* 64 bytes */
.set VS_VALID, 176
.set VS_KEY, 184                        /* 40 bytes */
LOCAL_FUNCTION libp2p_verify_static
    ENTER   0, 224
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    li      t0, 80
    sd      t0, (FL + VS_MSG)(sp)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (FL + VS_MSG + 8)(sp)
    li      t0, 56
    sd      t0, (FL + VS_MSG + 16)(sp)
    addi    a0, sp, (FL + VS_MSG + 24)
    lla     a1, 400b
    li      a2, NOISE_SIG_PREFIX
    call    libp2p_copy
    mv      a1, s6
    li      a2, 32
    call    libp2p_copy
    addi    a0, sp, (FL + VS_KEY)           # the key, aligned
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    li      t0, LIBP2P_KEY_ED25519
    bne     s1, t0, 1f
    li      t0, 32
    bne     s3, t0, 8f
    li      t0, 64
    bne     s5, t0, 8f
    addi    a0, sp, (FL + VS_SIG)
    mv      a1, s4
    li      a2, 64
    call    libp2p_copy
    addi    a0, sp, (FL + VS_KEY)
    addi    a1, sp, (FL + VS_MSG)
    addi    a2, sp, (FL + VS_SIG)
    addi    a3, sp, (FL + VS_VALID)
    CALL_GLOBAL crypto_ed25519_verify
    bnez    a0, 8f
    ld      a0, (FL + VS_VALID)(sp)
    j       9f
1:  li      t0, LIBP2P_KEY_SECP256K1
    bne     s1, t0, 8f
    li      t0, 33
    bne     s3, t0, 8f
    addi    a0, sp, (FL + VS_SIG)
    mv      a1, s4
    mv      a2, s5
    call    libp2p_der_decode
    beqz    a0, 8f
    addi    a0, sp, (FL + VS_SIG + 32)
    call    libp2p_low_s
    addi    a0, sp, (FL + VS_MSG)
    addi    a1, sp, (FL + VS_HASH)
    CALL_GLOBAL crypto_sha256
    addi    a0, sp, (FL + VS_KEY)
    addi    a1, sp, (FL + VS_HASH)
    addi    a2, sp, (FL + VS_SIG)
    addi    a3, sp, (FL + VS_VALID)
    CALL_GLOBAL crypto_secp256k1_verify
    bnez    a0, 8f
    ld      a0, (FL + VS_VALID)(sp)
    j       9f
8:  li      a0, 0
9:  LEAVE   0, 224
END_FUNCTION libp2p_verify_static

/*
 * libp2p_low_s(s): when the 32-byte big-endian s is above n / 2 of secp256k1,
 * replaces it with n - s. A leaf. a2 to a5 s as big-endian limbs, most
 * significant first.
 */
LOCAL_FUNCTION libp2p_low_s
    UNWIND_END_PROLOGUE
    BE64    a2, a0, 0, t0
    BE64    a3, a0, 8, t0
    BE64    a4, a0, 16, t0
    BE64    a5, a0, 24, t0
    lla     a6, 410f                        # n / 2
    ld      a7, 0(a6)                       # s > n / 2, most significant limb first
    bltu    a7, a2, 1f
    bltu    a2, a7, 9f
    ld      a7, 8(a6)
    bltu    a7, a3, 1f
    bltu    a3, a7, 9f
    ld      a7, 16(a6)
    bltu    a7, a4, 1f
    bltu    a4, a7, 9f
    ld      a7, 24(a6)
    bgeu    a7, a5, 9f
1:  ld      t1, 56(a6)                      # n - s, least significant limb first
    sltu    t5, t1, a5
    sub     t1, t1, a5
    ld      t2, 48(a6)
    sltu    t6, t2, a4
    sub     t2, t2, a4
    sltu    a7, t2, t5
    sub     t2, t2, t5
    or      t6, t6, a7
    ld      t3, 40(a6)
    sltu    t5, t3, a3
    sub     t3, t3, a3
    sltu    a7, t3, t6
    sub     t3, t3, t6
    or      t5, t5, a7
    ld      t4, 32(a6)
    sub     t4, t4, a2
    sub     t4, t4, t5
    STBE    t4, a0, 0, a7
    STBE    t3, a0, 8, a7
    STBE    t2, a0, 16, a7
    STBE    t1, a0, 24, a7
9:  ret
END_FUNCTION libp2p_low_s

    .p2align 3
/* n / 2, then n, of secp256k1: big-endian limbs, most significant first. */
410:
    .quad   0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0x5D576E7357A4501D, 0xDFE92F46681B20A0
    .quad   0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFE, 0xBAAEDCE6AF48A03B, 0xBFD25E8CD0364141
