# MacStream Product Brief

MacStream is a macOS 26-native streaming studio for solo creators who stream camera and screen together. It is not trying to become OBS feature parity. The first product promise is:

> Preview, record, and prove the stream before going live.

The wedge is a calm Mac-native director: it watches local signals, protects the stream from obvious mistakes, and suggests or performs bounded scene changes. AI supports setup, review, summaries, clip naming, and explanations; it does not own live switching.

## First Audience

- coding streams
- product demos
- design streams
- workshops and teaching
- founder livestreams
- screen-share podcasts

## First Workflow

1. Pick camera, mic, and screen/window target.
2. Verify Camera, Microphone, Screen Recording, source levels, and capture target readiness.
3. Preview the fixed scenes: Face, Screen + Face, Screen, and BRB.
4. Record a local proof clip, especially `Screen + Face`, before trusting RTMP.
5. Start a Preview session or an RTMP endpoint check.
6. The deterministic director watches speech, screen motion, active app, face presence, idle state, muted mic, frozen screen, stream health, and capture pressure.
7. The app suggests a cue, or switches automatically when the user enables Auto mode and the target scene is available for the active media path.

## Product Principle

Minimal means fewer knobs, not a shallow director. The first app should have a small surface area and one deep behavior: it helps a solo creator avoid babysitting production while live.

## AI Principle

Provider-first. MacStream should support:

1. Foundation Models for native Apple-local setup/review help on supported macOS 26 systems.
2. OpenAI-compatible local providers such as LM Studio, Ollama, llama.cpp servers, MLX servers, or other user-owned endpoints.
3. Rule-based fallback when no provider is configured or a provider is offline.
4. Experimental MLX compile-time adapter only after provider contracts and benchmarking justify it.

AI output must become typed setup/review artifacts before it affects the app. The live director consumes deterministic thresholds, scene availability, source state, and capture health; it never waits on a model token stream.
