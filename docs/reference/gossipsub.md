# gossipsub

## Contents

### Functions

- [`libp2p_peer_at`](#function-libp2p_peer_at): gives the peer slot of an index.
- [`libp2p_peer_idx`](#function-libp2p_peer_idx): gives the index of a peer slot.
- [`libp2p_topic_at`](#function-libp2p_topic_at): gives the topic slot of an index.
- [`libp2p_topic_idx`](#function-libp2p_topic_idx): gives the index of a topic slot.
- [`libp2p_pt`](#function-libp2p_pt): gives the entry of a peer in a topic.
- [`libp2p_topic_find`](#function-libp2p_topic_find): finds a topic by name.
- [`libp2p_topic_get`](#function-libp2p_topic_get): finds or takes a topic slot.
- [`libp2p_topic_tidy`](#function-libp2p_topic_tidy): frees a topic nobody uses.
- [`libp2p_gs_ready`](#function-libp2p_gs_ready): tells whether a peer takes gossipsub RPCs.
- [`libp2p_idx_find`](#function-libp2p_idx_find): finds a message ID in a hash index.
- [`libp2p_idx_add`](#function-libp2p_idx_add): adds an entry to a hash index.
- [`libp2p_idx_del`](#function-libp2p_idx_del): takes an entry out of a hash index.
- [`libp2p_seen_args`](#function-libp2p_seen_args): gives the seen cache index arguments.
- [`libp2p_seen_find`](#function-libp2p_seen_find): finds a seen message.
- [`libp2p_seen_drop_tail`](#function-libp2p_seen_drop_tail): drops the oldest seen entry.
- [`libp2p_seen_tail`](#function-libp2p_seen_tail): gives the oldest seen entry.
- [`libp2p_seen_add`](#function-libp2p_seen_add): adds a seen entry.
- [`libp2p_seen_args_keep`](#function-libp2p_seen_args_keep): gives the seen index and its slots.
- [`libp2p_seen_expire`](#function-libp2p_seen_expire): drops old seen entries.
- [`libp2p_mc_args`](#function-libp2p_mc_args): gives the message cache index arguments.
- [`libp2p_mc_find`](#function-libp2p_mc_find): finds a cached message.
- [`libp2p_mc_tail`](#function-libp2p_mc_tail): gives the oldest cached message.
- [`libp2p_mc_drop_tail`](#function-libp2p_mc_drop_tail): drops the oldest cached message.
- [`libp2p_mc_put`](#function-libp2p_mc_put): caches a message.
- [`libp2p_mc_shift`](#function-libp2p_mc_shift): drops messages of old windows.
- [`libp2p_mc_sent`](#function-libp2p_mc_sent): counts an IWANT answer.
- [`libp2p_pend`](#function-libp2p_pend): finds a pending message by handle.
- [`libp2p_pend_free`](#function-libp2p_pend_free): frees a pending message.
- [`libp2p_pend_status`](#function-libp2p_pend_status): gives MESSAGE_STATUS.
- [`libp2p_promise_add`](#function-libp2p_promise_add): records an IWANT promise.
- [`libp2p_promise_keep`](#function-libp2p_promise_keep): marks promises of a message kept.
- [`libp2p_promise_drop_peer`](#function-libp2p_promise_drop_peer): forgets the promises of a peer.
- [`libp2p_dw_ring`](#function-libp2p_dw_ring): gives the IDONTWANT ring of a peer.
- [`libp2p_dontwant`](#function-libp2p_dontwant): tells whether a peer sent IDONTWANT for a message.
- [`libp2p_gs_alloc`](#function-libp2p_gs_alloc): takes a send chunk.
- [`libp2p_gs_push`](#function-libp2p_gs_push): queues a chunk on the gossipsub stream of a peer.
- [`libp2p_pb_head`](#function-libp2p_pb_head): writes the head of a bytes field.
- [`libp2p_gs_rpc`](#function-libp2p_gs_rpc): starts a one-field RPC.
- [`libp2p_gs_send_sub`](#function-libp2p_gs_send_sub): sends one subscription change.
- [`libp2p_gs_send_ext`](#function-libp2p_gs_send_ext): sends our Extensions control message.
- [`libp2p_gs_send_partial`](#function-libp2p_gs_send_partial): sends one partial message RPC.
- [`libp2p_gs_send_msg`](#function-libp2p_gs_send_msg): sends one message.
- [`libp2p_gs_send_graft`](#function-libp2p_gs_send_graft): sends GRAFT.
- [`libp2p_gs_send_prune`](#function-libp2p_gs_send_prune): sends PRUNE.
- [`libp2p_gs_send_ids`](#function-libp2p_gs_send_ids): sends IHAVE, IWANT or IDONTWANT.
- [`libp2p_gs_idontwant`](#function-libp2p_gs_idontwant): sends IDONTWANT for a new message.
- [`libp2p_gs_announce`](#function-libp2p_gs_announce): tells every peer of a subscription change.
- [`libp2p_gossip_peer_up`](#function-libp2p_gossip_peer_up): opens our gossipsub stream to a peer.
- [`libp2p_gossip_peer_down`](#function-libp2p_gossip_peer_down): takes a peer out of gossipsub.
- [`libp2p_gossip_out_ready`](#function-libp2p_gossip_out_ready): sends our subscriptions on a new stream.
- [`libp2p_gossip_in_ready`](#function-libp2p_gossip_in_ready): notes the gossipsub stream of a peer.
- [`libp2p_gossip_rx`](#function-libp2p_gossip_rx): reads RPCs from a gossipsub stream.
- [`libp2p_rpc_handle`](#function-libp2p_rpc_handle): handles one RPC.
- [`libp2p_field_bytes`](#function-libp2p_field_bytes): finds a bytes field.
- [`libp2p_peer_topic`](#function-libp2p_peer_topic): gives PEER_TOPIC.
- [`libp2p_rpc_sub`](#function-libp2p_rpc_sub): handles one SubOpts.
- [`libp2p_rpc_msg`](#function-libp2p_rpc_msg): handles one published message.
- [`libp2p_rpc_control`](#function-libp2p_rpc_control): handles one ControlMessage.
- [`libp2p_ctl_extensions`](#function-libp2p_ctl_extensions): handles the Extensions control message.
- [`libp2p_rpc_partial`](#function-libp2p_rpc_partial): handles one PartialMessagesExtension.
- [`libp2p_backoff_secs`](#function-libp2p_backoff_secs): turns ms into whole seconds.
- [`libp2p_prune_to`](#function-libp2p_prune_to): sends PRUNE and starts a backoff.
- [`libp2p_ctl_graft`](#function-libp2p_ctl_graft): handles GRAFT.
- [`libp2p_ctl_prune`](#function-libp2p_ctl_prune): handles PRUNE.
- [`libp2p_ctl_ihave`](#function-libp2p_ctl_ihave): handles IHAVE.
- [`libp2p_ctl_iwant`](#function-libp2p_ctl_iwant): handles IWANT.
- [`libp2p_ctl_idontwant`](#function-libp2p_ctl_idontwant): handles IDONTWANT.
- [`libp2p_mesh_add`](#function-libp2p_mesh_add): adds a peer to a mesh.
- [`libp2p_mesh_remove`](#function-libp2p_mesh_remove): takes a peer out of a mesh.
- [`libp2p_candidates`](#function-libp2p_candidates): lists the peers that suit a topic.
- [`libp2p_shuffle`](#function-libp2p_shuffle): shuffles a peer list.
- [`libp2p_on_subscribe`](#function-libp2p_on_subscribe): handles SUBSCRIBE.
- [`libp2p_on_partial_subscribe`](#function-libp2p_on_partial_subscribe): handles PARTIAL_SUBSCRIBE.
- [`libp2p_subscribe`](#function-libp2p_subscribe): joins a topic.
- [`libp2p_fanout_clear_topic`](#function-libp2p_fanout_clear_topic): clears the fanout of a topic.
- [`libp2p_on_unsubscribe`](#function-libp2p_on_unsubscribe): handles UNSUBSCRIBE.
- [`libp2p_on_publish`](#function-libp2p_on_publish): handles PUBLISH.
- [`libp2p_fanout_list`](#function-libp2p_fanout_list): lists the fanout of a topic.
- [`libp2p_on_message_id`](#function-libp2p_on_message_id): handles MESSAGE_ID.
- [`libp2p_on_validation`](#function-libp2p_on_validation): handles VALIDATION.
- [`libp2p_seen_delivered`](#function-libp2p_seen_delivered): tells whether a peer delivered a message.
- [`libp2p_gossip_timers`](#function-libp2p_gossip_timers): runs the gossipsub timers.
- [`libp2p_heartbeat`](#function-libp2p_heartbeat): runs the gossipsub heartbeat.
- [`libp2p_list_score`](#function-libp2p_list_score): gives the score of a listed peer.
- [`libp2p_list_outbound`](#function-libp2p_list_outbound): tells whether a listed peer is outbound.
- [`libp2p_sort_score`](#function-libp2p_sort_score): sorts a peer list by score.
- [`libp2p_add_from_list`](#function-libp2p_add_from_list): adds the first listed peers to a mesh.
- [`libp2p_mesh_maintain`](#function-libp2p_mesh_maintain): maintains the mesh of a topic.
- [`libp2p_keep_outbound`](#function-libp2p_keep_outbound): keeps outbound peers in a shrunk mesh.
- [`libp2p_fanout_maintain`](#function-libp2p_fanout_maintain): maintains the fanout of a topic.
- [`libp2p_emit_gossip`](#function-libp2p_emit_gossip): sends IHAVE for a topic.
- [`libp2p_partial_flags`](#function-libp2p_partial_flags): gives a peer's partial flags of a topic.
- [`libp2p_wants_partial`](#function-libp2p_wants_partial): tells whether a peer gets partial messages from us.
- [`libp2p_sends_partial`](#function-libp2p_sends_partial): tells whether a peer sends us partial messages.
- [`libp2p_on_partial_peers`](#function-libp2p_on_partial_peers): handles PARTIAL_PEERS.
- [`libp2p_on_partial_send`](#function-libp2p_on_partial_send): handles PARTIAL_SEND.
- [`libp2p_on_partial_score`](#function-libp2p_on_partial_score): handles PARTIAL_SCORE.

### Types

- [`Topic`](#type-topic): the slot of one topic.
- [`PeerTopic`](#type-peertopic): the state of a peer in a topic.
- [`SeenEntry`](#type-seenentry): one message ID of the seen cache.
- [`DontWantEntry`](#type-dontwantentry): one message ID of IDONTWANT.
- [`CacheEntry`](#type-cacheentry): one message of the message cache.
- [`Pending`](#type-pending): a message waiting for the application.
- [`Promise`](#type-promise): an IWANT promise.
- [`SubscribeEvent`](#type-subscribeevent): a request to join a topic.
- [`UnsubscribeEvent`](#type-unsubscribeevent): a request to leave a topic.
- [`PublishEvent`](#type-publishevent): a message to publish.
- [`MessageIdEvent`](#type-messageidevent): the ID of a received message.
- [`ValidationEvent`](#type-validationevent): the verdict on a message.
- [`MessageAction`](#type-messageaction): a message from a peer.
- [`MessageStatusAction`](#type-messagestatusaction): what to do with a message.
- [`PublishedAction`](#type-publishedaction): a message we published went out.
- [`PartialSubscribeEvent`](#type-partialsubscribeevent): a request to join a topic with partial flags.
- [`PartialPeersEvent`](#type-partialpeersevent): a request for the partial message peers of a topic.
- [`PartialSendEvent`](#type-partialsendevent): a partial message RPC to one peer.
- [`PartialScoreEvent`](#type-partialscoreevent): the verdict on partial message data.
- [`PartialAction`](#type-partialaction): partial message data or metadata from a peer.
- [`PartialPeersAction`](#type-partialpeersaction): the partial message peers of a topic.
- [`PartialGossipAction`](#type-partialgossipaction): the gossip peers of a topic that take partial messages.
- [`PeerTopicAction`](#type-peertopicaction): a peer joined or left a topic.

### Constants

- `LIBP2P_MAX_TOPIC`: bytes of a topic.
- `LIBP2P_MAX_MSG_ID`: bytes of a message ID.
- `LIBP2P_PROMISES`: IWANT promises followed at a time.
- `LIBP2P_MAX_DELIVERERS`: peers kept for each seen message, for scores.
- `LIBP2P_PARTIAL_REQUESTS`: the partial flag: partial messages are wanted on the topic.
- `LIBP2P_PARTIAL_SUPPORTS`: the partial flag: partial messages are sent on the topic.

## Spec

- Document: [pubsub/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/pubsub/README.md), [gossipsub-v1.0.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/pubsub/gossipsub/gossipsub-v1.0.md) and [gossipsub-v1.1.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/pubsub/gossipsub/gossipsub-v1.1.md), [gossipsub-v1.2.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/pubsub/gossipsub/gossipsub-v1.2.md), [gossipsub-v1.3.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/pubsub/gossipsub/gossipsub-v1.3.md) and [partial-messages.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/pubsub/gossipsub/partial-messages.md), libp2p/specs at commit c750236; [p2p-interface.md](https://github.com/ethereum/consensus-specs/blob/313cbfe561517a81eb11607fea7c6985e562eaa9/specs/phase0/p2p-interface.md), consensus-specs at commit 313cbfe; and [partial-columns/p2p-interface.md](https://github.com/ethereum/consensus-specs/blob/313cbfe561517a81eb11607fea7c6985e562eaa9/specs/fulu/partial-columns/p2p-interface.md), consensus-specs at commit 313cbfe.
- Section: the RPC, StrictNoSign messages, the mesh, fanout, gossip and the message cache (v1.0); PRUNE backoff, flood publishing, adaptive gossip, outbound mesh quotas, opportunistic grafting and extended validators (v1.1); IDONTWANT (v1.2); the Extensions control message (v1.3); the Partial Messages extension. Peer exchange is not used.
- The application encodes group IDs, parts metadata and partial messages; the library carries them and picks the peers.
- The consensus specs name gossipsub v1.1 ("/meshsub/1.1.0"); v1.2 adds "/meshsub/1.2.0", and its IDONTWANT is optional for both sides.
- The partial columns of Fulu use the Partial Messages extension of "/meshsub/1.3.0"; a peer that does not ask for partial messages gets full messages.

## Function `libp2p_peer_at`

Gives the peer slot of an index.

### Signature

```
libp2p_peer_at(index) -> peer
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64: a peer slot index |

### Function does

- Gives the address of the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_at`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot, not a status.
- Argument order: `index`.

## Function `libp2p_peer_idx`

Gives the slot index of a peer.

### Signature

```
libp2p_peer_idx(peer) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |

### Function does

- Gives the index of the slot in the peer table.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_idx`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the index, not a status.
- Argument order: `peer`.

## Function `libp2p_topic_at`

Gives the topic slot of an index.

### Signature

```
libp2p_topic_at(index) -> topic
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64: a topic slot index |

### Function does

- Gives the address of the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_topic_at`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot, not a status.
- Argument order: `index`.

## Function `libp2p_topic_idx`

Gives the slot index of a topic.

### Signature

```
libp2p_topic_idx(topic) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | [`Topic`](gossipsub.md#type-topic) slot |

### Function does

- Gives the index of the slot in the topic table.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_topic_idx`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the index, not a status.
- Argument order: `topic`.

## Function `libp2p_pt`

Gives the peer x topic entry of a peer and a topic.

### Signature

```
libp2p_pt(peer, topic) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |

### Function does

- Gives the [`PeerTopic`](#type-peertopic) entry at peer x topics + topic.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pt`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the entry, not a status.
- Argument order: `peer`, `topic`.

## Function `libp2p_topic_find`

Finds the topic slot of a name.

### Signature

```
libp2p_topic_find(name, n) -> topic
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `name` | input | n bytes |
| `n` | input | u64 |

### Function does

- Compares the hash, then the name, of each topic in use.
- Gives the slot, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_topic_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `name`, `n`.

## Function `libp2p_topic_get`

Finds the topic slot of a name, or takes a new one.

### Signature

```
libp2p_topic_get(name, n) -> topic
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `name` | input | n bytes, 1 to `LIBP2P_MAX_TOPIC` |
| `n` | input | u64 |

### Function does

- Gives the slot of the name, or takes the first free slot, zeroed, with the name and its hash.
- Gives 0 when the table is full.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_topic_get`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `name`, `n`.

## Function `libp2p_topic_tidy`

Frees a topic slot that nothing uses.

### Signature

```
libp2p_topic_tidy(topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | state | [`Topic`](gossipsub.md#type-topic) slot |

### Function does

- Frees the slot when we do not subscribe, it has no score parameters, and no peer subscribes or is in its mesh or fanout.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_topic_tidy`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `topic`.

## Function `libp2p_gs_ready`

Tells whether our gossipsub stream to a peer is open.

### Signature

```
libp2p_gs_ready(peer) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |

### Function does

- Gives 1 when the peer is connected and our stream to it is negotiated, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_ready`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 1 or 0, not a status.
- Argument order: `peer`.

## Function `libp2p_idx_find`

Finds a message ID in a hash index of the seen cache or message cache.

### Signature

```
libp2p_idx_find(index, slots, entries, stride, id, n) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | `slots` u32 |
| `slots` | input | u64 |
| `entries` | input | the entry table |
| `stride` | input | u64: bytes of an entry |
| `id` | input | n bytes |
| `n` | input | u64 |

### Function does

- Probes from the hash of the ID modulo `slots`, one slot at a time, until an empty slot.
- A slot holds an entry index + 1, or 0; an entry holds the ID length at 0 and the ID at 8.
- Gives the entry index, or `NONE`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_idx_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the index or NONE, not a status.
- Argument order: `index`, `slots`, `entries`, `stride`, `id`, `n`.

## Function `libp2p_idx_add`

Adds an entry to a hash index.

### Signature

```
libp2p_idx_add(index, slots, entry, hash)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | state | `slots` u32 |
| `slots` | input | u64 |
| `entry` | input | u64: the entry index |
| `hash` | input | u64: the hash of its ID |

### Caller must

- Keep at least one slot empty: indexes have twice the slots of their entries.

### Function does

- Writes entry + 1 to the first empty slot from the hash modulo `slots`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_idx_add`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `index`, `slots`, `entry`, `hash`.

## Function `libp2p_idx_del`

Takes an entry out of a hash index.

### Signature

```
libp2p_idx_del(index, slots, entries, stride, entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | state | `slots` u32 |
| `slots` | input | u64 |
| `entries` | input | the entry table |
| `stride` | input | u64 |
| `entry` | input | u64: the entry index |

### Function does

- Empties the slot of the entry, then moves back each later entry of the probe run whose home slot does not lie cyclically after the hole, so every lookup still finds its entry.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_idx_del`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `index`, `slots`, `entries`, `stride`, `entry`.

## Function `libp2p_seen_args`

Gives the hash index arguments of the seen cache.

### Signature

```
libp2p_seen_args() -> index, slots, entries, stride
```

### Function does

- Gives the index, its slots (twice the capacity), the entry table and `SN_SIZE`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_seen_args`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the values in x0 to x3 on ARM64, a0 to a3 on RISC-V, and rdi, rsi, rdx, rcx on x86-64: the arguments of `libp2p_idx_find`.

## Function `libp2p_seen_find`

Finds the seen entry of a message ID.

### Signature

```
libp2p_seen_find(id, n) -> seen
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | n bytes |
| `n` | input | u64 |

### Function does

- Gives the [`SeenEntry`](#type-seenentry), or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_seen_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the entry or 0, not a status.
- Argument order: `id`, `n`.

## Function `libp2p_seen_drop_tail`

Drops the oldest seen entry from the ring and the index.

### Signature

```
libp2p_seen_drop_tail()
```

### Function does

- Does nothing when the ring is empty.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_seen_drop_tail`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_seen_tail`

Gives the oldest seen entry.

### Signature

```
libp2p_seen_tail() -> seen
```

### Function does

- Gives the [`SeenEntry`](#type-seenentry) at the tail of the ring, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_seen_tail`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the entry or 0, not a status.

## Function `libp2p_seen_add`

Adds a message ID to the seen cache.

### Signature

```
libp2p_seen_add(id, n, topic, status) -> seen
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | n bytes |
| `n` | input | u64: 1 to `LIBP2P_MAX_MSG_ID` |
| `topic` | input | u64: a topic slot index |
| `status` | input | u64: `SS_PENDING` or `SS_VALID` |

### Function does

- Drops the oldest entry when the ring is full.
- Writes the entry at the head of the ring, first seen now, with no deliverers, and adds it to the index.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_seen_add`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the entry, not a status.
- Argument order: `id`, `n`, `topic`, `status`.

## Function `libp2p_seen_args_keep`

Gives the seen index and its slots, keeping two registers.

### Signature

```
libp2p_seen_args_keep() -> index, slots
```

### Function does

- Gives the index and its slots, and changes no other register.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_seen_args_keep`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the values in x0 and x1 on ARM64, a0 and a1 on RISC-V, and rdi and rsi on x86-64.

## Function `libp2p_seen_expire`

Drops the seen entries older than `seen_ttl_ms`.

### Signature

```
libp2p_seen_expire()
```

### Function does

- Drops entries from the tail while their first-seen time + `seen_ttl_ms` is not after now.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_seen_expire`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_mc_args`

Gives the hash index arguments of the message cache.

### Signature

```
libp2p_mc_args() -> index, slots, entries, stride
```

### Function does

- Gives the index, its slots (twice the capacity), the entry table and the entry stride.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mc_args`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the values in x0 to x3 on ARM64, a0 to a3 on RISC-V, and rdi, rsi, rdx, rcx on x86-64: the arguments of `libp2p_idx_find`.

## Function `libp2p_mc_find`

Finds the message cache entry of a message ID.

### Signature

```
libp2p_mc_find(id, n) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | n bytes |
| `n` | input | u64 |

### Function does

- Gives the [`CacheEntry`](#type-cacheentry), or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mc_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the entry or 0, not a status.
- Argument order: `id`, `n`.

## Function `libp2p_mc_tail`

Gives the oldest message cache entry.

### Signature

```
libp2p_mc_tail() -> entry, index
```

### Function does

- Gives the entry at the tail of the ring and its index, or entry 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mc_tail`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the entry in x0, rax or a0 and its index in x1, rdx or a1.

## Function `libp2p_mc_drop_tail`

Drops the oldest message cache entry and its data.

### Signature

```
libp2p_mc_drop_tail()
```

### Function does

- Frees the data block, takes the entry out of the index and the ring.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mc_drop_tail`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_mc_put`

Puts a message in the current window of the message cache.

### Signature

```
libp2p_mc_put(id, n, topic, data, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | n bytes |
| `n` | input | u64 |
| `topic` | input | u64: a topic slot index |
| `data` | input | u64: heap offset of the data |
| `length` | input | u64 |

### Function does

- Drops the oldest entry when the ring is full.
- Writes the entry with the heartbeat count as its window, and adds it to the index.

### Function never

- Makes an OS call.

### Effects

- The cache owns the data block.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mc_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `id`, `n`, `topic`, `data`, `length`.

## Function `libp2p_mc_shift`

Drops cached messages of windows `mcache_len` heartbeats old or more.

### Signature

```
libp2p_mc_shift()
```

### Function does

- Drops entries from the tail while their window + `mcache_len` is not after the heartbeat count.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mc_shift`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_mc_sent`

Counts one IWANT answer of a message to a peer.

### Signature

```
libp2p_mc_sent(entry, peer) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | [`CacheEntry`](#type-cacheentry) |
| `peer` | input | u64: a peer slot index |

### Function does

- Keeps 2 bits for each peer.
- Gives 1 and counts one more when the peer got the message fewer than `retransmission` times (at most 3), else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mc_sent`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `entry`, `peer`.

## Function `libp2p_pend`

Finds the pending message of a handle.

### Signature

```
libp2p_pend(handle) -> pending
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: a handle ([`Handle`](node.md#type-handle)) |

### Function does

- Gives the live [`Pending`](#type-pending) slot, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pend`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `handle`.

## Function `libp2p_pend_free`

Frees a pending message slot.

### Signature

```
libp2p_pend_free(pending)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pending` | state | [`Pending`](#type-pending) slot |

### Function does

- Frees the data block it still owns, and marks the slot free.

### Function never

- Makes an OS call.

### Effects

- The handle of the message stops working.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pend_free`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `pending`.

## Function `libp2p_pend_status`

Gives MESSAGE_STATUS for a pending message.

### Signature

```
libp2p_pend_status(pending, status)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pending` | input | [`Pending`](#type-pending) slot |
| `status` | input | u64: `LIBP2P_MSG_<NAME>` |

### Function does

- Gives MESSAGE_STATUS with the handle of the message and the status.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pend_status`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `pending`, `status`.

## Function `libp2p_promise_add`

Records that a peer promised a message.

### Signature

```
libp2p_promise_add(peer, id, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `id` | input | n bytes |
| `n` | input | u64 |

### Function does

- Takes a free promise with the deadline now + `iwant_followup_ms`.
- Does nothing when all `LIBP2P_PROMISES` are in use.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_promise_add`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `id`, `n`.

## Function `libp2p_promise_keep`

Ends every promise of a message that came.

### Signature

```
libp2p_promise_keep(id, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | n bytes |
| `n` | input | u64 |

### Function does

- Frees each promise of the ID.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_promise_keep`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `id`, `n`.

## Function `libp2p_promise_drop_peer`

Forgets the promises of a peer that left.

### Signature

```
libp2p_promise_drop_peer(peer)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |

### Function does

- Frees each promise of the peer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_promise_drop_peer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`.

## Function `libp2p_dw_ring`

Gives the first entry of a peer's IDONTWANT ring.

### Signature

```
libp2p_dw_ring(peer) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |

### Function does

- Gives the [`DontWantEntry`](#type-dontwantentry) at peer x `dontwant_slots`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_dw_ring`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the entry, not a status.
- Argument order: `peer`.

## Function `libp2p_dontwant`

Tells whether a peer sent IDONTWANT for a message ID.

### Signature

```
libp2p_dontwant(peer, id, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `id` | input | n bytes |
| `n` | input | u64 |

### Function does

- Gives 1 when the peer's ring holds the ID from fewer than `dontwant_ttl` heartbeats ago, else 0.
- Gives 0 when `dontwant_slots` is 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_dontwant`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `peer`, `id`, `n`.

## Function `libp2p_gs_alloc`

Takes a send chunk for n bytes.

### Signature

```
libp2p_gs_alloc(n) -> place, chunk
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `n` | input | u64 |

### Function does

- Takes a heap block with a [`Chunk`](muxers.md#type-chunk) header of length n.
- Gives the place of the bytes and the chunk, or place 0 when the heap is full.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_alloc`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the place in x0, rax or a0 and the chunk in x1, rdx or a1.
- Argument order: `n`.

## Function `libp2p_gs_push`

Queues a filled chunk on our gossipsub stream to a peer.

### Signature

```
libp2p_gs_push(peer, chunk) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |
| `chunk` | input | u64: the chunk of `libp2p_gs_alloc` |

### Function does

- Gives 1 when the chunk is queued.
- Gives 0 and frees the chunk when the peer is not ready or its queue is past `stream_queue`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_push`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `peer`, `chunk`.

## Function `libp2p_pb_head`

Writes the key and length of a protobuf field of wire type 2.

### Signature

```
libp2p_pb_head(dst, field, n) -> dst after the head
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | the head bytes |
| `field` | input | u64 |
| `n` | input | u64 |

### Function does

- Writes the key (field << 3 | 2), then the varint length.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pb_head`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the head, not a status.
- Argument order: `dst`, `field`, `n`.

## Function `libp2p_gs_rpc`

Takes a chunk for an RPC of one field and writes its head.

### Signature

```
libp2p_gs_rpc(peer, inner, size, field) -> place, chunk
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |
| `inner` | input | unused |
| `size` | input | u64: bytes of the field value |
| `field` | input | u64: 1 subscriptions, 2 publish, 3 control, 10 partial |

### Function does

- Writes the varint length of the RPC and the head of its field.
- Gives the place for `size` bytes and the chunk, or place 0 when the heap is full.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_rpc`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the place in x0, rax or a0 and the chunk in x1, rdx or a1.
- Argument order: `peer`, `inner`, `size`, `field`.

## Function `libp2p_gs_send_sub`

Sends an RPC with one SubOpts.

### Signature

```
libp2p_gs_send_sub(peer, topic, subscribe)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |
| `topic` | input | [`Topic`](gossipsub.md#type-topic) slot |
| `subscribe` | input | u64: 1 or 0 |

### Function does

- Writes subscribe (field 1) and topicid (field 2).
- For a subscription, writes requestsPartial (field 3) and supportsSendingPartial (field 4) as true when our partial flags of the topic have them.
- Queues the RPC with `libp2p_gs_push`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_send_sub`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`, `subscribe`.

## Function `libp2p_gs_send_ext`

Sends an RPC with our Extensions control message.

### Signature

```
libp2p_gs_send_ext(peer)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |

### Function does

- With `partial_messages` on: writes control with extensions (field 6) holding partialMessages (field 10) true, and queues the RPC.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_send_ext`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`.

## Function `libp2p_gs_send_partial`

Sends an RPC with one PartialMessagesExtension.

### Signature

```
libp2p_gs_send_partial(peer, event, with_message)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |
| `event` | input | [`PartialSendEvent`](#type-partialsendevent) |
| `with_message` | input | u64: 1 or 0 |

### Function does

- Writes the extension as RPC field 10: topicID (field 1), groupID (field 2), partialMessage (field 3) when `with_message` is 1 and the event has message bytes, and partsMetadata (field 4) when the event has metadata bytes.
- Queues the RPC with `libp2p_gs_push`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_send_partial`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `event`, `with_message`.

## Function `libp2p_gs_send_msg`

Sends an RPC that publishes one message.

### Signature

```
libp2p_gs_send_msg(peer, topic, data, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |
| `topic` | input | [`Topic`](gossipsub.md#type-topic) slot |
| `data` | input | n bytes |
| `n` | input | u64 |

### Function does

- Writes a Message with data (field 2) and topic (field 4) only: StrictNoSign.
- Gives 1 when it is queued, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_send_msg`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `peer`, `topic`, `data`, `n`.

## Function `libp2p_gs_send_graft`

Sends control with one GRAFT.

### Signature

```
libp2p_gs_send_graft(peer, topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |
| `topic` | input | [`Topic`](gossipsub.md#type-topic) slot |

### Function does

- Writes ControlGraft with topicID (field 1).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_send_graft`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`.

## Function `libp2p_gs_send_prune`

Sends control with one PRUNE.

### Signature

```
libp2p_gs_send_prune(peer, topic, backoff)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |
| `topic` | input | [`Topic`](gossipsub.md#type-topic) slot |
| `backoff` | input | u64: seconds |

### Function does

- Writes ControlPrune with topicID (field 1) and backoff (field 3), and no peers.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_send_prune`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`, `backoff`.

## Function `libp2p_gs_send_ids`

Sends control with one IHAVE, one IWANT or one IDONTWANT.

### Signature

```
libp2p_gs_send_ids(peer, topic, list, count, kind)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | [`Peer`](connections.md#type-peer) slot |
| `topic` | input | [`Topic`](gossipsub.md#type-topic) slot for IHAVE; unused else |
| `list` | input | `count` pairs: the address of an ID, then its length |
| `count` | input | u64 |
| `kind` | input | u64: the field of the ControlMessage: 1 IHAVE, 2 IWANT, 5 IDONTWANT |

### Function does

- IHAVE: topicID (field 1), then each ID as messageIDs (field 2).
- IWANT and IDONTWANT: each ID as messageIDs (field 1).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_send_ids`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`, `list`, `count`, `kind`.

## Function `libp2p_gs_idontwant`

Sends IDONTWANT for a new message to the mesh of its topic.

### Signature

```
libp2p_gs_idontwant(pending)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pending` | input | [`Pending`](#type-pending) slot |

### Function does

- For a message of `idontwant_threshold` bytes or more, with `idontwant_threshold` above 0: sends IDONTWANT with its ID, at once, to each mesh peer of the topic that speaks "/meshsub/1.2.0", except the peer that sent it and the peers that send us partial messages of the topic (`libp2p_sends_partial`).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_idontwant`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `pending`.

## Function `libp2p_gs_announce`

Sends our subscription change to every gossipsub peer.

### Signature

```
libp2p_gs_announce(topic, subscribe)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | [`Topic`](gossipsub.md#type-topic) slot |
| `subscribe` | input | u64: 1 or 0 |

### Function does

- Sends one SubOpts to each peer that is ready.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_announce`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `topic`, `subscribe`.

## Function `libp2p_gossip_peer_up`

Opens our gossipsub stream to a peer that connected.

### Signature

```
libp2p_gossip_peer_up(peer)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | state | [`Peer`](connections.md#type-peer) slot |

### Function does

- Empties the IDONTWANT ring of the peer and its IDONTWANT counter.
- Opens a gossipsub stream on the first connection of the peer, with 1 + `gossipsub_v12` + `gossipsub_v13` proposals (`libp2p_gs_proposal`).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gossip_peer_up`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`.

## Function `libp2p_gossip_peer_down`

Takes a peer that left out of every topic.

### Signature

```
libp2p_gossip_peer_down(peer)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | state | [`Peer`](connections.md#type-peer) slot |

### Function does

- Forgets its promises.
- Takes it out of each mesh with `libp2p_mesh_remove` (with the mesh failure penalty), and out of fanouts and subscriber counts.
- Frees topics nothing uses any more.

### Function never

- Makes an OS call.

### Effects

- Its score counters and backoffs stay for a retained score.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gossip_peer_down`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`.

## Function `libp2p_gossip_out_ready`

Marks a peer ready and sends it our subscriptions.

### Signature

```
libp2p_gossip_out_ready(stream)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |

### Function does

- Marks the peer ready for gossipsub, and for IDONTWANT when the stream speaks "/meshsub/1.2.0" or "/meshsub/1.3.0".
- With "/meshsub/1.3.0": sends our Extensions control message first (`libp2p_gs_send_ext`).
- Sends one SubOpts for each topic we subscribe to.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gossip_out_ready`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`.

## Function `libp2p_gossip_in_ready`

Notes the peer's gossipsub stream to us.

### Signature

```
libp2p_gossip_in_ready(stream)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |

### Function does

- Keeps the stream index in the peer slot.
- Clears PF_EXT_SEEN, PF_EXT_GOT and PF_PARTIAL: the first RPC on the stream gives the extensions of the peer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gossip_in_ready`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`.

## Function `libp2p_gossip_rx`

Reads RPCs from a peer's gossipsub stream.

### Signature

```
libp2p_gossip_rx(stream, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Reads the varint length of each RPC, then that many bytes into one heap block, and handles a whole RPC with `libp2p_rpc_handle`.
- Skips an empty RPC, and an RPC the heap cannot hold.
- Keeps the block of an RPC that PARTIAL actions refer to on the kept list, linked by `HB_NEXT`, until the next step; frees the others.
- Resets the stream with PROTOCOL for an RPC above `max_rpc`, or a length prefix of more than 6 bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gossip_rx`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`, `p`, `n`.

## Function `libp2p_rpc_handle`

Handles one whole RPC of a peer.

### Signature

```
libp2p_rpc_handle(peer, p, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Ignores the RPC of a peer that is not connected, or whose score is below `graylist_threshold`.
- Handles subscriptions (field 1), publish (field 2), control (field 3) and partial (field 10) in their order.
- Stops at a field that is not well formed.
- Then marks the peer PF_EXT_SEEN: its extensions are known.
- Gives 1 when a PARTIAL action refers to bytes of the RPC, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_rpc_handle`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_field_bytes`

Finds the first field of wire type 2 with a number.

### Signature

```
libp2p_field_bytes(p, end, field) -> start, length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `p` | input | the bytes up to `end` |
| `end` | input | u64 |
| `field` | input | u64 |

### Function does

- Gives the start and length of the field, or start 0 when there is none or a field is not well formed.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_field_bytes`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the start in x0, rax or a0 and the length in x1, rdx or a1.
- Argument order: `p`, `end`, `field`.

## Function `libp2p_peer_topic`

Gives PEER_TOPIC for a subscription change of a peer.

### Signature

```
libp2p_peer_topic(peer, topic, subscribed)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | [`Topic`](gossipsub.md#type-topic) slot |
| `subscribed` | input | u64: 1 or 0 |

### Function does

- Gives PEER_TOPIC with the handle of the peer, the flag and the topic name.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_topic`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`, `subscribed`.

## Function `libp2p_rpc_sub`

Handles one subscription change of a peer.

### Signature

```
libp2p_rpc_sub(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Takes subscribe (field 1), topicid (field 2) of 1 to `LIBP2P_MAX_TOPIC` bytes, requestsPartial (field 3) and supportsSendingPartial (field 4); requestsPartial implies supportsSendingPartial.
- Subscribe: sets the partial flags of the peer in the topic; a new subscription marks the peer subscribed, counts it, and gives PEER_TOPIC; a topic slot is taken when needed.
- Unsubscribe: takes the peer out of our mesh and fanout of the topic, clears its partial flags, uncounts it, gives PEER_TOPIC, and frees the topic when nothing uses it.
- Ignores an unsubscription that changes nothing, or a topic with no free slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_rpc_sub`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_rpc_msg`

Handles one published message of a peer.

### Signature

```
libp2p_rpc_msg(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Takes data (field 2) and topic (field 4).
- Drops a message of a topic we do not subscribe to.
- Counts an invalid message of the peer for from, seqno, signature or key (fields 1, 3, 5, 6: StrictNoSign), or data above `max_data`.
- Else copies the data to a pending slot and gives MESSAGE: the application gives its ID with MESSAGE_ID.
- Drops the message when no pending slot, heap block or action room is free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_rpc_msg`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_rpc_control`

Handles one ControlMessage of a peer.

### Signature

```
libp2p_rpc_control(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Handles ihave (1), iwant (2), graft (3), prune (4), idontwant (5) and extensions (6) in their order; stops at a field that is not well formed.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_rpc_control`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_ctl_extensions`

Handles the Extensions control message of a peer.

### Signature

```
libp2p_ctl_extensions(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes: ControlExtensions |
| `n` | input | u64 |

### Function does

- The first one in the first RPC on the stream: marks the peer PF_EXT_GOT, and PF_PARTIAL when partialMessages (field 10) is true.
- Any other: one behaviour penalty (P7).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ctl_extensions`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_rpc_partial`

Handles the partial message RPC of a peer.

### Signature

```
libp2p_rpc_partial(peer, p, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes: PartialMessagesExtension |
| `n` | input | u64 |

### Function does

- Heard only with `partial_messages` on, from a peer marked PF_PARTIAL.
- Takes topicID (field 1, 1 to `LIBP2P_MAX_TOPIC` bytes) and groupID (field 2), which must be there, partialMessage (field 3) and partsMetadata (field 4).
- Drops partialMessage on a topic we do not want partial messages on.
- Gives PARTIAL with the flags of the peer on the topic when metadata or a message is left; its group, metadata and message point into the RPC.
- Gives 1 when it gave PARTIAL, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_rpc_partial`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_backoff_secs`

Gives milliseconds as whole seconds, rounded up.

### Signature

```
libp2p_backoff_secs(ms) -> seconds
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ms` | input | u64 |

### Function does

- Gives (ms + 999) / 1000.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_backoff_secs`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the seconds, not a status.
- Argument order: `ms`.

## Function `libp2p_prune_to`

Sends PRUNE to a peer and starts a backoff.

### Signature

```
libp2p_prune_to(peer, topic, backoff)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |
| `backoff` | input | u64: ms |

### Function does

- Sets the backoff of the peer in the topic to now + `backoff`, unless it ends later already.
- Sends PRUNE with the backoff in whole seconds.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_prune_to`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`, `backoff`.

## Function `libp2p_ctl_graft`

Handles a GRAFT of a peer.

### Signature

```
libp2p_ctl_graft(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes: ControlGraft |
| `n` | input | u64 |

### Function does

- Ignores a topic we do not subscribe to, or a peer already in the mesh.
- Within a backoff: one behaviour penalty, a second when within `graft_flood_ms` of the PRUNE, then PRUNE.
- A negative score, or a mesh of `d_high` or more and an inbound peer: PRUNE.
- Else the peer joins the mesh with `libp2p_mesh_add`.
- Each PRUNE carries `prune_backoff_ms`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ctl_graft`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_ctl_prune`

Handles a PRUNE of a peer.

### Signature

```
libp2p_ctl_prune(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes: ControlPrune |
| `n` | input | u64 |

### Function does

- Takes the peer out of our mesh of the topic.
- Sets a backoff: the backoff of the PRUNE in seconds, at most one day, or `prune_backoff_ms` without one.
- Ignores the exchanged peers.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ctl_prune`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_ctl_ihave`

Handles an IHAVE of a peer.

### Signature

```
libp2p_ctl_ihave(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes: ControlIHave |
| `n` | input | u64 |

### Function does

- Heard only from a peer at or above `gossip_threshold`, up to `max_ihave_messages` times and `max_ihave_length` IDs a heartbeat, for a topic we subscribe to.
- Asks for the IDs not seen with one IWANT.
- Records a promise for one of them, at random.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ctl_ihave`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_ctl_iwant`

Handles an IWANT of a peer.

### Signature

```
libp2p_ctl_iwant(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes: ControlIWant |
| `n` | input | u64 |

### Function does

- Heard only from a peer at or above `gossip_threshold`.
- Sends each message still in the cache, while `libp2p_mc_sent` allows it, unless the peer sent IDONTWANT for it.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ctl_iwant`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_ctl_idontwant`

Handles an IDONTWANT of a peer.

### Signature

```
libp2p_ctl_idontwant(peer, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `p` | input | n bytes: ControlIDontWant |
| `n` | input | u64 |

### Function does

- Not heard when `dontwant_slots` is 0, or after `max_idontwant_messages` IDONTWANT messages of the peer in this heartbeat.
- Puts up to `max_idontwant_length` message IDs of 1 to `LIBP2P_MAX_MSG_ID` bytes in the peer's ring, each with the heartbeat number, over the oldest entry.

### Function never

- Makes an OS call.

### Effects

- The peer does not get these messages from us for `dontwant_ttl` heartbeats.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ctl_idontwant`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `p`, `n`.

## Function `libp2p_mesh_add`

Adds a peer to our mesh of a topic, with GRAFT.

### Signature

```
libp2p_mesh_add(peer, topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |

### Function does

- Marks the peer in the mesh, from now, counts it, and sends GRAFT.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mesh_add`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`.

## Function `libp2p_mesh_remove`

Takes a peer out of our mesh of a topic.

### Signature

```
libp2p_mesh_remove(peer, topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |

### Function does

- Applies the mesh failure penalty with `libp2p_score_mesh_leave`, then unmarks and uncounts the peer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mesh_remove`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `peer`, `topic`.

## Function `libp2p_candidates`

Lists the peers of a topic that pass a filter.

### Signature

```
libp2p_candidates(topic, need, refuse, floor) -> count
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64: a topic slot index |
| `need` | input | u64: entry flags that must be set; `CAND_OUTBOUND`: outbound peers only |
| `refuse` | input | u64: entry flags that must be clear; `CAND_BACKOFF`: no peer within a backoff |
| `floor` | input | f64 in d0, xmm0 or fa0 |

### Function does

- Writes to the LIST of the scratch the peers that are ready, subscribed to the topic, with every need flag and no refuse flag, and a heartbeat score at or above `floor`.
- Gives their count.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_candidates`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the count, not a status.
- Argument order: `topic`, `need`, `refuse`, `floor`.

## Function `libp2p_shuffle`

Puts a list of u32 values in a random order.

### Signature

```
libp2p_shuffle(list, count)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `list` | state | `count` u32 |
| `count` | input | u64 |

### Function does

- Shuffles with Fisher-Yates and the DRBG.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_shuffle`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `list`, `count`.

## Function `libp2p_on_subscribe`

Joins a topic.

### Signature

```
libp2p_on_subscribe(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`SubscribeEvent`](#type-subscribeevent) |

### Function does

- Calls `libp2p_subscribe` with flags `NONE`: the partial flags of the topic stay.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_subscribe`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_partial_subscribe`

Joins a topic with partial flags.

### Signature

```
libp2p_on_partial_subscribe(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`PartialSubscribeEvent`](#type-partialsubscribeevent) |

### Function does

- Calls `libp2p_subscribe` with the flags of the event.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_partial_subscribe`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_subscribe`

Joins a topic, and sets our partial flags of it.

### Signature

```
libp2p_subscribe(name, n, flags)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `name` | input | n bytes |
| `n` | input | u64 |
| `flags` | input | u64: `LIBP2P_PARTIAL_*`, or `NONE` to keep the flags |

### Function does

- Takes or finds the topic slot; does nothing when the table is full.
- Sets our partial flags of the topic from `flags`; REQUESTS implies SUPPORTS.
- A topic we subscribe to already: tells every peer the new SubOpts when the flags change.
- Else fills the mesh up to `d`: first our fanout peers of the topic, then other subscribed peers at random; each with a score of 0 or more and outside a backoff, each with GRAFT.
- Then clears the fanout, and tells every peer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_subscribe`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `name`, `n`, `flags`.

## Function `libp2p_fanout_clear_topic`

Takes every peer out of the fanout of a topic.

### Signature

```
libp2p_fanout_clear_topic()
```

### Function does

- Unmarks and uncounts each fanout peer of the topic.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_fanout_clear_topic`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It takes the topic in x19, rbx or s1 and its index in x20, rbp or s2, from its caller.

## Function `libp2p_on_unsubscribe`

Leaves a topic.

### Signature

```
libp2p_on_unsubscribe(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`UnsubscribeEvent`](#type-unsubscribeevent) |

### Function does

- Clears our partial flags of the topic.
- Sends PRUNE with `unsub_backoff_ms` to each mesh peer and takes it out of the mesh.
- Tells every peer, and frees the topic when nothing uses it.
- Does nothing when we do not subscribe.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_unsubscribe`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_publish`

Publishes our own message.

### Signature

```
libp2p_on_publish(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`PublishEvent`](#type-publishevent) |

### Function does

- Does not send a message whose ID is seen.
- Marks the ID seen and valid, and caches the message.
- With `flood_publish`: sends it to every subscribed peer at or above `publish_threshold`.
- Else to the mesh of a topic we subscribe to; or to the fanout (`libp2p_fanout_list`).
- Skips a peer that sent IDONTWANT for the ID, and a peer that gets partial messages of the topic from us (`libp2p_wants_partial`).
- Gives PUBLISHED with the number of peers it went to.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_publish`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_fanout_list`

Lists the fanout peers of a topic we do not subscribe to.

### Signature

```
libp2p_fanout_list(topic, index) -> count
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | state | [`Topic`](gossipsub.md#type-topic) slot |
| `index` | input | u64: a topic slot index |

### Function does

- Sets our last publish to the topic to now.
- An empty fanout is first filled up to `d` at random with subscribed peers at or above `publish_threshold`.
- Writes the fanout peers to the LIST of the scratch and gives their count.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_fanout_list`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the count, not a status.
- Argument order: `topic`, `index`.

## Function `libp2p_on_message_id`

Takes the ID the application gave a received message.

### Signature

```
libp2p_on_message_id(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`MessageIdEvent`](#type-messageidevent) |

### Function does

- Ends the promises of the ID.
- Seen before: scores the delivery with `libp2p_score_duplicate`, gives MESSAGE_STATUS duplicate, and frees the slot.
- Else marks the ID seen and pending, sends IDONTWANT with `libp2p_gs_idontwant`, and gives MESSAGE_STATUS new: the application judges it with VALIDATION.
- Ignores a stale handle or a message that has its ID already.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_message_id`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_validation`

Acts on the verdict of the application.

### Signature

```
libp2p_on_validation(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`ValidationEvent`](#type-validationevent) |

### Function does

- ACCEPT: marks the ID valid, scores the deliveries, caches the message, and sends it to the mesh of the topic but not to the peers that sent it, sent IDONTWANT for it, or get partial messages of the topic from us.
- REJECT: marks the ID invalid and counts an invalid message for each peer that sent it.
- IGNORE: marks the ID ignored.
- Then frees the slot; ignores a stale handle or a message still waiting for its ID.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_validation`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_seen_delivered`

Tells whether a peer is a deliverer of a seen message.

### Signature

```
libp2p_seen_delivered(peer, seen) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `seen` | input | [`SeenEntry`](#type-seenentry), or 0 |

### Function does

- Gives 1 when the peer is among the deliverers, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_seen_delivered`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 1 or 0, not a status.
- Argument order: `peer`, `seen`.

## Function `libp2p_gossip_timers`

Runs the validation deadlines, retained scores, the heartbeat and score decay.

### Signature

```
libp2p_gossip_timers()
```

### Function does

- Drops a message the application did not judge within `validation_ms`: MESSAGE_STATUS dropped; with no action room, asks for a wakeup now.
- Frees a retained peer past its expiry.
- Runs the heartbeat when due; the next one is `heartbeat_ms` later, or `heartbeat_ms` after now when it fell behind.
- With scoring on, runs score decay when due, the same way.
- Asks for a wakeup at the next of these times.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gossip_timers`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_heartbeat`

Runs one gossipsub heartbeat.

### Signature

```
libp2p_heartbeat()
```

### Function does

- Scores every connected peer for this heartbeat.
- Resets the IHAVE and IDONTWANT counters.
- Gives a behaviour penalty for each promise past its deadline.
- Maintains the mesh of each topic we subscribe to, and the fanout of each other topic with one, then gossips with `libp2p_emit_gossip`.
- Moves the message cache to a new window, and drops old seen entries.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_heartbeat`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_list_score`

Gives the heartbeat score of the peer at a list place.

### Signature

```
libp2p_list_score(list, i) -> score
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `list` | input | u32 peer slot indexes |
| `i` | input | u64 |

### Function does

- Reads the score of the peer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_list_score`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the f64 score in d0, xmm0 or fa0.
- Argument order: `list`, `i`.

## Function `libp2p_list_outbound`

Tells whether the peer at a list place is outbound.

### Signature

```
libp2p_list_outbound(list, i) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `list` | input | u32 peer slot indexes |
| `i` | input | u64 |

### Function does

- Gives 1 when we dialled the peer, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_list_outbound`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `list`, `i`.

## Function `libp2p_sort_score`

Sorts a peer list by falling score.

### Signature

```
libp2p_sort_score(list, count)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `list` | state | u32 peer slot indexes |
| `count` | input | u64 |

### Function does

- Sorts with insertion sort; peers with equal scores keep their order.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_sort_score`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `list`, `count`.

## Function `libp2p_add_from_list`

Adds the first peers of the LIST of the scratch to a mesh.

### Signature

```
libp2p_add_from_list(topic, count)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64: a topic slot index |
| `count` | input | u64 |

### Function does

- Adds each with `libp2p_mesh_add`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_add_from_list`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `topic`, `count`.

## Function `libp2p_mesh_maintain`

Maintains our mesh of a topic in the heartbeat.

### Signature

```
libp2p_mesh_maintain(topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64: a topic slot index |

### Function does

- Takes out mesh peers that are not ready, and those with a negative score with PRUNE.
- Below `d_low`: adds peers at random up to `d`, with a score of 0 or more and outside a backoff.
- Above `d_high`: keeps the `d_score` best by score and others at random up to `d`, with at least `d_out` outbound peers when it can; the rest leave with PRUNE.
- With at least `d_low` peers but fewer than `d_out` outbound ones: adds outbound peers at random, with a score of 0 or more and outside a backoff.
- Every `opportunistic_ticks` heartbeats, when the mesh has more than one peer and its median score is below `opportunistic_threshold`: adds up to `opportunistic_peers` peers at random that score above the median, outside a backoff.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mesh_maintain`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `topic`.

## Function `libp2p_keep_outbound`

Moves outbound peers into the kept part of a list.

### Signature

```
libp2p_keep_outbound(list, kept, count)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `list` | state | u32 peer slot indexes |
| `kept` | input | u64 |
| `count` | input | u64 |

### Function does

- While the first `kept` peers have fewer than `d_out` outbound peers, swaps an outbound peer after them with the last inbound peer among them.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_keep_outbound`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `list`, `kept`, `count`.

## Function `libp2p_fanout_maintain`

Maintains the fanout of a topic in the heartbeat.

### Signature

```
libp2p_fanout_maintain(topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64: a topic slot index |

### Function does

- Ends a fanout unused for longer than `fanout_ttl_ms`, and frees the topic when nothing uses it.
- Else takes out peers that are not ready or score below `publish_threshold`, and fills it up to `d` at random.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_fanout_maintain`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `topic`.

## Function `libp2p_emit_gossip`

Sends IHAVE gossip for a topic.

### Signature

```
libp2p_emit_gossip(topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64: a topic slot index |

### Function does

- Takes the IDs of the cached messages of the topic in the last `mcache_gossip` windows, at most `max_ihave_length` chosen at random.
- Sends them as IHAVE to max(`d_lazy`, `gossip_factor` x candidates) peers at random: peers not in the mesh or fanout, at or above `gossip_threshold`.
- A chosen peer that gets partial messages of the topic from us (`libp2p_wants_partial`) gets no IHAVE: PARTIAL_GOSSIP lists these peers, also when there are no IDs and we send partial messages on the topic.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_emit_gossip`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `topic`.

## Function `libp2p_partial_flags`

Gives the partial flags of a peer in a topic.

### Signature

```
libp2p_partial_flags(peer, topic) -> flags
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |

### Function does

- Gives the `LIBP2P_PARTIAL_*` flags of the SubOpts of the peer.
- Gives 0 when `partial_messages` is off or the peer is not marked PF_PARTIAL.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_partial_flags`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the flags, not a status.
- Argument order: `peer`, `topic`.

## Function `libp2p_wants_partial`

Tells whether we send a peer partial messages of a topic.

### Signature

```
libp2p_wants_partial(peer, topic) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |

### Function does

- Gives 1 when we send partial messages on the topic and the peer wants them, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_wants_partial`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `peer`, `topic`.

## Function `libp2p_sends_partial`

Tells whether a peer sends us partial messages of a topic.

### Signature

```
libp2p_sends_partial(peer, topic) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | u64: a peer slot index |
| `topic` | input | u64: a topic slot index |

### Function does

- Gives 1 when we want partial messages on the topic and the peer sends them, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_sends_partial`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `peer`, `topic`.

## Function `libp2p_on_partial_peers`

Lists the peers of a topic to send partial messages to.

### Signature

```
libp2p_on_partial_peers(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`PartialPeersEvent`](#type-partialpeersevent) |

### Function does

- A topic we subscribe to: keeps the mesh peers with `libp2p_wants_partial` or `libp2p_sends_partial`.
- Else: keeps the fanout peers (`libp2p_fanout_list`) that want partial messages.
- Gives PARTIAL_PEERS with each peer and its `LIBP2P_PARTIAL_*` flags; the list is empty when the topic table is full.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_partial_peers`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_partial_send`

Sends a partial message RPC to one peer.

### Signature

```
libp2p_on_partial_send(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`PartialSendEvent`](#type-partialsendevent) |

### Function does

- With `partial_messages` on, to a connected peer marked PF_PARTIAL: sends the RPC with `libp2p_gs_send_partial`.
- The message goes only to a peer that wants partial messages on the topic.
- Sends nothing when no metadata or message is left.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_partial_send`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_partial_score`

Scores partial message data of a peer.

### Signature

```
libp2p_on_partial_score(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`PartialScoreEvent`](#type-partialscoreevent) |

### Function does

- ACCEPT: a first delivery of the peer in the topic (`libp2p_score_valid`).
- REJECT: an invalid message of the peer in the topic (`libp2p_score_invalid`).
- Does nothing for a peer that is not connected or a topic with no slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_partial_score`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Type `Topic`

One topic: our subscription, its mesh and fanout, its score parameters.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `used` | u64 | 1 while the slot is in use |
| 8 | `flags` | u64 | TF_SUBSCRIBED, TF_PARAMS, TF_REQUESTS_PARTIAL, TF_SUPPORTS_PARTIAL |
| 16 | `len` | u64 | Bytes of the name |
| 24 | `hash` | u64 | FNV-1a 64 of the name |
| 32 | `name` | 256 bytes | The name |
| 288 | `mesh` | u64 | Peers in the mesh |
| 296 | `fanout` | u64 | Peers in the fanout |
| 304 | `fanout_last` | u64 | ms: our last publish |
| 312 | `peers` | u64 | Peers subscribed |
| 320 | `params` | [`TopicParams`](scoring.md#type-topicparams) | Score parameters, with TF_PARAMS |

### Rules

- A slot is taken for a topic we join, a topic a peer subscribes to, or score parameters; it is freed when none is left.


## Type `PeerTopic`

The state of one peer in one topic.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `flags` | u64 | PTF_SUBSCRIBED, PTF_MESH, PTF_FANOUT, PTF_REQUESTS_PARTIAL, PTF_SUPPORTS_PARTIAL |
| 8 | `graft_time` | u64 | ms |
| 16 | `backoff` | u64 | ms: no GRAFT before then |
| 24 | `first` | f64 | P2 counter |
| 32 | `mesh_del` | f64 | P3 counter |
| 40 | `mesh_fail` | f64 | P3b counter |
| 48 | `invalid` | f64 | P4 counter |

### Rules

- Entries are zeroed when the peer slot is freed.
- An entry is 64 bytes.


## Type `SeenEntry`

A message ID the node has seen, and its verdict.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `id_len` | u64 | Bytes of the ID |
| 8 | `id` | 32 bytes | The ID |
| 40 | `time` | u64 | ms: first seen |
| 48 | `status` | u64 | SS_PENDING, SS_VALID, SS_INVALID or SS_IGNORED |
| 56 | `validated` | u64 | ms |
| 64 | `topic` | u32 | The topic slot index |
| 68 | `count` | u32 | Deliverers in `peers` |
| 72 | `peers` | 12 u16 | Peers that sent it while it was judged |

### Rules

- The seen cache is a ring of `seen_capacity` entries with a hash index; the oldest goes first.


## Type `DontWantEntry`

A message ID a peer sent in IDONTWANT.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `hb` | u64 | The heartbeat number when it came |
| 8 | `id_len` | u64 | Bytes of the ID; 0: empty |
| 16 | `id` | 32 bytes | The ID |

### Rules

- Each peer has a ring of `dontwant_slots` entries; a new ID goes over the oldest.
- An entry counts for `dontwant_ttl` heartbeats.


## Type `CacheEntry`

A message kept for IWANT and gossip.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `id_len` | u64 | Bytes of the ID |
| 8 | `id` | 32 bytes | The ID |
| 40 | `topic` | u64 | The topic slot index |
| 48 | `data` | u64 | Heap offset |
| 56 | `data_len` | u64 | Bytes of the data |
| 64 | `window` | u64 | Heartbeat number when it was put |
| 72 | `used` | u64 | 1 while the entry is in use |
| 80 | `tx` | 2 bits x max_peers | 2 bits for each peer: IWANT answers sent |

### Rules

- The cache is a ring of `mcache_capacity` entries with a hash index; an entry leaves after `mcache_len` heartbeats, or when the ring is full.


## Type `Pending`

A received message that waits for its ID and verdict.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `gen` | u32 | Generation of the slot |
| 4 | `state` | u32 | PDS_FREE, PDS_WAIT_ID or PDS_WAIT_VERDICT |
| 8 | `peer` | u64 | The peer slot index of the sender |
| 16 | `topic` | u64 | The topic slot index |
| 24 | `data` | u64 | Heap offset |
| 32 | `data_len` | u64 | Bytes of the data |
| 40 | `time` | u64 | ms: when it came |
| 48 | `id_len` | u64 | Bytes of the ID |
| 56 | `id` | 32 bytes | The ID |
| 88 | `seen` | u64 | The seen entry, once the ID came |

### Rules

- Its handle is the handle of MESSAGE, MESSAGE_ID, MESSAGE_STATUS and VALIDATION.


## Type `Promise`

A message a peer announced with IHAVE and that we asked for.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `peer` | u64 | NONE when unused |
| 8 | `deadline` | u64 | ms: the message is due by then |
| 16 | `id_len` | u64 | Bytes of the ID |
| 24 | `id` | 32 bytes | The ID |

### Rules

- A promise past its deadline costs the peer a behaviour penalty in the heartbeat.


## Type `SubscribeEvent`

The application joins a topic.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `topic_len` | u64 | Bytes of the topic, 1 to `LIBP2P_MAX_TOPIC` |
| 24 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_EVENT_SUBSCRIBE`; the size covers the topic.
- A request that changes nothing does nothing.


## Type `UnsubscribeEvent`

The application leaves a topic.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `topic_len` | u64 | Bytes of the topic, 1 to `LIBP2P_MAX_TOPIC` |
| 24 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_EVENT_UNSUBSCRIBE`; the size covers the topic.
- A request that changes nothing does nothing.


## Type `PublishEvent`

The application publishes a message.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `id_len` | u64 | Bytes of the message ID, 1 to `LIBP2P_MAX_MSG_ID` |
| 24 | `id` | 32 bytes | The message ID |
| 56 | `topic_len` | u64 | Bytes of the topic, 1 to `LIBP2P_MAX_TOPIC` |
| 64 | `data_len` | u64 | Bytes of the data, at most `max_data` |
| 72 | `topic` | `topic_len` bytes | The topic; the data follows at the next multiple of 8 |

### Rules

- Kind `LIBP2P_EVENT_PUBLISH`; the size covers the topic and the data.
- The application computes the message ID, as the consensus specs define it.
- It ends in PUBLISHED; a message whose ID is seen is not sent and gives 0 peers.


## Type `MessageIdEvent`

The application gives the ID of a received message.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `handle` | u64: a handle ([`Handle`](node.md#type-handle)) | The message |
| 24 | `id_len` | u64 | Bytes of the ID, 1 to `LIBP2P_MAX_MSG_ID` |
| 32 | `id` | 32 bytes | The ID |

### Rules

- Kind `LIBP2P_EVENT_MESSAGE_ID`, size at least `LIBP2P_EV_MSG_ID_SIZE`.
- It answers MESSAGE; MESSAGE_STATUS follows.
- A stale handle does nothing.


## Type `ValidationEvent`

The application judges a message.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `handle` | u64: a handle ([`Handle`](node.md#type-handle)) | The message |
| 24 | `result` | u64 | `LIBP2P_ACCEPT`, `LIBP2P_REJECT` or `LIBP2P_IGNORE` |

### Rules

- Kind `LIBP2P_EVENT_VALIDATION`, size at least `LIBP2P_EV_VALIDATION_SIZE`.
- It answers MESSAGE_STATUS new; the handle then stops working.
- A stale handle does nothing.


## Type `MessageAction`

A peer sent a message of a topic we subscribe to.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `handle` | u64: a handle ([`Handle`](node.md#type-handle)) | The message |
| 24 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer that sent it |
| 32 | `data_off` | u64 | Where the data is, from the start of the state |
| 40 | `data_len` | u64 | Bytes of the data |
| 48 | `topic_len` | u64 | Bytes of the topic |
| 56 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_ACTION_MESSAGE`; the size covers the topic.
- The data is valid until the next step.
- The application answers with MESSAGE_ID within `validation_ms`.


## Type `MessageStatusAction`

Tells the application what to do with a message.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `handle` | u64: a handle ([`Handle`](node.md#type-handle)) | The message |
| 24 | `status` | u64 | `LIBP2P_MSG_NEW`, `LIBP2P_MSG_DUPLICATE` or `LIBP2P_MSG_DROPPED` |

### Rules

- Kind `LIBP2P_ACTION_MESSAGE_STATUS`, size `LIBP2P_ACT_STATUS_SIZE`.
- NEW: judge it and send VALIDATION within `validation_ms`.
- DUPLICATE and DROPPED: drop it; the handle stops working.


## Type `PublishedAction`

A message of PUBLISH went out.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `id_len` | u64 | Bytes of the message ID |
| 24 | `id` | 32 bytes | The message ID |
| 56 | `peers` | u64 | Peers it was queued for |

### Rules

- Kind `LIBP2P_ACTION_PUBLISHED`, size `LIBP2P_ACT_PUB_SIZE`.
- Once for each PUBLISH.


## Type `PartialSubscribeEvent`

The application joins a topic, with partial flags.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `flags` | u64 | `LIBP2P_PARTIAL_REQUESTS`, `LIBP2P_PARTIAL_SUPPORTS`, both, or 0 |
| 24 | `topic_len` | u64 | Bytes of the topic, 1 to `LIBP2P_MAX_TOPIC` |
| 32 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_EVENT_PARTIAL_SUBSCRIBE`; the size covers the topic.
- Flags other than 0 need `partial_messages` on.
- REQUESTS implies SUPPORTS.
- On a topic we subscribe to, it changes the flags and peers hear the new SubOpts.


## Type `PartialPeersEvent`

The application asks which peers of a topic take part in partial messages.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `topic_len` | u64 | Bytes of the topic, 1 to `LIBP2P_MAX_TOPIC` |
| 24 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_EVENT_PARTIAL_PEERS`; the size covers the topic.
- It ends in PARTIAL_PEERS in the same step.


## Type `PartialSendEvent`

The application sends partial message data or metadata to one peer.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |
| 24 | `topic_len` | u64 | Bytes of the topic, 1 to `LIBP2P_MAX_TOPIC` |
| 32 | `group_len` | u64 | Bytes of the group ID, at most `max_rpc` |
| 40 | `meta_len` | u64 | Bytes of the parts metadata, at most `max_rpc`; 0: none |
| 48 | `msg_len` | u64 | Bytes of the partial message, at most `max_rpc`; 0: none |
| 56 | `bytes` | bytes | The topic, the group ID, the metadata and the message, each at a multiple of 8 |

### Rules

- Kind `LIBP2P_EVENT_PARTIAL_SEND`; the size covers the bytes.
- The encoding of the group ID, the metadata and the message is the application's.
- A peer that does not want partial messages on the topic gets the metadata only.


## Type `PartialScoreEvent`

The application judges partial message data of a peer.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |
| 24 | `result` | u64 | `LIBP2P_ACCEPT` or `LIBP2P_REJECT` |
| 32 | `topic_len` | u64 | Bytes of the topic, 1 to `LIBP2P_MAX_TOPIC` |
| 40 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_EVENT_PARTIAL_SCORE`; the size covers the topic.
- ACCEPT counts as a first delivery; REJECT as an invalid message.


## Type `PartialAction`

A peer sent a PartialMessagesExtension.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer that sent it |
| 24 | `flags` | u64 | The `LIBP2P_PARTIAL_*` flags of the peer on the topic |
| 32 | `topic_len` | u64 | Bytes of the topic |
| 40 | `group_off` | u64 | Where the group ID is, from the start of the state |
| 48 | `group_len` | u64 | Bytes of the group ID |
| 56 | `meta_off` | u64 | Where the parts metadata is; 0 with none |
| 64 | `meta_len` | u64 | Bytes of the parts metadata |
| 72 | `msg_off` | u64 | Where the partial message is; 0 with none |
| 80 | `msg_len` | u64 | Bytes of the partial message |
| 88 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_ACTION_PARTIAL`; the size covers the topic.
- The group ID, metadata and message are valid until the next step.
- It comes for any topic, also one we do not subscribe to.
- A message comes only on a topic we want partial messages on.


## Type `PartialPeersAction`

The peers of a topic to send partial messages to.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `topic_len` | u64 | Bytes of the topic |
| 24 | `count` | u64 | Peers in the list |
| 32 | `topic` | `topic_len` bytes | The topic; the list follows at the next multiple of 8: `count` pairs of a peer handle and its `LIBP2P_PARTIAL_*` flags |

### Rules

- Kind `LIBP2P_ACTION_PARTIAL_PEERS`; the size covers the topic and the list.
- It answers PARTIAL_PEERS.


## Type `PartialGossipAction`

Gossip peers of a heartbeat that get partial messages from us.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `topic_len` | u64 | Bytes of the topic |
| 24 | `count` | u64 | Peers in the list |
| 32 | `topic` | `topic_len` bytes | The topic; the list follows at the next multiple of 8: `count` peer handles |

### Rules

- Kind `LIBP2P_ACTION_PARTIAL_GOSSIP`; the size covers the topic and the list.
- The heartbeat gives it in place of IHAVE to these peers: the application may send them partial messages.


## Type `PeerTopicAction`

A peer joined or left a topic.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |
| 24 | `subscribed` | u64 | 1 joined, 0 left |
| 32 | `topic_len` | u64 | Bytes of the topic |
| 40 | `topic` | `topic_len` bytes | The topic |

### Rules

- Kind `LIBP2P_ACTION_PEER_TOPIC`; the size covers the topic.
- Only for a change: a repeated subscription gives none.


## Test vectors

- Scenarios of [tests/runner/runner.c](../../tests/runner/runner.c): gossip (6 nodes), gossip_lazy, scoring, secondary, idontwant (fewer duplicates with IDONTWANT, and a node of v1.1 only), partial (the Extensions control message, partial flags, PARTIAL_PEERS, PARTIAL_SEND, full messages routed around partial peers, PARTIAL_GOSSIP, and a node of v1.2 only).
- gossipsub-interop of libp2p/test-plans ([tests/gossipsub/](../../tests/gossipsub/)): networks shared with go, rust, jvm and nim, and partial message networks shared with go, rust and nim.
- The shell loop test ([tests/shell/loop.c](../../tests/shell/loop.c)): one message between two nodes on every OS.
- The live test on Ethereum mainnet ([tests/mainnet/](../../tests/mainnet/)): beacon blocks and attestations from peers of every client.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_peer_at`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_idx`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_topic_at`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_topic_idx`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pt`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_topic_find`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_topic_get`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_topic_tidy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_ready`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_idx_find`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_idx_add`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_idx_del`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_seen_args`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_seen_find`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_seen_drop_tail`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_seen_tail`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_seen_add`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_seen_args_keep`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_seen_expire`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mc_args`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mc_find`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mc_tail`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mc_drop_tail`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mc_put`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mc_shift`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mc_sent`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pend`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pend_free`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pend_status`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_promise_add`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_promise_keep`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_promise_drop_peer`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_dw_ring`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_dontwant`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_alloc`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_push`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pb_head`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_rpc`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_send_sub`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_send_ext`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_send_partial`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_send_msg`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_send_graft`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_send_prune`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_send_ids`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_idontwant`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_announce`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gossip_peer_up`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gossip_peer_down`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gossip_out_ready`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gossip_in_ready`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gossip_rx`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_rpc_handle`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_field_bytes`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_topic`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_rpc_sub`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_rpc_msg`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_rpc_control`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ctl_extensions`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_rpc_partial`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_backoff_secs`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_prune_to`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ctl_graft`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ctl_prune`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ctl_ihave`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ctl_iwant`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ctl_idontwant`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mesh_add`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mesh_remove`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_candidates`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shuffle`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_subscribe`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_partial_subscribe`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_subscribe`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_fanout_clear_topic`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_unsubscribe`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_publish`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_fanout_list`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_message_id`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_validation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_seen_delivered`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gossip_timers`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_heartbeat`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_list_score`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_list_outbound`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_sort_score`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_add_from_list`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mesh_maintain`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_keep_outbound`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_fanout_maintain`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_emit_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_partial_flags`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_wants_partial`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_sends_partial`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_partial_peers`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_partial_send`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_partial_score`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
