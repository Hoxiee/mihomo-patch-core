# Credits

This repository is a patch series, not an independent proxy implementation. The code in the
patches comes from the projects below; the original comments, SPDX headers and patch numbers are
kept wherever the source had them.

## Base

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) — GPL-3.0. The upstream tree the series
  applies to (tag `v1.19.34`).

## Host and ReClash layers

- [Hoxiee/mihomo](https://github.com/Hoxiee/mihomo), branch `ReClash` — GPL-3.0. FlClash host
  integration (`797b6757`) is kept as one patch; the ReClash additions of `5635c762` are split
  into the `reclash/` layer by concern.
- [chen08209/FlClash](https://github.com/chen08209/FlClash) — GPL-3.0. The host integration this
  layer descends from.

## Xray compatibility layer

- [Nemu-x/ClashFest](https://github.com/Nemu-x/ClashFest) — GPL-3.0. The patch series this layer is
  ported from. Each patch header names its ClashFest number; the code comments keep the same
  references.
- [legiz-ru/Prizrak-Core](https://github.com/legiz-ru/Prizrak-Core) — GPL-3.0. Origin of the
  finalmask implementation, the compact xdns spelling, Firefox 156/160 fingerprints, the mux.cool
  client and XDRIVE.
- [Rerowros/veles](https://github.com/Rerowros/veles) — GPL-3.0. Source of the graceful proxy
  options, Chrome 155, XHTTP packet-up work and several REALITY fixes as adapted by ClashFest.
- [getmikan/Citrus](https://github.com/getmikan/Citrus) — GPL-3.0. Origin of the chain/REALITY
  ideas and the XDRIVE/Mux.Cool code that ClashFest adapted.
- [Nemu-x/SlothClash](https://github.com/Nemu-x/SlothClash) — GPL-3.0. Origin of the desync patch
  family (not included) and of the transfer diagnostics (ClashFest 0024–0025) included here.
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — MPL-2.0. The XDRIVE transport files carry
  their original MPL-2.0 headers; keep them when redistributing.

## Diagnostics layer

- [Nemu-x/ClashFest](https://github.com/Nemu-x/ClashFest) — GPL-3.0. Probe error details
  (ClashFest 0016) and the transfer test (ClashFest 0024–0025), with the router hunk adapted to
  ReClash's endpoint set.

## Libraries referenced by the patches

- [metacubex/utls](https://github.com/metacubex/utls) — BSD-3-Clause. The TLS fingerprint
  implementation the patches extend without forking.
- [metacubex/mldsa](https://github.com/metacubex/mldsa) — BSD-3-Clause. The ML-DSA-65
  verification used by the REALITY patch.

## ReClash

- [Hoxiee/ReClash](https://github.com/Hoxiee/ReClash) — GPL-3.0. The application that consumes
  this series and the source of the host-integration requirements. Patches 0044–0046 set the
  current-browser fingerprint defaults and complete the Xray share-link conversion; 0045–0046
  adapt the Prizrak converter to the ClashFest finalmask port.

If a patch file and this summary disagree, the patch header and the source file's SPDX header are
authoritative.
