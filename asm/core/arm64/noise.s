/*
 * Noise of the ARM64 core: the libp2p Noise handshake
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
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    SCR     x22, SC_MIX
    add     x9, x21, #(LIBP2P_BL_FIXED + 32)
    str     x9, [x22, #LIBP2P_BL_SIZE]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x22, #LIBP2P_BL_OFFSET]
    add     x9, x21, #32
    str     x9, [x22, #LIBP2P_BL_COUNT]
    add     x0, x22, #LIBP2P_BL_FIXED
    add     x1, x19, #C_NS_H
    mov     x2, #32
    bl      libp2p_copy
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    mov     x0, x22
    add     x1, x19, #C_NS_H
    CALL_GLOBAL crypto_sha256
    LEAVE   0
END_FUNCTION libp2p_ns_mixhash

/*
 * libp2p_ns_hkdf(conn, ikm, n): HKDF(ck, ikm) of the Noise spec: the 64 output
 * bytes at the OKM of the scratch, then ck = the first 32.
 */
LOCAL_FUNCTION libp2p_ns_hkdf
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    SCR     x22, SC_WORK
    mov     x9, #56                         /* salt: ck */
    str     x9, [x22]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x22, #8]
    mov     x9, #32
    str     x9, [x22, #16]
    add     x0, x22, #24
    add     x1, x19, #C_NS_CK
    mov     x2, #32
    bl      libp2p_copy
    add     x23, x22, #56                   /* ikm */
    add     x9, x21, #LIBP2P_BL_FIXED
    str     x9, [x23]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x23, #8]
    str     x21, [x23, #16]
    add     x0, x23, #24
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    mov     x9, #SC_HMAC_SIZE
    str     x9, [x28, #SC_HMAC]
    mov     x0, x22
    mov     x1, x23
    add     x2, x28, #SC_HMAC
    add     x3, x28, #(SC_PRK + LIBP2P_BL_FIXED)
    CALL_GLOBAL crypto_hkdf_extract
    mov     x9, #(LIBP2P_BL_FIXED + 32)     /* PRK as a ByteList for Expand */
    str     x9, [x28, #SC_PRK]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x28, #SC_PRK + 8]
    mov     x9, #32
    str     x9, [x28, #SC_PRK + 16]
    mov     x9, #SC_HMAC_SIZE
    str     x9, [x28, #SC_HMAC]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x28, #SC_EMPTY]
    str     x9, [x28, #SC_EMPTY + 8]
    str     xzr, [x28, #SC_EMPTY + 16]
    mov     x9, #64
    str     x9, [x28, #SC_LENGTH]
    mov     x9, #(LIBP2P_BL_FIXED + 64)
    str     x9, [x28, #SC_OKM]
    add     x0, x28, #SC_PRK
    add     x1, x28, #SC_EMPTY
    add     x2, x28, #SC_LENGTH
    add     x3, x28, #SC_HMAC
    add     x4, x28, #SC_OKM
    CALL_GLOBAL crypto_hkdf_expand
    add     x0, x19, #C_NS_CK
    add     x1, x28, #SC_OKM + LIBP2P_BL_FIXED
    mov     x2, #32
    bl      libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_ns_hkdf

/* libp2p_ns_mixkey(conn, ikm): MixKey of a 32-byte DH output: ck and k from HKDF, n = 0. */
LOCAL_FUNCTION libp2p_ns_mixkey
    ENTER   0
    mov     x19, x0
    mov     x2, #32
    bl      libp2p_ns_hkdf
    add     x0, x19, #C_NS_K
    add     x1, x28, #SC_OKM + LIBP2P_BL_FIXED + 32
    mov     x2, #32
    bl      libp2p_copy
    str     xzr, [x19, #C_NS_N]
    mov     x9, #1
    str     x9, [x19, #C_NS_HASK]
    LEAVE   0
END_FUNCTION libp2p_ns_mixkey

/* libp2p_ns_nonce(n): the 12-byte ChaCha20-Poly1305 nonce of Noise at the scratch: 4 zero bytes, then n little endian. A leaf. */
LOCAL_FUNCTION libp2p_ns_nonce
    UNWIND_END_PROLOGUE
    add     x1, x28, #SC_NONCE
    str     wzr, [x1]
    str     x0, [x1, #4]
    str     wzr, [x1, #12]
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
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x9, [x19, #C_NS_HASK]
    cbnz    x9, 1f
    mov     x0, x22                         /* no key: the plaintext */
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    mov     x23, x21
    b       2f
1:  SCR     x24, SC_PLAIN
    add     x9, x21, #LIBP2P_BL_FIXED
    str     x9, [x24]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x24, #8]
    str     x21, [x24, #16]
    add     x0, x24, #24
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    mov     x9, #(LIBP2P_BL_FIXED + 32)     /* ad = h */
    str     x9, [x28, #SC_AAD]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x28, #SC_AAD + 8]
    mov     x9, #32
    str     x9, [x28, #SC_AAD + 16]
    add     x0, x28, #SC_AAD + 24
    add     x1, x19, #C_NS_H
    mov     x2, #32
    bl      libp2p_copy
    ldr     x0, [x19, #C_NS_N]
    add     x9, x0, #1
    str     x9, [x19, #C_NS_N]
    bl      libp2p_ns_nonce
    SCR     x25, SC_SEAL
    add     x9, x21, #(LIBP2P_BL_FIXED + 16)
    str     x9, [x25]
    add     x0, x19, #C_NS_K
    add     x1, x28, #SC_NONCE
    mov     x2, x24
    add     x3, x28, #SC_AAD
    mov     x4, x25
    CALL_GLOBAL crypto_chacha20_aead_encrypt
    add     x23, x21, #16
    mov     x0, x22
    add     x1, x25, #LIBP2P_BL_FIXED
    mov     x2, x23
    bl      libp2p_copy
2:  mov     x0, x19
    mov     x1, x22
    mov     x2, x23
    bl      libp2p_ns_mixhash
    add     x0, x22, x23
    LEAVE   0
END_FUNCTION libp2p_ns_encrypt_hash

/*
 * libp2p_ns_decrypt_hash(conn, src, n) -> 0, with the plaintext in the PLAIN
 * ByteList of the scratch; 1 when the tag does not match or n is below 16
 * with k set. DecryptAndHash: MixHash of the n bytes at src after.
 */
LOCAL_FUNCTION libp2p_ns_decrypt_hash
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    SCR     x24, SC_PLAIN
    ldr     x9, [x19, #C_NS_HASK]
    cbnz    x9, 1f
    add     x9, x21, #LIBP2P_BL_FIXED       /* no key: the bytes as they are */
    str     x9, [x24]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x24, #8]
    str     x21, [x24, #16]
    add     x0, x24, #24
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    b       2f
1:  cmp     x21, #16
    b.lo    8f
    SCR     x25, SC_SEAL
    add     x9, x21, #LIBP2P_BL_FIXED
    str     x9, [x25]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x25, #8]
    str     x21, [x25, #16]
    add     x0, x25, #24
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    mov     x9, #(LIBP2P_BL_FIXED + 32)
    str     x9, [x28, #SC_AAD]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x28, #SC_AAD + 8]
    mov     x9, #32
    str     x9, [x28, #SC_AAD + 16]
    add     x0, x28, #SC_AAD + 24
    add     x1, x19, #C_NS_H
    mov     x2, #32
    bl      libp2p_copy
    ldr     x0, [x19, #C_NS_N]
    add     x9, x0, #1
    str     x9, [x19, #C_NS_N]
    bl      libp2p_ns_nonce
    sub     x9, x21, #16
    add     x9, x9, #LIBP2P_BL_FIXED
    str     x9, [x24]
    add     x0, x19, #C_NS_K
    add     x1, x28, #SC_NONCE
    mov     x2, x25
    add     x3, x28, #SC_AAD
    mov     x4, x24
    CALL_GLOBAL crypto_chacha20_aead_decrypt
    cbnz    x0, 8f
2:  mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_ns_mixhash
    mov     x0, #0
    b       9f
8:  mov     x0, #1
9:  LEAVE   0
END_FUNCTION libp2p_ns_decrypt_hash

/* libp2p_ns_dh(conn, private, public) -> 0, after MixKey(DH(private, public)); 1 when the DH result is all zero. */
LOCAL_FUNCTION libp2p_ns_dh
    ENTER   0, 32
    mov     x19, x0
    mov     x0, x1
    mov     x1, x2
    mov     x2, sp
    CALL_GLOBAL crypto_x25519
    cbnz    x0, 8f
    mov     x0, x19
    mov     x1, sp
    bl      libp2p_ns_mixkey
    mov     x0, #0
    b       9f
8:  mov     x0, #1
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
    ldr     x2, [x0, #C_OUT_LEN]
    add     x3, x2, x1
    cmp     x3, #C_OUT_CAP
    b.hi    8f
    str     x3, [x0, #C_OUT_LEN]
    ldr     x4, [x0, #C_FLAGS]
    tst     x4, #CF_TRANSPORT
    b.ne    1f
    str     x3, [x0, #C_OUT_RAW]            /* before the transport keys, bytes go out as they are */
1:  add     x0, x0, #C_OUT
    add     x0, x0, x2
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_noise_out

/*
 * libp2p_noise_begin(conn): InitializeSymmetric, MixHash of the empty
 * prologue, a fresh e; the initiator then writes message 1: e and an
 * empty payload, with its 2-byte length.
 */
LOCAL_FUNCTION libp2p_noise_begin
    ENTER   0
    mov     x19, x0
    add     x0, x19, #C_NS_H
    adr     x1, 420b
    mov     x2, #32
    bl      libp2p_copy
    add     x0, x19, #C_NS_CK
    adr     x1, 420b
    mov     x2, #32
    bl      libp2p_copy
    str     xzr, [x19, #C_NS_HASK]
    str     xzr, [x19, #C_NS_N]
    str     xzr, [x19, #C_NS_STEP]
    mov     x0, x19
    mov     x1, x19
    mov     x2, #0
    bl      libp2p_ns_mixhash
    add     x0, x19, #C_NS_E
    mov     x1, #32
    bl      libp2p_random
    add     x0, x19, #C_NS_E
    adr     x1, 421b
    add     x2, x19, #C_NS_EPUB
    CALL_GLOBAL crypto_x25519
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_OUTBOUND
    b.eq    9f
    mov     x0, x19                         /* -> e */
    mov     x1, #34
    bl      libp2p_noise_out
    mov     x20, x0
    mov     w9, #32
    strb    wzr, [x20]
    strb    w9, [x20, #1]
    add     x0, x20, #2
    add     x1, x19, #C_NS_EPUB
    mov     x2, #32
    bl      libp2p_copy
    mov     x0, x19
    add     x1, x19, #C_NS_EPUB
    mov     x2, #32
    bl      libp2p_ns_mixhash
    mov     x0, x19                         /* the empty payload */
    mov     x1, x19
    mov     x2, #0
    bl      libp2p_ns_mixhash
9:  LEAVE   0
END_FUNCTION libp2p_noise_begin

/*
 * libp2p_noise_payload(conn, p, n, rs) -> 0 when the NoiseHandshakePayload at p
 * has an Ed25519 or secp256k1 identity_key and an identity_sig of
 * "noise-libp2p-static-key:" || rs by it; the key type and the peer ID go
 * to the connection. 1 otherwise.
 * x19 conn, x20 position, x21 end, x22 rs, x23 key, x24 key length,
 * x25 signature, x26 signature length.
 */
LOCAL_FUNCTION libp2p_noise_payload
    ENTER   16
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x22, x3
    mov     x23, #0
    mov     x25, #0
1:  mov     x0, x20                         /* the payload fields */
    mov     x1, x21
    bl      libp2p_pb_next
    cbz     x0, 3f
    cmn     x0, #1
    b.eq    8f
    mov     x20, x5
    cmp     x2, #2
    b.ne    1b
    cmp     x1, #1
    b.ne    2f
    mov     x23, x3                         /* identity_key */
    mov     x24, x4
    b       1b
2:  cmp     x1, #2
    b.ne    1b
    mov     x25, x3                         /* identity_sig */
    mov     x26, x4
    b       1b
3:  cbz     x23, 8f
    cbz     x25, 8f
    mov     x20, x23                        /* the PublicKey fields */
    add     x21, x23, x24
    mov     x23, #0
    mov     x24, #NONE
    str     xzr, [sp, #96]
4:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cbz     x0, 6f
    cmn     x0, #1
    b.eq    8f
    mov     x20, x5
    cmp     x1, #1
    b.ne    5f
    cmp     x2, #0
    b.ne    8f
    str     x3, [sp, #96]                   /* Type */
    b       4b
5:  cmp     x1, #2
    b.ne    4b
    cmp     x2, #2
    b.ne    8f
    mov     x23, x3                         /* Data */
    mov     x24, x4
    b       4b
6:  cbz     x23, 8f
    ldr     x0, [sp, #96]
    mov     x1, x23
    mov     x2, x24
    mov     x3, x25
    mov     x4, x26
    mov     x5, x22
    bl      libp2p_verify_static
    cbz     x0, 8f
    ldr     x1, [sp, #96]
    str     x1, [x19, #C_KEY_TYPE]
    add     x0, x19, #C_RID
    mov     x2, x23
    mov     x3, x24
    bl      libp2p_peer_id
    str     x0, [x19, #C_RID_LEN]
    mov     x0, #0
    b       9f
8:  mov     x0, #1
9:  LEAVE   16
END_FUNCTION libp2p_noise_payload

/*
 * libp2p_noise_split(conn): Split: (k1, k2) = HKDF(ck, empty); the initiator
 * sends with k1 and the responder with k2. Sets the transport flag.
 */
LOCAL_FUNCTION libp2p_noise_split
    ENTER   0
    mov     x19, x0
    mov     x1, x19
    mov     x2, #0
    bl      libp2p_ns_hkdf
    add     x20, x28, #SC_OKM + LIBP2P_BL_FIXED
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_OUTBOUND
    add     x21, x20, #32
    csel    x22, x20, x21, ne               /* send key */
    csel    x23, x21, x20, ne               /* receive key */
    add     x0, x19, #C_TX_K
    mov     x1, x22
    mov     x2, #32
    bl      libp2p_copy
    add     x0, x19, #C_RX_K
    mov     x1, x23
    mov     x2, #32
    bl      libp2p_copy
    str     xzr, [x19, #C_TX_N]
    str     xzr, [x19, #C_RX_N]
    ldr     x9, [x19, #C_FLAGS]
    orr     x9, x9, #CF_TRANSPORT
    str     x9, [x19, #C_FLAGS]
    add     x0, x19, #C_NS_E                /* forget the ephemeral key */
    mov     x1, #32
    bl      libp2p_zero
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
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x19, #C_FLAGS]
    ldr     x10, [x19, #C_NS_STEP]
    tst     x9, #CF_OUTBOUND
    b.ne    30f
    cbnz    x10, 20f

    /* Responder, message 1: <- e, then the payload. */
    cmp     x21, #32
    b.lo    80f
    add     x0, x19, #C_NS_RE
    mov     x1, x20
    mov     x2, #32
    bl      libp2p_copy
    mov     x0, x19
    add     x1, x19, #C_NS_RE
    mov     x2, #32
    bl      libp2p_ns_mixhash
    mov     x0, x19
    add     x1, x20, #32
    sub     x2, x21, #32
    bl      libp2p_ns_decrypt_hash
    cbnz    x0, 80f
    /* message 2: -> e, ee, s, es, then our payload. */
    ldr     x22, [x27, #ST_PAYLOAD_LEN]
    add     x1, x22, #(2 + 32 + 48 + 16)
    mov     x0, x19
    bl      libp2p_noise_out
    cbz     x0, 80f
    mov     x23, x0
    add     x9, x22, #(32 + 48 + 16)
    lsr     x10, x9, #8
    strb    w10, [x23]
    strb    w9, [x23, #1]
    add     x0, x23, #2
    add     x1, x19, #C_NS_EPUB
    mov     x2, #32
    bl      libp2p_copy
    mov     x0, x19
    add     x1, x19, #C_NS_EPUB
    mov     x2, #32
    bl      libp2p_ns_mixhash
    mov     x0, x19
    add     x1, x19, #C_NS_E
    add     x2, x19, #C_NS_RE
    bl      libp2p_ns_dh
    cbnz    x0, 80f
    mov     x0, x19
    add     x1, x27, #ST_NOISE_PUB
    mov     x2, #32
    add     x3, x23, #34
    bl      libp2p_ns_encrypt_hash
    mov     x24, x0
    mov     x0, x19
    add     x1, x27, #ST_NOISE_PRIV
    add     x2, x19, #C_NS_RE
    bl      libp2p_ns_dh
    cbnz    x0, 80f
    mov     x0, x19
    add     x1, x27, #ST_PAYLOAD
    mov     x2, x22
    mov     x3, x24
    bl      libp2p_ns_encrypt_hash
    mov     x9, #1
    str     x9, [x19, #C_NS_STEP]
    b       70f

    /* Responder, message 3: <- s, se, then the payload. */
20: cmp     x21, #48
    b.lo    80f
    mov     x0, x19
    mov     x1, x20
    mov     x2, #48
    bl      libp2p_ns_decrypt_hash
    cbnz    x0, 80f
    add     x0, x19, #C_NS_RS
    SCR     x1, (SC_PLAIN + LIBP2P_BL_FIXED)
    mov     x2, #32
    bl      libp2p_copy
    mov     x0, x19
    add     x1, x19, #C_NS_E
    add     x2, x19, #C_NS_RS
    bl      libp2p_ns_dh
    cbnz    x0, 80f
    mov     x0, x19
    add     x1, x20, #48
    sub     x2, x21, #48
    bl      libp2p_ns_decrypt_hash
    cbnz    x0, 80f
    mov     x0, x19
    SCR     x1, (SC_PLAIN + LIBP2P_BL_FIXED)
    ldr     x2, [x28, #SC_PLAIN + LIBP2P_BL_COUNT]
    add     x3, x19, #C_NS_RS
    bl      libp2p_noise_payload
    cbnz    x0, 80f
    mov     x0, x19
    bl      libp2p_noise_split
    mov     x9, #2
    str     x9, [x19, #C_NS_STEP]
    b       70f

    /* Initiator, message 2: <- e, ee, s, es, then the payload. */
30: cbnz    x10, 80f
    cmp     x21, #(32 + 48)
    b.lo    80f
    add     x0, x19, #C_NS_RE
    mov     x1, x20
    mov     x2, #32
    bl      libp2p_copy
    mov     x0, x19
    add     x1, x19, #C_NS_RE
    mov     x2, #32
    bl      libp2p_ns_mixhash
    mov     x0, x19
    add     x1, x19, #C_NS_E
    add     x2, x19, #C_NS_RE
    bl      libp2p_ns_dh
    cbnz    x0, 80f
    mov     x0, x19
    add     x1, x20, #32
    mov     x2, #48
    bl      libp2p_ns_decrypt_hash
    cbnz    x0, 80f
    add     x0, x19, #C_NS_RS
    SCR     x1, (SC_PLAIN + LIBP2P_BL_FIXED)
    mov     x2, #32
    bl      libp2p_copy
    mov     x0, x19
    add     x1, x19, #C_NS_E
    add     x2, x19, #C_NS_RS
    bl      libp2p_ns_dh
    cbnz    x0, 80f
    mov     x0, x19
    add     x1, x20, #80
    sub     x2, x21, #80
    bl      libp2p_ns_decrypt_hash
    cbnz    x0, 80f
    mov     x0, x19
    SCR     x1, (SC_PLAIN + LIBP2P_BL_FIXED)
    ldr     x2, [x28, #SC_PLAIN + LIBP2P_BL_COUNT]
    add     x3, x19, #C_NS_RS
    bl      libp2p_noise_payload
    cbnz    x0, 80f
    ldr     x1, [x19, #C_EXP_ID_LEN]        /* a dial: the responder must be the dialled peer */
    cbz     x1, 31f
    add     x0, x19, #C_EXP_ID
    add     x2, x19, #C_RID
    ldr     x3, [x19, #C_RID_LEN]
    bl      libp2p_compare
    cbz     x0, 81f
    /* message 3: -> s, se, then our payload. */
31:
    ldr     x22, [x27, #ST_PAYLOAD_LEN]
    add     x1, x22, #(2 + 48 + 16)
    mov     x0, x19
    bl      libp2p_noise_out
    cbz     x0, 80f
    mov     x23, x0
    add     x9, x22, #(48 + 16)
    lsr     x10, x9, #8
    strb    w10, [x23]
    strb    w9, [x23, #1]
    mov     x0, x19
    add     x1, x27, #ST_NOISE_PUB
    mov     x2, #32
    add     x3, x23, #2
    bl      libp2p_ns_encrypt_hash
    mov     x24, x0
    mov     x0, x19
    add     x1, x27, #ST_NOISE_PRIV
    add     x2, x19, #C_NS_RE
    bl      libp2p_ns_dh
    cbnz    x0, 80f
    mov     x0, x19
    add     x1, x27, #ST_PAYLOAD
    mov     x2, x22
    mov     x3, x24
    bl      libp2p_ns_encrypt_hash
    mov     x0, x19
    bl      libp2p_noise_split
    mov     x9, #2
    str     x9, [x19, #C_NS_STEP]
70: mov     x0, #0
    b       99f
80: mov     x0, #1
    b       99f
81: mov     x0, #2
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
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    SCR     x24, SC_PLAIN
    add     x9, x24, #LIBP2P_BL_FIXED       /* the plaintext may already be in place */
    cmp     x20, x9
    b.eq    1f
    add     x0, x24, #LIBP2P_BL_FIXED
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
1:  add     x9, x21, #LIBP2P_BL_FIXED
    str     x9, [x24]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x24, #8]
    str     x21, [x24, #16]
    str     x9, [x28, #SC_EMPTY]
    str     x9, [x28, #SC_EMPTY + 8]
    str     xzr, [x28, #SC_EMPTY + 16]
    ldr     x0, [x19, #C_TX_N]
    add     x9, x0, #1
    str     x9, [x19, #C_TX_N]
    bl      libp2p_ns_nonce
    SCR     x25, SC_SEAL
    add     x9, x21, #(LIBP2P_BL_FIXED + 16)
    str     x9, [x25]
    add     x0, x19, #C_TX_K
    add     x1, x28, #SC_NONCE
    mov     x2, x24
    add     x3, x28, #SC_EMPTY
    mov     x4, x25
    CALL_GLOBAL crypto_chacha20_aead_encrypt
    add     x9, x21, #16
    lsr     x10, x9, #8
    strb    w10, [x22]
    strb    w9, [x22, #1]
    add     x0, x22, #2
    add     x1, x25, #LIBP2P_BL_FIXED
    mov     x2, x9
    bl      libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_noise_seal

/*
 * libp2p_noise_open(conn, src, n) -> 0 with the plaintext in the PLAIN ByteList
 * of the scratch: the n bytes at src (a transport message without its
 * length) decrypted with the receive key; 1 when the tag does not match.
 */
LOCAL_FUNCTION libp2p_noise_open
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    cmp     x21, #16
    b.lo    8f
    SCR     x25, SC_SEAL
    add     x9, x21, #LIBP2P_BL_FIXED
    str     x9, [x25]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x25, #8]
    str     x21, [x25, #16]
    add     x0, x25, #24
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x28, #SC_EMPTY]
    str     x9, [x28, #SC_EMPTY + 8]
    str     xzr, [x28, #SC_EMPTY + 16]
    ldr     x0, [x19, #C_RX_N]
    add     x9, x0, #1
    str     x9, [x19, #C_RX_N]
    bl      libp2p_ns_nonce
    SCR     x24, SC_PLAIN
    sub     x9, x21, #16
    add     x9, x9, #LIBP2P_BL_FIXED
    str     x9, [x24]
    add     x0, x19, #C_RX_K
    add     x1, x28, #SC_NONCE
    mov     x2, x25
    add     x3, x28, #SC_EMPTY
    mov     x4, x24
    CALL_GLOBAL crypto_chacha20_aead_decrypt
    cbnz    x0, 8f
    mov     x0, #0
    b       9f
8:  mov     x0, #1
9:  LEAVE   0
END_FUNCTION libp2p_noise_open
