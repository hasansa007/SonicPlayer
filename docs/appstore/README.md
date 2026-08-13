# App Store copy

One directory per version. Each `whats-new.<lang>.md` holds **only the pasteable text** — no
heading, no front matter, no Markdown that would arrive as literal characters. Paste the whole file
into the matching localisation's *What's New in This Version* field.

## Why these live here and not in `RELEASE_NOTES.md`

`RELEASE_NOTES.md` is read by `.github/workflows/distribute.yml`, which matches the section whose
heading equals `## <CFBundleShortVersionString>` and ships it to **TestFlight**, in English only.
That is a different audience and a different field: it closes by inviting bug reports, which is
right for a tester and odd for a shopper.

So the English file here is that section **minus the tester-facing closer**, and the other languages
have no equivalent anywhere else — TestFlight's What's New is not localised, the App Store's is.

**Changing one does not change the other.** If a fact changes, it has to be edited in both, and in
every language present. That is the cost of the split and it is deliberate: the alternative is
shipping a shopper an invitation to report bugs.

## The five words

`CLAUDE.md` binds every word that ships, and this directory is squarely in scope. **iPod**, **Click
Wheel**, **Classic Player**, **Retro** and **Nostalgia** never appear — the first two are Apple
trademarks, and the other three are the words that argue an app is trading on a resemblance, which
is the evidence Guideline 5.2.5 turns on.

That applies to translations too, and a translator with no context is exactly how such a word gets
in. **Positioning stays affirmative in every language**: what the control does, never what it
recalls.

```bash
grep -rniE "ipod|click wheel|classic player|retro|nostalgia" docs/appstore/*/whats-new.*.md
# expect no matches
```

**The glob is the copy files, deliberately — not `docs/appstore/`.** This README names all five in
the paragraph above, because that is the only way to write the rule down, exactly as `CLAUDE.md`
and the design spec do. Point the check at the directory and it matches this file every time, and a
check that can only ever fail is one nobody runs. Widen it and you have removed the check, not
strengthened it.

## Translations follow the app, not the dictionary

A word in this copy that differs from the word on screen reads as a different feature. The Arabic
here is built from what `Localizable.xcstrings` already ships — `المكتبة`, `قيد التشغيل`,
`مجلد جديد`, `استيراد`, `الإعدادات`, and `اللف` for turning the wheel, which is the verb the app's
own hint uses. Check there before choosing a term, and if the UI string changes, this changes with
it.

## Limits

One file per field per language. The caps differ by an order of magnitude, and **the cap is what
decides the shape** — 170 characters is one sentence, not a trimmed list.

| File | Field | Cap |
|---|---|---|
| `whats-new.<lang>.md` | What's New in This Version | **4000** |
| `promotional-text.<lang>.md` | Promotional Text | **170** |

Promotional Text can be changed **without submitting a build**, which What's New cannot — so it is
the one to edit when the pitch needs to move between releases.

Counts are in characters, not bytes. Arabic runs roughly two bytes per character, so `wc -c`
overstates it by nearly double:

```bash
wc -m docs/appstore/3.0.0/*.md
```

Trailing newlines count in `wc -m` and not in the field, so a file one over the cap is fine; two
over is not. Check the number, not the verdict.

**The short pair must mirror the long pair.** Both languages open on the same claim in the same
shape, because a listing that pitches one thing in English and another in Arabic is two products.

## Coverage — 2 of the 9 languages the app ships

`Localizable.xcstrings` localises the app into **ar, bn, en, es, fr, hi, pt, ru, zh-Hans**.
`3.0.0/` holds copy for **en and ar** only. The remaining seven — bn, es, fr, hi, pt, ru, zh-Hans —
have **no App Store copy in any file**, so those storefronts fall back to the English listing.

That is a gap, not a decision, and it was invisible while the app was TestFlight-only: TestFlight's
What's New is not localised, so nothing asked the question until 3.0.0 went public on 2026-08-13.
A user browsing in Hindi sees a Hindi app described in English.

Adding a language means both files, at both caps, built from the terms
`Localizable.xcstrings` already ships — the rule under "Translations follow the app" applies to
every one of them, and so does the five-word rule.
