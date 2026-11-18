# Base

A base (「ベース」) is a computer with the desktop app that serves everyone
on the same Wi-Fi: in an evacuation shelter, a mountain hut, a school or a
camp. Older notes call it a "shelter" or "shelter computer"; the code
says "base" since 2026-11-19. The `lychnion://shelter?…` links on QR
codes keep the old word, so printed codes still work.

How to set up and use a base, step by step:
[help/en/05-base.md](../help/en/05-base.md). Sharing between phones
without a base: [help/en/06-share-nearby.md](../help/en/06-share-nearby.md).

## What a base serves

Phones with the app and phones without it both get:

- answers to their questions, from the computer's model (faster than most
  phones);
- current information entered on the computer (shelter status, closed
  roads, warnings).

Phones with the app also get the computer's guides, maps and models, so
they can download them there without internet.

Phones do not answer each other's questions: phones are too slow for that.

## Network

- The phones and the computer must be on the same Wi-Fi, and the Wi-Fi
  must let devices reach each other. Many guest and office networks block
  this ("client isolation").
- The safest setup is a Wi-Fi that the shelter controls: the computer's
  own hotspot or a small router. No internet is needed.
- The base listens on port 8642. The browser page uses plain http on a
  local address. Chrome shows "not secure" in the address bar, but no
  warning page (checked on a Pixel 5a).
- Opening the page by itself when a phone joins the Wi-Fi is planned
  ([#3](https://github.com/lychnion/lychnion/issues/3)).

## QR codes

The base shows one QR code at a time, so a camera cannot pick up the
wrong one:

- 「ブラウザで」 / "In the browser": an `http://` address, works on every
  phone.
- 「アプリで」 / "With the app": a `lychnion://` link that connects the
  app. The app asks before it connects and remembers the base.

Old codes made with the code name (`fieldkit://`) still work.

## Code

- `lib/base/`: the server, the data for the browser page, QR codes and
  links.
- `assets/web/base.html`: the browser page.
- To start a base from the command line, see `BASE_SERVER` in
  [dev-flags.md](dev-flags.md#base-and-current-information).

## Results

- [shelter-results.md](shelter-results.md): tests on real phones, speed,
  the Wi-Fi finding, the browser page.
- [facts-results.md](facts-results.md): current information.
