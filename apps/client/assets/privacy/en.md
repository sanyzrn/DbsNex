## Nex privacy policy

Last updated: version 2.3.5 · Developer: DbsStudio (DbsStudio.ir)

Nex is built so that what you write stays yours. This page says what is kept where, and when anything leaves your phone.

### What stays on your phone

- Nex has no account and no server that holds your notes. Notes, photos, recordings, files, tags, reminders and your conversations with the assistant are stored on this phone only.
- The **private vault** (passwords, bank cards and private messages) is encrypted with a key kept in Android's secure Keystore and opens only with your fingerprint or screen lock. Vault content is never given to the assistant, search or widgets.
- **Cycle** — period and cycle tracking, which is health data — is off by default. Its data stays on the phone, and only if you turn on "Let the assistant read Cycle" is a short summary of it given to the assistant — never its day notes. "Delete all cycle data" removes it, and the backups on this phone that held it.
- Backups are stored on the phone or in a folder you choose. In a complete backup, settings and service keys are encrypted with a recovery code only you have; the notes and files in it are not, so they can always be opened — keep it somewhere you trust.
- Speed metrics, if you turn them on, stay on the phone. Nex has no advertising SDK, no analytics and no tracking code.

### When something leaves your phone

- **Cloud AI, only if you turn it on.** AI is off by default. If you choose a provider such as OpenAI, Gemini, Anthropic or OpenRouter with your own key, only the part of your notes each request needs is sent to it, and that provider's privacy policy applies to it. Every request is recorded in **Settings → Security and privacy → What left this device**.
- **The on-device model** sends nothing anywhere.
- **Feedback, only when you send it.** Your message, any contact you write in, the app version and phone model, and — if you choose — redacted error reports go to the developer.
- **What Nex does on its own:** check for a new version (not in the copy from Cafe Bazaar or Myket), fetch the sponsor card (a picture and a link shown on the home screen), read the page of a link you save for its title and preview, and download a model you choose. None of these sends anything about you or your notes.
- **Sharing:** anything you share to another app is that app's from then on.

### Permissions

Microphone for voice notes, camera for photos, notifications and exact alarms for reminders, fingerprint or screen lock for the app lock and the vault, and — only in the copy downloaded from GitHub — installing apps, for the in-app updater; the copy from Cafe Bazaar or Myket does not ask for it, because those stores update it. Each is asked for only when you use what needs it, and Nex keeps working without any of them.

### How long things are kept

What is on your phone stays until you delete it or uninstall Nex; a deleted note waits 30 days in the trash, then goes for good. Nex keeps no copy anywhere else. Feedback you send is kept by the developer only as long as it takes to answer and fix what it reports. What a cloud AI provider keeps is set by that provider's own policy.

### Security

Notes are stored in the app's private storage, which other apps cannot read; the vault is also encrypted, as above. Everything Nex sends goes over an encrypted (HTTPS) connection — the app refuses unencrypted ones.

### Children

Nex is a general notes app, not made for children, and it collects no personal information from anyone — there is no account to sign up for.

### You are in control

You can delete any note, your Cycle data or vault content, turn AI off, and clear the "What left this device" list. Uninstalling Nex removes all of its data from the phone, except copies you saved elsewhere yourself.

### Contact

For any question about privacy, write to us from **About Nex → Send feedback**, email zrn_sany@yahoo.com, or visit DbsStudio.ir. If this policy changes, the new version arrives with an app update.
