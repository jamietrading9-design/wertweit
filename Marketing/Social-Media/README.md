# Wertweit Social-Media-Material

## Bilder

- `01-feed-portrait-4x5.png`: 1080 × 1350, Instagram-Feed im Hochformat
- `02-feed-square.png`: 1080 × 1080, quadratischer Feed-Post
- `03-story-reel-cover.png`: 1080 × 1920, Story oder Reel-Cover
- `04-story-travel-cover.png`: 1080 × 1920, alternative Reise-Story
- `07-story-road-photo.png`: 1080 × 1920, fotozentriertes Story-Cover
- `08-story-city-photo.png`: 1080 × 1920, urbanes Story-Cover
- `09-feed-travel-photo-4x5.png`: 1080 × 1350, fotozentrierter Feed-Post

## Videos

- `05-reel-wertweit-12s.mp4`: vertikaler Clip, 720 × 1280, 12 Sekunden
- `06-reel-reiseplanung-12s.mp4`: alternative Fassung, 720 × 1280, 12 Sekunden
- `10-reel-road-photo-12s.mp4`: fotozentrierter Clip mit Kamerafahrt, 720 × 1280, 12 Sekunden
- `11-reel-city-photo-12s.mp4`: alternative Foto-Fassung mit Kamerafahrt, 720 × 1280, 12 Sekunden

Die Videos sind ohne Ton und können direkt mit eigener Musik oder einem gesprochenen Text in der jeweiligen Social-Media-App ergänzt werden. Die ältere Serie verwendet eine gezeichnete Rechner-Illustration; die neue Serie setzt auf lizenzierte Reisefotos und behauptet keine konkreten Wechselkurse. Alle Quellfotos liegen in `Quellen/`.

Die Grafiken verwenden das Wertweit-App-Logo. Referenzkurse sind EZB-Kurse; Reise- und Budgetangaben sind unverbindliche Richtwerte. Die App ist kein Finanzberatungsangebot.

## Fotoquellen

Die drei Reisefotos stammen von Unsplash und werden gemäß der [Unsplash-Lizenz](https://unsplash.com/license) verwendet:

- [Straße durch rote Felsen](https://images.unsplash.com/photo-1500530855697-b586d89ba3ee)
- [Stadt am Abend](https://images.unsplash.com/photo-1519501025264-65ba15a82390)
- [Wanderer in den Bergen](https://images.unsplash.com/photo-1526772662000-3f88f10405ff)

## Neu rendern

Im Projektordner ausführen:

```sh
swift scripts/create_social_media_assets.swift
```

Nur die neue Foto-Kampagne rendern, ohne die bisherigen sechs Exporte neu zu schreiben:

```sh
swift scripts/create_social_media_assets.swift --photo-campaign-only
```