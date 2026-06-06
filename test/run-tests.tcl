#!/usr/bin/env tclsh
# Minimal Tcl test harness. Add real cases as implementation lands.

set repo_root [file dirname [file dirname [file normalize [info script]]]]
source [file join $repo_root lib manifest.tcl]
source [file join $repo_root lib ballot.tcl]
source [file join $repo_root lib tally.tcl]

set ::passed 0
set ::failed 0

proc test {name body} {
    if {[catch {uplevel 1 $body} err]} {
        incr ::failed
        puts "FAIL: $name -- $err"
    } else {
        incr ::passed
        puts "ok:   $name"
    }
}

# --- phase 1 smoke tests ---
# These confirm the modules load and that unimplemented stubs error as expected.
# Replace each with a real assertion as the corresponding function is written.

test "manifest::load stub errors on missing file" {
    if {![catch {::ppp::manifest::load /nonexistent/manifest.json} _err]} {
        error "expected error from unimplemented load"
    }
}

test "ballot::load stub errors on missing file" {
    if {![catch {::ppp::ballot::load /nonexistent/ballot.json} _err]} {
        error "expected error from unimplemented load"
    }
}

test "tally::run stub errors when called" {
    if {![catch {::ppp::tally::run {} {} ""} _err]} {
        error "expected error from unimplemented tally"
    }
}

puts ""
puts "$::passed passed, $::failed failed"
exit [expr {$::failed > 0}]
