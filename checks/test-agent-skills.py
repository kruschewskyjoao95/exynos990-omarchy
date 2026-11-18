#!/usr/bin/env python3
"""Check the Agent-skills config stays wired (AGENTS.md block + docs/agents/*)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AgentSkillsConfig(unittest.TestCase):
    def test_agents_md_block(self):
        text = (ROOT / "AGENTS.md").read_text()
        for marker in ("## Agent skills", "### Issue tracker",
                       "### Triage labels", "### Domain docs",
                       "docs/agents/issue-tracker.md",
                       "docs/agents/triage-labels.md",
                       "docs/agents/domain.md"):
            self.assertIn(marker, text)

    def test_docs_exist(self):
        for name in ("issue-tracker.md", "triage-labels.md", "domain.md"):
            self.assertTrue((ROOT / "docs" / "agents" / name).is_file(), name)

    def test_tracker_is_github_with_prs_off(self):
        text = (ROOT / "docs" / "agents" / "issue-tracker.md").read_text()
        self.assertIn("GitHub", text)
        self.assertIn("PRs as a request surface: no", text)

    def test_labels_are_canonical(self):
        text = (ROOT / "docs" / "agents" / "triage-labels.md").read_text()
        for label in ("needs-triage", "needs-info", "ready-for-agent",
                      "ready-for-human", "wontfix"):
            self.assertIn(label, text)


if __name__ == "__main__":
    unittest.main()
