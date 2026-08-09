<div align="center">

<img src="assets/branding/readme/wordmark.png" alt="Scrapyard" width="500"/>

**Scrap in, solutions out.**

[![Flutter](https://img.shields.io/badge/Built%20with-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Gemini](https://img.shields.io/badge/Powered%20by-Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white)](https://aistudio.google.com)
![Status](https://img.shields.io/badge/Status-In%20Development-orange?style=for-the-badge)
[![Price](https://img.shields.io/badge/Price-Free-brightgreen?style=for-the-badge)](#its-free)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge)](LICENSE)

<br>

<img src="assets/branding/readme/smelt_demo.webp" alt="Smelt demo: circling a problem on the canvas and getting an AI-worked solution" width="700"/>

</div>


## What is this?

Scrap paper is where most of the real thinking happens. It's messy, it's fast, and nobody ever grades it. Scrapyard tries to keep that feeling, except the paper can read what you wrote.

Scribble out a problem, select it, and the app works through it with you — step by step, not just an answer. When you want to keep digging, there's a chat panel next to your notes that already knows what you're looking at.

## It's free

Free without an asterisk. No subscription, no credits, nothing to upgrade to.

You bring your own API key from [Google AI Studio](https://aistudio.google.com/app/apikey), which is also free and takes about thirty seconds to create. Paste it in when the app asks and that's the whole setup. The key lives in your device's secure storage and never leaves it.

<div align="center">
<img src="assets/branding/readme/api_key_setup.jpg" alt="API key setup dialog in Scrapyard" width="400"/>
</div>

## Features

### The canvas

Pressure-aware vector ink keeps handwriting close to the real thing. Every tool you'd expect from a good note-taking app is here, plus a few you might not, and documents open in tabs so you can jump between notes without losing your place.

<div align="center">
<img src="assets/branding/readme/tools_demo.webp" alt="Toolbar demo: shapes, text, stickers, and other canvas tools" width="400"/>
</div>

### Smelt

Circle any part of the canvas and hit Smelt. It reads the selection with on-device OCR and Gemini's vision model, then streams back a worked solution, step by step. Stuck on something harder? Verify the result with code execution, or switch to a heavier model. If one model is unavailable, it falls back to another.

### Study chat

An ordinary conversation with the AI, except it already has context on what's on your canvas. Chats are saved, you can pick the model, and suggestion chips are there for when you're not sure what to ask.

### PDFs

Open a PDF and annotate right on top of it. Split-screen puts the document on one side and your scrap paper on the other — this is how I work through problem sets.

## Recently added

- **True splitscreen for study chat** allows users to keep writing on the canvas while the chat panel is open
- **Smelt popup can be pinned** and be dragged so that it doesn't disappear from writing.
- **Redesigned highlighter, eraser, and lasso icons** with clearer custom glyphs in the toolbar.
- **Improved automatic bounding box detection** that uses a sophisticated algorithm taking into account timing, proximity, outliers, and patterns. 
- **Infinite canvas** page style with unbounded pan and zoom.

## Getting started

You'll need the [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0 or newer) and a [Google AI Studio key](https://aistudio.google.com/app/apikey).

```bash
git clone https://github.com/<your-username>/scrapyard.git
cd scrapyard
flutter pub get
flutter run
```

The first launch walks you through onboarding and asks for the key.

## Built with

| Layer | Tech |
|---|---|
| Framework | [Flutter](https://flutter.dev) |
| State | [Riverpod](https://riverpod.dev) |
| AI | [Google Gemini API](https://aistudio.google.com) |
| Ink | [perfect_freehand](https://pub.dev/packages/perfect_freehand) |
| Storage | [sqflite](https://pub.dev/packages/sqflite), [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) |
| PDFs | [pdfrx](https://pub.dev/packages/pdfrx) |
| OCR | [Google ML Kit](https://pub.dev/packages/google_mlkit_text_recognition) |
| Math | [flutter_math_fork](https://pub.dev/packages/flutter_math_fork) |


## Contributing

Issues and pull requests are welcome.

## License

GPL-3.0. See [LICENSE](LICENSE).

---

<div align="center">

<img src="assets/branding/readme/wordmark.png" alt="Scrapyard" width="140"/>

<sub>Forged with love, out of scrap and late nights.</sub>

</div>
