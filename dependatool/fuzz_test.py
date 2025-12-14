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
    
    # Try to decode the data as UTF-8 and split into arguments
    args_str = data.decode('utf-8', errors='ignore').strip()
    if not args_str:
        return
    
    # Split into arguments and filter empty ones
    args = [arg for arg in args_str.split() if arg]
    if not args:
        return
    
    # Call the main function with fuzzed arguments
    # We catch expected exceptions from invalid inputs and exits
    try:
        main(*args)
    except (ValueError, TypeError, KeyError, IndexError, AttributeError, 
            SystemExit, FileNotFoundError, OSError, RuntimeError):
        # Expected exceptions from invalid inputs and CLI exits - ignore
        pass
    # Let unexpected exceptions (potential bugs) propagate to the fuzzer


if __name__ == '__main__':
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()
