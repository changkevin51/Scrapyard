# Privacy Policy for Scrapyard

Last updated: 20 August 2026

Scrapyard is a local note-taking app with optional AI features (Smelt and study chat) powered by Google Gemini. You bring your own Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

## Who we are

Scrapyard is developed as an open-source project ([github.com/changkevin51/Scrapyard](https://github.com/changkevin51/Scrapyard)). We do not operate a Scrapyard backend. We do not create accounts, and we do not collect analytics.

## Data stored on your device

The following stay on your device unless you use an AI feature or share/export them yourself:

- Handwritten scraps, typed text, tables, and canvas settings
- Imported PDFs and PDF annotations
- Study-chat transcripts and any images attached to chats
- Gesture and canvas preferences
- Your Gemini API key (in the device’s secure storage)

Chat history and notes are stored in local databases. Android Auto Backup is disabled so those files are not uploaded to your Google account backup.

## Data sent off the device

**Only when you use Smelt or study chat** (and only if you have saved an API key):

1. **Your Gemini API key** is sent to Google (`generativelanguage.googleapis.com`) with the request so Gemini can authenticate you. The key is stored on-device; it is not kept by Scrapyard on a server.
2. **Content you select or send** — circled handwriting (as an image), typed selection text, PDF page crops, chat messages, and previously attached chat images — is sent to Google Gemini so the model can reply.
3. If you use Smelt’s optional **code execution**, problem text/images may be processed in Google’s code-execution sandbox.

We do not send your scraps to our own servers. We cannot delete data Google has already received; see [Google’s Gemini API terms](https://ai.google.dev/gemini-api/terms) and Google’s privacy policy. Unpaid (free-tier) AI Studio keys are typically covered by Google’s unpaid-services terms, under which prompts may be used to improve Google products.

**On-device math (Quick calc)** runs locally on your device. It does not use your API key and does not send handwriting to Google.

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

## Contact

Open an issue on [the Scrapyard GitHub repository](https://github.com/changkevin51/Scrapyard/issues).
