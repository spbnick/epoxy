Epoxy
=====

> — a Bash testing framework.
> Named after the stronger kind of glue.

Development status: base functionality implemented, the framework is useful,
many more features planned, bugs likely exist.

See a presentation comparing Epoxy to BeakerLib:
http://slides.com/spbnick/epoxy

Installation
------------

Requirements:

* Bash >= 3.2.25
* Lua >= 5.1
* Python >= 2.4.3
* Thud (https://github.com/spbnick/thud)

Autoconf and automake are needed for installing from git.

Installing from git:
./bootstrap && ./configure && make install

Installing from distribution tarball:
./configure && make install


Introduction
------------

NOTE: below the word "assertion" used alone usually means
      "assertion verification".

Main features:

* Nesting assertions
* Ability to verify selected assertions only
* Verified setup and teardown execution
* Terse output by default, verbose when requested

Each assertion has a name, can have a brief description and a failure reason
description attached. Names of nested assertions are combined into paths with
slash as name initiator. The root assertion path is empty string.

Any assertion verification can be disabled, or its result waived in the code.
Any assertion can be enabled, claimed (unwaived), or skipped with command-line
options, arguments, or environment variables.

All the code is executed with "errexit" shell attribute set ("set -e").

Each assertion is either a "test" or a "suite", and could be implemented as
either an executable, a subshell, or a shell function.

A test verifies an assertion directly and can contain only verification code,
i.e. no setup or teardown. It can only be considered PASSED or FAILED.

A suite verifies an assertion only indirectly and can contain only setup and
teardown code along with invocations of other suites and tests. It is only
considered PASSED if all the invoked assertions PASSED.

If any setup command fails, the suite is considered ERRORED, normal execution
is stopped and teardown commands are executed. If any teardown command fails,
the suite is considered PANICKED and is stopped immediately, without
proceeding with further teardown. If a coding error occurred, such as passing
invalid arguments to a function, a suite is considered ABORTED and is stopped
immediately, without teardown.

If an assertion invoked by the suite is considered FAILED or ERRORED, the
suite is considered FAILED or ERRORED respectively, but otherwise proceeds.
If an invoked assertion is considered PANICKED or ABORTED, the suite is
considered PANICKED or ABORTED respectively, and is stopped immediately,
without teardown.

An example of a typical suite executable (try running it):

    #!/bin/bash

    # Add Epoxy module directory to PATH
    . <(ep_env || echo exit 1)

    # Source epoxy modules
    . ep.sh

    # Initialize the suite shell, processing command line arguments
    ep_suite_init "$@"
    # After the line above, all the code, except tests, is considered setup code

    declare TMP_DIR="`mktemp -d`"
    # Push a command to the teardown stack - it will be executed on exit
    ep_teardown_push rm -Rf "$TMP_DIR"

    pushd "$TMP_DIR" >/dev/null
    # Push another command to the teardown stack, to be executed *before* the
    # previously pushed one
    ep_teardown_push eval 'popd >/dev/null'

    # A subshell suite
    ep_suite_begin file; (
        ep_suite_init
        ep_teardown_push rm -f file1 file2
        ep_test create touch file1
        touch file2
        ep_test remove rm file2
    ); ep_suite_end

    # Another subshell suite
    ep_suite_begin dir; (
        ep_suite_init
        ep_teardown_push rm -Rf dir1 dir2
        ep_test create mkdir dir1
        mkdir dir2
        ep_test remove rmdir dir2
    ); ep_suite_end

    # A suite function
    # Args: num_files
    function stress_create() {
        declare -r num_files="$1"
        declare i
        ep_teardown_push eval "
            declare i
            for((i = 1; i <= $num_files; i++)); do \
                rm -f \"\$i\"; \
            done"
        for((i = 1; i <= num_files; i++)); do
            ep_test "$i" touch "$i"
        done
    }

    # A function suite invocation
    ep_suite_sh stress stress_create 10

Run the suite executable with "--help" option to get command-line usage
information, and experiment.

The most useful framework functions:

    ep_suite_init   Initialize a suite shell, used at the beginning of a suite
    ep_suite        Run a suite executable
    ep_suite_sh     Run a suite function
    ep_suite_begin  Setup a suite execution, used before a suite subshell
    ep_suite_end    Conclude a suite execution, used after a suite subshell

    ep_test_init    Initialize a test shell, used at the beginning of a test
    ep_test         Run a test executable
    ep_test_sh      Run a test function
    ep_test_begin   Setup a test execution, used before a test subshell
    ep_test_end     Conclude a test execution, used after a test subshell

    ep_teardown_push    Push a command to the suite teardown command stack
    ep_teardown_pop     Pop a command from the suite teardown command stack

Look at ep.sh and other modules for slightly more detailed function
descriptions and source code. Look at test suites under "tests" for more
examples.
