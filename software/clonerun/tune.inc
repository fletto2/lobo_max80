; Clone Runner's speeds and times, all in one place. They are Lode
; Runner's, the C64's, from PHYSICS.md.
;
; The game runs in rounds of ROUNDQ/ROUNDSTEP ticks of the system's
; 61.035 Hz tick, 2.4 ticks, 39 ms, 25% faster than the C64's pace. In
; a round a figure moves an
; eighth of a tile, 2 dots across or 1 line down, half the C64's
; quarter, so the runner crosses a tile in 8 rounds, 0.31 s. A time
; PHYSICS.md gives in C64 rounds is doubled here, and all of them run
; 25% faster, so the seconds given below are at 39 ms a round.
; Counting ticks keeps the pace if a frame overruns.

ROUNDSTEP equ	5		; added each tick
ROUNDQ	equ	12		; a round each time this is passed

; A dug hole (holes.asm). It crumbles open in 4 steps of DIGSTEP while
; the runner digs, ours, PHYSICS.md gives no time for the dig. Then it
; is open HOLEOPEN, and fills back in 4 steps of FILLSTEP: open and
; filling 360 rounds, the C64's 180, 14.2 s, the last 40 (its 20) filling.
DIGSTEP	equ	3		; a crumbling step: the dig takes 12 rounds, 0.47 s
HOLEOPEN equ	320		; then open 12.6 s
FILLSTEP equ	10		; then a filling step, the 4 in 40 rounds, 1.6 s
NHOLES	equ	30		; holes at once, the C64's LR_WA_HoleMax: a dig is refused past it

; The guards (guards.asm). PHYSICS.md: held 38 C64 rounds at difficulty
; 0, up to 78 at 10, 4 more a step, and back 20 rounds after a hole
; closes on one. Scores in BCD.
TRAPHOLD equ	76		; rounds held in a hole, 8 more each difficulty step, 3.0 s
BIRTHTIME equ	40		; rounds before a killed guard comes back, 1.6 s
LIVES	equ	5		; at the start of a game
SC_TRAP	equ	0075h		; a guard into a hole
SC_REBIRTH equ	0075h		; a guard back

; Gold and the stages (gold.asm). PHYSICS.md: a guard carries gold 12 to
; 37 C64 moves and waits 12 after dropping it, doubled as our moves are
; half its. Scores in BCD.
CARRYMIN equ	24		; moves a guard carries gold, at least, up to 51 more
GOLDCOOL equ	24		; moves after a drop before a guard takes gold again
SC_GOLD	equ	0250h		; gold taken
SC_LEVEL equ	15		; hundreds, counted up at the end of a stage
MAXDIFF	equ	10		; the difficulty, up 1 each time round the stages
