/*
 * Noise of the RISC-V core: the libp2p Noise handshake
 * (Noise_XX_25519_ChaChaPoly_SHA256, libp2p noise spec) and the transport
 * CipherStates. Included by libp2p.s.
 *
 * Every function takes the connection slot first. The SymmetricState lives
 * in the connection: h, ck, k, n and whether k is set.
 */

    .p2align 3
/* "Noise_XX_25519_ChaChaPoly_SHA256": 32 bytes, so it is h as it stands. */
420:
    .ascii  "Noise_XX_25519_ChaChaPoly_SHA256"
/* The X25519 base point u = 9. */
421:
    .quad   9, 0, 0, 0

/* ---------------------------------------------------------------- SymmetricState */

/* libp2p_ns_mixhash(conn, data, n): h = SHA-256(h || data). n is at most 65536. */
LOCAL_FUNCTION libp2p_ns_mixhash
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    SCR     s4, SC_MIX
    addi    t0, s3, (LIBP2P_BL_FIXED + 32)
    sd      t0, LIBP2P_BL_SIZE(s4)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, LIBP2P_BL_OFFSET(s4)
    addi    t0, s3, 32
    sd      t0, LIBP2P_BL_COUNT(s4)
    addi    a0, s4, LIBP2P_BL_FIXED
    addi    a1, s1, C_NS_H
    li      a2, 32
    call    libp2p_copy
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    mv      a0, s4
    addi    a1, s1, C_NS_H
    CALL_GLOBAL crypto_sha256
    LEAVE   0
END_FUNCTION libp2p_ns_mixhash

/*
 * libp2p_ns_hkdf(conn, ikm, n): HKDF(ck, ikm) of the Noise spec: the 64 output
 * bytes at the OKM of the scratch, then ck = the first 32.
 */
LOCAL_FUNCTION libp2p_ns_hkdf
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    addi    s4, s10, SC_WORK
    li      t0, 56                          # salt: ck
    sd      t0, 0(s4)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, 8(s4)
    li      t0, 32
    sd      t0, 16(s4)
    addi    a0, s4, 24
    addi    a1, s1, C_NS_CK
    li      a2, 32
    call    libp2p_copy
    addi    s5, s4, 56                      # ikm
    addi    t0, s3, LIBP2P_BL_FIXED
    sd      t0, 0(s5)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, 8(s5)
    sd      s3, 16(s5)
    addi    a0, s5, 24
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    li      t0, SC_HMAC_SIZE
    sd      t0, SC_HMAC(s10)
    mv      a0, s4
    mv      a1, s5
    addi    a2, s10, SC_HMAC
    addi    a3, s10, (SC_PRK + LIBP2P_BL_FIXED)
    CALL_GLOBAL crypto_hkdf_extract
    li      t0, (LIBP2P_BL_FIXED + 32)      # PRK as a ByteList for Expand
    sd      t0, SC_PRK(s10)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (SC_PRK + 8)(s10)
    li      t0, 32
    sd      t0, (SC_PRK + 16)(s10)
    li      t0, SC_HMAC_SIZE
    sd      t0, SC_HMAC(s10)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, SC_EMPTY(s10)
    sd      t0, (SC_EMPTY + 8)(s10)
    sd      zero, (SC_EMPTY + 16)(s10)
    li      t0, 64
    sd      t0, SC_LENGTH(s10)
    li      t0, (LIBP2P_BL_FIXED + 64)
    sd      t0, SC_OKM(s10)
    addi    a0, s10, SC_PRK
    addi    a1, s10, SC_EMPTY
    addi    a2, s10, SC_LENGTH
    addi    a3, s10, SC_HMAC
    addi    a4, s10, SC_OKM
    CALL_GLOBAL crypto_hkdf_expand
    addi    a0, s1, C_NS_CK
    addi    a1, s10, (SC_OKM + LIBP2P_BL_FIXED)
    li      a2, 32
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_ns_hkdf

/* libp2p_ns_mixkey(conn, ikm): MixKey of a 32-byte DH output: ck and k from HKDF, n = 0. */
LOCAL_FUNCTION libp2p_ns_mixkey
    ENTER   0
    mv      s1, a0
    li      a2, 32
    call    libp2p_ns_hkdf
    addi    a0, s1, C_NS_K
    addi    a1, s10, (SC_OKM + LIBP2P_BL_FIXED + 32)
    li      a2, 32
    call    libp2p_copy
    sd      zero, C_NS_N(s1)
    li      t0, 1
    sd      t0, C_NS_HASK(s1)
    LEAVE   0
END_FUNCTION libp2p_ns_mixkey

/*
 * libp2p_ns_nonce(n): the 12-byte ChaCha20-Poly1305 nonce of Noise at the
 * scratch: 4 zero bytes, then n little endian. A leaf. The nonce is only
 * 4-byte aligned, so it is written as 32-bit words.
 */
LOCAL_FUNCTION libp2p_ns_nonce
    UNWIND_END_PROLOGUE
    addi    a1, s10, SC_NONCE
    sw      zero, 0(a1)
    sw      a0, 4(a1)
    srli    a0, a0, 32
    sw      a0, 8(a1)
    sw      zero, 12(a1)
    ret
END_FUNCTION libp2p_ns_nonce

/*
 * libp2p_ns_encrypt_hash(conn, src, n, dst) -> dst after: EncryptAndHash of
 * the n bytes at src (at most 4096): with k set, ChaCha20-Poly1305 with ad
 * = h and n + 16 bytes out; without, the bytes as they are. Then MixHash of
 * what it wrote.
 */
LOCAL_FUNCTION libp2p_ns_encrypt_hash
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      t0, C_NS_HASK(s1)
    bnez    t0, 1f
    mv      a0, s4                          # no key: the plaintext
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    mv      s5, s3
    j       2f
1:  SCR     s6, SC_PLAIN
    addi    t0, s3, LIBP2P_BL_FIXED
    sd      t0, 0(s6)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, 8(s6)
    sd      s3, 16(s6)
    addi    a0, s6, 24
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    li      t0, (LIBP2P_BL_FIXED + 32)      # ad = h
    sd      t0, SC_AAD(s10)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (SC_AAD + 8)(s10)
    li      t0, 32
    sd      t0, (SC_AAD + 16)(s10)
    addi    a0, s10, (SC_AAD + 24)
    addi    a1, s1, C_NS_H
    li      a2, 32
    call    libp2p_copy
    ld      a0, C_NS_N(s1)
    addi    t0, a0, 1
    sd      t0, C_NS_N(s1)
    call    libp2p_ns_nonce
    SCR     s7, SC_SEAL
    addi    t0, s3, (LIBP2P_BL_FIXED + 16)
    sd      t0, 0(s7)
    addi    a0, s1, C_NS_K
    addi    a1, s10, SC_NONCE
    mv      a2, s6
    addi    a3, s10, SC_AAD
    mv      a4, s7
    CALL_GLOBAL crypto_chacha20_aead_encrypt
    addi    s5, s3, 16
    mv      a0, s4
    addi    a1, s7, LIBP2P_BL_FIXED
    mv      a2, s5
    call    libp2p_copy
2:  mv      a0, s1
    mv      a1, s4
    mv      a2, s5
    call    libp2p_ns_mixhash
    add     a0, s4, s5
    LEAVE   0
END_FUNCTION libp2p_ns_encrypt_hash

/*
 * libp2p_ns_decrypt_hash(conn, src, n) -> 0, with the plaintext in the PLAIN
 * ByteList of the scratch; 1 when the tag does not match or n is below 16
 * with k set. DecryptAndHash: MixHash of the n bytes at src after.
 */
LOCAL_FUNCTION libp2p_ns_decrypt_hash
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    SCR     s6, SC_PLAIN
    ld      t0, C_NS_HASK(s1)
    bnez    t0, 1f
    addi    t0, s3, LIBP2P_BL_FIXED         # no key: the bytes as they are
    sd      t0, 0(s6)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, 8(s6)
    sd      s3, 16(s6)
    addi    a0, s6, 24
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    j       2f
1:  li      t0, 16
    bltu    s3, t0, 8f
    SCR     s7, SC_SEAL
    addi    t0, s3, LIBP2P_BL_FIXED
    sd      t0, 0(s7)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, 8(s7)
    sd      s3, 16(s7)
    addi    a0, s7, 24
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    li      t0, (LIBP2P_BL_FIXED + 32)
    sd      t0, SC_AAD(s10)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (SC_AAD + 8)(s10)
    li      t0, 32
    sd      t0, (SC_AAD + 16)(s10)
    addi    a0, s10, (SC_AAD + 24)
    addi    a1, s1, C_NS_H
    li      a2, 32
    call    libp2p_copy
    ld      a0, C_NS_N(s1)
    addi    t0, a0, 1
    sd      t0, C_NS_N(s1)
    call    libp2p_ns_nonce
    addi    t0, s3, -16
    addi    t0, t0, LIBP2P_BL_FIXED
    sd      t0, 0(s6)
    addi    a0, s1, C_NS_K
    addi    a1, s10, SC_NONCE
    mv      a2, s7
    addi    a3, s10, SC_AAD
    mv      a4, s6
    CALL_GLOBAL crypto_chacha20_aead_decrypt
    bnez    a0, 8f
2:  mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    call    libp2p_ns_mixhash
    li      a0, 0
    j       9f
8:  li      a0, 1
9:  LEAVE   0
END_FUNCTION libp2p_ns_decrypt_hash

/* libp2p_ns_dh(conn, private, public) -> 0, after MixKey(DH(private, public)); 1 when the DH result is all zero. */
LOCAL_FUNCTION libp2p_ns_dh
    ENTER   0, 32
    mv      s1, a0
    mv      a0, a1
    mv      a1, a2
    addi    a2, sp, FL
    CALL_GLOBAL crypto_x25519
    bnez    a0, 8f
    mv      a0, s1
    addi    a1, sp, FL
    call    libp2p_ns_mixkey
    li      a0, 0
    j       9f
8:  li      a0, 1
9:  LEAVE   0, 32
END_FUNCTION libp2p_ns_dh

/* ---------------------------------------------------------------- Handshake */

/*
 * libp2p_noise_out(conn, n) -> the place for n more bytes in the output buffer
 * of the connection, with C_OUT_LEN already moved past them; 0 when they
 * do not fit. A leaf.
 */
LOCAL_FUNCTION libp2p_noise_out
    UNWIND_END_PROLOGUE
    ld      a2, C_OUT_LEN(a0)
    add     a3, a2, a1
    li      a4, C_OUT_CAP
    bltu    a4, a3, 8f
    sd      a3, C_OUT_LEN(a0)
    ld      a4, C_FLAGS(a0)
    andi    a4, a4, CF_TRANSPORT
    bnez    a4, 1f
    sd      a3, C_OUT_RAW(a0)               # before the transport keys, bytes go out as they are
1:  addi    a0, a0, C_OUT
    add     a0, a0, a2
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_noise_out

/*
 * libp2p_noise_begin(conn): InitializeSymmetric, MixHash of the empty
 * prologue, a fresh e; the initiator then writes message 1: e and an
 * empty payload, with its 2-byte length.
 */
LOCAL_FUNCTION libp2p_noise_begin
    ENTER   0
    mv      s1, a0
    addi    a0, s1, C_NS_H
    lla     a1, 420b
    li      a2, 32
    call    libp2p_copy
    addi    a0, s1, C_NS_CK
    lla     a1, 420b
    li      a2, 32
    call    libp2p_copy
    sd      zero, C_NS_HASK(s1)
    sd      zero, C_NS_N(s1)
    sd      zero, C_NS_STEP(s1)
    mv      a0, s1
    mv      a1, s1
    li      a2, 0
    call    libp2p_ns_mixhash
    addi    a0, s1, C_NS_E
    li      a1, 32
    call    libp2p_random
    addi    a0, s1, C_NS_E
    lla     a1, 421b
    addi    a2, s1, C_NS_EPUB
    CALL_GLOBAL crypto_x25519
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_OUTBOUND
    beqz    t0, 9f
    mv      a0, s1                          # -> e
    li      a1, 34
    call    libp2p_noise_out
    mv      s2, a0
    li      t0, 32
    sb      zero, 0(s2)
    sb      t0, 1(s2)
    addi    a0, s2, 2
    addi    a1, s1, C_NS_EPUB
    li      a2, 32
    call    libp2p_copy
    mv      a0, s1
    addi    a1, s1, C_NS_EPUB
    li      a2, 32
    call    libp2p_ns_mixhash
    mv      a0, s1                          # the empty payload
    mv      a1, s1
    li      a2, 0
    call    libp2p_ns_mixhash
9:  LEAVE   0
END_FUNCTION libp2p_noise_begin

/*
 * libp2p_noise_payload(conn, p, n, rs) -> 0 when the NoiseHandshakePayload at p
 * has an Ed25519 or secp256k1 identity_key and an identity_sig of
 * "noise-libp2p-static-key:" || rs by it; the key type and the peer ID go
 * to the connection. 1 otherwise.
 * s1 conn, s2 position, s3 end, s4 rs, s5 key, s6 key length,
 * s7 signature, s8 signature length. Local: the key type.
 */
LOCAL_FUNCTION libp2p_noise_payload
    ENTER   16
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
    mv      s4, a3
    li      s5, 0
    li      s7, 0
1:  mv      a0, s2                          # the payload fields
    mv      a1, s3
    call    libp2p_pb_next
    beqz    a0, 3f
    li      t0, NONE
    beq     a0, t0, 8f
    mv      s2, a5
    li      t0, 2
    bne     a2, t0, 1b
    li      t0, 1
    bne     a1, t0, 2f
    mv      s5, a3                          # identity_key
    mv      s6, a4
    j       1b
2:  li      t0, 2
    bne     a1, t0, 1b
    mv      s7, a3                          # identity_sig
    mv      s8, a4
    j       1b
3:  beqz    s5, 8f
    beqz    s7, 8f
    mv      s2, s5                          # the PublicKey fields
    add     s3, s5, s6
    li      s5, 0
    li      s6, NONE
    sd      zero, FL(sp)
4:  mv      a0, s2
    mv      a1, s3
    call    libp2p_pb_next
    beqz    a0, 6f
    li      t0, NONE
    beq     a0, t0, 8f
    mv      s2, a5
    li      t0, 1
    bne     a1, t0, 5f
    bnez    a2, 8f
    sd      a3, FL(sp)                      # Type
    j       4b
5:  li      t0, 2
    bne     a1, t0, 4b
    bne     a2, t0, 8f
    mv      s5, a3                          # Data
    mv      s6, a4
    j       4b
6:  beqz    s5, 8f
    ld      a0, FL(sp)
    mv      a1, s5
    mv      a2, s6
    mv      a3, s7
    mv      a4, s8
    mv      a5, s4
    call    libp2p_verify_static
    beqz    a0, 8f
    ld      a1, FL(sp)
    sd      a1, C_KEY_TYPE(s1)
    addi    a0, s1, C_RID
    mv      a2, s5
    mv      a3, s6
    call    libp2p_peer_id
    sd      a0, C_RID_LEN(s1)
    li      a0, 0
    j       9f
8:  li      a0, 1
9:  LEAVE   16
END_FUNCTION libp2p_noise_payload

/*
 * libp2p_noise_split(conn): Split: (k1, k2) = HKDF(ck, empty); the initiator
 * sends with k1 and the responder with k2. Sets the transport flag.
 */
LOCAL_FUNCTION libp2p_noise_split
    ENTER   0
    mv      s1, a0
    mv      a1, s1
    li      a2, 0
    call    libp2p_ns_hkdf
    addi    s2, s10, (SC_OKM + LIBP2P_BL_FIXED)
    addi    s3, s2, 32
    mv      s4, s2                          # send key
    mv      s5, s3                          # receive key
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_OUTBOUND
    bnez    t0, 1f
    mv      s4, s3
    mv      s5, s2
1:  addi    a0, s1, C_TX_K
    mv      a1, s4
    li      a2, 32
    call    libp2p_copy
    addi    a0, s1, C_RX_K
    mv      a1, s5
    li      a2, 32
    call    libp2p_copy
    sd      zero, C_TX_N(s1)
    sd      zero, C_RX_N(s1)
    ld      t0, C_FLAGS(s1)
    ori     t0, t0, CF_TRANSPORT
    sd      t0, C_FLAGS(s1)
    addi    a0, s1, C_NS_E                  # forget the ephemeral key
    li      a1, 32
    call    libp2p_zero
    LEAVE   0
END_FUNCTION libp2p_noise_split

/*
 * libp2p_noise_message(conn, msg, n) -> 0 when the handshake message (without
 * its length) is good and the next one, if any, is written; 1 when the
 * handshake fails; 2 when a dial reached another peer than the one dialled,
 * found in message 2, so message 3 is never sent. Responder: message 1,
 * then message 3. Initiator: message 2. After the last message both sides
 * hold the transport keys.
 */
LOCAL_FUNCTION libp2p_noise_message
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      t0, C_FLAGS(s1)
    ld      t1, C_NS_STEP(s1)
    andi    t0, t0, CF_OUTBOUND
    bnez    t0, 30f
    bnez    t1, 20f

    /* Responder, message 1: <- e, then the payload. */
    li      t0, 32
    bltu    s3, t0, 80f
    addi    a0, s1, C_NS_RE
    mv      a1, s2
    li      a2, 32
    call    libp2p_copy
    mv      a0, s1
    addi    a1, s1, C_NS_RE
    li      a2, 32
    call    libp2p_ns_mixhash
    mv      a0, s1
    addi    a1, s2, 32
    addi    a2, s3, -32
    call    libp2p_ns_decrypt_hash
    bnez    a0, 80f
    /* message 2: -> e, ee, s, es, then our payload. */
    ld      s4, ST_PAYLOAD_LEN(s9)
    addi    a1, s4, (2 + 32 + 48 + 16)
    mv      a0, s1
    call    libp2p_noise_out
    beqz    a0, 80f
    mv      s5, a0
    addi    t0, s4, (32 + 48 + 16)
    srli    t1, t0, 8
    sb      t1, 0(s5)
    sb      t0, 1(s5)
    addi    a0, s5, 2
    addi    a1, s1, C_NS_EPUB
    li      a2, 32
    call    libp2p_copy
    mv      a0, s1
    addi    a1, s1, C_NS_EPUB
    li      a2, 32
    call    libp2p_ns_mixhash
    mv      a0, s1
    addi    a1, s1, C_NS_E
    addi    a2, s1, C_NS_RE
    call    libp2p_ns_dh
    bnez    a0, 80f
    mv      a0, s1
    addi    a1, s9, ST_NOISE_PUB
    li      a2, 32
    addi    a3, s5, 34
    call    libp2p_ns_encrypt_hash
    mv      s6, a0
    mv      a0, s1
    addi    a1, s9, ST_NOISE_PRIV
    addi    a2, s1, C_NS_RE
    call    libp2p_ns_dh
    bnez    a0, 80f
    mv      a0, s1
    addi    a1, s9, ST_PAYLOAD
    mv      a2, s4
    mv      a3, s6
    call    libp2p_ns_encrypt_hash
    li      t0, 1
    sd      t0, C_NS_STEP(s1)
    j       70f

    /* Responder, message 3: <- s, se, then the payload. */
20: li      t0, 48
    bltu    s3, t0, 80f
    mv      a0, s1
    mv      a1, s2
    li      a2, 48
    call    libp2p_ns_decrypt_hash
    bnez    a0, 80f
    addi    a0, s1, C_NS_RS
    SCR     a1, (SC_PLAIN + LIBP2P_BL_FIXED)
    li      a2, 32
    call    libp2p_copy
    mv      a0, s1
    addi    a1, s1, C_NS_E
    addi    a2, s1, C_NS_RS
    call    libp2p_ns_dh
    bnez    a0, 80f
    mv      a0, s1
    addi    a1, s2, 48
    addi    a2, s3, -48
    call    libp2p_ns_decrypt_hash
    bnez    a0, 80f
    mv      a0, s1
    SCR     a1, (SC_PLAIN + LIBP2P_BL_FIXED)
    LDSC    a2, (SC_PLAIN + LIBP2P_BL_COUNT)
    addi    a3, s1, C_NS_RS
    call    libp2p_noise_payload
    bnez    a0, 80f
    mv      a0, s1
    call    libp2p_noise_split
    li      t0, 2
    sd      t0, C_NS_STEP(s1)
    j       70f

    /* Initiator, message 2: <- e, ee, s, es, then the payload. */
30: bnez    t1, 80f
    li      t0, (32 + 48)
    bltu    s3, t0, 80f
    addi    a0, s1, C_NS_RE
    mv      a1, s2
    li      a2, 32
    call    libp2p_copy
    mv      a0, s1
    addi    a1, s1, C_NS_RE
    li      a2, 32
    call    libp2p_ns_mixhash
    mv      a0, s1
    addi    a1, s1, C_NS_E
    addi    a2, s1, C_NS_RE
    call    libp2p_ns_dh
    bnez    a0, 80f
    mv      a0, s1
    addi    a1, s2, 32
    li      a2, 48
    call    libp2p_ns_decrypt_hash
    bnez    a0, 80f
    addi    a0, s1, C_NS_RS
    SCR     a1, (SC_PLAIN + LIBP2P_BL_FIXED)
    li      a2, 32
    call    libp2p_copy
    mv      a0, s1
    addi    a1, s1, C_NS_E
    addi    a2, s1, C_NS_RS
    call    libp2p_ns_dh
    bnez    a0, 80f
    mv      a0, s1
    addi    a1, s2, 80
    addi    a2, s3, -80
    call    libp2p_ns_decrypt_hash
    bnez    a0, 80f
    mv      a0, s1
    SCR     a1, (SC_PLAIN + LIBP2P_BL_FIXED)
    LDSC    a2, (SC_PLAIN + LIBP2P_BL_COUNT)
    addi    a3, s1, C_NS_RS
    call    libp2p_noise_payload
    bnez    a0, 80f
    ld      a1, C_EXP_ID_LEN(s1)            # a dial: the responder must be the dialled peer
    beqz    a1, 31f
    addi    a0, s1, C_EXP_ID
    addi    a2, s1, C_RID
    ld      a3, C_RID_LEN(s1)
    call    libp2p_compare
    beqz    a0, 81f
    /* message 3: -> s, se, then our payload. */
31:
    ld      s4, ST_PAYLOAD_LEN(s9)
    addi    a1, s4, (2 + 48 + 16)
    mv      a0, s1
    call    libp2p_noise_out
    beqz    a0, 80f
    mv      s5, a0
    addi    t0, s4, (48 + 16)
    srli    t1, t0, 8
    sb      t1, 0(s5)
    sb      t0, 1(s5)
    mv      a0, s1
    addi    a1, s9, ST_NOISE_PUB
    li      a2, 32
    addi    a3, s5, 2
    call    libp2p_ns_encrypt_hash
    mv      s6, a0
    mv      a0, s1
    addi    a1, s9, ST_NOISE_PRIV
    addi    a2, s1, C_NS_RE
    call    libp2p_ns_dh
    bnez    a0, 80f
    mv      a0, s1
    addi    a1, s9, ST_PAYLOAD
    mv      a2, s4
    mv      a3, s6
    call    libp2p_ns_encrypt_hash
    mv      a0, s1
    call    libp2p_noise_split
    li      t0, 2
    sd      t0, C_NS_STEP(s1)
70: li      a0, 0
    j       99f
80: li      a0, 1
    j       99f
81: li      a0, 2
99: LEAVE   0
END_FUNCTION libp2p_noise_message

/* ---------------------------------------------------------------- Transport */

/*
 * libp2p_noise_seal(conn, src, n, dst) -> dst after one transport message: the
 * 2-byte big-endian length, then ChaCha20-Poly1305 of the n bytes at src
 * (at most 65519) with the send key, its nonce and an empty ad.
 */
LOCAL_FUNCTION libp2p_noise_seal
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    SCR     s6, SC_PLAIN
    addi    t0, s6, LIBP2P_BL_FIXED         # the plaintext may already be in place
    beq     s2, t0, 1f
    addi    a0, s6, LIBP2P_BL_FIXED
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
1:  addi    t0, s3, LIBP2P_BL_FIXED
    sd      t0, 0(s6)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, 8(s6)
    sd      s3, 16(s6)
    sd      t0, SC_EMPTY(s10)
    sd      t0, (SC_EMPTY + 8)(s10)
    sd      zero, (SC_EMPTY + 16)(s10)
    ld      a0, C_TX_N(s1)
    addi    t0, a0, 1
    sd      t0, C_TX_N(s1)
    call    libp2p_ns_nonce
    SCR     s7, SC_SEAL
    addi    t0, s3, (LIBP2P_BL_FIXED + 16)
    sd      t0, 0(s7)
    addi    a0, s1, C_TX_K
    addi    a1, s10, SC_NONCE
    mv      a2, s6
    addi    a3, s10, SC_EMPTY
    mv      a4, s7
    CALL_GLOBAL crypto_chacha20_aead_encrypt
    addi    a2, s3, 16
    srli    t1, a2, 8
    sb      t1, 0(s4)
    sb      a2, 1(s4)
    addi    a0, s4, 2
    addi    a1, s7, LIBP2P_BL_FIXED
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_noise_seal

/*
 * libp2p_noise_open(conn, src, n) -> 0 with the plaintext in the PLAIN ByteList
 * of the scratch: the n bytes at src (a transport message without its
 * length) decrypted with the receive key; 1 when the tag does not match.
 */
LOCAL_FUNCTION libp2p_noise_open
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      t0, 16
    bltu    s3, t0, 8f
    SCR     s7, SC_SEAL
    addi    t0, s3, LIBP2P_BL_FIXED
    sd      t0, 0(s7)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, 8(s7)
    sd      s3, 16(s7)
    addi    a0, s7, 24
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    li      t0, LIBP2P_BL_FIXED
    sd      t0, SC_EMPTY(s10)
    sd      t0, (SC_EMPTY + 8)(s10)
    sd      zero, (SC_EMPTY + 16)(s10)
    ld      a0, C_RX_N(s1)
    addi    t0, a0, 1
    sd      t0, C_RX_N(s1)
    call    libp2p_ns_nonce
    SCR     s6, SC_PLAIN
    addi    t0, s3, -16
    addi    t0, t0, LIBP2P_BL_FIXED
    sd      t0, 0(s6)
    addi    a0, s1, C_RX_K
    addi    a1, s10, SC_NONCE
    mv      a2, s7
    addi    a3, s10, SC_EMPTY
    mv      a4, s6
    CALL_GLOBAL crypto_chacha20_aead_decrypt
    bnez    a0, 8f
    li      a0, 0
    j       9f
8:  li      a0, 1
9:  LEAVE   0
END_FUNCTION libp2p_noise_open
