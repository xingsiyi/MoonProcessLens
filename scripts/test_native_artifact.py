"""Platform-neutral regression tests; no compiler or PM4Py dependency."""
from pathlib import Path
import tempfile
import unittest

from native_artifact import processlens_executable


class NativeArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "_build/native/debug/build/cmd/processlens"
        self.folder.mkdir(parents=True)

    def test_exe_suffix_does_not_require_windows(self):
        path = self.folder / "processlens.exe"
        path.touch()
        self.assertEqual(processlens_executable(self.root), path)

    def test_legacy_bare_name_fallback(self):
        path = self.folder / "processlens"
        path.touch()
        self.assertEqual(processlens_executable(self.root), path)

    def test_current_suffix_preferred_over_legacy_artifact(self):
        (self.folder / "processlens").touch()
        path = self.folder / "processlens.exe"
        path.touch()
        self.assertEqual(processlens_executable(self.root), path)

    def test_directory_is_not_an_executable_artifact(self):
        (self.folder / "processlens.exe").mkdir()
        with self.assertRaisesRegex(FileNotFoundError, "artifact not found"):
            processlens_executable(self.root)


if __name__ == "__main__":
    unittest.main()
