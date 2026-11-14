# Node

## Contents

### Functions

- [`libp2p_state_size`](#function-libp2p_state_size): gives the bytes of the state for a config.
- [`libp2p_init`](#function-libp2p_init): builds the state of a node.
- [`libp2p_step`](#function-libp2p_step): handles events and gives actions.
- [`libp2p_layout`](#function-libp2p_layout): checks a config and lays out the state.
- [`libp2p_check_event`](#function-libp2p_check_event): checks one event before any is handled.
- [`libp2p_check_addr`](#function-libp2p_check_addr): checks an address.
- [`libp2p_event_room`](#function-libp2p_event_room): gives the action room an event may need.
- [`libp2p_event`](#function-libp2p_event): hands one event to the function of its kind.
- [`libp2p_timers`](#function-libp2p_timers): runs the deadlines of a step.
- [`libp2p_copy`](#function-libp2p_copy): copies bytes.
- [`libp2p_zero`](#function-libp2p_zero): writes zero bytes.
- [`libp2p_equal`](#function-libp2p_equal): compares bytes.
- [`libp2p_compare`](#function-libp2p_compare): compares two byte strings.
- [`libp2p_hash`](#function-libp2p_hash): hashes bytes for the hash tables.
- [`libp2p_heap_alloc`](#function-libp2p_heap_alloc): takes a heap block.
- [`libp2p_heap_free`](#function-libp2p_heap_free): gives a heap block back.
- [`libp2p_random`](#function-libp2p_random): draws random bytes.
- [`libp2p_random_below`](#function-libp2p_random_below): draws a random number below a bound.
- [`libp2p_reseed`](#function-libp2p_reseed): mixes entropy into the DRBG.
- [`libp2p_action`](#function-libp2p_action): starts an action.
- [`libp2p_room`](#function-libp2p_room): gives the action room left.
- [`libp2p_action_shrink`](#function-libp2p_action_shrink): shortens the last action.
- [`libp2p_wake_at`](#function-libp2p_wake_at): asks for a wakeup.
- [`libp2p_slot`](#function-libp2p_slot): finds the slot of a handle.
- [`libp2p_conn`](#function-libp2p_conn): finds a connection by handle.
- [`libp2p_stream`](#function-libp2p_stream): finds a stream by handle.
- [`libp2p_peer`](#function-libp2p_peer): finds a connected peer by handle.
- [`libp2p_handle`](#function-libp2p_handle): gives the handle of a slot.
- [`libp2p_alloc_slot`](#function-libp2p_alloc_slot): takes a free slot.

### Types

- [`Config`](#type-config): the input of `libp2p_init`.
- [`ProtocolEntry`](#type-protocolentry): a protocol ID.
- [`Tick`](#type-tick): the time and entropy of a step.
- [`StepResult`](#type-stepresult): the output of `libp2p_step`.
- [`ByteList`](#type-bytelist): a list of bytes with its buffer size.
- [`Address`](#type-address): an IP address and TCP port.
- [`Handle`](#type-handle): a reference to a connection, stream, peer or message.
- [`Event`](#type-event): the header of every event.
- [`Action`](#type-action): the header of every action.
- [`WakeupAction`](#type-wakeupaction): when the next step is due.
- [`State`](#type-state): the state of a node.
- [`Scratch`](#type-scratch): the work area of a step.
- [`HeapBlock`](#type-heapblock): a block of the state heap.

### Constants

- `LIBP2P_SCRATCH_SIZE`: the scratch `libp2p_step` needs.
- `LIBP2P_ACTIONS_MIN`: the action room `libp2p_step` needs after the 24-byte header.
- `LIBP2P_STATE_VERSION`: the version `libp2p_init` writes.

## Spec

- Document: [p2p-interface.md](https://github.com/ethereum/consensus-specs/blob/313cbfe561517a81eb11607fea7c6985e562eaa9/specs/phase0/p2p-interface.md), consensus-specs at commit 313cbfe; and [connections/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/connections/README.md), libp2p/specs at commit c750236.
- Section: the network of an Ethereum consensus client: TCP, Noise, mplex and yamux, gossipsub v1.1. ARCHITECTURE.md section 6 gives the event and action model.

## Function `libp2p_state_size`

Gives the bytes of the state that `libp2p_init` builds for a config.

### Signature

```
libp2p_state_size(config, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](node.md#type-config) |
| `size` | output | u64 |

### Returns

- `LIBP2P_OK`: `size` holds the state bytes.
- `LIBP2P_INVALID_CONFIG`: The config breaks a rule of [`Config`](#type-config). `size` is unchanged.

### Caller must

- Set the `size` field of `config` to its bytes, the protocol part included.
- Pass buffers that start at a multiple of 8.

### Function does

- Checks the config as `libp2p_init` does.
- Adds the fixed fields and each table of the config: connections, streams, peers, topics, peer x topic entries, the seen cache and its index, the message cache and its index, pending messages, promises, protocols, then the heap at a multiple of 64.

### Function never

- Writes more than `size` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack: 384 bytes on x86-64 (return address included), 384 bytes on ARM64, 416 bytes on RISC-V, callees included, the most the test runner measured.

### ABI

- Role: L2.
- Symbol: `libp2p_state_size` (`_libp2p_state_size` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `config`, `size`.

## Function `libp2p_init`

Builds the state of a node from a config.

### Signature

```
libp2p_init(config, state) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](node.md#type-config) |
| `state` | output | [`State`](node.md#type-state) |

### Returns

- `LIBP2P_OK`: `state` holds a node with no connections.
- `LIBP2P_BUFFER_TOO_SMALL`: The `size` field of `state` is below what `libp2p_state_size` gives. Nothing is written.
- `LIBP2P_INVALID_CONFIG`: The config breaks a rule of [`Config`](#type-config). Nothing is written.
- `LIBP2P_INVALID_KEY`: A secp256k1 private key is 0 or at least the group order. Nothing is written.

### Caller must

- Set the `size` field of `config` to its bytes, and the `size` field of `state` to its bytes.
- Pass 32 fresh random bytes in `entropy` of the config.
- Keep `state` apart from `config`.
- Pass buffers that start at a multiple of 8.

### Function does

- Checks the config and the state size before it writes anything.
- Writes the public key: compressed secp256k1 (33 bytes) or Ed25519 (32 bytes), and the peer ID: the identity multihash of the PublicKey protobuf.
- Keys the DRBG with SHA-256 of the entropy, and draws the static X25519 key of Noise from it.
- Signs "noise-libp2p-static-key:" and the static public key with the identity key, and keeps the NoiseHandshakePayload.
- Copies the fixed config fields and the protocol list into the state.
- Makes every table empty and the heap one free block.
- Sets the first heartbeat at `now` + `heartbeat_ms`, and the first score decay at `now` + `decay_interval_ms`.

### Function never

- Writes more than `state` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack: 2632 bytes on x86-64 (return address included), 2672 bytes on ARM64, 2784 bytes on RISC-V, callees included, the most the test runner measured.

### ABI

- Role: L2.
- Symbol: `libp2p_init` (`_libp2p_init` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `config`, `state`.

## Function `libp2p_step`

Handles the events since the last step, runs the timers, and gives the actions of the node.

### Signature

```
libp2p_step(state, tick, events, scratch, actions, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | [`State`](node.md#type-state) |
| `tick` | input | [`Tick`](#type-tick) |
| `events` | input | [`ByteList`](node.md#type-bytelist) of [`Event`](#type-event) values |
| `scratch` | scratch | [`Scratch`](#type-scratch) |
| `actions` | output | [`ByteList`](node.md#type-bytelist) of [`Action`](#type-action) values |
| `result` | output | [`StepResult`](#type-stepresult) |

### Returns

- `LIBP2P_OK`: The events in `result` are handled and `actions` holds the actions.
- `LIBP2P_BUFFER_TOO_SMALL`: The `size` of `scratch` is below `LIBP2P_SCRATCH_SIZE`, or the `size` of `actions` is below `LIBP2P_ACTIONS_MIN` + 24. Nothing changes.
- `LIBP2P_INVALID_EVENT`: An event breaks a rule of its kind. Nothing changes.

### Caller must

- Pass a state that `libp2p_init` built, and no other step on it at the same time.
- Pass a fresh tick: the monotonic time in ms and 32 fresh random bytes.
- Set the `size` fields of `scratch` and `actions`.
- Keep every buffer apart from the others.
- Pass buffers that start at a multiple of 8.
- Perform the shell actions (DIAL, ADOPT, REFUSE, SEND, CLOSE) in order, and pass their results as events of a later step.

### Function does

- Checks the scratch size, the action room and every event first.
- Takes the time of the tick, or the time of the last step when the tick is earlier.
- Mixes the entropy of the tick into the DRBG: the key becomes SHA-256 of the key and the 32 bytes.
- Handles the events in order while the action room left covers what the next event may need (`libp2p_event_room`), and writes the count handled to `result`.
- Runs the timers: upgrade deadlines, validation deadlines, retained scores, the gossipsub heartbeat and score decay.
- Turns queued bytes into SEND actions while each connection has send window.
- Ends the actions with one WAKEUP: the time of the next deadline, at most 60 s ahead, or now when events are left.
- Holds the state in x27, r15 or s9 and the scratch in x28, r14 or s10 while it runs; no function it calls changes them.

### Function never

- Writes more than `state`, `scratch`, `actions`, `result` and its own stack.
- Keeps a pointer after it returns.
- Reads an event past the count it handled.
- Makes an OS call.

### Effects

- Events past the count in `result` are not accepted; the caller passes them again in the next step.
- The state owns every connection, stream and message; the caller refers to them by handle.

### Limits

- Stack: 2672 bytes on x86-64 (return address included), 2832 bytes on ARM64, 3024 bytes on RISC-V, callees included, the most the test runner measured.

### ABI

- Role: L2.
- Symbol: `libp2p_step` (`_libp2p_step` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `tick`, `events`, `scratch`, `actions`, `result`.

## Function `libp2p_layout`

Checks a config and writes the offsets and counts of the state tables.

### Signature

```
libp2p_layout(config, tables) -> status, size
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](node.md#type-config) |
| `tables` | output | the table fields of a [`State`](#type-state), from `ST_TABLES` |

### Returns

- `LIBP2P_OK`: `tables` holds the offsets and counts; the second value is the state size.
- `LIBP2P_INVALID_CONFIG`: The config breaks a rule of [`Config`](#type-config); the size is 0.

### Function does

- Applies every rule of [`Config`](#type-config).
- Lays out the tables in this order: connections, streams, peers, topics, peer x topic, seen, seen index, message cache, its index, pending, promises, protocols, heap.

### Function never

- Writes more than `tables` and its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_layout`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the status in x0, rax or a0 and the size in x1, rdx or a1.
- Argument order: `config`, `tables`.

## Function `libp2p_check_event`

Checks that one event is well formed and fits in the event list.

### Signature

```
libp2p_check_event(event, end) -> 0 or 1
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`Event`](#type-event) |
| `end` | input | u64: the address after the last event |

### Function does

- Takes an event whose size is at least 16, a multiple of 8, within `end`, of a known kind, and at least the fixed size of its kind.
- Applies the rules of its kind: addresses, counts and lengths within the event and within their limits.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_check_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 0 when the event is good, else 1, not a status.
- Argument order: `event`, `end`.

## Function `libp2p_check_addr`

Checks the family and port of an address.

### Signature

```
libp2p_check_addr(addr) -> 0 or 1
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `addr` | input | [`Address`](#type-address) |

### Function does

- Takes family 4 or 6 and a port below 65536.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_check_addr`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 0 when the address is good, else 1, not a status.
- Argument order: `addr`.

## Function `libp2p_event_room`

Gives the action bytes that handling one event may need.

### Signature

```
libp2p_event_room(event) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`Event`](#type-event) |

### Function does

- Gives 64 + 16 for each byte of a RECEIVED event.
- Gives 16384 for CLOSED, DIAL_FAILED and DISCONNECT, which can end a connection and its streams.
- Gives 1024 for any other kind.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_event_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the byte count, not a status.
- Argument order: `event`.

## Function `libp2p_event`

Handles one checked event by calling the function of its kind.

### Signature

```
libp2p_event(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`Event`](#type-event) |

### Function does

- Calls the `libp2p_on_<kind>` function of the event kind, with a direct call.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_timers`

Runs the upgrade deadlines and the gossipsub timers, and asks for a wakeup at the next deadline.

### Signature

```
libp2p_timers()
```

### Function does

- Closes a connection whose upgrade passed its deadline: CONNECT before the TCP connection opened, else HANDSHAKE.
- Asks for a wakeup at the deadline of each connection still in its upgrade.
- Runs `libp2p_gossip_timers`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_timers`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_copy`

Copies n bytes.

### Signature

```
libp2p_copy(dst, src, n) -> dst + n
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | n bytes |
| `src` | input | n bytes |
| `n` | input | u64 |

### Caller must

- Keep the regions apart, or `dst` below `src`.

### Function does

- Copies the bytes forward, from the first.

### Function never

- Writes more than `dst`.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_copy`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns `dst` + `n`, not a status.
- Argument order: `dst`, `src`, `n`.

## Function `libp2p_zero`

Writes n zero bytes.

### Signature

```
libp2p_zero(dst, n) -> dst + n
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | n bytes |
| `n` | input | u64 |

### Function does

- Writes zero to each byte.

### Function never

- Writes more than `dst`.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_zero`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns `dst` + `n`, not a status.
- Argument order: `dst`, `n`.

## Function `libp2p_equal`

Compares n bytes.

### Signature

```
libp2p_equal(a, b, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | n bytes |
| `b` | input | n bytes |
| `n` | input | u64 |

### Function does

- Gives 1 when the bytes are equal, else 0.
- Reads every byte: its time depends only on `n`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_equal`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 1 or 0, not a status.
- Argument order: `a`, `b`, `n`.

## Function `libp2p_compare`

Compares two byte strings of their own lengths.

### Signature

```
libp2p_compare(a, alen, b, blen) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | `alen` bytes |
| `alen` | input | u64 |
| `b` | input | `blen` bytes |
| `blen` | input | u64 |

### Function does

- Gives 1 when the lengths and the bytes are equal, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_compare`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 1 or 0, not a status.
- Argument order: `a`, `alen`, `b`, `blen`.

## Function `libp2p_hash`

Hashes n bytes with FNV-1a 64.

### Signature

```
libp2p_hash(p, n) -> hash
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Gives FNV-1a 64 of the bytes: offset basis 0xCBF29CE484222325, prime 0x100000001B3.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_hash`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the hash, not a status.
- Argument order: `p`, `n`.

## Function `libp2p_heap_alloc`

Takes a block of the state heap for n bytes.

### Signature

```
libp2p_heap_alloc(n) -> offset
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `n` | input | u64 |

### Function does

- Takes the smallest free block of 2^order bytes that holds n + 16 bytes, at least 64, and splits larger blocks in halves to get it.
- Gives the state offset of the usable bytes, after the 16-byte [`HeapBlock`](#type-heapblock) header, or 0 when no block is free.
- Adds the block size to the heap bytes in use.

### Function never

- Writes outside the heap and the free lists of the state.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_heap_alloc`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the state offset or 0, not a status.
- Argument order: `n`.

## Function `libp2p_heap_free`

Gives back a block that `libp2p_heap_alloc` took.

### Signature

```
libp2p_heap_free(offset)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `offset` | input | u64: a state offset from `libp2p_heap_alloc`, or 0 |

### Function does

- Does nothing for offset 0.
- Joins the block with its free buddy while there is one, then puts it on the free list of its order.

### Function never

- Writes outside the heap and the free lists of the state.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_heap_free`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `offset`.

## Function `libp2p_random`

Draws n bytes from the DRBG of the state.

### Signature

```
libp2p_random(dst, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | n bytes |
| `n` | input | u64 |

### Function does

- Writes SHA-256 of the 32-byte DRBG key and the 8-byte counter for each 32 bytes, adding 1 to the counter each time.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 208 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_random`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `dst`, `n`.

## Function `libp2p_random_below`

Draws a random number below n.

### Signature

```
libp2p_random_below(n) -> number
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `n` | input | u64: 1 or more |

### Function does

- Takes 8 bytes from the DRBG and gives them modulo `n`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_random_below`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the number, not a status.
- Argument order: `n`.

## Function `libp2p_reseed`

Mixes 32 fresh bytes into the DRBG key.

### Signature

```
libp2p_reseed(entropy)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entropy` | input | 32 bytes |

### Function does

- Sets the DRBG key to SHA-256 of the key and the 32 bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 208 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_reseed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `entropy`.

## Function `libp2p_action`

Adds one zeroed action to the action list.

### Signature

```
libp2p_action(kind, size) -> action
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 |
| `size` | input | u64: a multiple of 8 |

### Function does

- Writes `size` and `kind` and zeroes the rest.
- Gives 0 and writes nothing when the list has no room for `size` bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_action`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the action or 0, not a status.
- Argument order: `kind`, `size`.

## Function `libp2p_room`

Gives the action bytes left beyond the reserve of the step.

### Signature

```
libp2p_room() -> bytes
```

### Function does

- Gives the room of the action list less the reserve of the step, or 0: 4096 bytes kept so that the end of the step always fits, until WAKEUP.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the byte count, not a status.

## Function `libp2p_action_shrink`

Makes the last action shorter.

### Signature

```
libp2p_action_shrink(action, size)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | state | [`Action`](#type-action): the last of the list |
| `size` | input | u64: a multiple of 8, at most its size |

### Function does

- Sets the size of the action and gives the bytes after it back to the list.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_action_shrink`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`, `size`.

## Function `libp2p_wake_at`

Brings the next wakeup forward to a time.

### Signature

```
libp2p_wake_at(time)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `time` | input | u64: ms |

### Function does

- Keeps the earlier of `time` and the wakeup time so far.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_wake_at`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `time`.

## Function `libp2p_slot`

Finds the slot of a live handle in a table.

### Signature

```
libp2p_slot(table, count, stride, handle) -> slot
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `table` | input | u64: the state field of the table offset |
| `count` | input | u64: the state field of the slot count |
| `stride` | input | u64: bytes of a slot |
| `handle` | input | u64: a handle ([`Handle`](node.md#type-handle)) |

### Function does

- Gives the slot when the index is below the count, the generation matches and the slot is in use, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_slot`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `table`, `count`, `stride`, `handle`.

## Function `libp2p_conn`

Finds the connection of a handle.

### Signature

```
libp2p_conn(handle) -> connection
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: a handle ([`Handle`](node.md#type-handle)) |

### Function does

- Gives the live [`Connection`](connections.md#type-connection) slot of the handle, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `handle`.

## Function `libp2p_stream`

Finds the stream of a handle.

### Signature

```
libp2p_stream(handle) -> stream
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: a handle ([`Handle`](node.md#type-handle)) |

### Function does

- Gives the live [`Stream`](streams.md#type-stream) slot of the handle, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `handle`.

## Function `libp2p_peer`

Finds the connected peer of a handle.

### Signature

```
libp2p_peer(handle) -> peer
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: a handle ([`Handle`](node.md#type-handle)) |

### Function does

- Gives the [`Peer`](connections.md#type-peer) slot of the handle when the peer is connected, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `handle`.

## Function `libp2p_handle`

Gives the handle of a slot.

### Signature

```
libp2p_handle(table, stride, slot) -> handle
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `table` | input | u64: the state field of the table offset |
| `stride` | input | u64: bytes of a slot |
| `slot` | input | a slot of the table |

### Function does

- Gives the slot index in the low 32 bits and the generation of the slot in the high 32 bits.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_handle`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the handle, not a status.
- Argument order: `table`, `stride`, `slot`.

## Function `libp2p_alloc_slot`

Takes the first free slot of a table.

### Signature

```
libp2p_alloc_slot(table, count, stride) -> slot
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `table` | input | u64: the state field of the table offset |
| `count` | input | u64: the state field of the slot count |
| `stride` | input | u64: bytes of a slot |

### Function does

- Zeroes the slot after its generation, adds 1 to the generation, sets the in-use word to 1, and gives the slot.
- Gives 0 when every slot is in use.

### Function never

- Makes an OS call.

### Effects

- Handles of the earlier use of the slot stop working.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_alloc_slot`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `table`, `count`, `stride`.

## Type `Config`

The limits, keys and parameters of a node.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the config, the protocol part included |
| 8 | `key_type` | u64 | `LIBP2P_KEY_ED25519` or `LIBP2P_KEY_SECP256K1` |
| 16 | `private_key` | 32 bytes | The identity key: an Ed25519 seed, or a secp256k1 scalar big endian |
| 48 | `entropy` | 32 bytes | Fresh random bytes for the DRBG |
| 80 | `now` | u64 | Monotonic time in ms |
| 88 | `max_connections` | u64 | Connection slots, 1 to 65536 |
| 96 | `max_streams` | u64 | Stream slots, 1 to 1048576 |
| 104 | `max_peers` | u64 | Peer slots, from max_connections to 65535 |
| 112 | `max_topics` | u64 | Topic slots, 1 to 4096 |
| 120 | `heap_size` | u64 | Heap bytes: a power of 2 from 65536 to 2^40 |
| 128 | `seen_capacity` | u64 | Seen cache entries, 1 to 16777216 |
| 136 | `mcache_capacity` | u64 | Message cache entries, 1 to 1048576 |
| 144 | `pending_capacity` | u64 | Messages waiting for the application, 1 to 1048576 |
| 152 | `muxers` | u64 | Bit 0 yamux, bit 1 mplex; 1 to 3; yamux is proposed first |
| 160 | `send_window` | u64 | Bytes a connection may have with the shell, 131072 to 2^30 |
| 168 | `max_rpc` | u64 | Bytes of a gossipsub RPC, 1024 to 2^30 |
| 176 | `max_data` | u64 | Bytes of the data of a gossipsub message, at most max_rpc |
| 184 | `handshake_ms` | u64 | Time for the upgrade of a connection, 1 or more |
| 192 | `validation_ms` | u64 | Time the application has to judge a message, 1 or more |
| 200 | `stream_queue` | u64 | Bytes a stream may have queued, 65536 to 2^30 |
| 208 | `protocols` | u64 | Offset in the config of the [`ProtocolEntry`](#type-protocolentry) list |
| 216 | `protocols_count` | u64 | Entries in the list, 0 to 64 |
| 224 | `d` | u64 | gossipsub D, 1 to 64 |
| 232 | `d_low` | u64 | D_low, at most d |
| 240 | `d_high` | u64 | D_high, from d to 64 |
| 248 | `d_lazy` | u64 | D_lazy, at most 64 |
| 256 | `d_score` | u64 | D_score, at most d_high |
| 264 | `d_out` | u64 | D_out, at most d_low |
| 272 | `heartbeat_ms` | u64 | Heartbeat interval, 1 or more |
| 280 | `fanout_ttl_ms` | u64 | Fanout TTL |
| 288 | `mcache_len` | u64 | Message cache windows, 1 to 64 |
| 296 | `mcache_gossip` | u64 | Windows gossiped in IHAVE, at most mcache_len |
| 304 | `seen_ttl_ms` | u64 | Time a message ID stays seen, 1 or more |
| 312 | `prune_backoff_ms` | u64 | Backoff after a PRUNE |
| 320 | `unsub_backoff_ms` | u64 | Backoff sent when we leave a topic |
| 328 | `graft_flood_ms` | u64 | A GRAFT this soon after a PRUNE costs a second penalty |
| 336 | `flood_publish` | u64 | 1: our messages go to every subscribed peer at or above publish_threshold |
| 344 | `gossip_factor` | f64 | Share of candidates that get IHAVE |
| 352 | `max_ihave_length` | u64 | IDs in IHAVE, sent or heard per peer per heartbeat, at most 8192 |
| 360 | `max_ihave_messages` | u64 | IHAVE messages heard per peer per heartbeat |
| 368 | `iwant_followup_ms` | u64 | Time a peer has to send a message it announced |
| 376 | `retransmission` | u64 | IWANT answers per message per peer, at most 3 |
| 384 | `opportunistic_ticks` | u64 | Heartbeats between opportunistic grafts; 0 turns them off |
| 392 | `opportunistic_peers` | u64 | Peers an opportunistic graft adds |
| 400 | `scoring` | u64 | 1 turns peer scores on, 0 off |
| 408 | `gossip_threshold` | f64 | Below it, no gossip to or from the peer |
| 416 | `publish_threshold` | f64 | Below it, no flood publish to the peer |
| 424 | `graylist_threshold` | f64 | Below it, RPCs of the peer are not heard |
| 432 | `accept_px_threshold` | f64 | Kept for the config layout; peer exchange is not used |
| 440 | `opportunistic_threshold` | f64 | A mesh whose median score is below it takes better peers |
| 448 | `decay_interval_ms` | u64 | Score decay interval, 1 or more with scoring on |
| 456 | `decay_to_zero` | f64 | A counter below it after decay becomes 0 |
| 464 | `retain_score_ms` | u64 | Time the score of a gone peer is kept |
| 472 | `app_weight` | f64 | Weight of P5 |
| 480 | `ip_weight` | f64 | Weight of P6 |
| 488 | `ip_threshold` | u64 | Peers on one IP before P6 counts |
| 496 | `behaviour_weight` | f64 | Weight of P7 |
| 504 | `behaviour_threshold` | f64 | P7 counts above it |
| 512 | `behaviour_decay` | f64 | Decay factor of P7 |
| 520 | `topic_cap` | f64 | Cap of the topic part of the score; 0 or less: no cap |
| 528 | `agent_len` | u64 | Bytes of agentVersion, at most 64 |
| 536 | `agent` | 64 bytes | agentVersion of identify |
| 600 | `pv_len` | u64 | Bytes of protocolVersion, at most 32 |
| 608 | `pv` | 32 bytes | protocolVersion of identify |

### Rules

- `size` is at least `LIBP2P_CFG_FIXED`.
- With protocols, `protocols` is a multiple of 8, at least `LIBP2P_CFG_FIXED`, and the list ends within `size`.
- Each ranged field holds a value in its range; a config outside them gives `LIBP2P_INVALID_CONFIG`.
- Fields with no range take any value.


## Type `ProtocolEntry`

A protocol ID: of the config, or proposed by OPEN_STREAM.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `len` | u64 | Bytes of the ID, 1 to `LIBP2P_MAX_PROTOCOL` |
| 8 | `bytes` | 128 bytes | The ID, without a newline |

### Rules

- The ID holds no newline byte.
- An entry is `LIBP2P_PROTO_SIZE` bytes.


## Type `Tick`

The input of each step: the time and fresh random bytes.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `now` | u64 | Monotonic time in ms |
| 8 | `entropy` | 32 bytes | Fresh random bytes |

### Rules

- `libp2p_shell_clock` writes one.


## Type `StepResult`

How many events a step accepted.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `accepted` | u64 | Events handled, from the first |

### Rules

- The caller removes the accepted events and passes the rest again.


## Type `ByteList`

A buffer: its size, where the bytes start, and how many there are.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this header included |
| 8 | `offset` | u64 | Where the bytes start, from the buffer start |
| 16 | `count` | u64 | Bytes in the list |

### Rules

- `offset` + `count` is at most `size`.
- An output list gets `offset` 24 from the function that writes it.
- Event and action lists hold whole records, each a multiple of 8 bytes.


## Type `Address`

An IPv4 or IPv6 address and a TCP port.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `family` | u64 | 4 or 6 |
| 8 | `port` | u64 | TCP port |
| 16 | `ip` | 16 bytes | IPv4 in the first 4 bytes, or IPv6, in network order |

### Rules

- The port is below 65536.
- An address is `LIBP2P_ADDR_SIZE` bytes.


## Type `Handle`

A reference the application holds to a slot of the state.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `index` | u32 | The slot index |
| 4 | `generation` | u32 | The generation of the slot when the handle was made |

### Rules

- A handle stops working when its slot is freed: the generation then goes up.
- An event with a handle that no longer works does nothing.


## Type `Event`

One input of a step: a shell result or an application request.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the event, a multiple of 8 |
| 8 | `kind` | u64 | `LIBP2P_EVENT_<KIND>`, 1 to `LIBP2P_EVENT_LAST` |

### Rules

- The fields of each kind follow, as its type gives.
- An event whose size is below the fixed size of its kind is invalid.
- Shell results: ACCEPTED, CONNECTED, DIAL_FAILED, RECEIVED, SENT, CLOSED.
- Application requests: the other kinds.


## Type `Action`

One output of a step: a shell request or an application notice.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the action, a multiple of 8 |
| 8 | `kind` | u64 | `LIBP2P_ACTION_<KIND>` |

### Rules

- The fields of each kind follow, as its type gives.
- Shell requests: DIAL, ADOPT, REFUSE, SEND, CLOSE and WAKEUP.
- Application notices: the other kinds.
- Actions come in the order the node made them; WAKEUP is the last action of every step.


## Type `WakeupAction`

The time by which the next step is due.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `time` | u64 | Monotonic time in ms |

### Rules

- Kind `LIBP2P_ACTION_WAKEUP`, size `LIBP2P_ACT_WAKEUP_SIZE`.
- A step may come earlier, with events.


## Type `State`

The state of a node: one buffer that `libp2p_init` builds.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, set by the caller |
| 8 | `version` | u64 | `LIBP2P_STATE_VERSION` |

### Rules

- Its other fields and tables are private: include/state.inc gives them.
- The data of a MESSAGE action lies in the state, at `data_off`, until the next step.
- One thread at a time uses a state.


## Type `Scratch`

The work area of `libp2p_step`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, set by the caller |

### Rules

- It holds at least `LIBP2P_SCRATCH_SIZE` bytes.
- Its contents do not carry from one step to the next.


## Type `HeapBlock`

The header of a block of the heap of the state.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `order` | u32 | The block is 2^order bytes |
| 4 | `free` | u32 | 1 on a free list |
| 8 | `next` | u64 | Free list links: heap offsets, or NONE |
| 16 | `prev` | u64 | Free list link to the previous block, or NONE |

### Rules

- A block is 2^order bytes, at least 64, at a multiple of its size from the heap start.
- The usable bytes of a used block start after 16 bytes.
- A free block sits on the free list of its order.


## Test vectors

- Scenarios of [tests/runner/runner.c](../../tests/runner/runner.c): config, errors, limits, and every other scenario through `libp2p_step`.
- Expected results: the checks of each scenario, and its transcript digest, recorded on ARM64, the same on every ISA.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_state_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_step`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_layout`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_check_event`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_check_addr`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_event_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_event`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_timers`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_zero`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_equal`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_compare`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_hash`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_heap_alloc`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_heap_free`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_random`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_random_below`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_reseed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_action`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_action_shrink`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_wake_at`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_handle`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_alloc_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |
