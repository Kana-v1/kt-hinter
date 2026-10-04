#!/usr/bin/env python3
"""Add the iOS engine's model fields to the censuses (idempotent).

Per effect / chapter tactic:
  when          activation | attack | defence | any — which group it shows in
  appliesTo     team | self | weapons — who it applies to (self = its requiresOperative)
  weaponMatch   for appliesTo=weapons: case-insensitive substrings of weapon names
  hint          one action-first line for mid-game
  grantsWeaponRules  [{match, rules, condition?}] — weapon-row notes; match is
                "*", "ranged", "melee" or weapon-name substrings
Per team: glossary of faction terms (definitions copied from the verified census text).

Values come from the rule text as verified against the August '26 PDFs.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
T, S, W = "team", "self", "weapons"

AOD = {
    "core.ff.command_reroll": ("any", T, "After rolling your attack or defence dice, re-roll one of them."),
    "aod.rule.astartes": ("activation", T, "Two Shoot or two Fight actions (one Shoot with a bolt weapon; a second shot with the same bolt sniper rifle or heavy bolter costs +1 AP). Can counteract regardless of order."),
    "aod.strat.combat_doctrine": ("attack", T, "Your weapons have Balanced while your doctrine's condition is met."),
    "aod.strat.and_they_shall_know_no_fear": ("any", T, "Injured operatives use their normal stats this turning point (weapons included)."),
    "aod.strat.indomitus": ("defence", T, "When shot: two or more fails? Discard one to retain another as a normal success."),
    "aod.strat.adaptive_tactics": ("any", T, "Swap your secondary chapter tactic until the end of the turning point."),
    "aod.ff.shock_assault": ("attack", T, "Fighting after a Charge: Shock, and +1 damage on your first strike (max 7)."),
    "aod.ff.transhuman_physiology": ("defence", T, "When shot, in the Roll Defence Dice step: retain one normal success as a critical."),
    "aod.ff.wrath_of_vengeance": ("activation", T, "When counteracting: one extra free 1AP action (both actions different)."),
    "aod.ff.adjust_doctrine": ("activation", T, "Before or after an action: change the Combat Doctrine you selected this turning point."),
    "aod.eq.purity_seals": ("attack", T, "Once per turning point, shooting, fighting or retaliating: two or more fails? Discard one to retain another as a normal success."),
    "aod.eq.auspex": ("attack", T, "Once per turning point when shooting: enemies within 8\" of this operative can't be obscured until its activation ends."),
    "aod.eq.tilting_shields": ("defence", T, "Once per turning point, fighting or retaliating, after they roll: they can't retain results below 6 as criticals this sequence."),
    "aod.eq.chapter_reliquaries": ("activation", T, "Wrath of Vengeance is free if the operative has an Engage order."),
    "aod.op.heroic_leader": ("any", T, "Once per turning point: a firefight ploy free for the Captain (not Command Re-roll), Combat Doctrine on activation, or Adjust Doctrine free."),
    "aod.op.iron_halo": ("defence", S, "Once per battle: ignore one attack die's Normal Dmg on the Captain."),
    "aod.op.optics": ("activation", S, "1AP: until its next activation, when this operative shoots, enemies can't be obscured. Not in enemy control range."),
    "aod.op.doctrine_warfare_asltsgt": ("any", T, "Once per battle each: Combat Doctrine is free when you pick Assault or Tactical (Sergeant in the killzone)."),
    "aod.op.doctrine_warfare_intsgt": ("any", T, "Once per battle each: Combat Doctrine is free when you pick Devastator or Tactical (Sergeant in the killzone)."),
    "aod.op.camo_cloak": ("defence", S, "When shot, ignore Saturate. Has Stealthy — and can use both Stealthy options if you picked it."),
    "aod.op.grenadier": ("attack", S, "Uses frag and krak grenades free of their limited uses, at +1 Hit."),
}
AOD_GRANTS = {
    "aod.ff.shock_assault": [{"match": ["melee"], "rules": ["Shock"], "condition": "fighting after a Charge"}],
}
AOD_OPTION_GRANTS = {
    "devastator": [{"match": ["ranged"], "rules": ["Balanced"], "condition": "target more than 6\" away"}],
    "tactical": [{"match": ["ranged"], "rules": ["Balanced"], "condition": "target within 6\""}],
    "assault": [{"match": ["melee"], "rules": ["Balanced"], "condition": "fighting or retaliating"}],
}
AOD_TACTICS = {
    "aggressive": ("attack", {"match": ["melee"], "rules": ["Rending"]}),
    "dueller": ("attack", None),
    "resolute": ("any", None),
    "stealthy": ("defence", None),
    "mobile": ("activation", None),
    "hardy": ("defence", None),
    "sharpshooter": ("attack", {"match": ["bolt"], "rules": ["Accurate 1", "Severe"],
                                "condition": "if it hasn't Charged, Fallen Back or Repositioned this activation"}),
    "siege_specialist": ("attack", {"match": ["ranged"], "rules": ["Saturate"]}),
}

PM = {
    "core.ff.command_reroll": ("any", T, "After rolling your attack or defence dice, re-roll one of them."),
    "pm.rule.astartes": ("activation", T, "Two Shoot or two Fight actions (one Shoot with a bolt pistol, boltgun or Psychic weapon; not the same Psychic ranged weapon twice). Can counteract regardless of order."),
    "pm.rule.poison": ("attack", T, "Poison weapon deals damage → the target (not a Plague Marine) gains a Poison token. A poisoned enemy takes 1 damage when it activates."),
    "pm.rule.disgustingly_resilient": ("defence", T, "Took 3+ damage on one die? Roll a D6 — on 4+, subtract 1 from that damage."),
    "pm.strat.contagion": ("defence", T, "Enemy −2\" Move and −1 Hit while poisoned within 3\" of a Plague Marine, or within 3\" of your Icon Bearer."),
    "pm.strat.lumbering_death": ("attack", T, "Ceaseless when shooting or fighting after moving ≤3\" this activation, or when retaliating."),
    "pm.strat.cloud_of_flies": ("defence", T, "A Plague Marine more than 3\" from its shooter and wholly within 1\" of your marker is obscured."),
    "pm.strat.nurglings": ("any", T, "One enemy within 3\" of a Plague Marine (or poisoned within 7\"): −1 APL until its next activation ends."),
    "pm.ff.virulent_poison": ("activation", T, "Before or after an action: an enemy within 3\", or visible and within 7\", gains a Poison token."),
    "pm.ff.poisonous_demise": ("defence", T, "When one of your Plague Marines is incapacitated, before it's removed: enemies within 3\" gain a Poison token; already-poisoned ones take 1 damage instead."),
    "pm.ff.sickening_resilience": ("defence", T, "Until this activation ends, Disgustingly Resilient subtracts 1 automatically (min 2) — no roll."),
    "pm.ff.curse_of_rot": ("attack", T, "After they roll, each 3 deals 1 damage and can't be retained as a success or re-rolled. Enemy within 3\", 7\" if poisoned."),
    "pm.eq.plague_bells": ("any", T, "Ignore injured-stat changes on your Plague Marines (weapons included)."),
    "pm.eq.plague_rounds": ("attack", W, "Boltguns and bolt pistols have Poison and Severe."),
    "pm.eq.blight_grenades": ("attack", T, "Blight grenade: ATK 4 · Hit 4+ · Dmg 2/4 · Range 6\", Blast 2\", Saturate, Severe, Poison. Twice per battle."),
    "pm.eq.poison_vents": ("any", T, "Enemy activating within 3\" of a Plague Marine: unpoisoned → roll D3, on 3 it gains a token; poisoned → D3 damage instead of 1."),
    "pm.op.grandfathers_blessing": ("any", S, "A poisoned enemy loses wounds within 7\" of the Champion? It regains that many (max 3 per turning point)."),
    "pm.op.icon_bearer": ("any", S, "Counts as 1 higher APL when determining marker control."),
    "pm.op.icon_of_contagion": ("any", S, "Contagion is free while the Icon Bearer is in your opponent's territory."),
    "pm.op.repulsive_fortitude": ("defence", S, "When shot, defence dice of 5+ are critical successes."),
    "pm.op.grenadier": ("attack", S, "Uses blight and krak grenades free of their limited uses, at +1 Hit; blight grenades gain Toxic."),
    "pm.op.poisonous_miasma": ("activation", S, "1AP Psychic: an enemy within 7\" gains a Poison token; if already poisoned, 3 damage instead. Not in enemy control range."),
    "pm.op.putrescent_vitality": ("activation", S, "1AP Psychic: a friendly operative within 3\" rolls 2D6 — a 7 regains 7 wounds, else the highest D6. Once per turning point; not in enemy control range."),
    "pm.op.flail": ("attack", S, "1AP (counts as Fight): D3+2 damage to each other operative visible and within 2\"; on a D3 of 3, enemies also gain a Poison token. Not on Conceal."),
}
# Ploys the app offers at a specific moment it can see (marking an operative down).
TRIGGERS = {"pm.ff.poisonous_demise": "incapacitated", "ci.ff.glory_to_the_martyrs": "incapacitated"}
PM_WEAPON_MATCH = {"pm.eq.plague_rounds": ["boltgun", "bolt pistol"]}
PM_GRANTS = {
    "pm.strat.lumbering_death": [{"match": ["*"], "rules": ["Ceaseless"],
                                  "condition": "if it hasn't moved more than 3\" this activation, or when retaliating"}],
    "pm.eq.plague_rounds": [{"match": ["boltgun", "bolt pistol"], "rules": ["Poison", "Severe"]}],
}
PM_GLOSSARY = {
    "Poison": {"kind": "weapon rule · Plague Marines",
               "def": "In the Resolve Attack Dice step, if you inflict damage with any successes, the operative this weapon is being used against (excluding friendly Plague Marines) gains one of your Poison tokens (if it doesn't already have one). Whenever an operative that has one of your Poison tokens is activated, inflict 1 damage on it."},
    "Poison token": {"kind": "token · Plague Marines",
                     "def": "An enemy operative with one of your Poison tokens takes 1 damage whenever it's activated. Many Plague Marine rules get stronger against poisoned enemies."},
    "Toxic": {"kind": "weapon rule · Plague Marines",
              "def": "Whenever this operative is using this weapon against an enemy operative that had one of your Poison tokens at the start of that action, add 1 to both Dmg stats of this weapon."},
}

CI = {
    "core.ff.command_reroll": ("any", T, "After rolling your attack or defence dice, re-roll one of them."),
    "ci.rule.inspiration": ("any", T, "Kills an enemy with 6+ Wounds, or Charges (before moving)? It becomes INSPIRING — tap its status on the operative sheet."),
    "ci.rule.martyrdom": ("defence", T, "An INSPIRING operative is incapacitated: another friendly operative that it's visible to or within 6\" of gains a BENEDICTION."),
    "ci.rule.benedictions": ("any", T, "Ardour +1 APL (not the Superior) or Wrath: Ceaseless, both all battle; Restoration: regain D3+2 wounds; Exigence: a free Charge (max 3\") or Dash towards the fallen one."),
    "ci.rule.weapons_of_the_witch_hunters": ("defence", T, "Enemy PSYCHIC ranged weapons can't damage you. Within 3\" of you: no PSYCHIC actions, rules or ranged weapons; PSYCHIC melee has no rules and Dmg at most 3/4."),
    "ci.strat.suspect_and_eliminate": ("attack", T, "Enemies with your Suspicion token: your weapons have Punishing against them."),
    "ci.strat.suffering_and_sacrifice": ("attack", T, "Wounded operatives have Balanced when shooting, fighting or retaliating."),
    "ci.strat.wrathful_determination": ("defence", T, "Shot while on an Engage order: re-roll one defence die."),
    "ci.strat.holy_resilience": ("defence", T, "INSPIRING operatives fighting or retaliating: Dmg of 4 or more deals 1 less to them."),
    "ci.ff.glory_to_the_martyrs": ("defence", T, "Incapacitated while fighting or retaliating: strike with one unresolved success first. If that kills, it becomes INSPIRING (Martyrdom)."),
    "ci.ff.unshakeable_pursuit": ("activation", T, "Before or after an action: ignore Move changes this activation; INSPIRING also gets +1\" Move."),
    "ci.ff.faith_and_fury": ("attack", T, "Fighting, you strike with a critical: after it, D3 damage to each other enemy visible and within 2\"."),
    "ci.ff.fervent_hate": ("attack", T, "After rolling attack dice against a non-IMPERIUM enemy: Ceaseless this sequence (Relentless if it's CHAOS or PSYKER)."),
    "ci.eq.psyk_out_grenades": ("attack", T, "Two stun grenades. A stun test of 3+ also deals half the roll (rounded up); full roll against a PSYKER."),
    "ci.eq.saintly_relics": ("defence", T, "An attack die would damage you: roll a D6 (two if INSPIRING); on a 6 ignore it. Once per action, twice per battle."),
    "ci.eq.vocifera_mortis": ("defence", T, "Once per battle, Martyrdom: the operative gaining the BENEDICTION can be anywhere."),
    "ci.eq.auto_flagellator": ("activation", T, "On activation: roll a D6, take half (rounded up); on 4+ it becomes INSPIRING. Once per turning point."),
    "ci.op.holy_example": ("any", S, "Once per turning point while INSPIRING: a firefight ploy for the Superior is free (Command Re-roll too)."),
    "ci.op.spiritual_mentor": ("activation", S, "1AP: a friendly operative visible and within 6\" becomes INSPIRING. Once per turning point; not in enemy control range."),
    "ci.op.holy_defender": ("defence", S, "Once per turning point: a friend within 2\" is shot or fought — the Abjuror takes it instead (not Blast or Torrent)."),
    "ci.op.censor_icon_bearer": ("any", S, "Counts as 1 higher APL when determining marker control."),
    "ci.op.null_field": ("defence", S, "Enemies in its null range: −2\" Move and −1 Hit."),
    "ci.op.nullifying_ritual": ("activation", S, "1AP: null range +1\" (max 5\"). Once per turning point; not in enemy control range."),
    "ci.op.inspirational_pyre": ("attack", S, "Once per turning point: the hand flamer damages but doesn't kill → a friend within 6\" becomes INSPIRING."),
    "ci.op.accusing_exorcist": ("any", S, "While INSPIRING: Suspect & Eliminate is free if the Denuncia can see, or is within 6\" of, your pick."),
    "ci.op.speak_of_her_deeds": ("activation", S, "1AP: an INSPIRING friend within 6\" stops being INSPIRING; another gets a BENEDICTION (not Exigence)."),
    "ci.op.zealous_ultimatum": ("any", S, "Once per battle, Strategic gambit: challenge an enemy within 8\". Accepted: +1 Atk against it. Declined: it gets −1 Atk against you."),
    "ci.op.bladed_stance": ("attack", S, "Fighting or retaliating: resolve one success early — it must block."),
    "ci.op.reliquarius_icon_bearer": ("any", S, "Enemies contesting a marker within 3\" of it count as 1 lower total APL."),
    "ci.op.devotion": ("activation", S, "End of activation, INSPIRING and holding a marker: a friend within 6\" becomes INSPIRING."),
    "ci.op.inspired_strikes": ("attack", S, "While INSPIRING: +1 Critical Dmg on its weapons."),
}
CI_GRANTS = {
    "ci.strat.suspect_and_eliminate": [{"match": ["*"], "rules": ["Punishing"], "condition": "against an enemy with your Suspicion token"}],
    "ci.strat.suffering_and_sacrifice": [{"match": ["*"], "rules": ["Balanced"], "condition": "if this operative is wounded"}],
}
CI_GLOSSARY = {
    "INSPIRING": {"kind": "status · Celestian Insidiants", "def": "An operative becomes INSPIRING when it incapacitates an enemy with a Wounds stat of 6 or more, when it performs the Charge action (before it moves), or through rules like Spiritual Mentor. While INSPIRING, weapons on its datacard have Severe; if it's incapacitated, Martyrdom gives another friendly operative a BENEDICTION."},
    "BENEDICTION": {"kind": "faction rule · Celestian Insidiants", "def": "Gained through Martyrdom. Ardour: +1 APL for the battle (not a Superior). Wrath: weapons on its datacard have Ceaseless for the battle. Restoration: regain up to D3+2 lost wounds. Exigence: a free Charge (max 3\") or Dash, ending closer to the incapacitated INSPIRING operative."},
    "Anti-PSYKER": {"kind": "weapon rule · Celestian Insidiants", "def": "Whenever this weapon is being used against an operative that has the PSYKER keyword, it has the Lethal 5+ weapon rule."},
    "Shield": {"kind": "weapon rule · Celestian Insidiants", "def": "Whenever this operative is fighting or retaliating with this weapon profile, each of your blocks can be allocated to block two unresolved successes (instead of one)."},
    "Suspicion token": {"kind": "token · Celestian Insidiants", "def": "From Suspect & Eliminate, until the end of the turning point. Whenever a friendly operative is shooting against or fighting against an operative with one of your Suspicion tokens, its weapons have Punishing."},
}

SS = {
    "core.ff.command_reroll": ("any", T, "After rolling your attack or defence dice, re-roll one of them."),
    "ss.rule.elite_fieldcraft": ("any", T, "An enemy on Engage just did an action: a ready operative (not in other enemies' control range) takes a free Shoot at it, Dash or Reposition."),
    "ss.rule.camo_cloaks": ("defence", T, "Shot, retaining cover saves: retain one more, or one as a critical (not with Vantage). Not the Beacon."),
    "ss.strat.disappear": ("any", T, "One operative takes a free Reposition, not ending closer to enemies or their drop zone; it can't Reposition again this turning point."),
    "ss.strat.ambushing_volley": ("attack", T, "Activated more than 3\" from enemies and not a valid target for them: ranged weapons get Devastating 1 (+1 if they have it) this activation."),
    "ss.strat.hidden_engagement": ("attack", T, "Shooting while in cover from the target's view: your weapons have Balanced."),
    "ss.strat.patience": ("any", T, "This firefight, once: skip an activation (after their first), or your last operative to activate gets Relentless for its Shoot or Fight."),
    "ss.ff.dodge": ("activation", T, "Before or after an action: Fall Back costs 1 less AP this activation."),
    "ss.ff.sharp_reactions": ("any", T, "An enemy on Conceal within 8\" of you just did an action: you can still interrupt it with Elite Fieldcraft."),
    "ss.ff.silent_killers": ("attack", T, "On Conceal and not a valid target: it can Charge on Conceal this activation; its first strike deals 3 more damage, but no other successes resolve."),
    "ss.ff.prepared_defence": ("defence", T, "Retaliating on Conceal or while ready: resolve one block early, or one block cancels two successes. Not after an Elite Fieldcraft interrupt."),
    "ss.eq.sniper_overwatch": ("attack", T, "Once per turning point, any operative can shoot Sniper overwatch: ATK 4 · Hit 3+ · Dmg 3/3 · Devastating 2, Heavy (Dash only), Saturate, Silent."),
    "ss.eq.starshell_flare": ("any", T, "Strategic gambit: one operative takes a free Stun Grenade action. Once it changes an enemy's APL, it's gone for the battle: mark it used."),
    "ss.eq.tvid_feed_triangulation": ("attack", T, "Once per turning point when shooting: the target can't be obscured if another of yours can target it, or it's within 6\" of your Beacon."),
    "ss.eq.advanced_camouflage": ("activation", T, "1AP (not the Beacon): until its next activation, on Conceal and in cover it can't be targeted except within 2\". Not visible and within 3\" of an enemy."),
    "ss.op.issue_mission": ("activation", S, "0AP: an expended friend it can see (not the Beacon) can still interrupt with Elite Fieldcraft this turning point. Not in enemy control range."),
    "ss.op.medic": ("defence", T, "First time each turning point a friend within 3\" of the Medicae would be incapacitated: it stays on 1 wound, can Dash to the Medicae; both −1 APL."),
    "ss.op.medikit": ("activation", S, "0AP: a friend in its control range (not the Beacon) regains up to 2D3 wounds, unless Medic! saved it this turning point."),
    "ss.op.grenadier": ("attack", S, "Uses frag, krak and smoke grenades free of their limited uses; frag and krak at +1 Hit."),
    "ss.op.melta_mine": ("activation", S, "Carries your Melta Mine: Pick Up and Place it, with a free Dash after placing. Not within an enemy's control range."),
    "ss.op.proximity_mine": ("any", S, "The Melta Mine is first within another operative's control range: 2D6+3 damage to it, and its action ends if it survives."),
    "ss.op.prepared_killzone": ("any", S, "Setup: one extra equipment option, an Ammo Cache or an equipment terrain feature."),
    "ss.op.scout_terrain": ("activation", T, "Scouted terrain (your territory, or within 3\" of the Guide): once per activation, ignore 2\" of a climb, or Operate Hatch for 1 less AP."),
    "ss.op.weapons_team": ("activation", S, "Activated with a friendly Loader in its control range: the missile launcher has Heavy (Dash only) instead of Heavy."),
    "ss.op.weapon_assist": ("attack", T, "Shooting within the Loader's control range (not the Loader itself): re-roll one attack die."),
    "ss.op.load_weapon": ("activation", S, "1AP: a friend in its control range, not within 3\" of enemies, takes a free Shoot (not Guard). Not with a Charge, Dash or Shoot this activation."),
    "ss.op.suppressive_fire": ("defence", S, "On Engage: enemies visible and within 3\" get −1 Atk (unless others are in its control range). Not if it Charged this turning point."),
    "ss.op.cool_headed": ("any", S, "Once per turning point, a Trooper can interrupt with Elite Fieldcraft for 0FP."),
    "ss.op.signal_vox": ("activation", S, "1AP Support: another friend it can see (not the Beacon) gets +1 APL until the end of its next activation. Not in enemy control range."),
    "ss.op.pre_deploy": ("any", S, "Setup: can deploy anywhere wholly in your territory, more than 2\" from markers and equipment terrain."),
    "ss.op.expendable": ("any", S, "Only does Signal; can't counteract, retaliate, assist or contest. Ignored for kill ops and escape/survive scoring."),
    "ss.op.signal_beacon": ("activation", S, "1AP: another friend within 6\" gets +1 APL until the end of its next activation. Not in enemy control range."),
}
_AMBUSH = "activated more than 3\" from enemies and not a valid target for them"
SS_GRANTS = {
    "ss.strat.ambushing_volley": [
        {"match": ["lascarbine", "lasrifle", "laspistol", "plasma gun", "missile launcher", "long-las (mobile)",
                   "autostubber (focused)", "autostubber (sweeping)"], "rules": ["Devastating 1"], "condition": _AMBUSH},
        {"match": ["meltagun"], "rules": ["Devastating 5"], "condition": "instead of Devastating 4, if " + _AMBUSH},
        {"match": ["long-las (concealed)", "long-las (stationary)"], "rules": ["Devastating 4"],
         "condition": "instead of Devastating 3, if " + _AMBUSH},
    ],
    "ss.strat.hidden_engagement": [{"match": ["ranged"], "rules": ["Balanced"], "condition": "if it's in cover from the target's perspective"}],
    "ss.strat.patience": [{"match": ["*"], "rules": ["Relentless"],
                           "condition": "if it's your last operative to activate this turning point (and you didn't skip an activation)"}],
    "ss.op.weapons_team": [{"match": ["missile launcher"], "rules": ["Heavy (Dash only)"],
                            "condition": "instead of Heavy, if a friendly Loader was in its control range when activated"}],
}
# Team-wide rules that don't apply to some operatives: the Beacon is excluded by
# name, or by Expendable (it can't perform any action other than Signal).
_BEACON = "spectre_vox_relay_beacon"
SS_NOT_FOR = {
    "ss.rule.camo_cloaks": [_BEACON],
    "ss.eq.advanced_camouflage": [_BEACON],
    "ss.op.medic": ["spectre_field_medicae", _BEACON],
    "ss.op.weapon_assist": ["spectre_loader", _BEACON],
    "ss.strat.ambushing_volley": [_BEACON],
    "ss.strat.hidden_engagement": [_BEACON],
    "ss.strat.patience": [_BEACON],
    "ss.eq.sniper_overwatch": [_BEACON],
    "ss.eq.tvid_feed_triangulation": [_BEACON],
    "ss.eq.starshell_flare": [_BEACON],
    "ss.op.scout_terrain": [_BEACON],
}
SS_GLOSSARY = {
    "Fieldcraft point": {"kind": "resource · Spectre Squad", "def": "Gained in the Ready step of each Strategy phase: 1, or 2 if a friendly Vox-Operator is in the killzone and isn't within control range of enemy operatives. Discarded at the end of each turning point. Spend 1 to interrupt an enemy operative's activation with Elite Fieldcraft."},
    "Concealed Position": {"kind": "weapon rule · Spectre Squad", "def": "This operative can only use this weapon the first time it's performing the Shoot action during the battle."},
    "scouted": {"kind": "Spectre Squad", "def": "Terrain features within your territory, or within 3\" of your Guide, are scouted for friendly Spectre Squad operatives (Scout Terrain). Terrain within your territory stays scouted if the Guide is incapacitated."},
}

VOCAB_ADD = {
    "phases": ["strategy", "firefight"],
    "when": ["activation", "attack", "defence", "any"],
    "appliesTo": ["team", "self", "weapons"],
}


def apply(team, table, grants, weapon_match, option_grants=None, tactics=None, glossary=None, not_for=None):
    p = ROOT / f"data/teams/{team}.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d["vocab"].update(VOCAB_ADD)
    ids = {e["id"] for e in d["effects"]}
    missing = ids - set(table)
    extra = set(table) - ids
    assert not missing and not extra, f"{team}: table mismatch missing={missing} extra={extra}"
    for e in d["effects"]:
        when, applies, hint = table[e["id"]]
        e["when"], e["appliesTo"], e["hint"] = when, applies, hint
        if applies == W:
            e["weaponMatch"] = weapon_match[e["id"]]
        if e["id"] in TRIGGERS:
            e["trigger"] = TRIGGERS[e["id"]]
        if e["id"] in grants:
            e["grantsWeaponRules"] = grants[e["id"]]
        if not_for and e["id"] in not_for:
            e["notFor"] = not_for[e["id"]]
        for o in e.get("options", []):
            if option_grants and o["id"] in option_grants:
                o["grantsWeaponRules"] = option_grants[o["id"]]
            o.setdefault("hint", "")
    for t in d.get("chapterTactics", []):
        when, g = tactics[t["id"]]
        t["when"] = when
        t.setdefault("hint", t["text"])
        if g:
            t["grantsWeaponRules"] = [g]
    if glossary:
        d["glossary"] = glossary
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{team}: {len(d['effects'])} effects, {len(d.get('chapterTactics', []))} tactics annotated")


apply("aod", AOD, AOD_GRANTS, {}, AOD_OPTION_GRANTS, AOD_TACTICS)
apply("plague_marines", PM, PM_GRANTS, PM_WEAPON_MATCH, glossary=PM_GLOSSARY)
apply("celestian_insidiants", CI, CI_GRANTS, {}, glossary=CI_GLOSSARY)
apply("spectre_squad", SS, SS_GRANTS, {}, glossary=SS_GLOSSARY, not_for=SS_NOT_FOR)
