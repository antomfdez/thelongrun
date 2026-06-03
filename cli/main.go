package main

/*
#cgo darwin LDFLAGS: -framework CoreGraphics -framework CoreFoundation
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

extern bool goOnKeyDown(int keycode);

static CGEventSourceRef gSource;
static CFMachPortRef     gTap;

static void postKey(int keycode, bool down, unsigned long long flags) {
    CGEventRef e = CGEventCreateKeyboardEvent(gSource, (CGKeyCode)keycode, down);
    CGEventSetFlags(e, (CGEventFlags)flags);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type,
                              CGEventRef event, void *refcon) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(gTap, true);
        return event;
    }
    if (type == kCGEventKeyDown) {
        CGKeyCode kc = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        if (goOnKeyDown((int)kc)) {
            return NULL; // consume the hotkey so the game never sees it
        }
    }
    return event;
}

static int runTap() {
    gSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);
    gTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                            kCGEventTapOptionDefault, mask, tapCallback, NULL);
    if (!gTap) return 1;
    CFRunLoopSourceRef rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopCommonModes);
    CGEventTapEnable(gTap, true);
    CFRunLoopRun();
    return 0;
}
*/
import "C"

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

// CGEventFlags modifier masks.
const (
	flagShift = 0x20000
	flagCtrl  = 0x40000
	flagAlt   = 0x80000
	flagCmd   = 0x100000
)

// modFlags maps a modifier key code to the flag it contributes.
var modFlags = map[int]uint64{
	56: flagShift, 60: flagShift, // L / R Shift
	59: flagCtrl, 62: flagCtrl, // L / R Control
	58: flagAlt, 61: flagAlt, // L / R Option
	55: flagCmd, 54: flagCmd, // L / R Command
}

// A bind = one hotkey that toggles holding its own set of keys.
type bindSpec struct {
	key       int
	holdKeys  []int
	holdFlags uint64
	running   bool
	label     string
}

var (
	binds   []*bindSpec
	quitKey int
)

func holdDown(b *bindSpec, down bool) {
	if down {
		for _, k := range b.holdKeys {
			C.postKey(C.int(k), true, C.ulonglong(b.holdFlags))
		}
	} else {
		for i := len(b.holdKeys) - 1; i >= 0; i-- {
			C.postKey(C.int(b.holdKeys[i]), false, 0)
		}
	}
}

//export goOnKeyDown
func goOnKeyDown(keycode C.int) C.bool {
	kc := int(keycode)
	for _, b := range binds {
		if kc == b.key {
			b.running = !b.running
			holdDown(b, b.running)
			if b.running {
				fmt.Printf("▶  %s ON\n", b.label)
			} else {
				fmt.Printf("⏸  %s OFF\n", b.label)
			}
			return true
		}
	}
	if kc == quitKey {
		for _, b := range binds {
			if b.running {
				holdDown(b, false)
			}
		}
		fmt.Println("bye 👋")
		os.Exit(0)
	}
	return false
}

// bindFlag lets --bind be repeated; each call appends to the global binds.
type bindFlag struct{}

func (bindFlag) String() string { return "" }
func (bindFlag) Set(s string) error {
	b, err := parseBind(s)
	if err != nil {
		return err
	}
	binds = append(binds, b)
	return nil
}

// parseBind turns "x=w,shift" into a bindSpec.
func parseBind(s string) (*bindSpec, error) {
	i := strings.Index(s, "=")
	if i < 0 {
		return nil, fmt.Errorf("expected key=holdkeys, e.g. x=w,shift")
	}
	keyTok, holdTok := s[:i], s[i+1:]
	return makeBind(keyTok, holdTok, s)
}

func makeBind(keyTok, holdTok, label string) (*bindSpec, error) {
	key, err := resolveKey(keyTok)
	if err != nil {
		return nil, fmt.Errorf("toggle key %q: %v", keyTok, err)
	}
	b := &bindSpec{key: key, label: label}
	for _, tok := range strings.Split(holdTok, ",") {
		tok = strings.TrimSpace(tok)
		if tok == "" {
			continue
		}
		k, err := resolveKey(tok)
		if err != nil {
			return nil, fmt.Errorf("hold key %q: %v", tok, err)
		}
		b.holdKeys = append(b.holdKeys, k)
		b.holdFlags |= modFlags[k]
	}
	if len(b.holdKeys) == 0 {
		return nil, fmt.Errorf("no hold keys given")
	}
	return b, nil
}

func main() {
	flag.Var(bindFlag{}, "bind", "repeatable: a hotkey and the keys it holds, e.g. --bind x=w,shift --bind z=w")
	toggle := flag.String("toggle", "backslash", "[single-bind shortcut] toggle key, used only when no --bind is given")
	hold := flag.String("hold", "w,shift", "[single-bind shortcut] keys to hold, used only when no --bind is given")
	quit := flag.String("quit", "f9", "key that quits the program")
	list := flag.Bool("list-keys", false, "print all known key names and exit")
	flag.Parse()

	if *list {
		printKeyTable()
		return
	}

	// If no --bind flags were passed, fall back to the single --toggle/--hold pair.
	if len(binds) == 0 {
		b, err := makeBind(*toggle, *hold, *toggle+"="+*hold)
		if err != nil {
			fail("--toggle/--hold", *toggle+"="+*hold, err)
		}
		binds = append(binds, b)
	}

	var err error
	if quitKey, err = resolveKey(*quit); err != nil {
		fail("--quit", *quit, err)
	}

	fmt.Println("The Long Run — auto-hold for The Long Dark")
	for _, b := range binds {
		fmt.Printf("  bind   : %s\n", b.label)
	}
	fmt.Printf("  quit   : %s\n", *quit)
	fmt.Println("Listening… (keep this window open while you play)")

	if C.runTap() != 0 {
		fmt.Println()
		fmt.Println("✗ Could not start. Grant this terminal app BOTH, then run again:")
		fmt.Println("  System Settings ▸ Privacy & Security ▸ Accessibility")
		fmt.Println("  System Settings ▸ Privacy & Security ▸ Input Monitoring")
		os.Exit(1)
	}
}

func fail(flagName, val string, err error) {
	fmt.Fprintf(os.Stderr, "invalid %s %q: %v\n", flagName, val, err)
	fmt.Fprintln(os.Stderr, "run with --list-keys to see valid names")
	os.Exit(2)
}

// resolveKey turns "w", "shift", "\\", "backslash", or "42" into a key code.
func resolveKey(tok string) (int, error) {
	tok = strings.TrimSpace(tok)
	if tok == "" {
		return 0, fmt.Errorf("empty")
	}
	if n, err := strconv.Atoi(tok); err == nil {
		return n, nil
	}
	if code, ok := keyNames[strings.ToLower(tok)]; ok {
		return code, nil
	}
	return 0, fmt.Errorf("unknown key")
}

func printKeyTable() {
	names := make([]string, 0, len(keyNames))
	for n := range keyNames {
		names = append(names, n)
	}
	sort.Strings(names)
	fmt.Println("Known key names (you can also pass a raw numeric code):")
	for _, n := range names {
		fmt.Printf("  %-12s %d\n", n, keyNames[n])
	}
}

// keyNames maps friendly names to macOS virtual key codes.
var keyNames = map[string]int{
	// letters
	"a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
	"i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35,
	"q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
	"y": 16, "z": 6,
	// digits
	"0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
	"5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
	// punctuation
	"minus": 27, "-": 27, "equal": 24, "=": 24,
	"leftbracket": 33, "[": 33, "rightbracket": 30, "]": 30,
	"backslash": 42, "\\": 42, "semicolon": 41, ";": 41,
	"quote": 39, "'": 39, "comma": 43, ",": 43,
	"period": 47, ".": 47, "slash": 44, "/": 44,
	"grave": 50, "`": 50,
	// whitespace / control
	"space": 49, "tab": 48, "return": 36, "enter": 36, "escape": 53, "esc": 53,
	"delete": 51, "backspace": 51,
	// arrows
	"left": 123, "right": 124, "down": 125, "up": 126,
	// modifiers
	"shift": 56, "leftshift": 56, "rightshift": 60,
	"ctrl": 59, "control": 59, "leftcontrol": 59, "rightcontrol": 62,
	"alt": 58, "option": 58, "leftoption": 58, "rightoption": 61,
	"cmd": 55, "command": 55, "leftcommand": 55, "rightcommand": 54,
	// function row
	"f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
	"f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
}
