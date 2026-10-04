"""Master pipeline: CRISP-DM phases execute in strict order."""
from scripts import phase1, phase2, phase3

def run_all():
    for phase in (phase1, phase2, phase3):
        print(f"\n=== {phase.__name__.rsplit('.', 1)[-1].upper()} ===")
        phase.run()
