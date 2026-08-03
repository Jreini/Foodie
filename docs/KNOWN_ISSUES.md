# Known Issues

Open bugs with what's already been ruled out, so the next attempt doesn't repeat the last one.

---

## Shared list emoji renders as a missing-glyph box on a second device

**Status:** open, deferred. Cosmetic — lists work correctly otherwise.

**Symptom:** the emoji on a shared list shows as an empty square containing a `?` (the missing-glyph / `.notdef` box) on the device that *joined* the list. It renders correctly on the owner's device.

**Ruled out:**

- **The stored value.** Verified directly in Postgres — `lists.emoji` holds the correct emoji for the affected row.
- **An owner-vs-member code path.** There isn't one. Both devices call the same `fetchLists()` (`select=*` on `lists`), decode through the same private `ListRow`, and render the same `SharedList.displayEmoji`. RLS filters rows, not columns, so both sessions receive an identical row.
- **A null falling back to the default.** The fallback in `displayEmoji` is `🍽️`, a real plate glyph. A `?`-box is not the fallback — it means the system tried to render a scalar it has no glyph for.
- **Dynamic Type clipping.** Was a genuine bug (fixed `40×40` frame with a scaling font); fixed with `@ScaledMetric` in `SharedListsView`. Did not resolve this.

**What that leaves:** the string reaching `Text` on the affected device is not the same sequence of Unicode scalars that's in the database. Either it's being mangled between PostgREST and SwiftUI, or the device genuinely lacks a glyph for it.

**Next step when picking this up:** log the actual scalars on the affected device rather than looking at the rendered result —

```swift
print(list.emoji?.unicodeScalars.map { String(format: "U+%04X", $0.value) } ?? ["nil"])
```

Compare against the owner's device for the same list. If they differ, it's a transport/decoding problem. If they match, compare iOS versions — a device on an older release won't have glyphs for newer Unicode emoji, though every emoji in the `CreateListSheet` palette is old enough that this would be surprising.

Worth checking too: whether the `?`-box is `U+FFFD` (the replacement character Unicode substitutes for invalid UTF-8), which would point squarely at decoding.
