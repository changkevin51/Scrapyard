# Privacy Policy for Scrapyard

Last updated: 24 August 2026

Scrapyard is a local note-taking app with optional AI features (Smelt and Ask) powered by Google Gemini. You bring your own Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

## Who we are

Scrapyard is developed as an open-source project ([github.com/changkevin51/Scrapyard](https://github.com/changkevin51/Scrapyard)). We do not create accounts, and we do not collect analytics. Notes stay on your device. The only Scrapyard-operated endpoint is an optional beta feedback form (see below).

## Data stored on your device

The following stay on your device unless you use an AI feature, send feedback, or share/export them yourself:

- Handwritten scraps, typed text, tables, and canvas settings
- Imported PDFs and PDF annotations
- Ask transcripts and any images attached to chats
- Gesture and canvas preferences
- Your Gemini API key (in the device’s secure storage)

Chat history and notes are stored in local databases. Android Auto Backup is disabled so those files are not uploaded to your Google account backup.

## Data sent off the device

**Smelt and Ask** (only if you have saved an API key):

1. **Your Gemini API key** is sent to Google (`generativelanguage.googleapis.com`) with the request so Gemini can authenticate you. The key is stored on-device; it is not kept by Scrapyard on a server.
2. **Content you select or send** — circled handwriting (as an image), typed selection text, PDF page crops, chat messages, and previously attached chat images — is sent to Google Gemini so the model can reply.
3. If you use Smelt’s optional **code execution**, problem text/images may be processed in Google’s code-execution sandbox.
4. Requests include Gemini **safety settings** so Google can block replies that match harassment, hate, sexual, or dangerous-content categories. Blocked replies stay on your device as an error message.

We do not send your scraps to our own servers. We cannot delete data Google has already received; see [Google’s Gemini API terms](https://ai.google.dev/gemini-api/terms) and Google’s privacy policy. Unpaid (free-tier) AI Studio keys are typically covered by Google’s unpaid-services terms, under which prompts may be used to improve Google products.

**On-device math (Quick calc)** runs locally on your device. It does not use your API key and does not send handwriting to Google.

**Beta feedback** (only if you tap Send on the in-app form):

The message you typed, the kind you picked (Bug / Idea / Other / Report), an optional reply email, and basic app/device metadata (app version and platform) are sent to a small Scrapyard function and emailed to the developer via Resend. This does not include your notes, PDFs, chats, or Gemini API key, except when you use **Report** on a Smelt or Ask reply — then the flagged model output is attached so we can look at it. You can close the form without sending anything.

## What we do not do

- We do not sell your data.
- We do not show ads.
- We do not require an account.
- We do not use your notes to train a Scrapyard model.

## Children

Scrapyard is not directed at children under 13 and is not part of Google Play’s Designed for Families program. Generative AI features can produce unexpected output. Do not use Scrapyard to process a child’s personal information.

## Your choices

- Skip adding an API key — drawing, PDFs, and Quick calc still work.
- Remove the API key in Settings at any time.
- Delete chat history in Settings (this only deletes the local copy).
- Crush scraps and empty Recently Deleted to remove local files.
- Close the feedback form without sending.
- Report a Smelt or Ask reply from the card or message itself.

## Contact

Use **Send feedback** in the app (Home sidebar, below Guide, or Settings), or open an issue on [the Scrapyard GitHub repository](https://github.com/changkevin51/Scrapyard/issues).
