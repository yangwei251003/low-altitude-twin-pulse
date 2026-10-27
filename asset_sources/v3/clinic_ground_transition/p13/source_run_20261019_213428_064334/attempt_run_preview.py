"""Run only after root grants the serial engine window. Source preview only."""
from pathlib import Path
import datetime
import json
import os
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
LIMIT = 240
BLENDER = Path('C:/Program Files/Blender Foundation/Blender 5.2/blender.exe')


def main():
    assert BLENDER.is_file(), BLENDER
    tag = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    run = HERE / ('source_run_' + tag)
    run.mkdir()
    stdout, stderr = run / 'stdout.log', run / 'stderr.log'
    env = dict(os.environ)
    env['TRANSITION_P13_OUTPUT'] = str(run)
    started = time.monotonic()
    row = {'status': 'STARTING', 'threads': 2, 'hard_timeout_seconds': LIMIT,
           'source_only': True, 'bake': False, 'export': False,
           'output': str(run), 'timeout_scope': 'only spawned Blender PID and descendants'}
    with stdout.open('wb') as out, stderr.open('wb') as err:
        proc = subprocess.Popen([str(BLENDER), '--background', '--threads', '2',
            '--python-exit-code', '3', '--python', str(HERE / 'build_preview.py')],
            cwd=str(HERE), env=env, stdout=out, stderr=err,
            creationflags=subprocess.CREATE_NO_WINDOW)
        row.update(pid=proc.pid, status='RUNNING')
        (run / 'process.json').write_text(json.dumps(row, indent=2), encoding='utf-8')
        print(json.dumps(row), flush=True)
        try:
            code = proc.wait(timeout=LIMIT)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'],
                stdout=err, stderr=err, timeout=20, creationflags=subprocess.CREATE_NO_WINDOW)
            proc.wait(timeout=20)
            code = 124
            row['timeout'] = True
    log = stdout.read_text(encoding='utf-8', errors='replace') + '\n' + stderr.read_text(encoding='utf-8', errors='replace')
    fatal = [line for line in log.splitlines() if re.search(
        r'(^|\s)(ERROR|Error:|Traceback)|Failed to load|Unable to load|Cannot read', line)]
    row.update(status='EXITED', exit_code=code, elapsed_seconds=time.monotonic() - started,
               process_poll=proc.poll(), error_lines=fatal)
    if code == 0 and fatal:
        row['status'] = 'FAIL_LOG_ERROR_WITH_ZERO_EXIT'
        code = 3
    (run / 'process.json').write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(row, ensure_ascii=False), flush=True)
    raise SystemExit(code)


if __name__ == '__main__':
    main()
