# Vendored Dependency: ProfileStore

- **Upstream Repository:** `https://github.com/MadStudioRoblox/ProfileStore`
- **Upstream Package (`wally.toml`):** `lm-loleris/profilestore`
- **Version:** `1.0.3`
- **Pinned Upstream Commit SHA:** `45c9847cbcf1fc260369c50eb335aba7c35aecdd`
- **License:** **Apache License 2.0** (upstream `LICENSE` preserved verbatim in this directory; corrects earlier Stage 0 planning assumption of MIT)
- **Vendored Files:**
  - `LICENSE` (verbatim, `11,357` bytes, SHA-256 `C71D239DF91726FC519C6EB72D318EC65820627232B2F796219E87DCF35D0AB4`)
  - `init.luau` (patched from pinned `ProfileStore.luau` upstream `64,654` bytes / SHA-256 `AD43737203688B8E88CAB34EBE8C483000C157E53BFB41E35F1B49EE89D0C95F` -> patched `65,622` bytes / SHA-256 `C7A5049B52627D2413128869A2BEE563A99B9BB2C076B7D8C8C136F700D5F11A`)
- **Vendored Date:** `2026-11-21`
- **Local Modifications (Apache-2.0 Section 4(b)):**
  - **2026-11-22 (Review #018):** Added prominent Section 4(b) notice banner and `Profile.OnFinalSaveResult(committed: boolean, reason, last_saved_data)` signal in `init.luau`, firing per ending-session `UpdateAsync` completion so callers know unambiguously whether this session's `EditProfile` transform actually owned and committed the final write (vs. lost ownership returning a newer owner's data).
