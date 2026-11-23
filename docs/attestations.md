# Checked publishers: attestations

Lychnion checks the keys of official publishers and signs an
**attestation** for each, so that people do not have to judge a key
alone (lychnion/lychnion#119). This page says who can get an
attestation, how Lychnion checks, and how an attestation is taken back.
The format and how attestations travel are in
[distribution.md](distribution.md#whom-to-trust-attestations).

**New to this?** [checked-publishers-explained.md](checked-publishers-explained.md)
explains the same in plain words, with diagrams, for people who are not
familiar with keys and signatures.

## What an attestation does, and what it never does

An attestation is a statement signed by Lychnion's key: "this key
belongs to this publisher, called this, checked on this day, in this
way, at this address". The app then shows the publisher as **Checked by
Lychnion**, under the name Lychnion checked, in the publishers screen,
the add dialog and Downloads. Answers say under a passage whose guide it
is when that is not Lychnion: "via “仙台市” · checked by Lychnion" or "via
“Aoba Club” · not checked by Lychnion". In a base's answers that label
is the base's word, and says so.

An attestation gives a label, never access:

- A publisher never needs an attestation to publish. Anyone, also a
  public body that Lychnion has not checked, can be added from a link or
  QR code, offline, after the user confirms. It is shown as "Added by
  you · not checked by Lychnion".
- An attestation never adds a publisher by itself, and never lets one do
  more: models and the official safety line stay Lychnion's.
- A publisher added before its attestation arrives becomes "Checked by
  Lychnion" by itself. Nothing has to be added again.

## Who can get an attestation

For now: **public bodies in Japan** that publish guides or maps
themselves:

- local governments (prefectures, cities, towns, villages, wards) and
  their fire departments;
- national ministries and agencies.

Other publishers (shelters run by others, NPOs, clubs) get no
attestation from Lychnion. Publishers attesting each other is
lychnion/lychnion#121.

## How a body applies

1. It creates its publisher key ("Publish your own" in the app on a
   computer) and gets the key's **code** shown there.
2. It puts the publisher name and the code on a page of its **official
   website**: a `*.lg.jp` or `*.go.jp` address, or the address the body
   has long used (for example `www.city.sendai.jp`). Next to the code: a
   sentence saying it is the body's Lychnion key.
3. It applies with the issue form "Ask Lychnion to check your publisher
   key" in
   [lychnion/lychnion-data](https://github.com/lychnion/lychnion-data/issues/new/choose),
   giving the publisher name, its name in Japanese and English, the
   publisher link, the code and the page's address. The form is public: no personal names, phone
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
   attested;
4. writes the attestation as a file in lychnion-data (where the catalog is
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
the same code. That is why Lychnion compares the whole key, and why an
attestation, not the code alone, is what makes a publisher "Checked by
Lychnion".

`method` names how the key was checked. `official-website` is the only
method so far; a new one is written down here before it is used.

## Checking again, and taking an attestation back

- The attestation keeps the day of the check, and the app shows it.
  Lychnion checks the page again when the body applies with a new key
  and when someone reports a problem.
- A key the body **replaces** by its own key statement stays attested:
  the statement proves the new key is the body's. A key the body
  **revokes** is shown as revoked, attested or not.
- Lychnion **takes an attestation back** with a newer attestation marked
  `"withdrawn": true`, when the page no longer shows the code, when the
  body asks, when bodies merge, or when the key is misused. The app then
  shows "Lychnion took back its check" in red. Catalogs carry the
  withdrawal like any attestation; until phones can tell how fresh a
  catalog is, a carrier can hold it back (lychnion/lychnion#117).
- If Lychnion's own key is revoked, all attestations it signed lapse on
  every device that learns the revocation.

## The warning for names that look official

Anyone can make a link with any name. When a link Lychnion has not
attested has a name or title like a publisher Lychnion attested, or like
a public body (市, 町, 村, 県, 都, 府, 庁, 省, 消防, 役所, City, Prefecture,
Ministry, Fire…; names `jp.go.*`, `jp.lg.*`, `jp.city.*`, `jp.pref.*`),
the add dialog says so in red and asks the user to tick "I compared the
code" before Add works. The same applies when the name has an
attestation for another key, or a withdrawn one. It never refuses: an
official body Lychnion has not checked must still be addable offline.
Titles are compared after folding full-width letters, case, spaces and
separators, and Cyrillic and Greek letters drawn like Latin ones. It is
a list, not a proof: other look-alikes (other scripts, words not on the
list) pass, and are still labelled "not checked by Lychnion". Words like
市 also match names that are not public bodies (市場); that costs a tick.
The rules are in `lib/download/lookalike.dart`.
