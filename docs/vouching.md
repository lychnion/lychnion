# Vouching for publishers

Lychnion vouches for official publishers so that people do not have to
judge a key alone (lychnion/lychnion#119). This page says who can be
vouched for, how Lychnion checks, and how a vouch is taken back. The
format and how vouches travel are in
[distribution.md](distribution.md#whom-to-trust-vouches).

## What a vouch does, and what it never does

A vouch is a statement signed by Lychnion's key: "this key belongs to
this publisher, called this, checked on this day, in this way, at this
address". The app then shows the publisher as **Checked by Lychnion**,
under the name Lychnion checked, in the publishers screen, the add
dialog and Downloads.

A vouch gives a label, never access:

- A publisher never needs a vouch to publish. Anyone, also a public body
  that Lychnion has not checked, can be added from a link or QR code,
  offline, after the user confirms. It is shown as "Added by you · not
  checked by Lychnion".
- A vouch never adds a publisher by itself, and never lets one do more:
  models and the official safety line stay Lychnion's.
- A publisher added before its vouch arrives becomes "Checked by
  Lychnion" by itself. Nothing has to be added again.

## Who can be vouched for

For now: **public bodies in Japan** that publish guides or maps
themselves:

- local governments (prefectures, cities, towns, villages, wards) and
  their fire departments;
- national ministries and agencies.

Other publishers (shelters run by others, NPOs, clubs) are not vouched
for by Lychnion. Publishers vouching for each other is
lychnion/lychnion#121.

## How a body applies

1. It creates its publisher key ("Publish your own" in the app on a
   computer) and gets the key's **code** shown there.
2. It puts the publisher name and the code on a page of its **official
   website**: a `*.lg.jp` or `*.go.jp` address, or the address the body
   has long used (for example `www.city.sendai.jp`). Next to the code: a
   sentence saying it is the body's Lychnion key.
3. It applies with the issue form "Apply for a vouch" in
   [lychnion/lychnion-data](https://github.com/lychnion/lychnion-data)
   (added there with the vouch tools, the next step of #119), giving the publisher name, its name in Japanese and English, the code
   and the page's address. The form is public: no personal names, phone
   numbers or e-mail addresses in it. If Lychnion needs to ask the body
   something, it uses the contact details on the body's official
   website.

## How Lychnion checks

The person checking:

1. opens the page over https and checks that the address belongs to the
   body: `*.lg.jp` and `*.go.jp` are only given to public bodies; any
   other address must be the one the body's prefecture or the Ministry
   of Internal Affairs links to;
2. compares the code on the page with the key in the application (the
   whole key, not only the first characters);
3. checks that the name in Japanese and English is the body's own
   official name, and that the publisher name is not like a name already
   vouched for;
4. writes the vouch as a file in lychnion-data (where the catalog is
   built and signed), with
   `checked` (that day), `method: official-website` and `url` (the
   page), in a pull request that someone reviews when there is someone
   to review it (the self-review rule of the lychnion org applies
   otherwise);
5. signs it with Lychnion's key. Only the holder of that key signs
   (lychnion/lychnion#118). The next catalog carries it to phones.

Anyone can make the same check without Lychnion: the code in the app's
add dialog and the code on the official page must be the same. The code
is the key's first 6 bytes (48 bits): enough against a link made in a
hurry, but someone with a lot of computing power could make a key with
the same code. That is why Lychnion compares the whole key, and why a
vouch, not the code alone, is what makes a publisher "Checked by
Lychnion".

`method` names how the key was checked. `official-website` is the only
method so far; a new one is written down here before it is used.

## Checking again, and taking a vouch back

- The vouch keeps the day of the check, and the app shows it. Lychnion
  checks the page again when the body applies with a new key and when
  someone reports a problem.
- A key the body **replaces** by its own key statement stays vouched
  for: the statement proves the new key is the body's. A key the body
  **revokes** is shown as revoked, vouched for or not.
- Lychnion **takes a vouch back** with a newer vouch marked
  `"withdrawn": true`, when the page no longer shows the code, when the
  body asks, when bodies merge, or when the key is misused. The app then
  shows "Lychnion took back its check" in red. Catalogs carry the
  withdrawal like any vouch; until phones can tell how fresh a catalog
  is, a carrier can hold it back (lychnion/lychnion#117).
- If Lychnion's own key is revoked, all vouches it signed lapse on every
  device that learns the revocation.

## The warning for names that look official

Anyone can make a link with any name. When a link Lychnion has not
vouched for has a name or title like a publisher Lychnion vouched for,
or like a public body (市, 町, 村, 県, 都, 府, 庁, 省, 消防, 役所,
City, Prefecture, Ministry, Fire…; names `jp.go.*`, `jp.lg.*`,
`jp.city.*`, `jp.pref.*`), the add dialog says so in red and asks the
user to tick "I compared the code" before Add works. The same applies
when the name has a vouch for another key, or a withdrawn one. It never
refuses: an official body Lychnion has not checked must still be
addable offline. Titles are compared after folding full-width letters,
case, spaces and separators, and Cyrillic and Greek letters drawn like
Latin ones. It is a list, not a proof: other look-alikes (other
scripts, words not on the list) pass, and are still labelled "not
checked by Lychnion". Words like 市 also match names that are not
public bodies (市場); that costs a tick. The rules are in
`lib/download/lookalike.dart`.
