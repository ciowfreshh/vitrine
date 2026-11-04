# Spotify SYNA app icon

The iOS packaging pipeline generates `icons/SYNA.png` with
`scripts/generate-syna-icon.py` when it does not already exist.
It uses this opaque 1024×1024 logo as the primary home-screen icon
and also registers it under **Appearance > App icon**.

The previous `Vitrine.png` is retained only as an upstream source artifact,
but the pipeline deliberately skips it when registering alternate icons.

Other square 1024×1024 PNGs in `icons/` continue to work as alternates.
