#!/usr/bin/env python3
"""Experimental research Lean driver. Never writes to either dependency checkout."""
import hashlib, json, os, pathlib, re, shutil, subprocess, sys
root = pathlib.Path(__file__).resolve().parent
source = pathlib.Path(os.environ['KERI_SOURCE']).resolve()
singular = pathlib.Path(os.environ['SINGULAR_SOURCE']).resolve()
lean = pathlib.Path(os.environ['LEAN_BIN']).resolve()
out = pathlib.Path(os.environ['RUN_DIR']).resolve()
out.mkdir(parents=True, exist_ok=True)
assert not (out/'inputs.json').exists(), 'RUN_DIR must be new'
delivery = '6734348688a82f31e4be38b83332144e450e618f'
model = '1bd8b08ccde5597a629a1c75de2de0c274b49397'
upstream = 'd69ab005c3b710aeebf033d3c5cd08c56feb5643'
def git(p, *args):
    return subprocess.check_output(['git', '-C', str(p), *args])
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
source_status = git(source, 'status', '--porcelain', '--untracked-files=all')
assert not out.is_relative_to(source) and not out.is_relative_to(singular), 'RUN_DIR must be outside source checkouts'
assert git(singular, 'rev-parse', 'HEAD').decode().strip() == upstream
# Research additions and later branch commits are allowed; imported bytes are pinned below.
assert not git(singular, 'diff', 'HEAD', '--'), 'Singular tracked sources must be clean'
assert not git(source, 'diff', model, '--', 'lean'), 'protocol Lean source drift'
packages = json.loads((source/'lean/lake-manifest.json').read_text())['packages']
pins = [p for p in packages if p['name'] == 'singular']
assert len(pins) == 1 and pins[0]['rev'] == upstream, 'Singular pin drift'
version = subprocess.check_output([str(lean), '--version']).decode().strip()
assert re.search(r'\bversion 4\.27\.0(?:,|\))', version), version
print(version, flush=True)
paths = [root, source/'lean', singular/'lean']
ordered, seen = [], set()
def visit(name):
    if name in seen: return
    seen.add(name)
    rel = pathlib.Path(*name.split('.')).with_suffix('.lean')
    found = next(((p, p/rel) for p in paths if (p/rel).is_file()), None)
    if found is None:
        assert not name.startswith(('Freshness.', 'CardanoKeri.', 'Singular.')), name
        return  # Lean distribution imports
    base, file = found
    # Bound project's ordinary import syntax; reject unexpected import forms.
    for line in file.read_text().splitlines():
        if line.startswith('import '):
            for dep in line[7:].split('--')[0].split(): visit(dep)
    ordered.append((name, base, file))
assert len(sys.argv) == 1, 'run the complete research package without module arguments'
for target in ['Freshness.Examples', 'Freshness.Claims']: visit(target)
for name, base, file in ordered:
    if name.startswith('CardanoKeri.'):
        assert file.read_bytes() == git(source, 'show', model+':lean/'+str(file.relative_to(base)))
    elif name.startswith('Singular.'):
        assert file.read_bytes() == git(singular, 'show', upstream+':lean/'+str(file.relative_to(base)))
    snapshot = out/'input-sources'/pathlib.Path(*name.split('.')).with_suffix('.lean')
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(file, snapshot)
inputs = {str(f): sha(f) for _, _, f in ordered}
inputs[str(lean)] = sha(lean)
for f in root.rglob('*'):
    if f.is_file(): inputs[str(f)] = sha(f)
inputs[str(source/'lean/lake-manifest.json')] = sha(source/'lean/lake-manifest.json')
(out/'inputs.json').write_text(json.dumps(inputs, indent=2)+'\n')
(out/'bindings.json').write_text(json.dumps(dict(model=model, original_delivery=delivery, source_head=git(source, 'rev-parse', 'HEAD').decode().strip(), singular=upstream, lean=version), indent=2)+'\n')
lib = out/'lib'
lib.mkdir(exist_ok=True)
env = dict(os.environ, LEAN_PATH=str(lib))
seed = os.environ.get('DEPENDENCY_RUN')
cached = set()
if seed:
    seed = pathlib.Path(seed).resolve()
    assert (seed/'exit-code.txt').read_text().strip() == '0'
    old_inputs = json.loads((seed/'inputs.json').read_text())
    old_outputs = json.loads((seed/'outputs.json').read_text())
    assert old_inputs.get(str(lean)) == sha(lean), 'reuse requires same compiler binary'
    for rel, digest in old_outputs.items():
        assert sha(seed/rel) == digest, rel
    for name, base, file in ordered:
        if not name.startswith('Freshness.'):
            source_rel = pathlib.Path(*name.split('.')).with_suffix('.lean')
            snapshot = seed/'input-sources'/source_rel
            digest = sha(file)
            assert sha(snapshot) == digest, file
            assert any(p.endswith('/lean/'+str(source_rel)) and h == digest for p, h in old_inputs.items()), file
            rel = pathlib.Path(*name.split('.')).with_suffix('.olean')
            assert 'lib/'+str(rel) in old_outputs, rel
            target = lib/rel
            target.parent.mkdir(parents=True, exist_ok=True)
            for artifact in (seed/'lib'/rel).parent.glob(rel.stem+'.olean*'):
                artifact_rel = str(artifact.relative_to(seed))
                assert artifact_rel in old_outputs and sha(artifact) == old_outputs[artifact_rel], artifact_rel
                shutil.copy2(artifact, target.parent/artifact.name)
            cached.add(name)
    (out/'dependency-reuse.json').write_text(json.dumps(dict(seed=str(seed), modules=sorted(cached)), indent=2)+'\n')
    print(f'REUSE {len(cached)} hash-verified modules from isolated dependency build', flush=True)
commands = []
for name, base, file in ordered:
    if name in cached: continue
    dest = lib/pathlib.Path(*name.split('.')).with_suffix('.olean')
    dest.parent.mkdir(parents=True, exist_ok=True)
    command = [str(lean), str(file), '-o', str(dest)]
    commands.append(dict(cwd=str(base), argv=command))
    (out/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
    print('COMPILE', name, flush=True)
    result = subprocess.run(command, cwd=base, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (out/(name+'.log')).write_text(result.stdout)
    print(result.stdout, end='', flush=True)
    if result.returncode: sys.exit(result.returncode)
    if name.startswith('Freshness.') and name != 'Freshness.Claims':
        assert "declaration uses 'sorry'" not in result.stdout and 'sorryAx' not in result.stdout, 'unexpected admission'
    if name == 'Freshness.Claims':
        claims = []
        for match in re.finditer(r'^theorem (C\d+_\w+)', file.read_text(), re.M):
            local = match.group(1)
            statement = file.read_text()[match.start():].split(':= by', 1)[0].strip()
            full = 'Freshness.Claims.'+local
            axiom_lines = [line for line in result.stdout.splitlines() if line.startswith("'"+full+"' depends on axioms:")]
            assert len(axiom_lines) == 1 and 'sorryAx' in axiom_lines[0], full
            claims.append(dict(name=full, statement=statement,
                sha256=hashlib.sha256(statement.encode()).hexdigest(), axioms=axiom_lines[0], status='ADMITTED'))
        assert [c['name'] for c in claims] == ['Freshness.Claims.C1_submit_over_stop', 'Freshness.Claims.C2_delay_composition', 'Freshness.Claims.C3_funded_work_bound']
        assert result.stdout.count("declaration uses 'sorry'") == 3
        assert result.stdout.count('sorryAx') == 3
        (out/'admitted-statements.json').write_text(json.dumps(claims, indent=2)+'\n')
assert all(sha(pathlib.Path(p)) == h for p, h in inputs.items()), 'inputs changed during run'
outputs = {str(p.relative_to(out)): sha(p) for p in lib.rglob('*') if p.is_file()}
(out/'outputs.json').write_text(json.dumps(outputs, indent=2)+'\n')
assert git(source, 'status', '--porcelain', '--untracked-files=all') == source_status, 'checkout changed during run'
assert not git(singular, 'diff', 'HEAD', '--')
print(f'PASS: {len(ordered)} modules; source hashes unchanged; checkouts unchanged', flush=True)
