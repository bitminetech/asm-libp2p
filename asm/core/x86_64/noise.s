/*
 * Noise of the x86-64 core: the libp2p Noise handshake
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
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    SCR     %r13, SC_MIX
    lea     (LIBP2P_BL_FIXED + 32)(%r12), %rax
    mov     %rax, LIBP2P_BL_SIZE(%r13)
    movq    $LIBP2P_BL_FIXED, LIBP2P_BL_OFFSET(%r13)
    lea     32(%r12), %rax
    mov     %rax, LIBP2P_BL_COUNT(%r13)
    lea     LIBP2P_BL_FIXED(%r13), %rdi
    lea     C_NS_H(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     %rax, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    mov     %r13, %rdi
    lea     C_NS_H(%rbx), %rsi
    CALL_GLOBAL crypto_sha256
    LEAVE   0
END_FUNCTION libp2p_ns_mixhash

/*
 * libp2p_ns_hkdf(conn, ikm, n): HKDF(ck, ikm) of the Noise spec: the 64 output
 * bytes at the OKM of the scratch, then ck = the first 32.
 * r13 the work area: the salt ByteList, then the ikm ByteList at 56.
 */
LOCAL_FUNCTION libp2p_ns_hkdf
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    SCR     %r13, SC_WORK
    movq    $56, (%r13)                     /* salt: ck */
    movq    $LIBP2P_BL_FIXED, 8(%r13)
    movq    $32, 16(%r13)
    lea     24(%r13), %rdi
    lea     C_NS_CK(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    lea     LIBP2P_BL_FIXED(%r12), %rax     /* ikm */
    mov     %rax, 56(%r13)
    movq    $LIBP2P_BL_FIXED, 64(%r13)
    mov     %r12, 72(%r13)
    lea     80(%r13), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    movq    $SC_HMAC_SIZE, SC_HMAC(%r14)
    mov     %r13, %rdi
    lea     56(%r13), %rsi
    lea     SC_HMAC(%r14), %rdx
    lea     (SC_PRK + LIBP2P_BL_FIXED)(%r14), %rcx
    CALL_GLOBAL crypto_hkdf_extract
    movq    $(LIBP2P_BL_FIXED + 32), SC_PRK(%r14)   /* PRK as a ByteList for Expand */
    movq    $LIBP2P_BL_FIXED, (SC_PRK + 8)(%r14)
    movq    $32, (SC_PRK + 16)(%r14)
    movq    $SC_HMAC_SIZE, SC_HMAC(%r14)
    movq    $LIBP2P_BL_FIXED, SC_EMPTY(%r14)
    movq    $LIBP2P_BL_FIXED, (SC_EMPTY + 8)(%r14)
    movq    $0, (SC_EMPTY + 16)(%r14)
    movq    $64, SC_LENGTH(%r14)
    movq    $(LIBP2P_BL_FIXED + 64), SC_OKM(%r14)
    lea     SC_PRK(%r14), %rdi
    lea     SC_EMPTY(%r14), %rsi
    lea     SC_LENGTH(%r14), %rdx
    lea     SC_HMAC(%r14), %rcx
    lea     SC_OKM(%r14), %r8
    CALL_GLOBAL crypto_hkdf_expand
    lea     C_NS_CK(%rbx), %rdi
    lea     (SC_OKM + LIBP2P_BL_FIXED)(%r14), %rsi
    mov     $32, %edx
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_ns_hkdf

/* libp2p_ns_mixkey(conn, ikm): MixKey of a 32-byte DH output: ck and k from HKDF, n = 0. */
LOCAL_FUNCTION libp2p_ns_mixkey
    ENTER   0
    mov     %rdi, %rbx
    mov     $32, %edx
    call    libp2p_ns_hkdf
    lea     C_NS_K(%rbx), %rdi
    lea     (SC_OKM + LIBP2P_BL_FIXED + 32)(%r14), %rsi
    mov     $32, %edx
    call    libp2p_copy
    movq    $0, C_NS_N(%rbx)
    movq    $1, C_NS_HASK(%rbx)
    LEAVE   0
END_FUNCTION libp2p_ns_mixkey

/* libp2p_ns_nonce(n): the 12-byte ChaCha20-Poly1305 nonce of Noise at the scratch: 4 zero bytes, then n little endian. A leaf. */
LOCAL_FUNCTION libp2p_ns_nonce
    UNWIND_END_PROLOGUE
    movl    $0, SC_NONCE(%r14)
    mov     %rdi, (SC_NONCE + 4)(%r14)
    movl    $0, (SC_NONCE + 12)(%r14)
    ret
END_FUNCTION libp2p_ns_nonce

/*
 * libp2p_ns_encrypt_hash(conn, src, n, dst) -> dst after: EncryptAndHash of
 * the n bytes at src (at most 4096): with k set, ChaCha20-Poly1305 with ad
 * = h and n + 16 bytes out; without, the bytes as they are. Then MixHash of
 * what it wrote. X23 the bytes written.
 */
LOCAL_FUNCTION libp2p_ns_encrypt_hash
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    cmpq    $0, C_NS_HASK(%rbx)
    jne     1f
    mov     %r13, %rdi                      /* no key: the plaintext */
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    mov     %r12, X23(%rsp)
    jmp     2f
1:  SCR     %rax, SC_PLAIN
    lea     LIBP2P_BL_FIXED(%r12), %rcx
    mov     %rcx, (%rax)
    movq    $LIBP2P_BL_FIXED, 8(%rax)
    mov     %r12, 16(%rax)
    lea     24(%rax), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    movq    $(LIBP2P_BL_FIXED + 32), SC_AAD(%r14)   /* ad = h */
    movq    $LIBP2P_BL_FIXED, (SC_AAD + 8)(%r14)
    movq    $32, (SC_AAD + 16)(%r14)
    lea     (SC_AAD + 24)(%r14), %rdi
    lea     C_NS_H(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     C_NS_N(%rbx), %rdi
    lea     1(%rdi), %rax
    mov     %rax, C_NS_N(%rbx)
    call    libp2p_ns_nonce
    lea     (LIBP2P_BL_FIXED + 16)(%r12), %rax
    mov     %rax, SC_SEAL(%r14)
    lea     C_NS_K(%rbx), %rdi
    lea     SC_NONCE(%r14), %rsi
    lea     SC_PLAIN(%r14), %rdx
    lea     SC_AAD(%r14), %rcx
    lea     SC_SEAL(%r14), %r8
    CALL_GLOBAL crypto_chacha20_aead_encrypt
    lea     16(%r12), %rdx
    mov     %rdx, X23(%rsp)
    mov     %r13, %rdi
    lea     (SC_SEAL + LIBP2P_BL_FIXED)(%r14), %rsi
    call    libp2p_copy
2:  mov     %rbx, %rdi
    mov     %r13, %rsi
    mov     X23(%rsp), %rdx
    call    libp2p_ns_mixhash
    mov     %r13, %rax
    add     X23(%rsp), %rax
    LEAVE   0
END_FUNCTION libp2p_ns_encrypt_hash

/*
 * libp2p_ns_decrypt_hash(conn, src, n) -> 0, with the plaintext in the PLAIN
 * ByteList of the scratch; 1 when the tag does not match or n is below 16
 * with k set. DecryptAndHash: MixHash of the n bytes at src after.
 */
LOCAL_FUNCTION libp2p_ns_decrypt_hash
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    cmpq    $0, C_NS_HASK(%rbx)
    jne     1f
    SCR     %rax, SC_PLAIN                  /* no key: the bytes as they are */
    lea     LIBP2P_BL_FIXED(%r12), %rcx
    mov     %rcx, (%rax)
    movq    $LIBP2P_BL_FIXED, 8(%rax)
    mov     %r12, 16(%rax)
    lea     24(%rax), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    jmp     2f
1:  cmp     $16, %r12
    jb      8f
    SCR     %rax, SC_SEAL
    lea     LIBP2P_BL_FIXED(%r12), %rcx
    mov     %rcx, (%rax)
    movq    $LIBP2P_BL_FIXED, 8(%rax)
    mov     %r12, 16(%rax)
    lea     24(%rax), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    movq    $(LIBP2P_BL_FIXED + 32), SC_AAD(%r14)
    movq    $LIBP2P_BL_FIXED, (SC_AAD + 8)(%r14)
    movq    $32, (SC_AAD + 16)(%r14)
    lea     (SC_AAD + 24)(%r14), %rdi
    lea     C_NS_H(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     C_NS_N(%rbx), %rdi
    lea     1(%rdi), %rax
    mov     %rax, C_NS_N(%rbx)
    call    libp2p_ns_nonce
    lea     (LIBP2P_BL_FIXED - 16)(%r12), %rax
    mov     %rax, SC_PLAIN(%r14)
    lea     C_NS_K(%rbx), %rdi
    lea     SC_NONCE(%r14), %rsi
    lea     SC_SEAL(%r14), %rdx
    lea     SC_AAD(%r14), %rcx
    lea     SC_PLAIN(%r14), %r8
    CALL_GLOBAL crypto_chacha20_aead_decrypt
    test    %rax, %rax
    jnz     8f
2:  mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_ns_mixhash
    xor     %eax, %eax
    jmp     9f
8:  mov     $1, %eax
9:  LEAVE   0
END_FUNCTION libp2p_ns_decrypt_hash

/* libp2p_ns_dh(conn, private, public) -> 0, after MixKey(DH(private, public)); 1 when the DH result is all zero. */
LOCAL_FUNCTION libp2p_ns_dh
    ENTER   0, 32
    mov     %rdi, %rbx
    mov     %rsi, %rdi
    mov     %rdx, %rsi
    lea     32(%rsp), %rdx
    CALL_GLOBAL crypto_x25519
    test    %rax, %rax
    jnz     8f
    mov     %rbx, %rdi
    lea     32(%rsp), %rsi
    call    libp2p_ns_mixkey
    xor     %eax, %eax
    jmp     9f
8:  mov     $1, %eax
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
    mov     C_OUT_LEN(%rdi), %rdx
    lea     (%rdx,%rsi), %rcx
    cmp     $C_OUT_CAP, %rcx
    ja      8f
    mov     %rcx, C_OUT_LEN(%rdi)
    testq   $CF_TRANSPORT, C_FLAGS(%rdi)
    jnz     1f
    mov     %rcx, C_OUT_RAW(%rdi)           /* before the transport keys, bytes go out as they are */
1:  lea     C_OUT(%rdi,%rdx), %rax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_noise_out

/*
 * libp2p_noise_begin(conn): InitializeSymmetric, MixHash of the empty
 * prologue, a fresh e; the initiator then writes message 1: e and an
 * empty payload, with its 2-byte length.
 */
LOCAL_FUNCTION libp2p_noise_begin
    ENTER   0
    mov     %rdi, %rbx
    lea     C_NS_H(%rbx), %rdi
    lea     420b(%rip), %rsi
    mov     $32, %edx
    call    libp2p_copy
    lea     C_NS_CK(%rbx), %rdi
    lea     420b(%rip), %rsi
    mov     $32, %edx
    call    libp2p_copy
    movq    $0, C_NS_HASK(%rbx)
    movq    $0, C_NS_N(%rbx)
    movq    $0, C_NS_STEP(%rbx)
    mov     %rbx, %rdi
    mov     %rbx, %rsi
    xor     %edx, %edx
    call    libp2p_ns_mixhash
    lea     C_NS_E(%rbx), %rdi
    mov     $32, %esi
    call    libp2p_random
    lea     C_NS_E(%rbx), %rdi
    lea     421b(%rip), %rsi
    lea     C_NS_EPUB(%rbx), %rdx
    CALL_GLOBAL crypto_x25519
    testq   $CF_OUTBOUND, C_FLAGS(%rbx)
    jz      9f
    mov     %rbx, %rdi                      /* -> e */
    mov     $34, %esi
    call    libp2p_noise_out
    mov     %rax, %rbp
    movb    $0, (%rbp)
    movb    $32, 1(%rbp)
    lea     2(%rbp), %rdi
    lea     C_NS_EPUB(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     %rbx, %rdi
    lea     C_NS_EPUB(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_ns_mixhash
    mov     %rbx, %rdi                      /* the empty payload */
    mov     %rbx, %rsi
    xor     %edx, %edx
    call    libp2p_ns_mixhash
9:  LEAVE   0
END_FUNCTION libp2p_noise_begin

/*
 * libp2p_noise_payload(conn, p, n, rs) -> 0 when the NoiseHandshakePayload at p
 * has an Ed25519 or secp256k1 identity_key and an identity_sig of
 * "noise-libp2p-static-key:" || rs by it; the key type and the peer ID go
 * to the connection. 1 otherwise.
 * rbx conn, rbp position, r12 end, r13 rs, X23 key, X24 key length,
 * X25 signature, X26 signature length; 32(%rsp) the key type.
 */
LOCAL_FUNCTION libp2p_noise_payload
    ENTER   16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    mov     %rcx, %r13
    movq    $0, X23(%rsp)
    movq    $0, X25(%rsp)
1:  mov     %rbp, %rdi                      /* the payload fields */
    mov     %r12, %rsi
    call    libp2p_pb_next
    test    %rax, %rax
    jz      3f
    cmp     $NONE, %rax
    je      8f
    mov     %r8, %rbp
    cmp     $2, %rcx
    jne     1b
    cmp     $1, %rdx
    jne     2f
    mov     %rsi, X23(%rsp)                 /* identity_key */
    mov     %rdi, X24(%rsp)
    jmp     1b
2:  cmp     $2, %rdx
    jne     1b
    mov     %rsi, X25(%rsp)                 /* identity_sig */
    mov     %rdi, X26(%rsp)
    jmp     1b
3:  cmpq    $0, X23(%rsp)
    je      8f
    cmpq    $0, X25(%rsp)
    je      8f
    mov     X23(%rsp), %rbp                 /* the PublicKey fields */
    mov     X24(%rsp), %r12
    add     %rbp, %r12
    movq    $0, X23(%rsp)
    movq    $NONE, X24(%rsp)
    movq    $0, 32(%rsp)
4:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    test    %rax, %rax
    jz      6f
    cmp     $NONE, %rax
    je      8f
    mov     %r8, %rbp
    cmp     $1, %rdx
    jne     5f
    test    %rcx, %rcx
    jnz     8f
    mov     %rsi, 32(%rsp)                  /* Type */
    jmp     4b
5:  cmp     $2, %rdx
    jne     4b
    cmp     $2, %rcx
    jne     8f
    mov     %rsi, X23(%rsp)                 /* Data */
    mov     %rdi, X24(%rsp)
    jmp     4b
6:  cmpq    $0, X23(%rsp)
    je      8f
    mov     32(%rsp), %rdi
    mov     X23(%rsp), %rsi
    mov     X24(%rsp), %rdx
    mov     X25(%rsp), %rcx
    mov     X26(%rsp), %r8
    mov     %r13, %r9
    call    libp2p_verify_static
    test    %rax, %rax
    jz      8f
    mov     32(%rsp), %rsi
    mov     %rsi, C_KEY_TYPE(%rbx)
    lea     C_RID(%rbx), %rdi
    mov     X23(%rsp), %rdx
    mov     X24(%rsp), %rcx
    call    libp2p_peer_id
    mov     %rax, C_RID_LEN(%rbx)
    xor     %eax, %eax
    jmp     9f
8:  mov     $1, %eax
9:  LEAVE   16
END_FUNCTION libp2p_noise_payload

/*
 * libp2p_noise_split(conn): Split: (k1, k2) = HKDF(ck, empty); the initiator
 * sends with k1 and the responder with k2. Sets the transport flag.
 * rbp the send key, r12 the receive key.
 */
LOCAL_FUNCTION libp2p_noise_split
    ENTER   0
    mov     %rdi, %rbx
    mov     %rbx, %rsi
    xor     %edx, %edx
    call    libp2p_ns_hkdf
    lea     (SC_OKM + LIBP2P_BL_FIXED)(%r14), %rbp
    lea     32(%rbp), %r12
    testq   $CF_OUTBOUND, C_FLAGS(%rbx)
    jnz     1f
    xchg    %rbp, %r12
1:  lea     C_TX_K(%rbx), %rdi
    mov     %rbp, %rsi
    mov     $32, %edx
    call    libp2p_copy
    lea     C_RX_K(%rbx), %rdi
    mov     %r12, %rsi
    mov     $32, %edx
    call    libp2p_copy
    movq    $0, C_TX_N(%rbx)
    movq    $0, C_RX_N(%rbx)
    orq     $CF_TRANSPORT, C_FLAGS(%rbx)
    lea     C_NS_E(%rbx), %rdi              /* forget the ephemeral key */
    mov     $32, %esi
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
 * rbx conn, rbp msg, r12 n, r13 our payload length, X23 the output, X24
 * the place after s.
 */
LOCAL_FUNCTION libp2p_noise_message
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     C_NS_STEP(%rbx), %rcx
    testq   $CF_OUTBOUND, C_FLAGS(%rbx)
    jnz     30f
    test    %rcx, %rcx
    jnz     20f

    /* Responder, message 1: <- e, then the payload. */
    cmp     $32, %r12
    jb      80f
    lea     C_NS_RE(%rbx), %rdi
    mov     %rbp, %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     %rbx, %rdi
    lea     C_NS_RE(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_ns_mixhash
    mov     %rbx, %rdi
    lea     32(%rbp), %rsi
    lea     -32(%r12), %rdx
    call    libp2p_ns_decrypt_hash
    test    %rax, %rax
    jnz     80f
    /* message 2: -> e, ee, s, es, then our payload. */
    mov     ST_PAYLOAD_LEN(%r15), %r13
    lea     (2 + 32 + 48 + 16)(%r13), %rsi
    mov     %rbx, %rdi
    call    libp2p_noise_out
    test    %rax, %rax
    jz      80f
    mov     %rax, X23(%rsp)
    lea     (32 + 48 + 16)(%r13), %rcx
    mov     %rcx, %rdx
    shr     $8, %rdx
    movb    %dl, (%rax)
    movb    %cl, 1(%rax)
    lea     2(%rax), %rdi
    lea     C_NS_EPUB(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     %rbx, %rdi
    lea     C_NS_EPUB(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_ns_mixhash
    mov     %rbx, %rdi
    lea     C_NS_E(%rbx), %rsi
    lea     C_NS_RE(%rbx), %rdx
    call    libp2p_ns_dh
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    lea     ST_NOISE_PUB(%r15), %rsi
    mov     $32, %edx
    mov     X23(%rsp), %rcx
    add     $34, %rcx
    call    libp2p_ns_encrypt_hash
    mov     %rax, X24(%rsp)
    mov     %rbx, %rdi
    lea     ST_NOISE_PRIV(%r15), %rsi
    lea     C_NS_RE(%rbx), %rdx
    call    libp2p_ns_dh
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    lea     ST_PAYLOAD(%r15), %rsi
    mov     %r13, %rdx
    mov     X24(%rsp), %rcx
    call    libp2p_ns_encrypt_hash
    movq    $1, C_NS_STEP(%rbx)
    jmp     70f

    /* Responder, message 3: <- s, se, then the payload. */
20: cmp     $48, %r12
    jb      80f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     $48, %edx
    call    libp2p_ns_decrypt_hash
    test    %rax, %rax
    jnz     80f
    lea     C_NS_RS(%rbx), %rdi
    lea     (SC_PLAIN + LIBP2P_BL_FIXED)(%r14), %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     %rbx, %rdi
    lea     C_NS_E(%rbx), %rsi
    lea     C_NS_RS(%rbx), %rdx
    call    libp2p_ns_dh
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    lea     48(%rbp), %rsi
    lea     -48(%r12), %rdx
    call    libp2p_ns_decrypt_hash
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    lea     (SC_PLAIN + LIBP2P_BL_FIXED)(%r14), %rsi
    mov     (SC_PLAIN + LIBP2P_BL_COUNT)(%r14), %rdx
    lea     C_NS_RS(%rbx), %rcx
    call    libp2p_noise_payload
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    call    libp2p_noise_split
    movq    $2, C_NS_STEP(%rbx)
    jmp     70f

    /* Initiator, message 2: <- e, ee, s, es, then the payload. */
30: test    %rcx, %rcx
    jnz     80f
    cmp     $(32 + 48), %r12
    jb      80f
    lea     C_NS_RE(%rbx), %rdi
    mov     %rbp, %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     %rbx, %rdi
    lea     C_NS_RE(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_ns_mixhash
    mov     %rbx, %rdi
    lea     C_NS_E(%rbx), %rsi
    lea     C_NS_RE(%rbx), %rdx
    call    libp2p_ns_dh
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    lea     32(%rbp), %rsi
    mov     $48, %edx
    call    libp2p_ns_decrypt_hash
    test    %rax, %rax
    jnz     80f
    lea     C_NS_RS(%rbx), %rdi
    lea     (SC_PLAIN + LIBP2P_BL_FIXED)(%r14), %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     %rbx, %rdi
    lea     C_NS_E(%rbx), %rsi
    lea     C_NS_RS(%rbx), %rdx
    call    libp2p_ns_dh
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    lea     80(%rbp), %rsi
    lea     -80(%r12), %rdx
    call    libp2p_ns_decrypt_hash
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    lea     (SC_PLAIN + LIBP2P_BL_FIXED)(%r14), %rsi
    mov     (SC_PLAIN + LIBP2P_BL_COUNT)(%r14), %rdx
    lea     C_NS_RS(%rbx), %rcx
    call    libp2p_noise_payload
    test    %rax, %rax
    jnz     80f
    mov     C_EXP_ID_LEN(%rbx), %rsi        /* a dial: the responder must be the dialled peer */
    test    %rsi, %rsi
    jz      31f
    lea     C_EXP_ID(%rbx), %rdi
    lea     C_RID(%rbx), %rdx
    mov     C_RID_LEN(%rbx), %rcx
    call    libp2p_compare
    test    %rax, %rax
    jz      81f
    /* message 3: -> s, se, then our payload. */
31: mov     ST_PAYLOAD_LEN(%r15), %r13
    lea     (2 + 48 + 16)(%r13), %rsi
    mov     %rbx, %rdi
    call    libp2p_noise_out
    test    %rax, %rax
    jz      80f
    mov     %rax, X23(%rsp)
    lea     (48 + 16)(%r13), %rcx
    mov     %rcx, %rdx
    shr     $8, %rdx
    movb    %dl, (%rax)
    movb    %cl, 1(%rax)
    mov     %rbx, %rdi
    lea     ST_NOISE_PUB(%r15), %rsi
    mov     $32, %edx
    mov     X23(%rsp), %rcx
    add     $2, %rcx
    call    libp2p_ns_encrypt_hash
    mov     %rax, X24(%rsp)
    mov     %rbx, %rdi
    lea     ST_NOISE_PRIV(%r15), %rsi
    lea     C_NS_RE(%rbx), %rdx
    call    libp2p_ns_dh
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    lea     ST_PAYLOAD(%r15), %rsi
    mov     %r13, %rdx
    mov     X24(%rsp), %rcx
    call    libp2p_ns_encrypt_hash
    mov     %rbx, %rdi
    call    libp2p_noise_split
    movq    $2, C_NS_STEP(%rbx)
70: xor     %eax, %eax
    jmp     99f
80: mov     $1, %eax
    jmp     99f
81: mov     $2, %eax
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
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    lea     (SC_PLAIN + LIBP2P_BL_FIXED)(%r14), %rdi    /* the plaintext may already be in place */
    cmp     %rdi, %rbp
    je      1f
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
1:  lea     LIBP2P_BL_FIXED(%r12), %rax
    mov     %rax, SC_PLAIN(%r14)
    movq    $LIBP2P_BL_FIXED, (SC_PLAIN + 8)(%r14)
    mov     %r12, (SC_PLAIN + 16)(%r14)
    movq    $LIBP2P_BL_FIXED, SC_EMPTY(%r14)
    movq    $LIBP2P_BL_FIXED, (SC_EMPTY + 8)(%r14)
    movq    $0, (SC_EMPTY + 16)(%r14)
    mov     C_TX_N(%rbx), %rdi
    lea     1(%rdi), %rax
    mov     %rax, C_TX_N(%rbx)
    call    libp2p_ns_nonce
    lea     (LIBP2P_BL_FIXED + 16)(%r12), %rax
    mov     %rax, SC_SEAL(%r14)
    lea     C_TX_K(%rbx), %rdi
    lea     SC_NONCE(%r14), %rsi
    lea     SC_PLAIN(%r14), %rdx
    lea     SC_EMPTY(%r14), %rcx
    lea     SC_SEAL(%r14), %r8
    CALL_GLOBAL crypto_chacha20_aead_encrypt
    lea     16(%r12), %rdx
    mov     %rdx, %rax
    shr     $8, %rax
    movb    %al, (%r13)
    movb    %dl, 1(%r13)
    lea     2(%r13), %rdi
    lea     (SC_SEAL + LIBP2P_BL_FIXED)(%r14), %rsi
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
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    cmp     $16, %r12
    jb      8f
    SCR     %rax, SC_SEAL
    lea     LIBP2P_BL_FIXED(%r12), %rcx
    mov     %rcx, (%rax)
    movq    $LIBP2P_BL_FIXED, 8(%rax)
    mov     %r12, 16(%rax)
    lea     24(%rax), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    movq    $LIBP2P_BL_FIXED, SC_EMPTY(%r14)
    movq    $LIBP2P_BL_FIXED, (SC_EMPTY + 8)(%r14)
    movq    $0, (SC_EMPTY + 16)(%r14)
    mov     C_RX_N(%rbx), %rdi
    lea     1(%rdi), %rax
    mov     %rax, C_RX_N(%rbx)
    call    libp2p_ns_nonce
    lea     (LIBP2P_BL_FIXED - 16)(%r12), %rax
    mov     %rax, SC_PLAIN(%r14)
    lea     C_RX_K(%rbx), %rdi
    lea     SC_NONCE(%r14), %rsi
    lea     SC_SEAL(%r14), %rdx
    lea     SC_EMPTY(%r14), %rcx
    lea     SC_PLAIN(%r14), %r8
    CALL_GLOBAL crypto_chacha20_aead_decrypt
    test    %rax, %rax
    jnz     8f
    xor     %eax, %eax
    jmp     9f
8:  mov     $1, %eax
9:  LEAVE   0
END_FUNCTION libp2p_noise_open
