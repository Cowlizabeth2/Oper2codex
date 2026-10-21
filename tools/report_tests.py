"""Expose JUnit failures in the workflow summary without requiring log access."""
import html
import os
from pathlib import Path
import xml.etree.ElementTree as ET


def report():
    source = Path("artifacts/tests.xml")
    destination = os.environ.get("GITHUB_STEP_SUMMARY")
    if not source.exists() or not destination:
        return
    root = ET.parse(source).getroot()
    lines = ["## Windows tests\n"]
    for suite in root.iter("testsuite"):
        lines.append(f"Tests: {suite.get('tests')}; failures: {suite.get('failures')}; errors: {suite.get('errors')}; skipped: {suite.get('skipped')}\n")
    for case in root.iter("testcase"):
        for tag in ("failure", "error"):
            issue = case.find(tag)
            if issue is not None:
                lines.append("### " + case.get("classname", "") + "." + case.get("name", "") + "\n")
                lines.append("<pre>" + html.escape(issue.text or issue.get("message", "")) + "</pre>\n")
    with Path(destination).open("a", encoding="utf-8") as stream:
        stream.write("\n".join(lines))


if __name__ == "__main__":
    report()
