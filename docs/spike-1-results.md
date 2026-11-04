# Spike 1: Gemma 4 E2B on the device

Date: 2026-11-04. Model: `gemma-4-E2B-it-Q4_0.gguf` from
`ggml-org/gemma-4-E2B-it-GGUF` (2.84 GB, Apache 2.0, SHA-256 checked).
Engine: flutter_edge_ai 2.5.5 + flutter_edge_ai_llama 0.0.5 (llama.cpp via
llamadart 0.15.1). Eight fixed Japanese questions, no retrieval, a fresh chat
per question, temperature 0.3. Raw answers: [spike-results/](spike-results/).

## Speed and memory

| Device | Backend | Load | First token | Speed | RAM |
|---|---|---|---|---|---|
| MacBook Pro, M4 Max, 36 GB | GPU (Metal) | 4.5 s | 40 to 50 ms (785 ms on the first question) | 111 to 121 tokens/s | 1.6 to 3.0 GB |
| Android emulator (arm64, 8 GB, on the same Mac) | CPU | download + load 306 s | 0.6 to 4.5 s | 0.8 to 5.1 tokens/s | 4.4 to 4.6 GB |

A typical answer (120 to 180 tokens) takes 1 to 2 seconds on the Mac. Two
Mac runs gave the same answers. On the emulator the same answer takes 25 s
to 2.5 minutes. The emulator says little about real phones (no GPU, shared
CPU), but two things carry over: on Android the engine picked the CPU, and
the app used about 4.5 GB of RAM, so phones with 6 GB or less will struggle
with this 2.8 GB model. The emulator answers matched the Mac ones in
substance, including the same mistakes. One emulator result line (hiking)
was cut off by logcat.

## Answer quality (no retrieval)

Checked by hand against official guidance (内閣府, 気象庁, 消防庁).

| Question | Verdict | Problem |
|---|---|---|
| Earthquake, at home | OK | Fits the standard advice (protect your head, keep away from glass, gas after shaking stops). |
| Strong shaking near the sea, no tsunami warning yet | **Dangerous** | Says to hide under furniture and wait for TV/radio information. Official advice: go to high ground at once, do not wait for a warning. |
| Water for 4 people, 3 days | **Wrong** | Says 3 L per person per day, then "9 L" in total. Correct: 36 L. |
| 10 things for the shelter | OK | Reasonable list. |
| Lost while hiking, no signal | Weak | "Stay put" is fine, but says to call 119 although there is no signal; no "go up to a ridge, never down into a valley". |
| Bear encounter | Mixed | "Don't run, back away slowly" is right; "hit it lightly with a stick" is not standard advice. |
| Avalanche, buried partner | **Wrong** | No mention of avalanche transceiver, probe and shovel, and that the first 15 minutes matter. Says to call 119 first. |
| Heavy bleeding from the arm | OK | Direct pressure, raise the arm. Suggesting 110 (police) is odd. |

## What this means

- **Speed is fine on desktop, open on phones.** On a recent Mac the 2B model
  is fast and light. On Android the open questions are GPU use and memory:
  test a real phone, and try a smaller model (1B class) as the phone
  default.
- **The bare model must not answer safety questions on its own.** Two of
  eight answers were dangerous or wrong in a way that could cost lives, and
  the model sounded just as sure as when it was right. This confirms the plan:
  answers must come from retrieved official text with citations, and key
  safety steps (tsunami: go up now) must be fixed text from the package,
  not generated.
- **flutter_edge_ai works**, but the setup has sharp edges: exact version
  pairs (llamadart 0.15.1 with Apple companion 0.15.0), SwiftPM on, macOS 14,
  Android API 28 and arm64/x86_64 only.

## Build notes

- macOS release builds fail with Flutter 3.44.7 + Xcode 27.2 ("does not
  contain architectures arm64 x86_64" while copying FlutterMacOS). Workaround:
  `ARCHS = arm64` in `macos/Runner/Configs/Release.xcconfig` (Apple Silicon
  only).
- Release APK: 130 MB (arm64-v8a + x86_64). macOS app: 61 MB. The model is
  downloaded separately.
- Gemma 4 E2B Q4_0 is 2.84 GB, not about 1.5 GB as first assumed: the
  per-layer embeddings are large. The QAT Q4_0 file from Google is 3.35 GB.

## Next

1. Run on a real Android phone and an iPhone (needs a device).
2. Spike 2: retrieval over a small Bousai package with citations, then rerun
   the same eight questions and compare.
3. Try a smaller or different model (Qwen3.5-4B, LFM2.5-1.2B-JP) on the same
   questions once retrieval is in.
