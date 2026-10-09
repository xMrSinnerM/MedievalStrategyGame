extends Node
## Signals shared between parts of the world map that don't know about each other.

## Camera zoom as 0 (closest) .. 1 (strategic overview).
signal camera_zoom_changed(zoom_t: float)
## How strongly the parchment map is showing, 0 .. 1.
signal parchment_amount_changed(amount: float)
## One-line description of what the player's party is doing, for the HUD.
signal party_status_changed(text: String)
