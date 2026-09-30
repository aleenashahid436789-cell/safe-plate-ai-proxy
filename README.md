# Safe Plate AI proxy

Backend proxy for the Safe Plate AI app. Holds the Gemini API key
server-side (set as an environment variable on the host), rate-limits
requests, and requires the X-App-Secret header.
