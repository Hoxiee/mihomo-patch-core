# Rain Core

The official mihomo core of [ReClash](https://github.com/Hoxiee/ReClash): a patch series that turns
a clean [mihomo](https://github.com/MetaCubeX/mihomo) checkout into the proxy engine the
application ships. It is built for ReClash and usable by any mihomo host through its `core`
profile; the upstream tree stays unmodified and every behaviour is a numbered, reviewable patch
that can be rebased or deleted on its own.

The dependency direction is explicit:

```
core  ->  flclash  ->  reclash
```

- **core** — Xray compatibility and neutral diagnostics. It has no FlClash or ReClash references
  and applies to a clean mihomo checkout on its own.
- **flclash** — the FlClash host integration on top of core, plus the small adaptation that moves
  the finalmask `features.CMFA` guard to FlClash's `features.Android`.
- **reclash** — ReClash product logic on top of FlClash: external adapters, proxy metadata, dial
  hooks, health scheduling, diagnostics, site lock, policy hooks, direct split, geo digests and
  listener plumbing. Each concern is a separate patch.

The profiles are the source of truth. A host layer never moves into core, and a core patch is
never appended after a host patch.

## Base

`base.env` is the only source of truth:

```
MIHOMO_TAG=v1.19.34
MIHOMO_COMMIT=0455d0d28c4526937380505153e65a843d8612e8
```

All patches are generated against that tag. A core bump starts by changing `base.env`, replaying
the profiles, and fixing the first patch that no longer applies.

## Layout

```
patches/
  xray/                     core: client-side Xray compatibility
  diagnostics/              core: probe and transfer diagnostics
  flclash/                  FlClash host integration and feature.Android adaptation
  reclash/                  ReClash product layers, one concern per patch
profiles/
  core.txt                  xray + diagnostics
  flclash.txt               core + flclash
  reclash.txt               flclash + reclash
tool/
  patch.sh                  list / status / check / apply / revert
  test.sh                   fresh checkout + apply + go test
  packages.txt              packages exercised by test.sh
base.env                    upstream pin
```

Patch names keep the original ClashFest numbers for the Xray layer, so comments inside the code
that say “ClashFest core patch 0027” still point at the right source.

## Apply

The target is any mihomo git checkout at the pinned base. The default profile is `reclash`:

```bash
tool/patch.sh apply ../ReClash/core/mihomo --profile reclash
```

Other commands and profiles:

```bash
tool/patch.sh list   --profile core
tool/patch.sh status ../ReClash/core/mihomo --profile flclash
tool/patch.sh check  ../ReClash/core/mihomo --profile core
tool/patch.sh revert ../ReClash/core/mihomo --profile reclash
```

`apply` uses plain `git apply`. It skips patches that are already applied and stops at the first
patch that does not apply, printing the `git apply --3way` command to resolve it. Do not commit
applied patches into the mihomo checkout: the series is the source of truth.

## Test

`tool/test.sh` clones the pinned tag into a temporary directory, applies the selected profile,
adds the `mldsa` module the REALITY patch imports, and runs the patched packages:

```bash
tool/test.sh --profile core
tool/test.sh --profile flclash
tool/test.sh --profile reclash
tool/test.sh --profile reclash --keep   # leave the checkout for inspection
```

The packages are listed in `tool/packages.txt`. The build uses `with_gvisor`, the tag ReClash
ships with. Tests that need an Xray binary or external network skip themselves.

`tool/xray_interop.sh` runs the mux.cool interop test against a pinned Xray-core release. It
downloads `Xray-linux-64.zip` for `XRAY_VERSION` (default 26.11.9), verifies `XRAY_SHA256`, clones
the base, applies the `core` profile and runs `TestXrayInterop`:

```bash
tool/xray_interop.sh
tool/xray_interop.sh --target ../ReClash/core/.mihomo   # existing core-profile checkout
```

CI runs the same script in the `interop` job. Without `MIHOMO_XRAY_BIN` the Go test skips with an
explicit message, so a normal `tool/test.sh` run stays self-contained.

The mux.cool fault suite is part of every run and stays under five seconds.
`transport/muxcool/fault_carrier_test.go` wraps the carrier in a `net.Conn` that injects latency,
deterministic jitter, token-bucket bandwidth throttling, temporary write stalls, short writes and a
partial write failure; its dialer owns the peer side, so a test can produce a clean FIN, a TCP reset
(`SO_LINGER 0`) or a blackholed peer the way a real peer does. `fault_injection_test.go` runs TCP and
UDP sessions at 0/20/250 ms delay (plus 20 ms of jitter), a stall past the frame timeout, short and
partial writes, peer EOF and RST, a server that stops reading, and sibling isolation, and asserts
bounded errors and no panic. `goroutine_leak_test.go` captures `runtime.NumGoroutine` before and
after a mixed TCP+UDP workload with carrier rotation and deadline churn, retries with a bound, and
fails with a `runtime.Stack` dump on growth. No new dependency is required.

The soak is opt-in because it is a wall-clock stress run:

```bash
MIHOMO_SOAK_SECONDS=30 go test -run TestSoak -timeout 180s ./transport/muxcool/
MIHOMO_SOAK_SECONDS=30 MIHOMO_SOAK_WORKERS=128 go test -run TestSoak -timeout 180s ./transport/muxcool/
```

It mixes `MIHOMO_SOAK_WORKERS` sessions (default 128, minimum 100) split between TCP and UDP,
open/close churn, carrier rotation, consumers that trip `ErrSessionOverflow`, UDP datagram drops and
periodic carrier kills. Every successful session must echo its payload, every failure must be one of
the documented errors, and the goroutine count must return to its pre-run baseline.

## Profiles

| Profile | Patches | Contents |
|---|---:|---|
| `core` | 50 | xray 47 + diagnostics 3 |
| `flclash` | 52 | core + FlClash host 1 + feature.Android adaptation 1 |
| `reclash` | 73 | flclash + ReClash 21 |

`core` is independently usable by any mihomo host. `flclash` keeps the FlClash contract. `reclash`
is what the ReClash application consumes.

## mux.cool

`xray/0037` ports the client from Veles/Prizrak; `xray/0048` fixes the draining-carrier close
deadlock. The hardening patches keep that port as the wire source and fix the transport around it:

| Patch | Concern |
|---|---|
| `0049-muxcool-downlink-backpressure` | byte/frame-bounded per-session queues; a slow TCP consumer resets only its session with `ErrSessionOverflow`; UDP drops are counted; pooled buffers are released on overflow/reset/close; End never blocks the read loop |
| `0050-muxcool-write-deadlines` | deadline-aware carrier write turn; 30 s whole-frame write timeout closes a stalled carrier; `WriteTo` honors its deadline across the turn and the physical write |
| `0051-muxcool-pool-lifecycle` | the carrier dial belongs to the pool, not the caller; waiters of a failed dial share its error; exponential failure backoff; idle carriers of another pool are reclaimed under limiter pressure |
| `0052-muxcool-xray-modes` | Xray aliases `concurrency`, `xudpConcurrency`, `xudpProxyUDP443`; TCP-only, UDP-only and Vision+XUDP-only modes; a no-pool block is ignored with a warning |
| `0053-muxcool-diagnostics` | `Pool.Stats` / `MuxCool.Stats` counters without hot-path logging or a ReClash dependency |
| `0054-muxcool-protocol-hardening` | server-initiated New is ignored; the uncontended write turn avoids a per-frame timer; fuzz targets, protocol edge tests and benchmarks |
| `0055-muxcool-xray-interop` | real Xray-core interop suite, pinned and run in CI |
| `0056-muxcool-expired-write-deadline` | an already-expired caller deadline is rejected after taking the write turn without closing the carrier |
| `0057-muxcool-soak-fault-injection` | fault-injecting carrier (latency, jitter, token bucket, stalls, short/partial writes), deterministic TCP and UDP fault matrix, goroutine-leak check, opt-in soak; fixes a clean-EOF payload drop and a failed carrier still accepting sessions |
| `0058-muxcool-dial-retry-contract` | the failed-dial tests follow the 0051 immediate first retry: the caller may observe the error or the transparent success, with exactly two dials, dial-failure stats matching the attempted dials and the limiter slot released |

### Compatibility

| Feature | Status |
|---|---|
| TCP mux | supported; default `max-concurrency` 8, `max-connections` 128 |
| XUDP, shared pool | `xudp-concurrency: 0` (the historical meaning, same as Xray) |
| XUDP, separate pool | `xudp-concurrency: > 0` |
| TCP-only | `concurrency: 0` with no XUDP pool means no mux at all; with an XUDP pool it means UDP-only |
| UDP-only | `concurrency: 0`, `xudp-concurrency: > 0`; interop-tested |
| Vision + UDP-only mux | allowed; TCP stays plain Vision, the carrier carries only UDP; interop-tested |
| Vision + TCP mux | rejected; Xray breaks such carriers and the parser keeps that rule |
| `xudp-proxy-udp443` | `reject` (default), `allow`, `skip`; the outer mihomo `udp-443: reject` still wins when set |
| GlobalID | derived from `SrcIP:SrcPort`; zero when the source is invalid, which Xray treats as plain UDP |
| IPv4, IPv6, domains | codec golden vectors and unit tests; interop covers IPv4 and domains |
| VLESS transports | mux sits above the transport; interop covers plain TCP and TLS 1.3, unit tests cover REALITY/XHTTP/WS construction |
| XDRIVE, smux | mux.cool over XDRIVE and smux together are rejected, as before |

### Limits

- One carrier is one physical TCP connection. Transport-level head-of-line blocking cannot be
  removed by the client without changing the wire protocol.
- Mux.Cool has no per-stream window. A TCP consumer more than 256 KiB behind is reset with
  `ErrSessionOverflow` instead of stalling every sibling; the caller sees the error, and TCP data
  is never silently dropped or reordered. The carrier-wide budget defaults to 4 MiB.
- UDP overflow drops the datagram (the protocol's lossy mode) and increments the drop counter.
- The carrier write timeout and buffer budgets are core API options with defaults; they are not
  YAML keys, so existing profiles keep their meaning.
- The interop suite pins Xray 26.11.9. The framing has been stable, but a new Xray release needs a
  re-run of `tool/xray_interop.sh` before claiming compatibility.

### Performance

Measured on a Ryzen 5 7500F (linux/amd64, Go 1.27.2), `-benchmem -benchtime 500ms -count=3`, the
pre-hardening core profile (through `0048`) against the hardened tree. Absolute numbers are
microbenchmarks; the deltas are the relevant part:

| Benchmark | Before | After |
|---|---|---|
| encode 8 KiB Keep/Data | 551 ns, 1 alloc | 548 ns, 1 alloc |
| decode 8 KiB Keep/Data | 896 ns, 4 allocs | 910 ns, 4 allocs |
| carrier frame write, uncontended | 71–77 ns, 0 allocs | 92–105 ns, 0 allocs |
| carrier frame write, 30 s deadline | n/a | 122–135 ns, 0 allocs |
| pool dial + close | 1.46 µs, 21 allocs | 1.6–1.9 µs, 26 allocs |
| stream write 8 KiB | 678 ns, 0 allocs | 822–866 ns, 0 allocs |

The codec is unchanged. The per-frame write adds the deadline-aware turn (~25 ns); the per-session
path adds the bounded queue and the asynchronous End (~0.3 µs, five allocations per session, not
per byte). No hot path gained an allocation.

### ReClash layer

The former `feat: support ReClash` commit is one concern per patch:

| Patch | Concern |
|---|---|
| `0001-external-adapter-registry` | proxy types registered by the embedding application |
| `0002-proxy-metadata` | annotations, route/endpoint fingerprints, route dependency, diversity |
| `0003-dial-hooks` | dial policy, dial-result evidence, URL-test status |
| `0004-provider-health-scheduling` | screen-off deferral and single-prover auto health checks |
| `0005-flow-evidence` | ingress/route/dial evidence for failed connections |
| `0006-connection-progress` | connection admission and first-progress notification |
| `0007-policy-hooks` | metadata policy and mode-change hooks |
| `0008-site-lock` | the host claims a connection before mode or rules |
| `0009-direct-split` | an explicit DIRECT rule can use another proxy |
| `0010-geo-digest` | skip a geo database body when the published digest matches |
| `0011-listener-plumbing` | duplicate close removal and injectable TUN stack |
| `0012-controller-serve-log` | log external-controller serve errors |
| `0013-udp-443` | reject QUIC (UDP/443) per proxy or provider |
| `0014-random-mlkem` | randomized/random ClientHellos always offer X25519MLKEM768; random no longer picks iOS |
| `0015-fallback-urls` | mirror addresses for HTTP proxy and rule providers |
| `0016-xhttp-h2-flow` | HTTP/2 downlink flow governor for XHTTP |
| `0017-reality-password` | Xray's `reality-opts.password` alias for `public-key` |
| `0018-ping-config` | real-download ping checks with sampling, without the smart group |

### Xray coverage

- **REALITY and TLS** — configurable global and per-proxy client version, adaptive
  X25519MLKEM768 policy with a per-server memo (modern-first, classic fallback), the Xray
  `password` alias, ML-DSA-65 verification, Xray fingerprint names, comma-separated certificate
  pins and name lists, ECH
  PEM/query forms, Chrome 155, Firefox 156/160, and Xray's
  current defaults: `chrome` = Chrome 155, `firefox` = Firefox 160; `chrome133` and `firefox148`
  keep the older mihomo parrots.
- **Share links** — `pqv` → `reality-opts.mldsa65-verify`, `vcn` → `name-cert-verify`,
  `?serverDescription=` after the remark, the full `fm` finalmask block for VLESS and Trojan
  (not just the fragment mask), and Trojan REALITY links (`pbk`, `sid`, `pqv`). UDP masks are
  kept only for VLESS over XHTTP with `alpn: h3`.
- **XHTTP** — default uplink data key, per-direction read/write deadlines, pipelined packet-up
  uploads with an 8-seq window, and the HTTP/2 flow governor (`h2-flow` / `h2-flow-control`).
- **mux.cool** — VLESS Mux.Cool and XUDP client with carrier limits; a draining carrier
  closes without re-entering its own close.
- **udp-443** — per-proxy and provider-override QUIC rejection.
- **providers** — `fallback-urls` for HTTP proxy and rule providers.
- **health checks** — `ping-config` with a destination check, sampling, and screen-aware scheduling.
- **XDRIVE** — VLESS over Google Drive, template storage or a local folder; the local service is
  disabled on Android.
- **finalmask** — Xray masks on VLESS and Trojan (`fragment`, `header-custom`, `sudoku`, `xmc`,
  `noise`, `udphop`, `xdns`, `xicmp`), plus the compact xdns spelling.
- **fragment** — `fragment-opts` on any proxy, including `dialer-proxy` hops.
- **quality/security** — OpenVPN server identity, QUIC MTU discovery switch, TCP connect timeout,
  sniffer skip threshold, DNS serve-expired, gRPC frame reader hardening, share-link redaction,
  Snell `unsafe-raw` warning, graceful handling of unusable proxy options.

### Diagnostics

- Probe failures keep the upstream error text and log it, instead of a generic 503.
- `GET /proxies/{name}/transfer` reads a response body with a stall watchdog, so a tunnel that
  passes the header-only delay test but freezes after the first tens of kilobytes is visible.
  `ProxyTransfer` exposes the same test to in-process callers.

### Not in the series yet

Deliberately left out until they have a product reason and a tested integration:

- desync outbounds (ClashFest 0015–0022);
- proxy groups of type `chain` (ClashFest 0005);
- Prizrak's `smart` group, XHTTP `h2-flow`, QUIC parrots, mKCP and the server-side roles of
  mux.cool, finalmask, XDRIVE and REALITY.

They can be added as new layers without changing the base. The split `reclash` layer also drops
the former fork's comment-only edit to `component/process/process.go`; it had no behavior.

## Consuming from ReClash

1. Pin `core/mihomo` to the tag in `base.env`.
2. Apply the ReClash profile in the build setup, before the Go build:
   `tool/patch.sh apply core/mihomo --profile reclash`.
3. Revert it before `git checkout`/`clean` of the submodule:
   `tool/patch.sh revert core/mihomo --profile reclash`.
4. Add the module the REALITY patch imports to the **application** module, not the submodule:

   ```
   require github.com/metacubex/mldsa v0.1.1
   ```

   in `core/go.mod`, then sync `core/go.sum`.
5. Keep `core/mihomo` clean in git. The applied profile is a build-tree state, not a commit.

The FlClash adaptation exists because FlClash replaces upstream's `cmfa` build-tag constant with
`features.Android`; core keeps `features.CMFA`. If a host keeps `features.CMFA`, use the `core`
profile and skip `flclash/0002`.

## Adding a patch

- One concern per patch, numbered in the layer directory.
- Core patches go in `xray/` or `diagnostics/` and must apply before any host layer.
- Host patches go in `flclash/` or `reclash/` and must apply after the profile they extend.
- Keep the original code credit. Patches ported from ClashFest/Prizrak/Veles/Citrus/Xray keep
  their comments and SPDX headers; add the source commit to the patch header.
- Ship a test when the change is logic rather than a constant.
- Record the condition under which the patch is deleted (upstream fix, feature removed, or the
  consuming app no longer needs it).
- Append the patch to the profile after the patches it depends on.
- Do not renumber existing patches: external comments and commit messages refer to them.

## When a patch stops applying

1. `tool/patch.sh apply <target> --profile <name>` names the first failing patch.
2. Try `git -C <target> apply --3way <patch>`. The patch files keep `index` lines, but a shallow
   consumer checkout may not have the preimage blobs; if `--3way` cannot run, use
   `git apply --reject` (or `patch -p1`) and resolve the `.rej` hunks by hand.
3. Commit the resolved state in a scratch branch that already has the earlier patches of the
   same profile.
4. Regenerate the patch as the diff of that commit against its parent:
   `git diff <parent> <commit> > patches/<layer>/<name>.patch`.
5. Re-run `tool/test.sh --profile <name>`.

A core bump that breaks several patches is a signal to check whether upstream fixed the problem
and the patch can be deleted.

## Provenance and license

The series is GPL-3.0, like mihomo and ReClash. Xray compatibility patches are ported from
[ClashFest](https://github.com/Nemu-x/ClashFest); their code comments name the original ClashFest
patch, and several of them were originally adapted from
[Prizrak-Core](https://github.com/legiz-ru/Prizrak-Core), Rerowros/veles and getmikan/Citrus.
XDRIVE carries MPL-2.0 headers from Xray-core. Detailed credits are in [CREDITS.md](CREDITS.md).

The patches are provided as-is. They are not a claim that the resulting binary is identical to
stock mihomo: the host layers deliberately change lifecycle and can change the selected outbound.
