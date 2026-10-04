"""Command-line launcher for one phase or the complete pipeline."""
import argparse
from etl import run_all
from db import close_pool
from scripts import phase1, phase2, phase3

def main():
    parser = argparse.ArgumentParser(description="DEPI Olist PostgreSQL Feature Store")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--all", action="store_true", help="run all three phases")
    group.add_argument("--phase", choices=("1", "2", "3"), help="run one CRISP-DM phase")
    args = parser.parse_args()
    try:
        if args.all:
            run_all()
        else:
            {"1": phase1, "2": phase2, "3": phase3}[args.phase].run()
    finally:
        close_pool()

if __name__ == "__main__":
    main()
