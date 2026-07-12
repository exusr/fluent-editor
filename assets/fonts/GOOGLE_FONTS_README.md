# Google Fonts Local Assets

This directory contains Google Fonts bundled locally for offline use.

## How to download fonts

1. Visit https://fonts.google.com
2. Select the font families you want to use (see list below)
3. Download each font family
4. Extract the .ttf or .otf files to this directory
5. Rename files using this pattern: `FontName-Variant.ttf`

### Naming convention

- `Roboto-Regular.ttf`
- `Roboto-Bold.ttf`
- `Roboto-Italic.ttf`
- `Roboto-BoldItalic.ttf`

## Required font families

For the curated web font list, download these 34 font families:

### Sans-serif (23 fonts)
- Roboto, Open Sans, Lato, Montserrat, Poppins, Inter, Nunito
- Source Sans Pro, Oswald, Raleway, Ubuntu, PT Sans, Noto Sans
- Work Sans, Quicksand, Titillium Web, Fira Sans, Space Grotesk
- DM Sans, Mulish, Karla, Barlow, Manrope

### Serif (8 fonts)
- Merriweather, Playfair Display, Noto Serif, Lora
- Crimson Text, Libre Baskerville, Roboto Slab, Literata

### Monospace (3 fonts)
- Space Mono, Fira Code, JetBrains Mono, Inconsolata

## How it works

The `google_fonts` Flutter package automatically:
1. First checks if the font exists locally in this directory
2. If found locally, uses the bundled font file
3. If not found, fetches from Google Fonts CDN at runtime

Bundling fonts locally ensures they work offline and loads faster.
