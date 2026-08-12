from pathlib import Path
import tempfile
import unittest
import zipfile

from tool.verify_android_artifact import verify


class ArtifactVerifierTest(unittest.TestCase):
    def _artifact(self, content: bytes, filename: str = "classes.dex") -> Path:
        temp = tempfile.NamedTemporaryFile(suffix=".apk", delete=False)
        temp.close()
        path = Path(temp.name)
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(filename, content)
        self.addCleanup(path.unlink, missing_ok=True)
        return path

    def test_accepts_store_clean_artifact(self) -> None:
        findings = verify("bazaar", self._artifact(b"ir.cafebazaar.poolakey.Payment"))
        self.assertEqual(findings, [])

    def test_rejects_cross_store_artifact(self) -> None:
        findings = verify("bazaar", self._artifact(b"Lir/myket/billingclient/IabHelper;"))
        self.assertTrue(findings)
        self.assertEqual(findings[0][1], "ir/myket/billingclient")

    def test_rejects_nested_path(self) -> None:
        findings = verify("myket", self._artifact(b"com.farsitel.bazaar", filename="assets/bazaar.txt"))
        self.assertTrue(findings)
        self.assertEqual(findings[0][0], "assets/bazaar.txt")

    def test_case_insensitivity(self) -> None:
        findings = verify("myket", self._artifact(b"COM.FARSITEL.BAZAAR"))
        self.assertTrue(findings)

    def test_error_on_missing_file(self) -> None:
        with self.assertRaises(FileNotFoundError):
            verify("bazaar", Path("non_existent.apk"))

    def test_error_on_non_zip(self) -> None:
        temp = tempfile.NamedTemporaryFile(delete=False)
        temp.write(b"not a zip")
        temp.close()
        path = Path(temp.name)
        self.addCleanup(path.unlink, missing_ok=True)
        with self.assertRaises(ValueError):
            verify("bazaar", path)


if __name__ == "__main__":
    unittest.main()
