import unittest
from pathlib import Path

if __name__ == '__main__':
    loader = unittest.TestLoader()
    suite = loader.discover(Path(__file__).parent.absolute())
    runner = unittest.TextTestRunner()
    runner.run(suite)
