# Connections

## Contents

### Functions

- [`libp2p_ms_put`](#function-libp2p_ms_put): writes a multistream message.
- [`libp2p_ms_put_proto`](#function-libp2p_ms_put_proto): writes the message of a protocol ID.
- [`libp2p_ms_take`](#function-libp2p_ms_take): reads bytes into a multistream message.
- [`libp2p_ms_is`](#function-libp2p_ms_is): compares the multistream message with a string.
- [`libp2p_conn_new`](#function-libp2p_conn_new): takes a connection slot.
- [`libp2p_conn_handle`](#function-libp2p_conn_handle): gives the handle of a connection.
- [`libp2p_conn_free`](#function-libp2p_conn_free): frees a connection slot.
- [`libp2p_conn_out`](#function-libp2p_conn_out): queues a multistream message on a connection.
- [`libp2p_conn_teardown`](#function-libp2p_conn_teardown): ends everything above the socket of a connection.
- [`libp2p_conn_close`](#function-libp2p_conn_close): closes a live connection.
- [`libp2p_conn_send_close`](#function-libp2p_conn_send_close): gives the CLOSE action of a connection.
- [`libp2p_on_accepted`](#function-libp2p_on_accepted): handles ACCEPTED.
- [`libp2p_on_dial`](#function-libp2p_on_dial): handles DIAL.
- [`libp2p_on_connected`](#function-libp2p_on_connected): handles CONNECTED.
- [`libp2p_on_dial_failed`](#function-libp2p_on_dial_failed): handles the DIAL_FAILED event.
- [`libp2p_on_closed`](#function-libp2p_on_closed): handles CLOSED.
- [`libp2p_on_sent`](#function-libp2p_on_sent): handles SENT.
- [`libp2p_on_disconnect`](#function-libp2p_on_disconnect): handles DISCONNECT.
- [`libp2p_on_received`](#function-libp2p_on_received): handles RECEIVED.
- [`libp2p_conn_live`](#function-libp2p_conn_live): tells whether a connection is live.
- [`libp2p_conn_process`](#function-libp2p_conn_process): handles the receive buffer of a connection.
- [`libp2p_conn_plain`](#function-libp2p_conn_plain): handles the plaintext of a transport message.
- [`libp2p_conn_propose_muxer`](#function-libp2p_conn_propose_muxer): proposes a muxer.
- [`libp2p_conn_ms`](#function-libp2p_conn_ms): handles one multistream message of a connection.
- [`libp2p_conn_opened`](#function-libp2p_conn_opened): opens a connection after its upgrade.
- [`libp2p_peer_find`](#function-libp2p_peer_find): finds a peer by ID.
- [`libp2p_id_less`](#function-libp2p_id_less): orders two peer IDs.
- [`libp2p_peer_conns`](#function-libp2p_peer_conns): counts the connections of a peer.
- [`libp2p_peer_other`](#function-libp2p_peer_other): finds another connection of a peer.
- [`libp2p_peer_bind`](#function-libp2p_peer_bind): binds an open connection to its peer.
- [`libp2p_peer_evict`](#function-libp2p_peer_evict): frees the oldest retained peer.
- [`libp2p_peer_release`](#function-libp2p_peer_release): frees a peer slot.
- [`libp2p_peer_down`](#function-libp2p_peer_down): ends a peer whose connection ended.

### Types

- [`Connection`](#type-connection): the slot of one TCP connection.
- [`Peer`](#type-peer): the slot of one peer.
- [`AcceptedEvent`](#type-acceptedevent): a new inbound socket.
- [`ConnectedEvent`](#type-connectedevent): a dial connected.
- [`DialFailedEvent`](#type-dialfailedevent): a dial did not connect.
- [`SentEvent`](#type-sentevent): the shell wrote bytes of SEND actions.
- [`ClosedEvent`](#type-closedevent): a socket closed.
- [`ReceivedEvent`](#type-receivedevent): bytes from a socket.
- [`DialEvent`](#type-dialevent): a request to dial a peer.
- [`DisconnectEvent`](#type-disconnectevent): a request to end a peer.
- [`DialAction`](#type-dialaction): a request to the shell to connect.
- [`AdoptAction`](#type-adoptaction): a request to the shell to keep an accepted socket.
- [`RefuseAction`](#type-refuseaction): a request to the shell to close an accepted socket.
- [`CloseAction`](#type-closeaction): a request to the shell to close a socket.
- [`PeerConnectedAction`](#type-peerconnectedaction): a peer connected.
- [`PeerDisconnectedAction`](#type-peerdisconnectedaction): a peer left.
- [`DialFailedAction`](#type-dialfailedaction): a dial failed.

### Constants

- `LIBP2P_PEER_CONNS`: open connections of one peer.
- `LIBP2P_RX_SIZE`: the receive buffer of a connection.
- `LIBP2P_REASON_CONNECT`: the TCP connection failed, or did not open within `handshake_ms`.
- `LIBP2P_REASON_HANDSHAKE`: the upgrade failed or timed out.
- `LIBP2P_REASON_PEER_ID`: the peer is not the one dialled.
- `LIBP2P_REASON_LIMIT`: a table or the heap is full.
- `LIBP2P_REASON_PROTOCOL`: the peer refused every proposed protocol.
- `LIBP2P_REASON_NO_PEER`: the peer is not connected.
- `LIBP2P_REASON_CLOSED`: the connection closed.
- `LIBP2P_REASON_DUPLICATE`: a connection to the same peer was kept instead.

## Spec

- Document: [connections/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/connections/README.md), libp2p/specs at commit c750236; and [multistream-select](https://github.com/multiformats/multistream-select/blob/9a1fbe8edadebea223f47102f1913b8026c23a1c/README.md), multiformats/multistream-select at commit 9a1fbe8.
- Section: Upgrading Connections, Protocol Negotiation (multistream-select 1.0), simultaneous open of TCP connections.

## Function `libp2p_ms_put`

Writes one multistream message.

### Signature

```
libp2p_ms_put(dst, str, n) -> dst after the message
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | n + 1 or more bytes |
| `str` | input | n bytes, the newline last |
| `n` | input | u64 |

### Function does

- Writes the varint `n`, then the bytes.

### Function never

- Writes more than the message.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ms_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the message, not a status.
- Argument order: `dst`, `str`, `n`.

## Function `libp2p_ms_put_proto`

Writes the multistream message of a protocol ID.

### Signature

```
libp2p_ms_put_proto(dst, bytes, n) -> dst after the message
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | n + 2 or more bytes |
| `bytes` | input | n bytes, no newline |
| `n` | input | u64 |

### Function does

- Writes the varint n + 1, the bytes, then a newline.

### Function never

- Writes more than the message.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ms_put_proto`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the message, not a status.
- Argument order: `dst`, `bytes`, `n`.

## Function `libp2p_ms_take`

Takes bytes until one whole multistream message is held.

### Signature

```
libp2p_ms_take(ms, cap, src, n) -> taken, result
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ms` | state | negotiation record: state, bytes held, varint length, then `cap` bytes |
| `cap` | input | u64: bytes of the buffer |
| `src` | input | n bytes |
| `n` | input | u64 |

### Function does

- Takes one byte at a time until the varint length and that many bytes are held, and leaves the bytes after them in `src`.
- Gives result 1 when a whole message ending with a newline is held, 0 when more bytes are needed, and 2 when the bytes are not such a message or it would not fit in `cap`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ms_take`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the bytes taken in x0, rax or a0 and the result in x1, rdx or a1.
- Argument order: `ms`, `cap`, `src`, `n`.

## Function `libp2p_ms_is`

Tells whether the message held is a given string.

### Signature

```
libp2p_ms_is(ms, str, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ms` | input | negotiation record: state, bytes held, varint length, then `cap` bytes |
| `str` | input | n bytes, the newline last |
| `n` | input | u64 |

### Function does

- Gives 1 when the message, its newline included, is the n bytes, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ms_is`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 1 or 0, not a status.
- Argument order: `ms`, `str`, `n`.

## Function `libp2p_conn_new`

Takes a connection slot with its receive buffer.

### Signature

```
libp2p_conn_new(outbound) -> connection
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `outbound` | input | u64: 1 for a dial, 0 for an accepted connection |

### Function does

- Takes a free slot and a heap block of `LIBP2P_RX_SIZE` bytes for received bytes.
- Sets phase DIALING, the deadline now + `handshake_ms`, and no peer, stream or cursor.
- Gives 0 when no slot or heap block is free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_new`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `outbound`.

## Function `libp2p_conn_handle`

Gives the handle of a connection slot.

### Signature

```
libp2p_conn_handle(conn) -> handle
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | input | [`Connection`](connections.md#type-connection) slot |

### Function does

- Gives the index and generation of the slot as a [`Handle`](node.md#type-handle).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_handle`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the handle, not a status.
- Argument order: `conn`.

## Function `libp2p_conn_free`

Frees a connection slot and its receive buffer.

### Signature

```
libp2p_conn_free(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Gives the receive buffer back to the heap and marks the slot free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_free`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_conn_out`

Queues one multistream message in the output buffer.

### Signature

```
libp2p_conn_out(conn, str, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `str` | input | n bytes, the newline last |
| `n` | input | u64 |

### Function does

- Writes the message with `libp2p_ms_put` when the output buffer has room, else drops it.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_out`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `str`, `n`.

## Function `libp2p_conn_teardown`

Ends the streams of a connection, then its peer or dial, then its receive buffer.

### Signature

```
libp2p_conn_teardown(conn, reason)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `reason` | input | u64: `LIBP2P_REASON_<NAME>` |

### Function does

- Ends each stream with `libp2p_stream_kill` and the reason CLOSED.
- For the first connection of a peer: another open connection of the peer takes over when there is one (the peer keeps its slot, and our gossipsub stream opens again on it); else the peer goes with `libp2p_peer_down`.
- For a secondary connection, the peer stays.
- For a dial not yet reported, gives DIAL_FAILED with the reason.
- Frees the receive buffer and empties the output buffer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_teardown`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `reason`.

## Function `libp2p_conn_close`

Ends a live connection and asks the shell to close it.

### Signature

```
libp2p_conn_close(conn, reason)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `reason` | input | u64: `LIBP2P_REASON_<NAME>` |

### Function does

- Does nothing unless the connection is between DIALING and CLOSING.
- Runs `libp2p_conn_teardown`, sets phase CLOSING, and gives CLOSE with `libp2p_conn_send_close`.

### Function never

- Makes an OS call.

### Effects

- The slot stays until the CLOSED event.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_close`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `reason`.

## Function `libp2p_conn_send_close`

Gives CLOSE for a connection, or keeps a flag for the drain.

### Signature

```
libp2p_conn_send_close(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Gives CLOSE with the handle of the connection.
- When the action list has no room, sets a flag; the drain gives CLOSE later.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_send_close`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_on_accepted`

Takes a new inbound connection, or refuses it.

### Signature

```
libp2p_on_accepted(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`AcceptedEvent`](#type-acceptedevent) |

### Function does

- Takes a connection slot in phase SECURITY with the address, and gives ADOPT with the token and the handle.
- Gives REFUSE with the token when no slot is free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_accepted`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_dial`

Starts a dial the application asked for.

### Signature

```
libp2p_on_dial(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`DialEvent`](#type-dialevent) |

### Function does

- Takes a connection slot with the tag, the address and the expected peer ID, and gives DIAL with its handle.
- Gives DIAL_FAILED with the reason LIMIT when no slot is free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_dial`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_connected`

Starts the upgrade of a dial that connected.

### Signature

```
libp2p_on_connected(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`ConnectedEvent`](#type-connectedevent) |

### Function does

- For a dialing connection: sets phase SECURITY and queues the multistream header and "/noise".
- Does nothing for a stale handle or another phase.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_connected`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_dial_failed`

Ends a dial the shell could not connect.

### Signature

```
libp2p_on_dial_failed(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`DialFailedEvent`](#type-dialfailedevent) |

### Function does

- For a dialing connection: gives DIAL_FAILED with the reason CONNECT and frees the slot.
- For a closing connection: frees the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_dial_failed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_closed`

Frees a connection whose socket the shell closed.

### Signature

```
libp2p_on_closed(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`ClosedEvent`](#type-closedevent) |

### Function does

- For a live connection: runs `libp2p_conn_teardown` with the reason CLOSED.
- Then frees the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_closed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_sent`

Counts bytes the shell wrote.

### Signature

```
libp2p_on_sent(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`SentEvent`](#type-sentevent) |

### Function does

- Takes the count, at most the bytes in flight, off the bytes the connection has with the shell.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_sent`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_disconnect`

Closes every connection of a peer.

### Signature

```
libp2p_on_disconnect(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`DisconnectEvent`](#type-disconnectevent) |

### Function does

- Closes the secondary connections of the peer, then its first, each with the reason CLOSED.
- Does nothing for a peer that is not connected.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_disconnect`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_received`

Takes received bytes into the receive buffer of a connection.

### Signature

```
libp2p_on_received(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`ReceivedEvent`](#type-receivedevent) |

### Function does

- Copies as many bytes as the buffer holds, handles them with `libp2p_conn_process`, and repeats until all are taken.
- Closes the connection when the buffer is full and nothing in it can be handled.
- Does nothing for a stale handle or a connection that is not live.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_received`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_conn_live`

Tells whether a connection is in its upgrade or open.

### Signature

```
libp2p_conn_live(conn) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | input | [`Connection`](connections.md#type-connection) slot |

### Function does

- Gives 1 for the phases SECURITY to OPEN, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_live`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 1 or 0, not a status.
- Argument order: `conn`.

## Function `libp2p_conn_process`

Handles what the receive buffer holds.

### Signature

```
libp2p_conn_process(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- SECURITY: multistream messages, with `libp2p_conn_ms`.
- NOISE: handshake messages, each with a 2-byte length, with `libp2p_noise_message`; after the last, phase MUXER, and the dialer proposes a muxer.
- MUXER and OPEN: transport messages, opened with `libp2p_noise_open` and passed to `libp2p_conn_plain`.
- Moves the bytes of an unfinished message to the front.
- Closes the connection when a message fails: HANDSHAKE in the upgrade, CLOSED when open, PEER_ID when a dial reached another peer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_process`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_conn_plain`

Hands the plaintext of a transport message on.

### Signature

```
libp2p_conn_plain(conn, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- MUXER: multistream messages, with `libp2p_conn_ms`.
- OPEN: muxer frames, with `libp2p_mux_feed`.
- Closes the connection with HANDSHAKE when the multistream bytes are bad.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_plain`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `p`, `n`.

## Function `libp2p_conn_propose_muxer`

Queues the dialer's multistream header and first muxer.

### Signature

```
libp2p_conn_propose_muxer(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Proposes "/yamux/1.0.0" when yamux is on in the config, else "/mplex/6.7.0".

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_propose_muxer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_conn_ms`

Handles one multistream message before or after Noise.

### Signature

```
libp2p_conn_ms(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Takes the header "/multistream/1.0.0" first, and answers it when ours is not sent yet.
- Listener: selects "/noise" before Noise; after it, "/yamux/1.0.0" or "/mplex/6.7.0" when on in the config, by echoing it; answers "na" to anything else.
- Dialer: takes the echo of its proposal; after "na" to yamux, proposes mplex when it is on.
- Starts Noise after "/noise"; opens the connection after the muxer.
- Closes the connection with HANDSHAKE when the header is wrong or the dialer gets an answer it cannot use.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_ms`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_conn_opened`

Opens a connection whose muxer is chosen.

### Signature

```
libp2p_conn_opened(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Sets phase OPEN and the first stream ID of this side: yamux 1 for the dialer and 2 for the listener; mplex 0.
- Binds the connection to its peer with `libp2p_peer_bind`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_opened`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_peer_find`

Finds the peer slot of a peer ID.

### Signature

```
libp2p_peer_find(id, n) -> peer
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | n bytes |
| `n` | input | u64 |

### Function does

- Gives the connected or retained peer with the ID, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `id`, `n`.

## Function `libp2p_id_less`

Tells whether one byte string sorts before another.

### Signature

```
libp2p_id_less(a, alen, b, blen) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | `alen` bytes |
| `alen` | input | u64 |
| `b` | input | `blen` bytes |
| `blen` | input | u64 |

### Function does

- Compares byte by byte; a shorter string that is a prefix of the other sorts first.
- Gives 1 when `a` sorts first, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_id_less`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 1 or 0, not a status.
- Argument order: `a`, `alen`, `b`, `blen`.

## Function `libp2p_peer_conns`

Counts the open connections bound to a peer.

### Signature

```
libp2p_peer_conns(peer) -> count
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |

### Function does

- Counts the connections in phase OPEN whose peer is this one, secondary connections included.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_conns`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the count, not a status.
- Argument order: `peer`.

## Function `libp2p_peer_other`

Finds an open connection of a peer other than one.

### Signature

```
libp2p_peer_other(peer, conn) -> connection
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `conn` | input | [`Connection`](connections.md#type-connection) slot |

### Function does

- Gives the first other connection in phase OPEN bound to the peer, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_other`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `peer`, `conn`.

## Function `libp2p_peer_bind`

Binds an open connection to the peer the handshake proved.

### Signature

```
libp2p_peer_bind(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Closes with PEER_ID a dial that reached another peer than it named, or a connection to ourselves.
- With an open connection to the peer already: when each side dialled one, the connection dialled by the peer with the smaller ID stays and the other closes with DUPLICATE, with its secondary connections.
- When the peer dialled again, the new connection becomes a secondary one, up to `LIBP2P_PEER_CONNS`; past that, or when we dialled again, it closes with DUPLICATE.
- Brings back a retained peer with its score, or takes a peer slot, freeing the retained peer whose score ends first when none is free; closes with LIMIT when no slot can be had.
- Gives PEER_CONNECTED and opens our gossipsub stream with `libp2p_gossip_peer_up`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_bind`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_peer_evict`

Frees the retained peer whose score ends first.

### Signature

```
libp2p_peer_evict() -> 1 or 0
```

### Function does

- Gives 1 after it frees the retained peer with the earliest expiry, or 0 when no peer is retained.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_evict`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.

## Function `libp2p_peer_release`

Frees a peer slot and its peer x topic entries.

### Signature

```
libp2p_peer_release(peer)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | state | [`Peer`](connections.md#type-peer) slot |

### Function does

- Marks the slot free and zeroes its entry of each topic.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_release`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`.

## Function `libp2p_peer_down`

Ends a peer whose last connection ended.

### Signature

```
libp2p_peer_down(peer)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | state | [`Peer`](connections.md#type-peer) slot |

### Function does

- Takes the peer out of gossipsub with `libp2p_gossip_peer_down`, and gives PEER_DISCONNECTED.
- With scoring on and `retain_score_ms` above 0, keeps the slot as retained until then, with a new generation; else frees it.

### Function never

- Makes an OS call.

### Effects

- Handles of the peer stop working.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_down`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`.

## Type `Connection`

One TCP connection: its upgrade, Noise keys, muxer and streams.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `gen` | u32 | Generation of the slot |
| 4 | `phase` | u32 | PH_FREE, DIALING, ADOPTING, SECURITY, NOISE, MUXER, OPEN or CLOSING |
| 8 | `flags` | u64 | CF_ flags of include/state.inc |
| 16 | `peer` | u64 | Peer slot index once bound (P_CONN of the peer, or a secondary connection), else NONE |
| 24 | `tag` | u64 | The DIAL tag |
| 32 | `addr` | [`Address`](node.md#type-address) | The address of the socket |
| 64 | `deadline` | u64 | ms: the upgrade must finish by then |
| 72 | `exp_id_len` | u64 | The peer ID the dial expects, or length 0 |
| 80 | `exp_id` | 48 bytes | The peer ID the dial expects |
| 128 | `rx` | u64 | Heap offset of the receive buffer |
| 136 | `rx_len` | u64 | Bytes in the receive buffer |
| 144 | `inflight` | u64 | Bytes with the shell, not yet SENT |
| 152 | `out_len` | u64 | Bytes in the output buffer |
| 160 | `out` | 768 bytes | Bytes before the muxer: multistream and Noise handshake |
| 928 | `ns_h` | 32 bytes | Noise handshake hash |
| 960 | `ns_ck` | 32 bytes | Noise chaining key |
| 992 | `ns_k` | 32 bytes | Noise cipher key |
| 1024 | `ns_n` | u64 | Noise nonce |
| 1032 | `ns_hask` | u64 | 1 when the cipher key is set |
| 1040 | `ns_e` | 32 bytes | Our ephemeral private key |
| 1072 | `ns_epub` | 32 bytes | Our ephemeral public key |
| 1104 | `ns_re` | 32 bytes | The peer's ephemeral key |
| 1136 | `ns_rs` | 32 bytes | The peer's static key |
| 1168 | `tx_k` | 32 bytes | Send key |
| 1200 | `tx_n` | u64 | Send nonce |
| 1208 | `rx_k` | 32 bytes | Receive key |
| 1240 | `rx_n` | u64 | Receive nonce |
| 1248 | `ms_state` | u64 | Multistream before the muxer |
| 1256 | `ms_len` | u64 | Bytes of the multistream message held |
| 1264 | `ms_need` | u64 | Bytes of its varint length |
| 1272 | `ms_buf` | 160 bytes | The multistream message being read |
| 1432 | `mx_hdr` | 24 bytes | Muxer frame header being read |
| 1456 | `mx_hlen` | u64 | Header bytes read |
| 1464 | `mx_stream` | u64 | Stream slot of the current frame, or NONE |
| 1472 | `mx_remain` | u64 | Data bytes of the current frame still to come |
| 1480 | `mx_flags` | u64 | Type and flags of the current frame |
| 1488 | `mx_next_id` | u64 | The next stream ID this side opens |
| 1496 | `ping_count` | u64 | Yamux pings to answer |
| 1504 | `pings` | 4 u32 | Opaque values of yamux pings to answer |
| 1520 | `stream_head` | u64 | First stream slot of the connection |
| 1528 | `streams` | u64 | Streams of the connection |
| 1536 | `backlog` | u64 | Inbound streams not yet acknowledged |
| 1544 | `cursor` | u64 | The stream the drain starts at |
| 1552 | `ns_step` | u64 | Noise messages handled |
| 1560 | `rid_len` | u64 | The peer ID the handshake proved |
| 1568 | `rid` | 48 bytes | The peer ID the handshake proved |
| 1616 | `key_type` | u64 | The key type of the peer |
| 1624 | `out_raw` | u64 | The first C_OUT_RAW bytes of C_OUT go out unencrypted |
| 1632 | `rsts` | u64 | Resets to send for streams without a slot |
| 1640 | `rst_ids` | 6 u32 | Up to 6 u32: yamux stream IDs or mplex headers |

### Rules

- A connection belongs to at most one peer: its first connection, or a secondary one.
- Bytes in `out` up to `out_raw` go out as they are; later ones go in Noise transport messages.


## Type `Peer`

One peer: its ID, connection, gossipsub streams and score.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `gen` | u32 | Generation of the slot |
| 4 | `state` | u32 | PS_FREE, PS_CONNECTED or PS_RETAINED |
| 8 | `conn` | u64 | Index of its first connection |
| 16 | `id_len` | u64 | Bytes of the peer ID |
| 24 | `id` | 48 bytes | The peer ID |
| 72 | `flags` | u64 | PF_OUTBOUND, PF_GOSSIP, PF_HELLO, PF_IDONTWANT |
| 80 | `gs_out` | u64 | Index of our gossipsub stream to the peer, or NONE |
| 88 | `gs_in` | u64 | Index of the peer's gossipsub stream to us, or NONE |
| 96 | `ip` | 16 bytes | The IP address of its first connection |
| 112 | `ip_family` | u64 | 4 or 6 |
| 120 | `app_score` | f64 | P5, from APP_SCORE |
| 128 | `behaviour` | f64 | The P7 counter |
| 136 | `ihave_count` | u64 | IHAVE messages this heartbeat |
| 144 | `ihave_ids` | u64 | IDs asked for this heartbeat |
| 152 | `expire` | u64 | ms: a retained score ends then |
| 160 | `score` | f64 | The score at the last heartbeat |
| 168 | `dw_head` | u64 | The next entry of the IDONTWANT ring to write |
| 176 | `dw_count` | u64 | IDONTWANT messages this heartbeat |

### Rules

- A retained peer keeps its score counters and backoffs until `expire`; then its slot is free.
- Each connected peer has one first connection and up to `LIBP2P_PEER_CONNS` open connections in all.


## Type `AcceptedEvent`

The shell accepted a new inbound socket.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `token` | u64 | The native socket, as the shell knows it |
| 24 | `addr` | [`Address`](node.md#type-address) | The peer's address |

### Rules

- Kind `LIBP2P_EVENT_ACCEPTED`, size at least `LIBP2P_EV_ACCEPTED_SIZE`.
- The node answers it in the same step with ADOPT or REFUSE and the same token.


## Type `ConnectedEvent`

A dial connected.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |

### Rules

- Kind `LIBP2P_EVENT_CONNECTED`, size at least `LIBP2P_EV_CONN_SIZE`.
- Answers a DIAL action with the same connection.


## Type `DialFailedEvent`

A dial did not connect.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |
| 24 | `error` | u64 | The OS error number |

### Rules

- Kind `LIBP2P_EVENT_DIAL_FAILED`, size at least `LIBP2P_EV_CONN_SIZE`.
- Answers a DIAL action with the same connection.
- The node gives the DIAL_FAILED action to the application with the reason CONNECT.


## Type `SentEvent`

The shell wrote bytes of SEND actions.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |
| 24 | `count` | u64 | Bytes written |

### Rules

- Kind `LIBP2P_EVENT_SENT`, size at least `LIBP2P_EV_CONN_SIZE`.
- Counts bytes of earlier SEND actions of the connection, in order.


## Type `ClosedEvent`

A socket closed.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |
| 24 | `error` | u64 | The OS error number, or 0 |

### Rules

- Kind `LIBP2P_EVENT_CLOSED`, size at least `LIBP2P_EV_CONN_SIZE`.
- Answers a CLOSE action, or tells of a socket the peer or an error closed.
- A CLOSED for a handle that is no longer live does nothing.


## Type `ReceivedEvent`

Bytes the shell read from a socket.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |
| 24 | `count` | u64 | Bytes, at most `LIBP2P_RECEIVE_MAX` |
| 32 | `data` | `count` bytes | The bytes, in the order they came |

### Rules

- Kind `LIBP2P_EVENT_RECEIVED`; the size covers the bytes, rounded up to a multiple of 8.


## Type `DialEvent`

The application asks for a connection.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `tag` | u64 | Any value: PEER_CONNECTED or DIAL_FAILED carries it back |
| 24 | `addr` | [`Address`](node.md#type-address) | Where to dial |
| 56 | `id_len` | u64 | Bytes of the expected peer ID, 0 to `LIBP2P_MAX_PEER_ID`; 0: any peer |
| 64 | `id` | 48 bytes | The expected peer ID |

### Rules

- Kind `LIBP2P_EVENT_DIAL`, size at least `LIBP2P_EV_DIAL_SIZE`.
- It ends in PEER_CONNECTED or in the DIAL_FAILED action, with the tag.
- A dial that reaches another peer than it names fails with PEER_ID after Noise message 2.


## Type `DisconnectEvent`

The application ends the connections of a peer.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |

### Rules

- Kind `LIBP2P_EVENT_DISCONNECT`, size at least `LIBP2P_EV_PEER_SIZE`.
- It ends in PEER_DISCONNECTED; a stale handle does nothing.


## Type `DialAction`

The shell opens a TCP connection.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |
| 24 | `addr` | [`Address`](node.md#type-address) | Where to connect |

### Rules

- Kind `LIBP2P_ACTION_DIAL`, size `LIBP2P_ACT_DIAL_SIZE`.
- The shell answers with CONNECTED or DIAL_FAILED for the connection.


## Type `AdoptAction`

The shell binds an accepted socket to a connection.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `token` | u64 | The token of ACCEPTED |
| 24 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |

### Rules

- Kind `LIBP2P_ACTION_ADOPT`, size `LIBP2P_ACT_ADOPT_SIZE`.
- A token the shell no longer holds is ignored.


## Type `RefuseAction`

The shell closes an accepted socket.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `token` | u64 | The token of ACCEPTED |

### Rules

- Kind `LIBP2P_ACTION_REFUSE`, size `LIBP2P_ACT_REFUSE_SIZE`.


## Type `CloseAction`

The shell closes the socket of a connection.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |

### Rules

- Kind `LIBP2P_ACTION_CLOSE`, size `LIBP2P_ACT_CLOSE_SIZE`.
- The shell answers with CLOSED, also when it holds no socket for the handle.


## Type `PeerConnectedAction`

A peer is connected: the handshake proved its ID.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |
| 24 | `tag` | u64 | The tag of the dial, or 0 for an inbound connection |
| 32 | `direction` | u64 | `LIBP2P_INBOUND` or `LIBP2P_OUTBOUND` |
| 40 | `addr` | [`Address`](node.md#type-address) | The address of the connection |
| 72 | `id_len` | u64 | Bytes of the peer ID |
| 80 | `id` | 48 bytes | The peer ID |

### Rules

- Kind `LIBP2P_ACTION_PEER_CONNECTED`, size `LIBP2P_ACT_PC_SIZE`.
- Once for each peer until PEER_DISCONNECTED; a secondary connection gives none.


## Type `PeerDisconnectedAction`

A peer is gone: its last connection ended.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |
| 24 | `id_len` | u64 | Bytes of the peer ID |
| 32 | `id` | 48 bytes | The peer ID |

### Rules

- Kind `LIBP2P_ACTION_PEER_DISCONNECTED`, size `LIBP2P_ACT_PD_SIZE`.
- The handle of the peer stops working.


## Type `DialFailedAction`

A dial the application asked for failed.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `tag` | u64 | The tag of the dial |
| 24 | `reason` | u64 | `LIBP2P_REASON_<NAME>` |

### Rules

- Kind `LIBP2P_ACTION_DIAL_FAILED`, size `LIBP2P_ACT_FAILED_SIZE`.
- Once for each failed dial.


## Test vectors

- Scenarios of [tests/runner/runner.c](../../tests/runner/runner.c): yamux, mplex, fallback, mplex_first, no_muxer, peer_id, timeout, garbage, errors, simultaneous, limits, secondary.
- transport-interop of libp2p/test-plans ([tests/interop/](../../tests/interop/)): both directions with 16 implementations.
- The shell loop test ([tests/shell/loop.c](../../tests/shell/loop.c)) over 127.0.0.1 on every OS.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_ms_put`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ms_put_proto`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ms_take`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ms_is`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_new`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_handle`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_free`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_out`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_teardown`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_close`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_send_close`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_accepted`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_dial`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_connected`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_dial_failed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_closed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_sent`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_disconnect`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_received`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_live`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_process`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_plain`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_propose_muxer`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_ms`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_opened`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_find`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_id_less`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_conns`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_other`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_bind`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_evict`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_release`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_down`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
