#!/usr/bin/env python3
"""Inventory the actual fetched revisions before binding to private APIs."""
import hashlib,json,re,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]).resolve()
patterns={
 'proxy-audio-device':re.compile(r'CustomProperty|DeviceUID|OutputDevice|outputDevice|VolumeScalar|AudioDeviceIOProc|ringBuffer|RingBuffer'),
 'candela':re.compile(r'IOHIDUserDevice|EDID|ReportDescriptor|DisplayUUID|DisplayVendorID|IOAVService|SMAppService|entitlement'),
}
report={'sources':{},'nativeBrightnessVerified':False,'nativeAudioPlaybackVerified':False}
for name,pattern in patterns.items():
 repo=root/name
 if not (repo/'.git').is_dir():raise SystemExit('Missing source checkout: '+str(repo))
 head=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
 files=subprocess.check_output(['git','-C',str(repo),'ls-files','-z']).decode().split('\0')
 entry={'revision':head,'licenseFiles':[],'matches':[]}
 for relative in files:
  if not relative:continue
  path=(repo/relative)
  if path.is_symlink() or not path.is_file() or path.stat().st_size>2_000_000:continue
  if path.name.upper().startswith(('LICENSE','COPYING')):
   entry['licenseFiles'].append({'path':relative,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
  if path.suffix.lower() not in ('.swift','.m','.mm','.cpp','.c','.h','.plist','.entitlements'):continue
  try:lines=path.read_text().splitlines()
  except UnicodeDecodeError:continue
  for number,line in enumerate(lines,1):
   if pattern.search(line):entry['matches'].append({'path':relative,'line':number,'text':line[:400]})
 report['sources'][name]=entry
out=root/'source-audit.json';out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(out)
