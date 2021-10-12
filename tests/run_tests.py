import unittest
from pathlib import Path
import sys

if __name__ == '__main__':
    loader = unittest.TestLoader()
    suite = loader.discover(Path(__file__).parent.absolute())
    runner = unittest.TextTestRunner()
    result = runner.run(suite)

    sys.exit(0 if result.wasSuccessful() else 1)
