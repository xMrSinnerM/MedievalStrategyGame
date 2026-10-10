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
## A castle on the world map was clicked ("" when the selection is cleared).
signal settlement_selected(settlement_id: String)
## Asks the player's party to travel to a settlement.
signal travel_requested(settlement_id: String)
## A party on the world map was clicked (its id; "" clears the selection).
signal party_selected(party_id: String)
## Asks the player's warband to march on a castle and lay siege to it.
signal siege_requested(castle_id: String)
## Asks the player's warband to march on a party and attack it.
signal attack_requested(party_id: String)
## Two warbands fought. The report is described in parties_layer._fight().
signal battle_fought(report: Dictionary)
## A lord laid siege to a castle; the assault comes at `until` (seconds since start).
signal siege_started(castle_id: String, besieger: String, until: float)
## A lord's siege ended: stormed, lifted or abandoned.
signal siege_ended(castle_id: String)

## Something (an attack on a faction at peace) needs war declared first: the
## diplomacy screen asks, declares it and then calls then.
signal war_declaration_requested(faction_id: String, then: Callable)
## A robber baron camp was clicked on the map ("" clears the selection).
signal baron_selected(camp_id: String)
## Open the attack screen against this robber baron camp.
signal attack_screen_requested(camp_id: String)
