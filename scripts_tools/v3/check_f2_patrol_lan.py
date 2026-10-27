#!/usr/bin/env python3
"""Actual debug MAIN / ENet F2 scout life, bullet and epoch slice; loopback only."""
from __future__ import annotations
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback

sys.dont_write_bytecode = True
ROOT = next(parent for parent in Path(__file__).resolve().parents
            if (parent / "scripts_tools/v3/dev.py").is_file())
sys.path.insert(0, str(ROOT / "scripts_tools/v3"))
import dev
from test_lan_local import LanPortLock, LanRunBusy, process_options, utc_now
from check_lan_environment import write_json, read_json, sha256

SUITE = "f2-patrol-lan"
PROTOCOL = 25
JOB_SECONDS = 90
WORKER_SECONDS = 85
B = {"airframe_id": "tr01", "slots": {"weapon": "burst_capacitor", "tool": "scan_base",
     "drive": "stock_drive", "battery": "stock_battery", "utility": "guard_base"}}


import check_weapon_lan_combat as lifecycle
lifecycle.SUITE = SUITE
lifecycle.PROTOCOL = PROTOCOL
assert lifecycle.PROTOCOL == 25 # Strict actual peer reports + original handshake, no bypass.

class Run(lifecycle.Run):
    """Reuse shipped two-MAIN lifecycle/lease/commands/quit; no fake transport."""
    def __init__(self, args, lock):
        super().__init__(args, lock)
        self.output = self.exe.parent / 'artifacts/v3/network/f2-patrol' / args.run_id
        self.summary.update(suite=SUITE, protocol=PROTOCOL,
            scope='Two actual packaged MAIN peers and original ENet loopback. F2 start/player observation/owned burst qualification are explicit QA fixtures, no natural progress/enemy HP/hit/outcome fixture. Old snapshot negative probe alters transport sequence only.',
            full_acceptance=False,
            pending=['real two-computer LAN', 'uncontrolled loss/jitter and long-duration load',
                     'natural campaign unlock/flight', 'gamepad, graphics and human combat readability',
                     'fresh process reconnect after exit; first real Guest join only covered here'])

    def state(self, role):
        # Godot's Windows replace can briefly leave the destination absent.
        # Retry fresh IO only. Never return a cached state or invent fields.
        deadline = min(self.deadline, time.monotonic() + .5)
        while True:
            sample = super().state(role)
            if sample:
                return sample
            if time.monotonic() >= deadline:
                return {}
            self.summary.setdefault('fresh_state_io_retries', {}).setdefault(role, 0)
            self.summary['fresh_state_io_retries'][role] += 1
            time.sleep(.002)

    def launch(self, role):
        self.beat()
        command = [str(self.exe), '--headless'] + (['--verbose'] if self.args.verbose else [])
        command += ['--', '--qa-suite=' + SUITE,
            '--qa-profile=qa_lan_f2_patrol_' + role + '_' + self.args.run_id,
            '--qa-lan-patrol-role=' + role, '--qa-lan-patrol-run=' + self.args.run_id,
            '--qa-lan-patrol-evidence=' + str(self.output)]
        log = (self.output / (role + '.log')).open('xb')
        try:
            process = subprocess.Popen(command, cwd=self.exe.parent, stdout=log,
                                       stderr=subprocess.STDOUT, **process_options())
        except BaseException:
            log.close()
            raise
        self.children[role] = (process, log)
        self.summary['processes'][role] = {'pid': process.pid, 'command': command,
            'cwd': str(self.exe.parent), 'started_utc': utc_now(), 'forced_stop': False}

    def common_pause(self, wanted, already_requested=False):
        if not already_requested:
            self.command('host', 'pause')
        self.wait('received_Consensus_toggle', lambda: self.state('guest').get('proposal', {}).get('kind') == 'pause')
        self.check('two_real_Consensus_participants', len(self.state('guest')['proposal'].get('participants', [])) == 2)
        self.command('guest', 'confirm')
        self.wait('both_common_pause_' + str(wanted), lambda: self.state('host').get('paused') is wanted
                  and self.state('guest').get('paused') is wanted
                  and not self.state('host').get('proposal') and not self.state('guest').get('proposal'))

    def scenario(self):
        self.launch('host')
        self.wait('normal_F2_scout_factory', lambda: self.state('host').get('ready') is True, 20, ('host',))
        self.wait('actual_Host_warning_and_bullet_before_late_join', lambda: bool(self.state('host').get('first_warning'))
                  and bool(self.state('host').get('first_bullet')), 12, ('host',))
        self.milestone('actual_Host_AI_before_Guest_join')
        self.launch('guest')
        self.wait('actual_Guest_F2_snapshot', lambda: self.state('guest').get('received_sequence', -1) >= 0
                  and self.state('guest').get('region') == 'F2'
                  and len(self.state('guest').get('players', {})) == 2, 20)
        host, guest = self.state('host'), self.state('guest')
        peer = str(guest['local_peer'])
        setup = guest.get('guest_setup', {})
        self.check('native_Hangar_private_ownership_fixture_and_distinct_UUID', setup.get('hardware') == B
                   and setup.get('reader_equal') is True and setup.get('world_unchanged') is True
                   and setup.get('earned_campaign') is False and guest['profile_uuid'] != host['profile_uuid'], setup)
        self.check('original_ENet_build_handshake', host['session_id'] == guest['session_id']
                   and host.get('announced_guest_hardware', {}).get(peer) == B
                   and host['players'][peer]['hardware'] == guest['players'][peer]['hardware'] == B
                   and host['players'][peer]['identity'] == guest['profile_uuid'])
        self.wait('Guest_actual_reliable_warning_and_bullet_mesh', lambda: bool(self.state('guest').get('first_warning'))
                  and bool(self.state('guest').get('first_bullet')) and self.state('guest').get('mesh_checks', 0) > 0, 10)
        self.command('host', 'stage_guest')
        self.wait('actual_clear_Guest_observation_pose', lambda: self.state('host').get('staged_guest') is True)
        self.command('guest', 'lock')
        self.wait('real_lock_on_both_peers', lambda: self.state('host').get('locks', {}).get(peer) == 'F2:patrol_01'
                  and self.state('guest').get('locks', {}).get(peer) == 'F2:patrol_01')
        self.command('host', 'warning_pause')
        self.wait('real_active_warning_same_call_propose_boundary',
                  lambda: self.state('host').get('warning_pause', {}).get('ok') is True, 12)
        probe = self.state('host')['warning_pause']
        self.check('real_active_warning_remains_sealed_in_same_synchronous_rank',
                   probe.get('physics_frame_before') == probe.get('physics_frame_after')
                   and probe.get('before_digest') == probe.get('after_digest')
                   and probe.get('warning_before', {}).get('active') is True
                   and probe.get('warning_before', {}).get('remaining_ms', 0) >= 850
                   and probe.get('warning_after', {}).get('active') is True
                   and probe['warning_before']['token'] == probe['warning_after']['token']
                   and probe.get('policy_before') == 'none' and probe.get('policy_after') == 'vote', probe)
        self.common_pause(True, already_requested=True)
        self.wait('same_paused_full_view_arrives', lambda: self.state('host').get('view_digest') == self.state('guest').get('view_digest'))
        frozen = self.state('host')
        self.check('later_vote_ceasefire_cancel_only_on_a_new_rank',
                   frozen['view']['epoch'] == probe['epoch']
                   and (frozen['view']['serial'] > probe['serial']
                        or frozen['view_digest'] == probe['before_digest']),
                   {'synchronous_probe': probe, 'final_paused_view': frozen['view'],
                    'scope': 'new-serial vote ceasefire may legally cancel warning; no paused-active requirement'})
        before_events = self.state('guest').get('event_count', 0)
        self.command('host', 'replay')
        self.wait('actual_reliable_reorder_duplicates', lambda: self.state('guest').get('event_count', 0) >= before_events + 3
                  and any(e.get('epoch') == frozen['old_replay_rank']['epoch']
                          and e.get('serial') == frozen['old_replay_rank']['serial'] for e in self.state('guest').get('reliable_events', [])))
        self.wait('18_ordinary_physics_frames_while_paused', lambda: self.state('host').get('physics_frame', 0) >= frozen['physics_frame'] + 18)
        self.check('pause_seals_entire_same_rank_actor_warning_bullets', self.state('host')['view_digest'] == frozen['view_digest']
                   == self.state('guest')['view_digest'], {'before': frozen['view'], 'after': self.state('guest')['view']})
        self.common_pause(False)
        # A resume packet may precede the real Guest physics/input activation.
        # Wait past the original safety clear before issuing this NEW held press.
        # No reassertion across clear and no production input policy change.
        ready_observation = {}
        def original_input_ready():
            host_now, guest_now = self.state('host'), self.state('guest')
            if host_now and guest_now:
                ready_observation.clear()
                ready_observation.update(guest_frame=guest_now.get('physics_frame'),
                    guest_router_active=guest_now.get('input_router_active'),
                    guest_test_held=guest_now.get('input_test_held'),
                    guest_last_held=guest_now.get('input_last_held'),
                    guest_control_epoch=guest_now.get('input_control_epoch'),
                    guest_paused=guest_now.get('paused'),host_paused=host_now.get('paused'),
                    host_player=host_now.get('players', {}).get(peer, {}),
                    actual_context=host_now.get('patrol_diagnostics', {}).get(peer, {}))
            return (guest_now.get('input_router_active') is True
                    and guest_now.get('paused') is False and host_now.get('paused') is False
                    and host_now.get('players', {}).get(peer, {}).get('enabled') is True
                    and host_now.get('players', {}).get(peer, {}).get('command_active') is True)
        try:
            self.wait('original_Guest_router_active_after_resume_safety_clear', original_input_ready)
        finally:
            self.summary['milestones']['before_new_held_input_actual_ready'] = ready_observation
        self.command('guest', 'hold')
        last_complete_host = {}
        last_complete_host_read = {}
        death_poll = {'count': 0, 'incomplete_reads': 0}
        def observe_actual_disabled():
            sample = self.state('host') # Fresh read, never a stale success fallback.
            death_poll['count'] += 1
            players = sample.get('players')
            diagnostics = sample.get('patrol_diagnostics')
            complete = (sample.get('suite') == SUITE and sample.get('protocol') == PROTOCOL
                        and sample.get('run_id') == self.args.run_id and sample.get('role') == 'host'
                        and sample.get('pid') == self.children['host'][0].pid
                        and sample.get('actual_package') is True and sample.get('region') == 'F2'
                        and isinstance(players, dict) and len(players) == 2
                        and isinstance(diagnostics, dict) and set(diagnostics) == set(players)
                        and all(isinstance(diagnostics[p].get('context'), dict)
                                and all(k in players[p] for k in ['position', 'velocity', 'freeze', 'enabled', 'command_active'])
                                for p in players)
                        and isinstance(sample.get('view', {}).get('actor'), dict)
                        and 'cycle' in sample and 'input_router_active' in sample)
            if not complete:
                death_poll['incomplete_reads'] += 1
                return False
            # Diagnostic retention only, in memory until this bounded wait exits.
            # Cleanup/disconnect cannot replace this evidence with an empty cycle.
            last_complete_host.clear()
            last_complete_host.update(sample)
            last_complete_host_read.update(poll=death_poll['count'], utc=utc_now(),
                                           monotonic=time.monotonic(), physics_frame=sample['physics_frame'])
            return sample['view']['actor'].get('alive') is False
        try:
            self.wait('actual_original_DamageModel_disables_scout', observe_actual_disabled, 10)
        finally:
            self.summary['milestones']['death_wait_last_complete_host'] = {
                'source': 'last complete actual host-state read during this wait; evidence only, never cached success',
                'sample': last_complete_host, 'read': last_complete_host_read, 'polls': death_poll}

        self.command('guest', 'release')
        self.wait('Guest_authority_disabled_view', lambda: self.state('guest').get('view', {}).get('actor', {}).get('alive') is False)
        host, guest = self.state('host'), self.state('guest')
        hits = host.get('hit_receipts', [])
        cycle = host.get('cycle', {})
        receipts = [row['detail']['receipt'] for row in hits]
        self.check('real_held_input_Cycle_sequences_and_native_DamageModel', bool(receipts)
                   and all(r.get('raw_damage') == 28 and r.get('damage', 0) > 0
                           and abs(r['health_before'] - r['health'] - r['damage']) < 0.000001 for r in receipts)
                   and [r['serial'] for r in receipts] == list(range(1, len(receipts) + 1))
                   and receipts[-1].get('killed') is True and receipts[-1].get('health') == 0
                   and cycle.get('accepted_shots') == len(receipts) == host['stats']['shots']
                   and cycle.get('serial', 0) >= len(receipts)
                   and any(r.get('input_sequence', -1) > 0 and r.get('command_fire') is True
                           and r.get('charged_frames', 0) >= 42 for r in host.get('damage_rows', [])),
                   {'receipts': receipts, 'damage_rows': host.get('damage_rows'), 'cycle': cycle})
        self.check('Guest_has_no_AI_damage_clock_or_native_settlement', guest.get('scout_authoritative') is False
                   and guest.get('scout_auto_physics') is False and guest.get('local_cycle_count') == 0
                   and guest.get('local_patrol_event_count') == 0 and guest.get('local_damage_serial') == 0
                   and guest.get('mesh_evidence', {}).get('exact_equal') is True)
        self.common_pause(True)
        self.wait('same_disabled_view_arrives', lambda: self.state('host')['view_digest'] == self.state('guest')['view_digest'])
        dead = self.state('guest')['view_digest']
        before_events = self.state('guest')['event_count']
        self.command('host', 'replay')
        self.wait('old_alive_view_replayed_after_disabled', lambda: self.state('guest')['event_count'] >= before_events + 3)
        self.check('old_alive_replay_does_not_resurrect_same_epoch', self.state('guest')['view_digest'] == dead
                   and self.state('guest')['view']['actor']['alive'] is False)
        self.common_pause(False)
        self.command('host', 'store_check')
        self.command('guest', 'store_check')
        self.wait('original_Host_SaveGate_and_two_Store_readers', lambda: self.state('host').get('store_check', {}).get('ok') is True
                  and self.state('host').get('store_check', {}).get('SaveGate_callback', {}).get('ok') is True
                  and self.state('guest').get('store_check', {}).get('ok') is True)
        self.milestone('real_remote_combat_disabled_no_rewards')
        old_epoch = self.state('host')['view']['epoch']
        self.command('host', 'to_i1')
        self.wait('both_original_I1_load_and_old_adapter_cleanup', lambda: self.state('host').get('region') == 'I1'
                  and self.state('guest').get('region') == 'I1' and self.state('guest').get('view') == {})
        self.command('guest', 'old_epoch_atomic')
        probe = self.state('guest').get('atom_probe', {})
        self.check('old_epoch_high_sequence_rejects_before_any_world_player_entity_change', probe.get('ok') is True
                   and probe.get('can_receive') is False and probe.get('before') == probe.get('after'), probe)
        self.command('host', 'back_f2')
        self.wait('new_real_F2_factory_epoch', lambda: self.state('host').get('region') == 'F2'
                  and self.state('guest').get('region') == 'F2'
                  and self.state('guest').get('view', {}).get('epoch', 0) > old_epoch)
        self.common_pause(True)
        self.wait('new_epoch_same_view', lambda: self.state('host')['view_digest'] == self.state('guest')['view_digest'])
        fresh = self.state('guest')['view_digest']
        before_events = self.state('guest')['event_count']
        self.command('host', 'replay')
        self.wait('old_visit_actual_ENet_replay', lambda: self.state('guest')['event_count'] >= before_events + 3)
        self.check('old_epoch_replay_cannot_replace_new_visit', self.state('guest')['view_digest'] == fresh
                   and self.state('guest')['view']['epoch'] > old_epoch)
        # Atomic state replacement may briefly make read_json return {} on Windows.
        # Capture one complete real sample through the existing bounded wait;
        # missing telemetry is never defaulted to a successful zero.
        transport_sample = {}
        def capture_actual_transport():
            sample = self.state('host').get('transport')
            if not isinstance(sample, dict) or 'snapshot_encode_rejections' not in sample or 'snapshots_sent' not in sample:
                return False
            transport_sample.clear()
            transport_sample.update(sample)
            return True
        self.wait('complete_actual_transport_sample', capture_actual_transport)
        self.check('original_codec_no_rejections', transport_sample['snapshot_encode_rejections'] == 0
                   and transport_sample['snapshots_sent'] > 0, transport_sample)
        self.milestone('actual_old_epoch_atomic_and_new_visit')
        self.stop('guest')
        self.wait('original_Guest_departure', lambda: len(self.state('host').get('players', {})) == 1, required=('host',))
        self.stop('host')

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--owned-worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--run-id", default="", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.exe.is_absolute() or not args.exe.is_file() or args.exe.suffix.lower() != ".exe":
        parser.error("existing absolute exported Windows EXE required")
    if not args.run:
        print(json.dumps({"status": "prepared_no_process_or_port_lock", "suite": SUITE,
            "executable": str(args.exe), "sha256": sha256(args.exe), "protocol": PROTOCOL,
            "requires": "Root promotes observer/App entry and exports; promoted protocol25/Core+Bullet+CORE_BOUNDARIES and observer/App entry; actual EXE main, no --script or --path",
            "scope": "two peers on one computer, not two PCs or full fight"}, ensure_ascii=False))
        return 0
    if not args.owned_worker:
        run_id = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        output = args.exe.parent / "artifacts/v3/network/f2-patrol" / run_id
        output.mkdir(parents=True, exist_ok=False)
        dev.EVIDENCE = output / "driver"
        command = [sys.executable, "-B", str(Path(__file__).resolve()), "--exe", str(args.exe),
                   "--run", "--owned-worker", "--run-id", run_id] + (["--verbose"] if args.verbose else [])
        dev.execute_command(command, "controller", JOB_SECONDS)
        summary = read_json(output / "summary.json")
        print(json.dumps({"passed": summary.get("passed", False), "evidence": str(output),
                          "error": summary.get("error")}, ensure_ascii=False))
        return 0 if summary.get("passed") is True else 1
    import re
    if not re.fullmatch(r"[0-9]{8}_[0-9]{6}_[0-9]{6}", args.run_id):
        parser.error("exact owned run ID required")
    lock = LanPortLock()
    try:
        lock.acquire()
    except LanRunBusy as error:
        print(str(error))
        return 3
    try:
        return Run(args, lock).execute()
    finally:
        lock.release()


if __name__ == "__main__":
    raise SystemExit(main())
