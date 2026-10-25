"""Measure cumulative CPU time for the running Board process; no key events read."""
import subprocess, time, json
from pathlib import Path
output=subprocess.check_output(['/bin/ps','-A','-o','pid=,comm='],text=True)
matching=[line.strip().split(None,1) for line in output.splitlines() if 'Board.app/Contents/MacOS/Board' in line]
if len(matching)!=1: raise SystemExit('Run exactly one Board app before measuring.')
pid=matching[0][0]
def sample():
    row=subprocess.check_output(['/bin/ps','-p',pid,'-o','time=,rss='],text=True).strip().split()
    t=row[0].split(':'); seconds=0
    for part in t: seconds=seconds*60+float(part)
    return seconds,int(row[1])/1024
start=time.monotonic(); first=sample(); memory=[]
for _ in range(30):
    time.sleep(1); last=sample(); memory.append(last[1])
elapsed=time.monotonic()-start
report={'date':'2026-09-10','scenario':'Release app idle; overlays off; settings visible; input permission not granted','wallSeconds':elapsed,'cpuSeconds':last[0]-first[0],'averageCPUPercent':100*(last[0]-first[0])/elapsed,'peakRSS_MB':max(memory),'notes':'Cumulative process CPU divided by wall time. This does not establish active typing performance or audible latency.'}
root=Path(__file__).resolve().parents[1]
(root/'Docs/idle-measurement.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
