# Privacy

NAKASHA is designed so that nothing you give it ever leaves your
Mac. This document states, in concrete terms, what the app does and does
not do with your data.

## What the app does

- Reads PDF files that you open with the file picker.
- Writes the filtered output PDF to a location you choose with the save
  dialog.
- Stores the list of advocate names you type in, in the standard macOS
  user defaults for this application, so they are remembered between
  launches.
- Runs entirely on your computer. No network code is present in the
  binary, and the App Sandbox denies any socket operation at the kernel
  level.

## What the app does not do

- It does not collect analytics.
- It does not report crashes to any server.
- It does not phone home for updates.
- It does not contact the developer, the publisher, or any third party,
  for any reason, at any time.
- It does not transmit, upload, sync, mirror, or back up your PDFs or
  your name list to anywhere outside the Mac you are sitting at.
- It does not install background daemons, launch agents, or login items.
- It does not write outside the folders you choose.

## Where your files live

Every file the app can see is one you selected yourself. The board PDFs
stay in the folder they were already in. The output PDF is written to
the folder you chose in the save dialog. The app does not copy files
into its own sandbox container, an `Application Support` folder, or
anywhere else. The only persistent state it creates on disk is the
preference file holding your saved advocate names.

## Your saved names

The advocate names you enter are stored in
`~/Library/Containers/net.wolfgangrush.nakasha/Data/Library/Preferences/
net.wolfgangrush.nakasha.plist`. They are
plain text. They are local to your Mac, accessible only to your user
account, and never read or transmitted by the app for any purpose other
than matching them against cause lists you open. To erase them, quit
the app and delete that preferences file. The names will be cleared the
next time the app launches.

## Verifying the claim

You do not have to take this document on trust. The full source is in
the public repository. The shipped binary is ad-hoc signed but
unmodified; you can inspect it with `nm` and `otool` to confirm that no
network symbols are linked. The `entitlements.plist` in the repository
grants only `app-sandbox` and `files.user-selected.read-write`. The
absence of any `network.*` entitlement is what makes "no network"
enforced by the operating system rather than merely claimed by the
developer.

## Why this matters for Indian advocates

Cause lists contain the names of parties, witnesses, and matters under
your professional duty of confidentiality. Storing them on a remote
service — even one you trust — exposes them to a third-party data
processor under the Digital Personal Data Protection Act, 2023. A tool
that runs entirely on your own machine and cannot, by construction,
contact any other machine does not create that exposure. That is the
design rationale for the sandbox, the missing network entitlement, and
the absence of any update mechanism.

This statement is a description of the software's design, not a legal
certification. It is not a substitute for your own assessment of your
professional obligations.
