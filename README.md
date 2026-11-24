# mihomo-patch-core

A patch series that turns a clean [mihomo](https://github.com/MetaCubeX/mihomo) checkout into the
proxy core ReClash runs. The upstream tree stays unmodified; every behaviour ReClash needs is a
numbered, reviewable patch that can be rebased or deleted on its own.

The series is consumed by [ReClash](https://github.com/Hoxiee/ReClash) and is not a standalone
proxy distribution. It replaces the long-lived `Hoxiee/mihomo` fork with two explicit layers:

- **host** — FlClash and ReClash integration: lifecycle, hooks, flow evidence, route identity,
  battery-aware health checks, direct split, listener ownership.
- **xray** — client-side Xray compatibility: REALITY, TLS fingerprints, ECH, mux.cool, finalmask,
  XHTTP, XDRIVE.
- **compat** — small adaptations where the Xray patches assume a different host environment.

The current status is **initial series**: it applies and its packages pass their tests on the
pinned base. ReClash will move onto it after the integration is exercised in the application.

## Base

`base.env` is the only source of truth:

```
MIHOMO_TAG=v1.19.34
MIHOMO_COMMIT=0455d0d28c4526937380505153e65a843d8612e8
```

All patches are generated against that tag. A core bump starts by changing `base.env`, replaying
the series, and fixing the first patch that no longer applies.

## Layout

```
patches/
  order.txt                 apply order, one patch per line
  host/                     FlClash + ReClash host integration (required)
  xray/                     client-side Xray compatibility
  compat/                   adaptations to the host layer
tool/
  patch.sh                  list / status / check / apply / revert
  test.sh                   fresh checkout + apply + go test
  packages.txt              packages exercised by test.sh
base.env                    upstream pin
```

Patch names keep the original ClashFest numbers for the Xray layer, so comments inside the code
that say “ClashFest core patch 0027” still point at the right source.

## Apply

The target is any mihomo git checkout at the pinned base:

```bash
tool/patch.sh apply ../ReClash/core/mihomo
```

Other commands:

```bash
tool/patch.sh list
tool/patch.sh status   ../ReClash/core/mihomo
tool/patch.sh check    ../ReClash/core/mihomo
tool/patch.sh revert   ../ReClash/core/mihomo
```

`apply` uses plain `git apply`. It skips patches that are already applied and stops at the first
patch that does not apply, printing the `git apply --3way` command to resolve it. Do not commit
applied patches into the mihomo checkout: the series is the source of truth.

## Test

`tool/test.sh` clones the pinned tag into a temporary directory, applies the series, adds the
`mldsa` module the REALITY patch imports, and runs the patched packages:

```bash
tool/test.sh
tool/test.sh --keep   # leave the checkout for inspection
```

The packages are listed in `tool/packages.txt`. The build uses `with_gvisor`, the tag ReClash
ships with. Tests that need an Xray binary or external network skip themselves.

## Series

| Layer | Patches | What it carries |
|---|---:|---|
| host | 2 | FlClash integration, then ReClash additions |
| xray | 32 | REALITY/TLS/ECH, XHTTP, mux.cool, XDRIVE, finalmask, fragment, quality/security |
| compat | 1 | `features.CMFA` → `features.Android` in the finalmask xicmp guard |

### Xray coverage

- **REALITY and TLS** — configurable global and per-proxy client version, adaptive X25519MLKEM768
  policy with a per-server memo, ML-DSA-65 verification, Xray fingerprint names, comma-separated
  certificate pins and name lists, ECH PEM/query forms, Chrome 155, Firefox 156/160, default
  chrome for REALITY proxies without a fingerprint.
- **XHTTP** — default uplink data key, per-direction read/write deadlines, pipelined packet-up
  uploads with an 8-seq window.
- **mux.cool** — VLESS Mux.Cool and XUDP client with carrier limits.
- **XDRIVE** — VLESS over Google Drive, template storage or a local folder; the local service is
  disabled on Android.
- **finalmask** — Xray masks on VLESS and Trojan (`fragment`, `header-custom`, `sudoku`, `xmc`,
  `noise`, `udphop`, `xdns`, `xicmp`), plus the compact xdns spelling.
- **fragment** — `fragment-opts` on any proxy, including `dialer-proxy` hops.
- **quality/security** — OpenVPN server identity, QUIC MTU discovery switch, TCP connect timeout,
  sniffer skip threshold, DNS serve-expired, gRPC frame reader hardening, share-link redaction,
  Snell `unsafe-raw` warning, graceful handling of unusable proxy options.

### Not in the series yet

Deliberately left out until they have a product reason and a tested integration:

- desync outbounds (ClashFest 0015–0022);
- proxy groups of type `chain` (ClashFest 0005);
- transfer-level probes (ClashFest 0024–0025);
- Prizrak's `smart` group, XHTTP `h2-flow`, QUIC parrots, mKCP and the server-side roles of
  mux.cool, finalmask, XDRIVE and REALITY.

They can be added as new layers without changing the base.

## Consuming from ReClash

1. Pin `core/mihomo` to the tag in `base.env`.
2. Apply the series in the build setup, before the Go build:
   `tool/patch.sh apply core/mihomo`.
3. Revert it before `git checkout`/`clean` of the submodule:
   `tool/patch.sh revert core/mihomo`.
4. Add the module the REALITY patch imports to the **application** module, not the submodule:

   ```
   require github.com/metacubex/mldsa v0.1.1
   ```

   in `core/go.mod`, then sync `core/go.sum`.
5. Keep `core/mihomo` clean in git. The applied series is a build-tree state, not a commit.

The compat patch exists because the host layer replaced upstream's `cmfa` build-tag constant with
`features.Android`. If the host layer ever keeps `features.CMFA`, delete `compat/` and restore the
`features.CMFA` references in `xray/0041`.

## Adding a patch

- One concern per patch, numbered in the layer directory.
- Keep the original code credit. Patches ported from ClashFest/Prizrak/Veles/Citrus/Xray keep
  their comments and SPDX headers; add the source commit to the patch header.
- Ship a test when the change is logic rather than a constant.
- Record the condition under which the patch is deleted (upstream fix, feature removed, or the
  consuming app no longer needs it).
- Append the patch to `patches/order.txt` after the patches it depends on.
- Do not renumber existing patches: external comments and commit messages refer to them.

## When a patch stops applying

1. `tool/patch.sh apply <target>` names the first failing patch.
2. Try `git -C <target> apply --3way <patch>`. The patch files keep `index` lines, but a shallow
   consumer checkout may not have the preimage blobs; if `--3way` cannot run, use
   `git apply --reject` (or `patch -p1`) and resolve the `.rej` hunks by hand.
3. Commit the resolved state in a scratch branch that already has the earlier patches.
4. Regenerate the patch as the diff of that commit against its parent:
   `git diff <parent> <commit> > patches/<layer>/<name>.patch`.
5. Re-run `tool/test.sh`.

A core bump that breaks several patches is a signal to check whether upstream fixed the problem
and the patch can be deleted.

## Provenance and license

The series is GPL-3.0, like mihomo and ReClash. Xray compatibility patches are ported from
[ClashFest](https://github.com/Nemu-x/ClashFest); their code comments name the original ClashFest
patch, and several of them were originally adapted from
[Prizrak-Core](https://github.com/legiz-ru/Prizrak-Core), Rerowros/veles and getmikan/Citrus.
XDRIVE carries MPL-2.0 headers from Xray-core. Detailed credits are in [CREDITS.md](CREDITS.md).

The patches are provided as-is. They are not a claim that the resulting binary is identical to
stock mihomo: the host layer deliberately changes lifecycle and can change the selected outbound.
