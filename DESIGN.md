---
name: MindForge
description: A near-white technical sheet where the product is shown as an annotated specimen and hairlines carry every structure.
colors:
  paper: "#F7F7F6"
  panel: "#FDFDFC"
  ink: "#141414"
  body-ink: "#2E2E2E"
  mute: "#63635F"
  rule: "#1F1F1F"
  rule-soft: "#DFDFDB"
  rule-hair: "rgba(20,20,20,.10)"
  accent: "#DA4A14"
  accent-ink: "#A83409"
  navy: "#1D3557"
  plate-label: "#C8D6E6"
  ok: "#146B3F"
typography:
  display:
    fontFamily: "Alumni Sans, Albert Sans, sans-serif"
    fontSize: "clamp(46px, 7.4vw, 112px)"
    fontWeight: 200
    lineHeight: 0.92
    letterSpacing: "-.012em"
  headline:
    fontFamily: "Alumni Sans, Albert Sans, sans-serif"
    fontSize: "clamp(34px, 5.4vw, 76px)"
    fontWeight: 200
    lineHeight: 0.92
    letterSpacing: "-.012em"
  title:
    fontFamily: "Alumni Sans, sans-serif"
    fontSize: "30px"
    fontWeight: 400
    lineHeight: 1.05
    letterSpacing: "normal"
  figure:
    fontFamily: "Alumni Sans, sans-serif"
    fontSize: "25px"
    fontWeight: 300
    lineHeight: 1.15
    letterSpacing: "normal"
  wordmark:
    fontFamily: "Alumni Sans, sans-serif"
    fontSize: "21px"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: ".11em"
  body:
    fontFamily: "Albert Sans, system-ui, sans-serif"
    fontSize: "16.5px"
    fontWeight: 400
    lineHeight: 1.6
    letterSpacing: "normal"
  lede:
    fontFamily: "Albert Sans, system-ui, sans-serif"
    fontSize: "clamp(16.5px, 1.42vw, 19px)"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "normal"
  label:
    fontFamily: "JetBrains Mono, ui-monospace, Menlo, monospace"
    fontSize: "12.5px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: ".02em"
  label-strong:
    fontFamily: "JetBrains Mono, ui-monospace, Menlo, monospace"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: ".06em"
rounded:
  none: "0"
  control: "2px"
spacing:
  gutter: "clamp(16px, 4vw, 54px)"
  row: "15px"
  row-wide: "21px"
  panel-pad: "18px"
  section: "clamp(46px, 7vw, 108px)"
  close: "clamp(52px, 8vw, 124px)"
components:
  button-fill:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "11px 17px"
  button-fill-hover:
    backgroundColor: "{colors.accent-ink}"
    textColor: "{colors.paper}"
  button-line:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "11px 17px"
  button-line-hover:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  nav-link:
    backgroundColor: "transparent"
    textColor: "{colors.body-ink}"
    rounded: "{rounded.none}"
    padding: "7px 11px"
  nav-link-hover:
    textColor: "{colors.ink}"
  panel:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "18px 18px 20px"
  plate-header:
    backgroundColor: "{colors.navy}"
    textColor: "#FFFFFF"
    rounded: "{rounded.none}"
    padding: "12px 15px"
    height: "40px"
  tag-due:
    backgroundColor: "transparent"
    textColor: "{colors.accent-ink}"
    rounded: "{rounded.none}"
    padding: "3px 6px"
  tag-ok:
    backgroundColor: "transparent"
    textColor: "{colors.ok}"
    rounded: "{rounded.none}"
    padding: "3px 6px"
  tag-new:
    backgroundColor: "{colors.accent-ink}"
    textColor: "#FFFFFF"
    rounded: "{rounded.none}"
    padding: "3px 6px"
---

# Design System: MindForge

## Overview

**Creative North Star: "The Annotated Specimen Sheet"**

This world is a near-white technical sheet. The product is not described and not
dramatised — it is *exhibited*, laid out like a specimen on a plate and labelled
part by part, with mono callouts on leader lines naming what each row is. Every
structure in the page is carried by a 1px hairline rule: no card shadows, no
fills standing in for a container, no rounded chrome. Corners are square
everywhere except a single 2px softening on the interactive control, which is
the only place the sheet admits a hand touches it.

The world is **user-pinned**, and that pin is load-bearing. After three other
directions were rejected, the user named https://impeccable.style as the
reference they wanted. Its actual system was inspected and derived — near-white
ground, hairline structure, radius 0, very large ultra-light condensed display,
mono labels, a single warm accent, and an annotated product artifact in the hero
— and then executed in MindForge's own colour rather than copied. **A later
agent must not "correct" this world toward a conventional SaaS or EdTech
aesthetic.** The reference is pinned; the brand colour (orange `#DA4A14`, navy
`#1D3557`) is MindForge's own; both halves stay.

Density is high in the ruled zones and generous everywhere else. Warmth arrives
in exactly one hue and only in a labelling role: keys, callouts, status tags,
the diagram arrow, focus rings, selection. The page reads in sunlight because
it is nearly all true black-on-near-white, with no grey-on-grey pairings.

**Key Characteristics:**
- Hairline rules, never shadow or fill, carry every structural boundary.
- Radius 0 everywhere; 2px on controls only.
- Very large Alumni Sans at weight 200 against 16.5px Albert Sans body.
- Mono is for labels, keys, figures and annotations — never running prose.
- One warm accent, used as annotation ink, not as decoration.
- The product is shown annotated, with numbered keys tying specimen to text.

## Colors

A near-white paper ground with near-black ink, three weights of hairline, and a
single warm accent that does annotation work.

### Primary
- **Forge Orange** (`#DA4A14`): annotation ink. Leader lines, the diagram arrow,
  the focus ring, text selection, and the `.owed` notice's left rule. It marks
  and points; it never fills a large area.
- **Forge Orange Deep** (`#A83409`): the text-safe cut of the accent. Every
  place the accent must be *read* rather than seen — numeric keys, callout
  labels, question numbers, the "Due" tag, the filled button's hover — uses this
  darker value so contrast holds on paper.

### Secondary
- **Plate Navy** (`#1D3557`): the logo navy, the world's dark plate. In the
  shipped build it appears in exactly one place: the 40px header bar of the
  annotated device. See Known Ceiling.
- **Plate Label Blue** (`#C8D6E6`): the only mono label colour permitted on top
  of Plate Navy. Mute grey is illegible there; this is its on-plate substitute.

### Tertiary
- **Marked Green** (`#146B3F`): settled-state status only — Graded, Paid,
  present-count. It is a status colour, not a palette colour; it never appears
  in prose, headings or rules.

### Neutral
- **Sheet Paper** (`#F7F7F6`): the page ground and the sticky bar behind it.
- **Panel White** (`#FDFDFC`): the slightly-lifted surface of a specimen panel
  or slab. The lift is tonal only — one step brighter than paper, no shadow.
- **Ink** (`#141414`): display type, headings, the filled control, item titles.
- **Body Ink** (`#2E2E2E`): running copy.
- **Mute** (`#63635F`): mono labels, captions, secondary item lines, table keys.
- **Structure Rule** (`#1F1F1F`): the strong hairline — page bar, section tops,
  device border, table head.
- **Soft Rule** (`#DFDFDB`): the list hairline — between rows, cards, cells.
- **Hair Rule** (`rgba(20,20,20,.10)`): the faintest hairline, used inside the
  specimen where rows must separate without competing with the device border.

### Named Rules
**The Annotation-Only Accent Rule.** Orange exists to point at things. It is
allowed on hairlines, keys, tags, arrows, focus rings and one filled hover
state. It is never a hero background, never a gradient, never a section fill.

**The Three-Hairline Rule.** Every border in this world is 1px and is one of
exactly three values: `#1F1F1F` for structure, `#DFDFDB` for lists, and
`rgba(20,20,20,.10)` for the interior of a specimen. There is no fourth weight
and no 2px rule.

**The Sunlight Rule.** No grey text on grey ground. Mute (`#63635F`) is the
lightest text allowed on paper, and it is reserved for labels and captions; body
copy always sits at `#2E2E2E` or darker.

## Typography

**Display Font:** Alumni Sans (with Albert Sans, sans-serif)
**Body Font:** Albert Sans (with system-ui, sans-serif)
**Label/Mono Font:** JetBrains Mono (with ui-monospace, Menlo, monospace)

**Character:** Very large, very light condensed display set tight against small,
plain, humanist running copy — a laboratory sheet's title over a laboratory
sheet's notes. Mono is the third voice and speaks only in labels.

The reference world uses "Alumni Sans Hero", which is not publicly available.
**Alumni Sans is the nearest public cut, and the spacing compensation below is
part of the system, not a hack**: that cut sets punctuation and word spaces
loose at display size, so display type ships with `word-spacing:-.10em` and a
`.pn` span that pulls commas and periods in by `-.14em` on the left and `-.11em`
on the right. Any new display headline that contains punctuation wraps that
punctuation in `.pn`. Removing the compensation breaks the display voice.

### Hierarchy
- **Display** (200, `clamp(46px,7.4vw,112px)`, 0.92): the page's one h1 and the
  closing call. Tabular numerals on, `text-wrap:balance`.
- **Headline** (200, `clamp(34px,5.4vw,76px)`, 0.92): section h2s, capped at
  22ch (30ch for the wide variant) so they break into stacked lines.
- **Title** (400, 29–30px, 1.05): row and keyed-row headings. Alumni Sans at a
  heavier weight than display — small display type needs the extra weight.
- **Figure** (300, 25px, 1.15): the spec strip's values and the specimen
  chapter title; a number or short phrase presented as a value.
- **Wordmark** (500, 21px, `.11em`, uppercase): "MIND FORGE" in the bar and
  footer, and 17px on the navy plate.
- **Body** (400, 16.5px, 1.6): running copy, capped at 44ch in the hero lede,
  52ch in section subs, 56ch in rows.
- **Label** (400, 12.5px, `.02em`): mono labels, callouts, captions, synthetic-
  sample notices. The strong variant (500, 12px, `.06em`, uppercase) is for
  table headers and keys.

### Named Rules
**The Mono-Is-Not-Prose Rule.** JetBrains Mono carries labels, keys, figures and
annotations only. It never sets a sentence a reader is meant to read for
meaning. The build carries **one deliberate exception**: the `.owed` block is a
build-time notice addressed to the site owner listing URLs still to be supplied.
It is mono precisely because it is not reader copy and must not be mistaken for
it. That exception does not extend to any new surface.

**The Punctuation Pull Rule.** Display punctuation is always wrapped in `.pn`.
The public Alumni Sans cut sets it loose at 100px; the pull is the system
compensating for the substitute face.

**The Three-Voice Rule.** Alumni Sans states, Albert Sans explains, JetBrains
Mono labels. A block never uses two of the three for the same job.

## Layout

A single 1280px centred column (`.wrap`) with a fluid gutter of
`clamp(16px,4vw,54px)`, which is also the world's one spacing primitive — the
bar, the page body and the footer all breathe from it.

The hero is an asymmetric two-column grid, `.86fr / 1.14fr`: the annotated
specimen on the left (capped at 330px wide), the argument on the right. It
collapses to one column at 980px with the specimen ordered *below* the
argument, so the headline always lands first on a phone. Section heads use a
50/50 grid (headline left, sub right, baseline-aligned at the bottom edge)
collapsing at 860px. The mechanism pair is `1fr auto 1fr` with the arrow in the
middle, collapsing at 860px with the arrow rotated 90°.

Vertical rhythm is set by section padding `clamp(46px,7vw,108px)` on top only,
so hairline rules — not whitespace — are what close a section. Ruled rows are
15px tall below 900px and 21–24px at 900px and up: the sheet gets denser on
small screens, not looser. The spec strip is an auto-fit grid of
`minmax(min(50%,180px),1fr)` cells, becoming a stacked hairline list under
760px.

Breakpoints observed: 1280 (callouts), 980 (hero), 920 (nav), 900 (row
density), 860 (head row, mechanism), 760 (strip, rows), 640 (keyed rows), 430
(control padding). The page is built to hold at 360px.

**The Marginal Column Rule.** The hero reserves space outside the specimen for
mono callouts on leader lines, hidden below 1280px rather than reflowed
inward. Annotation is a wide-viewport affordance; it is never allowed to crowd
the artifact it annotates.

## Elevation & Depth

**This system has no elevation.** There is no shadow vocabulary. Depth is tonal
and linear only: a panel is one step brighter than paper (`#FDFDFC` on
`#F7F7F6`) and is bounded by a hairline. A specimen "sits above" the sheet
because it is brighter and ruled, not because it casts anything.

The one `box-shadow` in the build is not elevation: it is a transient 4px
expanding ring in the "New" tag's pulse keyframe, an accent-coloured
`rgba(218,74,20,.22)` halo that animates to zero and leaves nothing behind.

### Named Rules
**The Hairline-Carries-It Rule.** If a region needs to be distinguished, rule
it. Do not reach for a shadow, a fill, or a radius to do a hairline's job.

## Shapes

Radius 0 is the default and near-universal: panels, slabs, tags, tables, the
device, the spec strip, nav links, redaction bars. The single exception is the
2px radius on `.btn`, applied to both the filled and outlined control — just
enough to read as pressable without becoming a pill.

Borders are always exactly 1px and always one of the three rule values. The one
authored border variation is `border-style:dashed` on a disabled control
(together with `opacity:.45`), which reads as "not yet issued" rather than
"broken". Illustrative graphics are geometric line SVG at 1.2–1.4 stroke weight,
matching the hairline language.

## Components

### Buttons
- **Shape:** square-feeling with the faintest softening (2px radius), 11px/17px
  padding, an inline 15px SVG glyph before the label, Albert Sans 600 at 14.5px.
- **Filled (primary):** ink ground (`#141414`) with paper text — the page's one
  filled control. Hover swaps the ground to Forge Orange Deep; active nudges 1px
  down.
- **Outlined (secondary):** transparent with a structure hairline; hover inverts
  to the ink ground.
- **Disabled:** 45% opacity, dashed border, pointer events off, marked
  `aria-disabled` — used for the unreleased iPhone build.
- **Focus:** a 2px accent outline at 3px offset, globally, on every focusable
  element.

### Cards / Containers
- **Corner Style:** square (0).
- **Background:** Panel White for slabs and the specimen; pure white for the
  innermost chapter page, which is one step brighter again.
- **Shadow Strategy:** none. See Elevation & Depth.
- **Border:** 1px soft rule for slabs, 1px structure rule for the specimen
  device.
- **Internal Padding:** 18px for slabs, 15px for the specimen body.

### Tags
- **Style:** mono 12px/500, 3px 6px padding, square, `border:1px solid
  currentColor` so the border is always the text colour.
- **Variants:** due (accent deep), settled (marked green), new (filled accent
  deep with white text — the only filled tag).

### Navigation
- Albert Sans 14px links at 7px/11px padding with a *transparent* 1px border at
  rest; hover reveals the structure hairline and darkens the text to ink. The
  border is reserved at rest so nothing shifts on hover. Hidden below 920px; the
  sticky bar keeps the wordmark and the filled Sign in control at every width.

### Data Rows and Tables
- Ruled lists (`.keyed`, `.list`) open with a structure hairline and separate
  rows with a soft hairline; the last row's rule is removed so the list ends
  open. The spec table uses mono uppercase headers over a structure hairline and
  a mono first column that acts as the field key.

### The Annotated Specimen (signature)
The world's signature device and its reusable pattern:
1. A bounded panel (structure hairline, Panel White, navy plate header) showing
   an authored product view, its rows separated by hair rules.
2. Each row carries a mono numeric **key** in accent deep, in a dedicated
   `2.4ch` column.
3. Selected rows carry a **callout**: a mono label in accent deep on a 26px
   accent leader line, placed in the margin outside the panel, right-aligned
   into it.
4. A mono `synthline` closes the panel declaring the content illustrative.
5. **The section below repeats the same keys, in the same order**, so numbers
   1–5 tie the specimen to the prose that explains it.

This is a reusable device, not a one-off. Any future surface that shows product
UI should key it and answer the keys in text. Always label authored UI as
illustrative in mono.

### Motion
Exactly one authored moment on the whole page: three leader lines scale out from
their anchored (right) edge while their labels fade in, staggered .25s / .42s /
.59s, plus the "New" tag pulsing twice. CSS-only, `cubic-bezier(.16,1,.3,1)`,
no scroll trigger, completes unconditionally, wrapped in
`prefers-reduced-motion: no-preference`, and gated on a `.js` class that fails
open — with JS off, every element is simply visible.

**The Motion Never Gates Visibility Rule.** No animation on any MindForge
surface may start an element at `opacity:0`, `visibility:hidden`, or a transform
that removes it from view unless the animation is unconditional, untriggered,
and reversible by `prefers-reduced-motion`. Reveal-on-scroll is banned. This
rule is written from scar tissue: the same defect killed two earlier builds in
this project.

## Do's and Don'ts

### Do:
- **Do** carry structure with 1px hairlines in one of the three rule values.
- **Do** keep radius at 0, with the 2px control as the only exception.
- **Do** wrap display punctuation in `.pn` so the public Alumni Sans cut sets
  tightly.
- **Do** use Forge Orange Deep (`#A83409`) wherever the accent must be read as
  text, and Forge Orange (`#DA4A14`) where it is a line or a mark.
- **Do** key authored product UI with mono numerals and answer those keys in the
  section below it.
- **Do** label every authored screen, mark or paper as an illustrative sample.
- **Do** let controls hover by inverting ground and text, not by glowing.

### Don't:
- **Don't** add a box-shadow for elevation; this system has none.
- **Don't** set running prose in JetBrains Mono. The `.owed` owner notice is a
  build-time exception and does not generalise.
- **Don't** fill a large area with orange, or introduce a gradient of any kind.
- **Don't** hide content behind an animation, or attach animation to scroll.
- **Don't** add a decorative kicker or eyebrow above a headline. Mono over a
  value is a *field label* naming that value (spec strip, slab caption); it is
  not licence for a floating label above display type.
- **Don't** introduce a fourth hairline weight or a 2px rule.
- **Don't** substitute glyph or icon-font characters for the inline line SVGs.
- **Don't** "modernise" this world toward rounded cards, soft shadows or an
  EdTech gradient hero. It is user-pinned.

## Known Ceiling

Recorded at the finish review (disposition **ship**, eight scored fixes
resolved) as deliberate limits of this build, not as system rules:

1. **The left marginal annotation column is underused.** It carries the hero's
   three callouts and is partly answered by the keyed list, but sits empty down
   the rest of the page. The device is established and then dropped.
2. **Plate Navy is thin against its claim.** The direction contract names
   `#1D3557` as the world's dark plate, but the build gives it only the 40px
   device header. Reviewer's suggestion, recorded for the next pass: the close
   section's empty right half at 1440px is where a navy plate would earn its
   keep rather than decorate.

## Assets and Provenance

No rasters ship with this artifact — every graphic is inline SVG or CSS, so
there is no image provenance to embed. The one image, the bar/footer logo at
`marketing/landing/assets/mindforge-logo.png`, is pre-existing: it is an upscale
of the repo's own `frontend/assets/images/logo.png`.

The following files exist in the repo but are **not part of this world and are
superseded**: `marketing/landing/notice-board.html`, `register.html`,
`four-voices.html`, `earlier-options.html`, and their three surface briefs under
`.impeccable/surfaces/`. They are rejected earlier directions the user asked to
replace; do not read design rules out of them.
