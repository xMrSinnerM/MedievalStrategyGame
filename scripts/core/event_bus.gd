extends Node
## Signals shared between parts of the game that don't know about each other.

## Camera zoom as 0 (closest) .. 1 (strategic overview).
signal camera_zoom_changed(zoom_t: float)
## How strongly the parchment map is showing, 0 .. 1.
signal parchment_amount_changed(amount: float)
## One-line description of what the player's party is doing, for the HUD.
signal party_status_changed(text: String)

## Asks the game to open the castle screen for a castle (Economy castle id).
signal castle_requested(castle_id: String)
## Asks the game to go back to the world map.
signal world_map_requested
