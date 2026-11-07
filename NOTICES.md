# Notices

Bato is released under the MIT License (see `LICENSE`). It builds on, bundles or downloads the software below. Each project keeps its own license and copyright; the summaries here are a guide, not a substitute for the license texts.

## Bundled with the application

### Chromium

The browser engine is built from Chromium source. Chromium is distributed under a BSD-3-Clause license and includes many third-party components under their own licenses. The full list for a given build is shown at `chrome://credits` in the running browser. Copyright The Chromium Authors.

### Chromium Embedded Framework (CEF)

The host process uses CEF. CEF is distributed under a BSD-3-Clause license. Copyright (c) 2008-2020 Marshall A. Greenblatt and portions copyright (c) 2006-2009 Google Inc. The license text is kept in `spikes/cef-baseline/CEF-LICENSE.txt`.

### adblock-rust

Content blocking uses the `adblock` crate from the Brave project ([brave/adblock-rust](https://github.com/brave/adblock-rust)), pinned to version 0.13.5, under the Mozilla Public License 2.0 (MPL-2.0). Bato links it unmodified through a small Rust wrapper (`spikes/blocking/adblock-ffi`, MIT). The MPL-2.0 text and the crate's source are available from the project above. The crate's own Rust dependencies carry their own licenses, listed in `spikes/blocking/adblock-ffi/Cargo.lock`.

## Downloaded at runtime, never bundled

Bato fetches these filter lists over the network, on first start and then daily, and keeps them in the user's data folder. No list is included in the application or committed to this repository. Lists are the work of their maintainers and are used under their terms.

| List | Source | Terms |
| --- | --- | --- |
| EasyList | https://easylist.to/easylist/easylist.txt | Dual licensed: GPL-3.0-or-later or CC BY-SA 3.0 |
| EasyPrivacy | https://easylist.to/easylist/easyprivacy.txt | Dual licensed: GPL-3.0-or-later or CC BY-SA 3.0 |
| uBlock Origin lists (filters, privacy, badware, unbreak) | https://ublockorigin.github.io/uAssets/ | GPL-3.0. Downloaded only after the user accepts the offer; removing them deletes the downloads |

Bato is not affiliated with or endorsed by the EasyList, uBlock Origin or Brave projects.
