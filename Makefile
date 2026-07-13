.PHONY: venv test
venv:
	@if [ ! -d ".venv" ]; then \
		python3 -m venv .venv; \
		.venv/bin/pip install -r requirements-test.txt; \
	else \
		echo "Venv already exists"; \
	fi

test: venv
	.venv/bin/pytest tests/ -v -ra -s
