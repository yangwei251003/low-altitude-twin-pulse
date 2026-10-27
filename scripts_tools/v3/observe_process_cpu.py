"""External read-only process CPU observer around the unchanged performance runner.
Requires the Dev67 environment time bridge; never changes frame acceptance.
"""
import csv, ctypes as C, datetime, importlib.util, json, math, os, pathlib, sys, threading, time
from ctypes import wintypes as W
sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[2]
PERIOD = .2
CLOCK_LIMIT_S = .020  # Mapping-validity bound only, never a game/performance gate.
UTC_QUANTIZATION_GUARD_S = .020  # Explicit assumed guard, not an absolute OS clock-resolution guarantee.
FT_UNIX = 116444736000000000


def bridge(env):
    b = env.get('time_alignment', {})
    before, utc, after = (float(b[k]) for k in ('elapsed_before', 'unix_seconds', 'elapsed_after'))
    if not all(math.isfinite(v) for v in (before, utc, after)) or not 0 <= before <= after or after-before > CLOCK_LIMIT_S:
        raise ValueError('missing/invalid new67 time_alignment or bridge wider than20ms')
    quant = 4*math.ulp(utc)  # Conservative UTC-double + offset arithmetic rounding envelope.
    return {'before':before, 'utc':utc, 'after':after, 'lo':utc-after-quant-UTC_QUANTIZATION_GUARD_S, 'hi':utc-before+quant+UTC_QUANTIZATION_GUARD_S}


class Windows:
    def __init__(self):
        self.k = C.WinDLL('kernel32', use_last_error=True)
        pointer = C.POINTER(W.FILETIME)
        signatures = {
            'OpenProcess':([W.DWORD,W.BOOL,W.DWORD],W.HANDLE),
            'QueryFullProcessImageNameW':([W.HANDLE,W.DWORD,W.LPWSTR,C.POINTER(W.DWORD)],W.BOOL),
            'GetProcessTimes':([W.HANDLE,pointer,pointer,pointer,pointer],W.BOOL),
            'GetSystemTimePreciseAsFileTime':([pointer],None),
            'WaitForSingleObject':([W.HANDLE,W.DWORD],W.DWORD),
            'CloseHandle':([W.HANDLE],W.BOOL),
        }
        for name,(args,result) in signatures.items():
            function=getattr(self.k,name); function.argtypes=args; function.restype=result
    @staticmethod
    def require(ok):
        if not ok: raise C.WinError(C.get_last_error())
    @staticmethod
    def ticks(ft): return (int(ft.dwHighDateTime)<<32)|int(ft.dwLowDateTime)
    def utc_ns(self):
        value=W.FILETIME(); self.k.GetSystemTimePreciseAsFileTime(C.byref(value))
        return (self.ticks(value)-FT_UNIX)*100
    def sample(self,handle):
        signalled=self.k.WaitForSingleObject(handle,0)
        if signalled not in (0,258): raise C.WinError(C.get_last_error())
        mono0=time.perf_counter_ns(); utc0=self.utc_ns()
        created,exited,kernel,user=(W.FILETIME() for unused in range(4))
        self.require(self.k.GetProcessTimes(handle,C.byref(created),C.byref(exited),C.byref(kernel),C.byref(user)))
        utc1=self.utc_ns(); mono1=time.perf_counter_ns()
        return {'monotonic_before_ns':mono0,'monotonic_after_ns':mono1,
                'utc_before_ns':str(utc0),'utc_after_ns':str(utc1),
                'utc_iso':datetime.datetime.fromtimestamp(((utc0+utc1)//2)/1e9,datetime.timezone.utc).isoformat(),
                'creation_filetime_100ns':str(self.ticks(created)),
                'kernel_100ns':self.ticks(kernel),'user_100ns':self.ticks(user),
                'exited_before_query':signalled==0,
                'exit_filetime_100ns':str(self.ticks(exited)) if signalled==0 else None}


class Sampler(threading.Thread):
    def __init__(self,output,exe,profile,timeout):
        super().__init__(name='target-process-cpu-only',daemon=True)
        self.output,self.exe,self.profile=output,exe,profile
        self.stop_event=threading.Event(); self.deadline=time.monotonic()+timeout
        self.api=Windows(); self.launch_utc_ns=self.api.utc_ns()
        self.samples=[]; self.error=''; self.identity={}; self.prepared={}
        self.closed=True; self.transient_prepared_reads=0; self.last_prepared_read_utc_ns=None
    def run(self):
        handle=None
        try:
            # Read just this new prepared file. Once accepted, no more file IO
            # in this thread: every ROI sample stays entirely in memory.
            while not self.stop_event.is_set():
                if time.monotonic()>=self.deadline: raise TimeoutError('prepared deadline')
                try:
                    self.prepared=json.loads((self.output/'prepared.json').read_text(encoding='utf-8'))
                    self.last_prepared_read_utc_ns=self.api.utc_ns()
                    break
                except (OSError,ValueError):
                    self.transient_prepared_reads+=1
                    self.stop_event.wait(.05)
            if not self.prepared: raise ValueError('prepared not observed before original runner ended')
            env=self.prepared.get('environment',{}); alignment=bridge(env)
            pid=self.prepared.get('pid')  # Sole PID source; never enumerate/find by image name.
            if type(pid) is not int or not 0<pid<=0xffffffff or env.get('profile')!=self.profile or pathlib.Path(env.get('executable','')).resolve()!=self.exe:
                raise ValueError('prepared PID/profile/executable mismatch')
            handle=self.api.k.OpenProcess(0x00101000,False,pid)  # QUERY_LIMITED_INFORMATION|SYNCHRONIZE only.
            self.api.require(handle); self.closed=False
            buffer=C.create_unicode_buffer(32768); size=W.DWORD(len(buffer))
            self.api.require(self.api.k.QueryFullProcessImageNameW(handle,0,buffer,C.byref(size)))
            if pathlib.Path(buffer.value).resolve()!=self.exe: raise ValueError('opened image path mismatch')
            first=self.api.sample(handle); creation=int(first['creation_filetime_100ns'])
            creation_ns=(creation-FT_UNIX)*100
            if first['exited_before_query'] or not self.launch_utc_ns<=creation_ns<=round(alignment['utc']*1e9):
                raise ValueError('not a live new process in this launch/prepared creation window')
            self.identity={'pid':pid,'image':buffer.value,'profile':self.profile,
                           'creation_filetime_100ns':str(creation),'creation_unix_ns':str(creation_ns),
                           'rights_hex':'0x00101000','one_handle_no_reopen':True,
                           'scope':'fresh output/profile + path + creation window; initial same-path PID race not an authentication guarantee'}
            self.samples.append(first)
            while not self.stop_event.wait(PERIOD):
                if time.monotonic()>=self.deadline: raise TimeoutError('observer deadline')
                sample=self.api.sample(handle); prior=self.samples[-1]
                if sample['creation_filetime_100ns']!=str(creation) or any(sample[k]<prior[k] for k in ('kernel_100ns','user_100ns')):
                    raise ValueError('creation changed or cumulative CPU counter regressed')
                self.samples.append(sample)
                if sample['exited_before_query']: break
        except Exception as error:
            self.error=type(error).__name__+': '+str(error)
        finally:
            if handle is not None:
                if self.api.k.CloseHandle(handle): self.closed=True
                else: self.error+='; CloseHandle: '+str(C.WinError(C.get_last_error()))


def summarize(sampler,report,rows):
    start=bridge(sampler.prepared.get('environment',{})); end=bridge(report.get('environment',{}))
    drift=(end['utc']-start['utc'])-((end['before']+end['after']-start['before']-start['after'])/2)
    if abs(drift)>CLOCK_LIMIT_S: raise ValueError('UTC/engine monotonic drift exceeds20ms; raw samples retained')
    offsets=[((int(s['utc_before_ns'])+int(s['utc_after_ns']))//2)-((s['monotonic_before_ns']+s['monotonic_after_ns'])//2) for s in sampler.samples]
    if not offsets or (max(offsets)-min(offsets))/1e9>CLOCK_LIMIT_S:
        raise ValueError('external UTC/monotonic clock changed by more than20ms')
    external_clock_range=(max(offsets)-min(offsets))/1e9
    lower=min(start['lo'],end['lo'])-external_clock_range; upper=max(start['hi'],end['hi'])+external_clock_range
    regions=[]
    for region in ('I2','I3','F4'):
        window=[r for r in rows if r['phase']=='measure:'+region and r['region']==region]
        if len(window)<3: raise ValueError('missing original CSV ROI '+region)
        # Original CSV/report frames remain intact. Drop both edge frames ONLY
        # for this CPU attribution, making its window strictly inside measure.
        outer0,outer1=float(window[0]['start_s']),float(window[-1]['end_s'])
        inner0,inner1=float(window[0]['end_s']),float(window[-1]['start_s'])
        safe0=math.ceil((inner0+upper)*1e9); safe1=math.floor((inner1+lower)*1e9)
        if sampler.last_prepared_read_utc_ns is None or sampler.last_prepared_read_utc_ns>=math.floor((outer0+lower)*1e9):
            raise ValueError('prepared read was not demonstrably before all ROIs')
        accepted=[]
        for index,(a,b) in enumerate(zip(sampler.samples,sampler.samples[1:])):
            if int(a['utc_before_ns'])>=safe0 and int(b['utc_after_ns'])<=safe1:
                accepted.append((index,a,b))
        if not accepted: raise ValueError('no wholly interior CPU sample interval '+region)
        user=sum(b['user_100ns']-a['user_100ns'] for _,a,b in accepted)/1e7
        kernel=sum(b['kernel_100ns']-a['kernel_100ns'] for _,a,b in accepted)/1e7
        wall=sum(((b['monotonic_before_ns']+b['monotonic_after_ns'])-(a['monotonic_before_ns']+a['monotonic_after_ns']))/2e9 for _,a,b in accepted)
        regions.append({'region':region,'original_csv_roi_seconds':[outer0,outer1],
                        'strict_inner_frame_window_seconds':[inner0,inner1],
                        'safe_utc_ns':[str(safe0),str(safe1)],'cpu_interval_indices':[i for i,_,_ in accepted],
                        'covered_wall_seconds':wall,'original_roi_coverage':wall/(outer1-outer0),
                        'edge_frame_seconds_excluded':(inner0-outer0)+(outer1-inner1),
                        'user_cpu_seconds':user,'kernel_cpu_seconds':kernel,'all_thread_cpu_seconds':user+kernel,
                        'thread_seconds_per_wall_second':(user+kernel)/wall})
    return {'regions':regions,'time_alignment':{'prepared':sampler.prepared['environment']['time_alignment'],'report':report['environment']['time_alignment']},'engine_UTC_bridge_drift_seconds':drift,
            'mapping_envelope_seconds':upper-lower,'assumed_UTC_quantization_guard_seconds':UTC_QUANTIZATION_GUARD_S,'absolute_clock_alignment_guaranteed':False,'external_UTC_monotonic_range_seconds':(max(offsets)-min(offsets))/1e9,
            'max_counter_read_bracket_ms':max(s['monotonic_after_ns']-s['monotonic_before_ns'] for s in sampler.samples)/1e6,
            'max_sample_gap_seconds':max((b['monotonic_before_ns']-a['monotonic_before_ns'])/1e9 for a,b in zip(sampler.samples,sampler.samples[1:]))}


def main():
    if os.name!='nt': raise SystemExit('Windows only; no fallback enumerator or additional engine')
    tools=ROOT/'scripts_tools/v3'
    if not (tools/'check_campaign_performance.py').is_file(): raise SystemExit('wrong project root')
    sys.path.insert(0,str(tools))
    import dev
    spec=importlib.util.spec_from_file_location('cpu67_unchanged_runner',tools/'check_campaign_performance.py')
    base=importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
    original=dev._windows_run; invocation={}; sampler=None; runner_exit=1; caught=''
    def observe(command,log,timeout):
        nonlocal sampler
        if invocation: raise RuntimeError('observer supports exactly one original private-Job invocation')
        def argument(prefix):
            matches=[v[len(prefix):] for v in command if v.startswith(prefix)]
            if len(matches)!=1: raise ValueError('missing/duplicate original argument '+prefix)
            return matches[0]
        output=pathlib.Path(argument('--qa-performance-output=')).resolve(strict=True)
        profile=argument('--qa-profile='); exe=pathlib.Path(command[0]).resolve(strict=True)
        if output.parent!=(ROOT/'artifacts/v3/performance').resolve() or output.name!='campaign-performance-'+profile.removeprefix('qa_campaign_performance_') or not profile.startswith('qa_campaign_performance_') or any((output/f).exists() for f in ('prepared.json','report.json','validation.json','frames.csv','process_cpu.json')):
            raise ValueError('observer requires this runner freshly-created output and unique profile')
        invocation.update(output=str(output),command=list(command),timeout=timeout)
        sampler=Sampler(output,exe,profile,timeout); sampler.start()
        try:
            result=original(command,log,timeout)  # Original cwd, args, Job, watchdog and cleanup, unchanged.
            invocation['process']=dict(result)
            return result
        finally:
            sampler.stop_event.set(); sampler.join(2.0)
            if sampler.is_alive(): sampler.error+='; observer thread did not stop within2s'
    try:
        dev._windows_run=observe
        base.main()  # The original argparse/EXE hash/evidence/normal acceptance, unchanged.
    except SystemExit as error:
        runner_exit=int(error.code or 0) if isinstance(error.code,(int,type(None))) else 1
    except BaseException as error:
        caught=type(error).__name__+': '+str(error)
    finally:
        dev._windows_run=original
        if sampler is not None:
            sampler.stop_event.set(); sampler.join(2.0)
    if sampler is None: return runner_exit  # Original --help/preflight; no extra files.
    result={'diagnostic_only':True,'normal_performance_pass_claimed':False,'invocation':invocation,
            'original_runner_exit_code':runner_exit,'observer_error':sampler.error,'exception':caught,
            'identity':sampler.identity,'handle_closed':sampler.closed,'thread_stopped':not sampler.is_alive(),
            'period_seconds':PERIOD,'transient_prepared_reads':sampler.transient_prepared_reads,
            'last_prepared_read_utc_ns':str(sampler.last_prepared_read_utc_ns),
            'samples':sampler.samples,'cpu_observation_valid':False,
            'scope':'GetProcessTimes is cumulative CPU for all process threads. CPU seconds may exceed wall; ratio is thread-seconds/wall-second, not a percent or GPU time. No other process, thread attribution, priority/affinity, CIM, ETW, screenshot or ROI disk writes. No subtraction from inclusive engine scopes can isolate GPU or GDScript time.'}
    try:
        output=pathlib.Path(invocation['output'])
        report=json.loads((output/'report.json').read_text(encoding='utf-8'))
        validation=json.loads((output/'validation.json').read_text(encoding='utf-8'))
        with (output/'frames.csv').open(encoding='utf-8',newline='') as file: rows=list(csv.DictReader(file))
        if sampler.error or caught or sampler.is_alive() or not sampler.closed: raise ValueError('observer lifecycle failure')
        if not (report.get('valid_measurement') is True or report.get('valid_diagnostic_measurement') is True): raise ValueError('original ROI measurement invalid')
        if not validation.get('checks',{}).get('no_engine_error') or not validation.get('checks',{}).get('frozen_export'): raise ValueError('original engine-error/export-hash gate failed')
        if invocation.get('process',{}).get('pid')!=sampler.identity.get('pid'): raise ValueError('original private-Job PID differs from prepared PID')
        process=invocation['process']
        if process.get('returncode') not in (0,1) or process.get('timed_out') or process.get('orphan_cleanup') or process.get('remaining_owned_processes')!=0: raise ValueError('original private Job cleanup failed')
        if process.get('returncode')==1 and (report.get('screening_target_met') is not False or report.get('qa_audio_shutdown',{}).get('ready') is not True): raise ValueError('nonzero exit is not the observed P95-only shutdown')
        result['cpu_summary']=summarize(sampler,report,rows)
        result['original_validation']={k:validation.get(k) for k in ('measurement_valid','screening_passed','screening_target_met','checks','before_sha256','after_sha256','process')}
        result['cpu_observation_valid']=True
    except (OSError,ValueError,KeyError,TypeError) as error:
        result['mapping_error']=type(error).__name__+': '+str(error)
    # No observer file write until the original engine/Job/runner have finished.
    with (pathlib.Path(invocation['output'])/'process_cpu.json').open('x',encoding='utf-8') as file:
        json.dump(result,file,ensure_ascii=False,indent=2)
    print(json.dumps({'output':invocation['output'],'cpu_observation_valid':result['cpu_observation_valid'],
                      'original_runner_exit_code':runner_exit,'observer_error':sampler.error,
                      'cpu_summary':result.get('cpu_summary'),'mapping_error':result.get('mapping_error')},ensure_ascii=False))
    return runner_exit if runner_exit else (0 if result['cpu_observation_valid'] else 2)


if __name__=='__main__':
    raise SystemExit(main())
