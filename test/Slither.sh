# 1. Install Slither (Python 3.9+)
pip install slither-analyzer

# 2. Run static analysis on production contracts and fail on High/Medium issues
slither . --config-file slither.config.json --fail-high

# 3. Export clean Markdown checklist for the GitHub Issue / Employer report
slither . --config-file slither.config.json --checklist > slither-audit-report.md