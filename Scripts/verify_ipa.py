#!/usr/bin/env python3
import hashlib, json, plistlib, sys, zipfile
from pathlib import Path
path = Path(sys.argv[1])
with zipfile.ZipFile(path) as archive:
    names = archive.namelist()
    plists = [n for n in names if n.count('/') == 2 and n.startswith('Payload/') and n.endswith('.app/Info.plist')]
    assert len(plists) == 1, plists
    info = plistlib.loads(archive.read(plists[0]))
    assert info['CFBundleIdentifier'] == 'com.personafree.editor'
    assert info['CFBundleDisplayName'] == 'personaж'
    assert info['MinimumOSVersion'] == '17.0'
    for key in ['NSCameraUsageDescription','NSPhotoLibraryUsageDescription','NSPhotoLibraryAddUsageDescription']:
        assert info.get(key), key
    executable = plists[0].removesuffix('Info.plist') + info['CFBundleExecutable']
    binary = archive.read(executable)
    assert binary[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'), 'Missing Mach-O executable'
    assert len(binary) > 100_000
    report = dict(bundle_id=info['CFBundleIdentifier'],display_name=info['CFBundleDisplayName'],minimum_ios=info['MinimumOSVersion'],executable_bytes=len(binary),unsigned=True,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    print(json.dumps(report,ensure_ascii=False,indent=2))
