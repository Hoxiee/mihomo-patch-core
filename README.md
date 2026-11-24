# mihomo-patch-core

A patch series that turns a clean [mihomo](https://github.com/MetaCubeX/mihomo) checkout into the
proxy core ReClash runs. The upstream tree stays unmodified; every behaviour is a numbered,
reviewable patch that can be rebased or deleted on its own.

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

## Profiles

| Profile | Patches | Contents |
|---|---:|---|
| `core` | 38 | xray 35 + diagnostics 3 |
| `flclash` | 40 | core + FlClash host 1 + feature.Android adaptation 1 |
| `reclash` | 59 | flclash + ReClash 19 |

`core` is independently usable by any mihomo host. `flclash` keeps the FlClash contract. `reclash`
is what the ReClash application consumes.

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
- **mux.cool** — VLESS Mux.Cool and XUDP client with carrier limits.
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
