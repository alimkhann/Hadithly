# H3 Saved design

## Caller view

The reader keeps calling `toggleBookmark`, `toggleFavorite`, `saveNote`, and
`deleteNote`. The Saved destination receives one `SavedSnapshot`: unique Saved
items, private folders, and each item's optional folder. It filters item facets
without creating duplicate rows and opens the existing canonical target.

## Shape

`savedItems` is unique by `(userId, hadithId)`. It owns the three independent
facets and the nullable `folderId`. `savedFolders` is unique by a private,
normalized name per user. The server validates and normalizes folder names at
the boundary. It prevents control characters, empty names, and names over 64
Unicode scalar values.

`listSavedSnapshot` reads `savedItems` and legacy bookmark, favorite, and note
rows. It merges facets by hadith ID, so a partially completed backfill and a
rollback to legacy reads produce the same unique targets. New mutations dual
write their legacy projection while old clients still exist. The bounded
backfill only inserts or merges `savedItems`; it never deletes legacy rows.

The two clients retain reading-progress as its own subscription. They replace
three Saved subscriptions with one Saved snapshot subscription. Snapshot
updates never include progress, so frequent reader position writes do not
resend the Saved list. A representative serialized fixture measures fewer
initial Saved bytes where one hadith has multiple facets.

## Lifecycle rules

- Folder deletion unfiles its items. Undo assigns the remembered folder back
  if that folder still exists.
- Removing one facet removes the whole Saved item only when no other facet and
  no folder remain.
- A guest merge accepts both legacy arrays and the new Saved/folder payload.
  It unions boolean facets, resolves notes by latest update, and preserves the
  existing folder when a newer payload has none.
- A Saved target is always the existing `HadithRef` target. Legacy bookmark
  offsets remain legacy metadata and never become a fabricated reading
  position.
