SWIFTLINT = swiftlint

.PHONY: test
test:
	swift test

.PHONY: lint
lint:
	$(SWIFTLINT) --strict

.PHONY: fix
fix:
	$(SWIFTLINT) --fix
