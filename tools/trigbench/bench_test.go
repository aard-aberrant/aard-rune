// trigbench: what the config's triggers cost per line.
//
// Reads every trigger pattern from the config's .lua files - the
// rune.trigger.exact / starts / contains / regex calls, and util.group's
// .add("<kind>", ...) ones (those exist only while their feature runs, so
// they're counted apart) - and times them against real lines from Rune
// logs, color codes stripped. The match loop is the same as Rune's
// lua/matcher.go: every line tested against every pattern in order (==,
// HasPrefix, Contains, or Go's RE2), captures taken only on a match.
// Patterns built at run time (a variable, util.await's) aren't seen.
//
// Run from this folder, with one or more /log files:
//   go test -bench . -args ~/combatmsg ~/immune ~/groupinfo
// (Mac: the logs are in /Volumes/Seth.) Results, per line:
//   Permanent       every always-registered trigger - the real per-line cost
//   Literals        ... just the exact / starts / contains ones
//   Regexes         ... just the regexes
//   WithGroups      permanent plus util.group's, as during a walk or hunt
//   Each/<pattern>  each regex alone, to find the costly ones
// A literal is ~8 ns, a regex with a fixed start ~15-35 ns, one whose start
// varies (an optional "*[N] " before "Your") ~115 ns. 2026-11-08, 50
// permanent triggers on the Mac: ~0.93 us a line. What runs Lua (a match)
// costs more than what doesn't - a few us a line - so a broad pattern costs
// more than many precise ones.

package trigbench

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
)

type pat struct {
	mode  string // exact, starts, contains, regex
	lit   string
	re    *regexp.Regexp
	group bool // a util.group trigger: only while its feature runs
	file  string
}

func (p *pat) match(line string) bool {
	switch p.mode {
	case "exact":
		return line == p.lit
	case "starts":
		return strings.HasPrefix(line, p.lit)
	case "contains":
		return strings.Contains(line, p.lit)
	}
	if !p.re.MatchString(line) {
		return false
	}
	_ = p.re.FindStringSubmatch(line)
	return true
}

// A Lua string literal's body -> its value (\\ \" \n \t \ddd; any other
// \x is x, as Lua 5.1)
func unlua(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c != '\\' || i+1 == len(s) {
			b.WriteByte(c)
			continue
		}
		i++
		switch d := s[i]; {
		case d == 'n':
			b.WriteByte('\n')
		case d == 't':
			b.WriteByte('\t')
		case d >= '0' && d <= '9':
			j := i
			for j < len(s) && j < i+3 && s[j] >= '0' && s[j] <= '9' {
				j++
			}
			n, _ := strconv.Atoi(s[i:j])
			b.WriteByte(byte(n))
			i = j - 1
		default:
			b.WriteByte(d)
		}
	}
	return b.String()
}

var (
	callRe  = regexp.MustCompile(`rune\.trigger\.(exact|starts|contains|regex)\(\s*"((?:[^"\\]|\\.)*)"`)
	groupRe = regexp.MustCompile(`\.add\("(exact|starts|contains|regex)",\s*"((?:[^"\\]|\\.)*)"`)
	ansiRe  = regexp.MustCompile("\x1b\\[[0-9;]*m")
)

// The config: two folders up from here
func patterns(b *testing.B) []pat {
	root, _ := filepath.Abs("../..")
	var ps []pat
	filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() && info.Name() == "tools" {
			if info != nil && info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".lua") {
			return nil
		}
		src, _ := os.ReadFile(path)
		rel, _ := filepath.Rel(root, path)
		add := func(m []string, group bool) {
			p := pat{mode: m[1], lit: unlua(m[2]), group: group, file: rel}
			if p.mode == "regex" {
				re, err := regexp.Compile(p.lit)
				if err != nil {
					b.Logf("%s: %q: %v (skipped)", rel, p.lit, err)
					return
				}
				p.re = re
			}
			ps = append(ps, p)
		}
		for _, m := range callRe.FindAllStringSubmatch(string(src), -1) {
			add(m, false)
		}
		for _, m := range groupRe.FindAllStringSubmatch(string(src), -1) {
			add(m, true)
		}
		return nil
	})
	if len(ps) == 0 {
		b.Fatal("no trigger patterns found under " + root)
	}
	return ps
}

func lines(b *testing.B) []string {
	if flag.NArg() == 0 {
		b.Fatal("give log files after -args: go test -bench . -args ~/combatmsg ...")
	}
	var out []string
	for _, f := range flag.Args() {
		data, err := os.ReadFile(f)
		if err != nil {
			b.Fatal(err)
		}
		for _, l := range strings.Split(string(data), "\n") {
			out = append(out, ansiRe.ReplaceAllString(strings.TrimRight(l, "\r"), ""))
		}
	}
	return out
}

func pick(ps []pat, keep func(pat) bool) []pat {
	var out []pat
	for _, p := range ps {
		if keep(p) {
			out = append(out, p)
		}
	}
	return out
}

func run(b *testing.B, ps []pat, ls []string) {
	b.ReportMetric(float64(len(ps)), "triggers")
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := ls[i%len(ls)]
		for k := range ps {
			ps[k].match(l)
		}
	}
}

func BenchmarkPermanent(b *testing.B) {
	run(b, pick(patterns(b), func(p pat) bool { return !p.group }), lines(b))
}

func BenchmarkLiterals(b *testing.B) {
	run(b, pick(patterns(b), func(p pat) bool { return !p.group && p.mode != "regex" }), lines(b))
}

func BenchmarkRegexes(b *testing.B) {
	run(b, pick(patterns(b), func(p pat) bool { return !p.group && p.mode == "regex" }), lines(b))
}

func BenchmarkWithGroups(b *testing.B) {
	run(b, patterns(b), lines(b))
}

func BenchmarkEach(b *testing.B) {
	ls := lines(b)
	rs := pick(patterns(b), func(p pat) bool { return p.mode == "regex" })
	sort.Slice(rs, func(i, j int) bool { return rs[i].file < rs[j].file })
	for _, p := range rs {
		p := p
		name := p.lit
		if len(name) > 40 {
			name = name[:40]
		}
		b.Run(fmt.Sprintf("%s:%s", p.file, name), func(b *testing.B) { run(b, []pat{p}, ls) })
	}
}
