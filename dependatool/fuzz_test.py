#!/usr/bin/env python3
"""Minimal fuzz test harness for dependatool CLI using atheris."""

import sys
import atheris

# Import the dependatool main function
with atheris.instrument_imports():
    from dependatool.cmd import main


def TestOneInput(data: bytes) -> None:
    """Fuzz test function that processes input data as CLI arguments.
    
    Args:
        data: Raw fuzzing input from atheris
    """
    # Basic sanity check on input
    if len(data) < 1:
        return
    
    try:
        # Try to decode the data as UTF-8 and split into arguments
        args_str = data.decode('utf-8', errors='ignore').strip()
        if not args_str:
            return
        
        # Split into arguments and filter empty ones
        args = [arg for arg in args_str.split() if arg]
        if not args:
            return
        
        # Call the main function with fuzzed arguments
        # We catch all exceptions since we expect many invalid inputs
        main(*args)
    except Exception:
        # Ignore all exceptions during fuzzing - we're looking for crashes/hangs
        pass


if __name__ == '__main__':
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()
