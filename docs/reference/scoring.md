# Peer scoring

## Contents

### Functions

- [`libp2p_params`](#function-libp2p_params): gives the score parameters of a topic.
- [`libp2p_score`](#function-libp2p_score): computes the score of a peer.
- [`libp2p_ip_count`](#function-libp2p_ip_count): counts the peers on an IP.
- [`libp2p_score_all`](#function-libp2p_score_all): scores every connected peer.
- [`libp2p_behaviour_penalty`](#function-libp2p_behaviour_penalty): adds to the P7 counter.
- [`libp2p_score_invalid`](#function-libp2p_score_invalid): counts an invalid message.
- [`libp2p_score_delivery`](#function-libp2p_score_delivery): counts a valid delivery.
- [`libp2p_score_valid`](#function-libp2p_score_valid): scores an accepted message.
- [`libp2p_score_rejected`](#function-libp2p_score_rejected): scores a rejected message.
- [`libp2p_score_duplicate`](#function-libp2p_score_duplicate): scores a duplicate delivery.
- [`libp2p_score_mesh_leave`](#function-libp2p_score_mesh_leave): applies the mesh failure penalty.
- [`libp2p_decay`](#function-libp2p_decay): decays one counter.
- [`libp2p_score_decay`](#function-libp2p_score_decay): decays every counter.
- [`libp2p_on_app_score`](#function-libp2p_on_app_score): handles APP_SCORE.
- [`libp2p_on_topic_params`](#function-libp2p_on_topic_params): handles TOPIC_PARAMS.

### Types

- [`TopicParams`](#type-topicparams): the score parameters of a topic.
- [`AppScoreEvent`](#type-appscoreevent): the application score of a peer.
- [`TopicParamsEvent`](#type-topicparamsevent): the score parameters of a topic.

## Spec

- Document: [gossipsub-v1.1.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/pubsub/gossipsub/gossipsub-v1.1.md), libp2p/specs at commit c750236; and [p2p-interface.md](https://github.com/ethereum/consensus-specs/blob/313cbfe561517a81eb11607fea7c6985e562eaa9/specs/phase0/p2p-interface.md), consensus-specs at commit 313cbfe.
- Section: Peer Scoring: the score function, P1 to P7, score thresholds, parameter decay.

## Function `libp2p_params`

Gives the score parameters of a topic.

### Signature

```
libp2p_params(topic) -> params
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64: a topic slot index |

### Function does

- Gives the [`TopicParams`](#type-topicparams) of a topic in use with parameters, when scoring is on; else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_params`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the parameters or 0, not a status.
- Argument order: `topic`.

## Function `libp2p_score`

Computes the gossipsub v1.1 score of a peer.

### Signature

```
libp2p_score(peer) -> score
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |

### Function does

- Adds, for each topic with parameters, the topic weight times w1 P1 + w2 P2 + w3 P3 + w3b P3b + w4 P4.
- P1: whole time quanta in the mesh, at most the cap. P3: the square of the deficit below the threshold, once the mesh activation time passed. P4: the square of the counter.
- Caps the topic part at `topic_cap` when that is above 0.
- Adds w5 P5 (the application score), w6 P6 (the square of the peers on the same IP above `ip_threshold`) and w7 P7 (the square of the counter above `behaviour_threshold`).
- Gives 0 when scoring is off.
- Rounds each product, then each sum, on its own, and takes `min` as ARM64 `fmin` does: every ISA gives the same score.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the f64 score in d0, xmm0 or fa0.
- Argument order: `peer`.

## Function `libp2p_ip_count`

Counts the connected peers on the IP address of a peer.

### Signature

```
libp2p_ip_count(peer) -> count
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |

### Function does

- Counts the connected peers with the same family and address, the peer included.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ip_count`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the count, not a status.
- Argument order: `peer`.

## Function `libp2p_score_all`

Scores every connected peer for the rest of the step.

### Signature

```
libp2p_score_all()
```

### Function does

- Writes `libp2p_score` of each connected peer to its slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score_all`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_behaviour_penalty`

Adds to the behaviour penalty counter of a peer.

### Signature

```
libp2p_behaviour_penalty(peer, count)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | state | [`Peer`](connections.md#type-peer) slot |
| `count` | input | u64 |

### Function does

- Adds `count` to P7.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_behaviour_penalty`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `peer`, `count`.

## Function `libp2p_score_invalid`

Counts an invalid message of a peer in a topic.

### Signature

```
libp2p_score_invalid(peer, topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |

### Function does

- Adds 1 to P4 of the peer in the topic, when the topic has parameters.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score_invalid`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`.

## Function `libp2p_score_delivery`

Counts a valid delivery of a peer in a topic.

### Signature

```
libp2p_score_delivery(peer, topic, first)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |
| `first` | input | u64: 1 for the first delivery |

### Function does

- When the topic has parameters: with `first`, adds 1 to P2 up to its cap; in the mesh, adds 1 to P3 up to its cap.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score_delivery`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`, `first`.

## Function `libp2p_score_valid`

Scores the deliveries of an accepted message.

### Signature

```
libp2p_score_valid(peer, topic, seen)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |
| `seen` | input | [`SeenEntry`](gossipsub.md#type-seenentry), or 0 |

### Function does

- A first delivery for the sender.
- A mesh delivery for each peer that sent it while it was judged.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score_valid`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`, `seen`.

## Function `libp2p_score_rejected`

Scores the deliveries of a rejected message.

### Signature

```
libp2p_score_rejected(peer, topic, seen)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |
| `seen` | input | [`SeenEntry`](gossipsub.md#type-seenentry), or 0 |

### Function does

- An invalid message for the sender, and for each peer that sent it while it was judged.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score_rejected`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`, `seen`.

## Function `libp2p_score_duplicate`

Scores a message a peer sent that was seen before.

### Signature

```
libp2p_score_duplicate(peer, seen)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `seen` | state | [`SeenEntry`](gossipsub.md#type-seenentry) |

### Function does

- Still judged: keeps the peer as a deliverer, up to `LIBP2P_MAX_DELIVERERS`.
- Valid: a mesh delivery when it came within `mesh_window_ms` of the verdict.
- Invalid: an invalid message of the peer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score_duplicate`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `seen`.

## Function `libp2p_score_mesh_leave`

Applies the mesh failure penalty when a peer leaves a mesh.

### Signature

```
libp2p_score_mesh_leave(peer, topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |

### Function does

- For a mesh peer whose P3 is active and below its threshold: adds the square of the deficit to P3b.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score_mesh_leave`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`.

## Function `libp2p_decay`

Multiplies one counter by its decay factor.

### Signature

```
libp2p_decay(address, factor)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `address` | state | f64 |
| `factor` | input | f64 in d0, xmm0 or fa0 |

### Function does

- Writes the counter times the factor, or 0 when its absolute value is below `decay_to_zero`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_decay`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `address`, `factor`.

## Function `libp2p_score_decay`

Decays the score counters of every peer.

### Signature

```
libp2p_score_decay()
```

### Function does

- For each connected or retained peer: P2, P3, P3b and P4 in each topic with parameters, and P7.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_score_decay`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_on_app_score`

Sets the application score of a peer.

### Signature

```
libp2p_on_app_score(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`AppScoreEvent`](#type-appscoreevent) |

### Function does

- Writes P5 of a connected peer; a stale handle does nothing.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_app_score`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_topic_params`

Sets the score parameters of a topic.

### Signature

```
libp2p_on_topic_params(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`TopicParamsEvent`](#type-topicparamsevent) |

### Function does

- Takes or finds the topic slot and copies the parameters; does nothing when the table is full.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_topic_params`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Type `TopicParams`

The score parameters of one topic (gossipsub v1.1).

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `weight` | f64 | Topic weight |
| 8 | `time_weight` | f64 | w1 |
| 16 | `time_quantum_ms` | u64 | P1 counts whole quanta; 0 counts as 1 |
| 24 | `time_cap` | f64 | Cap of P1 |
| 32 | `first_weight` | f64 | w2 |
| 40 | `first_decay` | f64 | Decay of P2 |
| 48 | `first_cap` | f64 | Cap of P2 |
| 56 | `mesh_weight` | f64 | w3 |
| 64 | `mesh_decay` | f64 | Decay of P3 |
| 72 | `mesh_threshold` | f64 | P3 counts below it |
| 80 | `mesh_cap` | f64 | Cap of the P3 counter |
| 88 | `mesh_activation_ms` | u64 | Time in the mesh before P3 counts |
| 96 | `mesh_window_ms` | u64 | A duplicate this soon after the verdict is a mesh delivery |
| 104 | `fail_weight` | f64 | w3b |
| 112 | `fail_decay` | f64 | Decay of P3b |
| 120 | `invalid_weight` | f64 | w4 |
| 128 | `invalid_decay` | f64 | Decay of P4 |

### Rules

- A topic has no topic score until it gets parameters.
- Weights of penalties (w3, w3b, w4) are negative in the consensus specs; the library takes any value.
- A set is `LIBP2P_TP_SIZE` bytes.


## Type `AppScoreEvent`

The application sets the application-specific score of a peer (P5).

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |
| 24 | `score` | f64 | P5 |

### Rules

- Kind `LIBP2P_EVENT_APP_SCORE`, size at least `LIBP2P_EV_SCORE_SIZE`.
- The score holds until the next APP_SCORE, also while the peer is retained.


## Type `TopicParamsEvent`

The application sets the score parameters of a topic.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `topic_len` | u64 | Bytes of the topic, 1 to `LIBP2P_MAX_TOPIC` |
| 24 | `params` | [`TopicParams`](#type-topicparams) | The parameters |
| 160 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_EVENT_TOPIC_PARAMS`; the size covers the topic.
- Later parameters replace earlier ones; the counters stay.


## Test vectors

- Scenarios of [tests/runner/runner.c](../../tests/runner/runner.c): scoring (rejected messages and a low application score put a peer below the thresholds: its messages are not heard, and messages no longer go to it), gossip.
- Expected results: the transcript digests, the same on x86-64, ARM64 and RISC-V, so the floating point steps agree.

## Results

<!-- CI generates the tick table for each function here. -->
