import json
import subprocess
import os


def load_dicts():
    script = os.path.join(os.path.dirname(__file__), 'get_entity_dicts.ps1')
    result = subprocess.check_output(['pwsh', '-NoProfile', '-File', script], text=True)
    return json.loads(result)


def test_synonyms_admin():
    data = load_dicts()
    assert 'Admin' in data['Synonyms']
    assert 'administrator' in [s.lower() for s in data['Synonyms']['Admin']]


def test_corrections_pirece():
    data = load_dicts()
    assert '\\bpirece\\b' in data['Corrections']
    assert data['Corrections']['\\bpirece\\b'] == 'Pierce'
