from pathlib import Path
import tempfile
import unittest
import zipfile

from tool.verify_android_artifact import verify


class ArtifactVerifierTest(unittest.TestCase):
    def _artifact(self, content: bytes) -> Path:
        temp = tempfile.NamedTemporaryFile(suffix=".apk", delete=False)
        temp.close()
        path = Path(temp.name)
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("classes.dex", content)
        self.addCleanup(path.unlink, missing_ok=True)
        return path

    def test_accepts_store_clean_artifact(self) -> None:
        findings = verify("bazaar", self._artifact(b"ir.cafebazaar.poolakey.Payment"))
        self.assertEqual(findings, [])

    def test_rejects_cross_store_artifact(self) -> None:
        findings = verify("bazaar", self._artifact(b"Lir/myket/billingclient/IabHelper;"))
        self.assertTrue(findings)
        self.assertEqual(findings[0][1], "ir/myket/billingclient")


if __name__ == "__main__":
    unittest.main()
