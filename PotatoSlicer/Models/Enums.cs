/*
 * Enums shared across the game.
 */
namespace PotatoSlicer
{
    // Result of a single cut attempt (centre-outward quality bands).
    enum CutQuality { Miss, Poor, Good, Great, Perfect }

    // Which minigame a potato uses for each of its cuts.
    //   Sweep       : classic left/right bar, press SPACE at centre
    //   HoldRelease : hold SPACE to fill a gauge, release inside the zone
    //   MultiTarget : stop the bar N times in quick succession (real julienne)
    //   ShrinkZone   : sweet spot shrinks over time — commit fast
    //   Dodge        : hazard spud; pressing SPACE is the WRONG move
    enum CutType { Sweep, HoldRelease, MultiTarget, ShrinkZone, Dodge }

    // Top-level game modes selectable from the menu.
    enum GameMode { Championship, Endless, TimeAttack, Daily }
}
