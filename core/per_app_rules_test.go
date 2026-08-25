package main

import (
	"testing"

	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/rules"
)

func TestPerAppProcessPathRuleMatchesCaseInsensitively(t *testing.T) {
	const processPath = `C:\Program Files\Browser\browser.exe`
	rule, err := rules.ParseRule(
		"PROCESS-PATH",
		processPath,
		"GLOBAL",
		nil,
		nil,
	)
	if err != nil {
		t.Fatalf("parse PROCESS-PATH rule: %v", err)
	}

	matched, adapter := rule.Match(
		&C.Metadata{ProcessPath: `c:\program files\browser\BROWSER.EXE`},
		C.RuleMatchHelper{},
	)
	if !matched {
		t.Fatal("expected PROCESS-PATH rule to match the executable path")
	}
	if adapter != "GLOBAL" {
		t.Fatalf("unexpected adapter: %q", adapter)
	}
}
