# NAKASHA

**Make tomorrow's board tonight.**

The daily board is published in the evening, for the next day's hearings. NAKASHA reads it and
gives you your own matters out of it, on your own Mac, without anything leaving your Mac.

*Nakasha* means the sanctioned plan — the drawing you are allowed to build from.

---

## What it is for

The board arrives in the evening and runs to 87 pages and 700 or more matters. You sit with it
and look for your own name so you know where you have to be tomorrow. It is slow, it is late,
and matters get missed.

NAKASHA turns that into: open the PDF, type your surname, get your list, check each one against
the printed page, export it. Ten minutes instead of an hour, and nothing skipped because you
were tired.

It reads two kinds of board:

- your **bar association's daily board**, and
- the **High Court's own daily causelist**.

Open both for the same date and it uses one to complete the other — the causelist carries full
advocate names where the bar board cuts them short.

---

## It does not use AI

This is worth saying plainly, because most new legal software is the opposite.

There is no AI in NAKASHA. No language model, no machine learning, no cloud "intelligence", no
API key, nothing to sign up for. It does not summarise, interpret, predict or generate
anything.

What it actually does is arithmetic on the page:

1. It reads the text layer that is already inside the PDF.
2. It measures which column each piece of text sits in.
3. It matches your surname against the counsel column with a fixed text rule.

That is the whole method. Two consequences follow, and both matter to a lawyer:

- **It cannot invent a matter, and it cannot quietly drop one.** An AI can hallucinate a case
  number or paraphrase a party's name. There is nothing in NAKASHA that is capable of
  producing text that was not printed on the board.
- **It is repeatable.** The same PDF and the same name give you the same answer every single
  time. Nothing is sampled, nothing is random, nothing changes between runs. If it found your
  matter yesterday, it finds it today.

---

## It is completely offline

NAKASHA has **no permission to use the network at all**. Not "we promise not to" — the
permission is simply absent from the application, so macOS itself refuses any connection,
whatever the program asks for.

You do not have to take that on trust. Check it yourself:

```
codesign -d --entitlements - /Applications/NAKASHA.app
```

Read what it prints. There is no line containing `network`.

You can also open Activity Monitor, or Little Snitch if you use it, and watch the app for a
whole session. It never talks to anything.

There is also nothing to talk to. There is no NAKASHA server, no account, no login, no sync,
no update check, no analytics, no crash reporting, and no "anonymous usage statistics".

---

## How it works, in four steps

1. **You open a board PDF.** It is read where it sits. NAKASHA never copies it, never moves
   it, never writes anything next to it, and never changes it.
2. **It reads the page.** The board already contains its text; NAKASHA takes that text and
   works out which column each word belongs to — court, serial number, case number, parties,
   office note, counsel.
3. **It looks for your name.** Deliberately loosely — see below.
4. **You check and prune.** Click any result and the PDF beside it jumps to that page with the
   matter highlighted, so you are always verifying against the board itself. Delete what is
   not yours, then export what is left as a PDF or a spreadsheet.

---

## Why you will see matters that are not yours

The board cuts advocate names off at a fixed width, and wraps them mid-word without a hyphen.
A surname can be printed like this:

```
VERNE KAR
```

That is `VERNEKAR`, split across the field boundary by the export. Software that looked for the
exact spelling would find nothing, and you would close it believing you are not listed
tomorrow.

So NAKASHA matches loosely. It sees through a name broken mid-word, and it still matches when
the board has cut the end off. The price is that you also see other people who share your
surname.

That trade is deliberate and it only goes one way: **showing you one extra matter costs you a
click; missing one of yours costs you something you cannot get back.** Deleting the extras is
how the tool is meant to be used, not a fault in it.

A row marked **verify** is one where your name turned up somewhere other than the counsel
column. It is shown rather than hidden — hiding it could hide a real listing — but look at
that one twice.

---

## Your data

NAKASHA collects nothing. There is nothing to collect it with.

- **The publisher never receives anything.** Not your board, not your names, not your matters,
  not a count of how many times you opened the app. There is no channel by which anything
  could reach him, and no server for it to reach.
- **The board PDF never leaves your Mac,** and is never copied anywhere on it either.
- **The names you watch** are stored in this Mac's own preferences, on this Mac, and nowhere
  else. Delete them and they are gone.
- **What you export** is written only to the folder you choose in the save dialog.
- **Nothing is retained** between sessions except the names you typed. Results live in memory
  and disappear when you quit.

Because nothing is transmitted, no personal data in the board — parties, advocates, case
numbers — is ever disclosed to the publisher or to any third party by using this application.
Whatever obligations attach to the board in your hands are unchanged by NAKASHA, because
NAKASHA does not move it anywhere.

---

## Professional conduct

NAKASHA is a reading tool. Stated as facts rather than as a conclusion:

- It does not advertise, and contains no advertising.
- It does not solicit work, for anyone.
- It names no advocate, no chambers and no firm, anywhere in the application or in this
  repository.
- It does not publish, transmit or share any advocate's details, or any litigant's.
- It communicates with no one.
- It is given away free, under an open-source licence, with the source published so that any
  of the above can be checked rather than believed.

You remain responsible for verifying every listing against the board itself before acting on
it. That does not expire, and this application does not ask you to take its word for anything
— which is exactly why every result clicks through to the printed page.

---

## Why it is open source

Because a privacy promise you cannot check is only a promise.

Every claim on this page is a claim about what the software does when it is not being watched.
The only way to make that verifiable is to publish the source, so that you — or any programmer
you trust — can read it and see for yourself that there is no network code, no telemetry, and
no copy of your files being made.

Three practical consequences:

- **You are not depending on me.** If I stop working on it, the source is still there and the
  app still runs. Nothing switches off.
- **You are not locked in.** There is no subscription, no licence key, no activation, nothing
  that can be revoked.
- **It can be checked by someone else.** If you are asked to justify using it, you can hand
  over the source rather than a brochure.

---

## Installing it

Written for someone who has not installed software this way before. It takes about two minutes.

**Step 1 — download.** Download the `.dmg` file from the Releases page of this repository.
It will go to your Downloads folder.

**Step 2 — open it.** Double-click the downloaded `NAKASHA-v0.1.0.dmg`. A small window opens
showing the NAKASHA icon on the left and a folder called **Applications** on the right.

**Step 3 — drag it across.** Drag the NAKASHA icon onto the Applications folder in that same
window. That installs it. You can then close the window and eject the disk image (drag it to
the Bin, or press Command-E).

**Step 4 — the first launch will be refused. This is expected.**

macOS blocks applications that have not been through Apple's paid notarisation service.
NAKASHA has not, deliberately: it is free, and notarisation requires an annual Apple developer
subscription. The application is still signed and still runs inside macOS's security sandbox —
it simply has no Apple-issued identity, and macOS treats anything without one as suspicious
until you say otherwise.

**Step 5 — allow it.** Either method works. The first is more reliable.

*Method A — Terminal (recommended).* Open the **Terminal** app (press Command-Space, type
`Terminal`, press Return). Copy this line, paste it in, press Return:

```
xattr -dr com.apple.quarantine /Applications/NAKASHA.app
```

Nothing will appear to happen. That is correct. Now open NAKASHA normally from Applications.

*Method B — no Terminal.* Try to open NAKASHA and let macOS refuse. Then go to the Apple
menu → **System Settings** → **Privacy & Security**, scroll to the bottom, and you will see a
line about NAKASHA being blocked with a button marked **Open Anyway**. Click it, then confirm.

You may see advice elsewhere to right-click the app and choose **Open**. That worked on older
versions of macOS and is no longer dependable. Use Method A or B.

**After this, NAKASHA opens normally like any other application.** You only do this once.

---

## Using it

1. Open the board PDF — drag it onto the window, or click the box to choose it.
2. Type the names you want to watch, one per line. **Your surname on its own is the right
   thing to type.**
3. Press **Find my matters**.
4. Click any row. The PDF on the right jumps to that page and highlights the matter. Read the
   printed line and satisfy yourself.
5. Delete the rows that are not yours.
6. **Export PDF** or **Export CSV**. Only the rows you kept are written.

If you have both boards for the same date, open both together before pressing Find.

---

## What it does not do

- **It does not read scanned boards.** If a page is a photograph or a scan with no text in it,
  NAKASHA tells you which page it cannot read, rather than guessing at it. Boards published as
  proper PDFs are read completely.
- **It does not fetch anything.** You supply the file. It never goes looking for one.
- **It is not case management.** No calendar, no reminders, no notifications, no diary.
- **It does not change your PDF.** The file is opened read-only and left exactly as it was.

---

## Before you rely on it

Run it beside your usual reading of the board for two weeks and satisfy yourself that it finds
everything you find by eye. It is an assistant to that reading, not a replacement for it.

---

## Building it yourself

Requires macOS 13 or later and Apple's command line tools.

```
swift build -c release      # build it
swift test                  # run the tests
./build.sh                  # produce NAKASHA.app and the .dmg
```

**Zero third-party dependencies.** The application links Apple's own frameworks only —
Foundation, PDFKit, CoreGraphics, CoreText, AppKit, SwiftUI and UniformTypeIdentifiers. There
is no dependency list to audit: `Package.swift` declares none at all. Nothing is downloaded at
build time and nothing is downloaded at run time.

There is also a command-line version, useful for checking a board without opening the app:

```
nakasha-cli --names names.txt board.pdf
nakasha-cli --dump-lines 40 board.pdf     # for calibrating a board it reads badly
```

---

## Licence

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

Copyright Rushikesh R. Mahajan (publishing as wolfgang_rush).

Apache-2.0 was chosen over MIT for three reasons that matter for a tool used in legal practice:
it grants users an express patent licence, it expressly grants no right to the author's name or
marks, and its warranty and liability terms are set out properly rather than in a single
sentence.

**No warranty.** This software is provided as is. You are responsible for checking every
listing against the board itself.
