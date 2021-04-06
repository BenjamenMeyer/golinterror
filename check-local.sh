#!/bin/bash
# A simple little tool to verify the desired support and compliance:
# - Verifies it compiles Windows, Linux, and Mac for x86-64 processors
# - Verifies it compiles for Mac ARM64
# - Verifies it matches the Golang lint requirements
# - Verifies the unit tests pass

GO_BINARY="go1.13.10"

# The following are for additional platforms but golang cross-compilation has some issues
# ARM has issues with Assembler output
# Linux:linux:arm:arm-linux-gnueabi-gcc:arm-linux-gnueabi-cpp
# ARM64 has issues with the -marm parameters
# Linux:linux:arm64:aarch64-linux-gnu-gcc:aarch64-linux-gnu-cpp
# Mac OSX:darwin:arm:arm-linux-gnueabi-gcc:arm-linux-gnueabi-cpp
# Mac OSX:darwin:arm64:aarch64-linux-gnu-gcc:aarch64-linux-gnu-cpp

# Windows has issues with the `-pthread` version `-mthread` for threading functionality
# `-mthread` enables the Multi-thread libraries on Windows.
# Windows:windows:386:i686-w64-mingw32-gcc:i686-w64-mingw32-g++
PLATFORM_TARGETS="
Linux:linux:amd64::
Mac OSX:darwin:amd64::
"


function runLinters()
{
    printf "\ngolangci-lint..."
    golangci-lint run -v --new-from-rev=HEAD~
    let -i ret=$?
    if [ ${ret} -eq 0 ]; then
        printf "\ngolint..."
        golint ./...
        let -i ret=$?
    fi
    return ${ret}
}

function doBuilds()
{
    local GO_BINARY="${1}"
    local OLD_IFS="${IFS}"
    IFS="
"
    local -i result=0
    for PLATFORM_TARGET in ${PLATFORM_TARGETS}
    do
        local TARGET_OS_NAME=$(echo ${PLATFORM_TARGET} | cut -f 1 -d ':')
        local TARGET_OS=$(echo ${PLATFORM_TARGET} | cut -f 2 -d ':')
        local TARGET_ARCH=$(echo ${PLATFORM_TARGET} | cut -f 3 -d ':')
        local TARGET_CC=$(echo ${PLATFORM_TARGET} | cut -f 4 -d ':')
        local TARGET_CXX=$(echo ${PLATFORM_TARGET} | cut -f 5 -d ':')
        printf "\nBuilding for ${TARGET_OS_NAME} (GOOS: ${TARGET_OS} - GOARCH: ${TARGET_ARCH}) ..."
        if [ -n "${TARGET_CC}" ]; then
            printf "Cross Compile..."
            CXX_FOR_TARGET=${TARGET_CXX} CC_FOR_TARGET=${TARGET_CC} CGO_ENABLED=1 GOOS=${TARGET_OS} GOARCH=${TARGET_ARCH} ${GO_BINARY} build
        else
            CGO_ENABLED=1 GOOS=${TARGET_OS} GOARCH=${TARGET_ARCH} ${GO_BINARY} build
        fi
        let -i result=$?
        if [ ${result} -ne 0 ]; then
            break
        fi
    done
    printf "\n"

    IFS="${OLD_IFS}"
    return ${result}
}

function doCleanDisk()
{
    local MY_TMPDIR="${TMPDIR}"
    if [ -z "${MY_TMPDIR}" ]; then
        MY_TMPDIR="/tmp"
    fi

    local WORK_LOCATION="${TMPDIR}"
    if [ -z "${WORK_LOCATION}" ]; then
        WORK_LOCATION="/tmp"
    fi

    for A_TESTFILE_DIR in `find "${WORK_LOCATION}" -maxdepth 1 -type d -name testfile-\**`
    do
        printf "Found: ${A_TESTFILE_DIR}\n"
        if [ -z "${A_TESTFILE_DIR}" ]; then
            printf "Skipping empty directory - ${WORKING_LOCATION} - ${A_TESTFILE_DIR}"
            continue
        fi
        if [ "${A_TESTFILE_DIR}" == "${MY_TMPDIR}" ]; then
            printf "Not cleaning out ${MY_TMPDIR}"
            continue
        fi
        if [ -d "${A_TESTFILE_DIR}" ]; then
            rm -Rf ${A_TESTFILE_DIR}/*
            rmdir "${A_TESTFILE_DIR}"
        fi
    done
}

function checkFormat()
{
    let -i ret=0
    CGO_ENABLED=1 go fmt ./...
    return ${ret}
}

function runUnitTests()
{
    local GO_BINARY="${1}"
    printf "\nRunning unit tests...\n"
    CGO_ENABLED=1 ${GO_BINARY} test '-coverprofile=coverage.txt' -covermode count -test.short -failfast -v ./...
    let -i ret=$?
    return ${ret}
}

function printRunIntegrationTestsHelp()
{
    local PROGRAM_NAME="${1}"
    printf "${PROGRAM_NAME} integration [<options>]\n"
    printf "\n"
    printf "    --enable-long-tests    enable tests that take extra long\n"
    printf "    --set-timeout <time>   set the timeout for the tests\n"
    printf "    --full-band-only       only run the full band tests\n"
    printf "    --concurrent-only      only run the concurrent access tests\n"
    printf "    --reload-only          only run the reload tests\n"
    printf "    --debug                run under the Golang dlv debugger\n"
    printf "\n"
    printf "NOTE: Recommend a timeout value of 900 for all current integration tests to pass. Default is 600."
    printf "\n"
    return 0
}

function runInstall()
{
    local GO_BINARY="${1}"

    if [ -f go.sum && -f go.mod ]; then
        git stash

        ${GO_BINARY} get -u golang.org/x/lint/golint
        curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(${GO_BINARY} env GOPATH)/bin v1.35.2

        git checkout go.sum
        git checkout go.mod

        #printf "Please install the following tools:\n"
        #printf "    arm-linux-gnueabi-gcc       gcc-arm-linux-gnueabi (Ubuntu)\n"

        # The following Debian/Ubuntu packages would be useful for cross compilation:
        # ARM64:
        #   gccgo-aarch64-linux-gnu
        # ARM:
        #   gcc-arm-linux-gnueabi
        # Win64:
        #   gcc-multilib
        #   gcc-mingw-w64

        git stash pop

    else
        printf "Run from the project loop\n"
    fi
}

function runIntegrationTests()
{
    local PROGRAM_NAME="${1}"
    shift
    local GO_BINARY="${1} test"
    shift

    local -i ENABLE_LONG_RUN_TEST=0
    local -i RUN_TIMEOUT=600
    local RUN_TEST_SUITE=""
    local RUN_TEST_SUITE_OPTS=""
    while (($#))
    do
        case "${1}" in
            "help")
                printRunIntegrationTestsHelp "${PROGRAM_NAME}"
                return 0
                ;;
            "--enable-long-tests")
                printf "Enabling log running integration tests\n"
                local -i ENABLE_LONG_RUN_TEST=1
                ;;
            "--set-timeout")
                shift
                printf "Updating timeout from ${RUN_TIMEOUT} seconds to ${1} seconds\n"
                local -i RUN_TIMEOUT=${1}
                ;;
            "--full-band-only")
                RUN_TEST_SUITE="-test.run TestIntegrationFullBand"
                ;;
            "--concurrent-only")
                RUN_TEST_SUITE="-test.run TestIntegrationConcurrentUse"
                ;;
            "--reload-only")
                RUN_TEST_SUITE="-test.run TestIntegrationReload"
                ;;
            "--check-race")
                RUN_TEST_SUITE_OPTS="${RUN_TEST_SUITE_OPTS} -race"
                ;;
            "--debug")
                printf "Enabling Debug Mode"
                GO_BINARY="dlv test --"
                ;;
            *)
                printf "Unknown argument: ${1}"
                printRunIntegrationTestsHelp "${PROGRAM_NAME}"
                return 1
                ;;
        esac
        shift
    done

    printf "\nRunning integration tests...\n"
    local INTEGRATION_TEST_OPTIONS=""
    if [ ${ENABLE_LONG_RUN_TEST} -eq 0 ]; then
        INTEGRATION_TEST_OPTIONS="-test.short"
    fi
    if [ ${RUN_TIMEOUT} -eq 0 ]; then
        printf "*** Timeout Disabled ***\n"
    fi
    printf "Test Timeout: ${RUN_TIMEOUT} seconds\n"
    CGO_ENABLED=1 ${GO_BINARY} -test.failfast ${INTEGRATION_TEST_OPTIONS} -test.v -test.timeout ${RUN_TIMEOUT}s . ${RUN_TEST_SUITE} ${RUN_TEST_SUITE_OPTS}
    let -i ret=$?
    return ${ret}
}

function main()
{
    printf "Go version: $(${GO_BINARY} version)\n"
    printf "Linting..."
    runLinters
    if [ $? -eq 0 ]; then
        printf "\nChecking formatting..."
        checkFormat
        let -i cfResult=$?
        if [ ${cfResult} -eq 0 ]; then
            printf "\nTesting build..."
            doBuilds "${GO_BINARY}"
            if [ $? -eq 0 ]; then
                runUnitTests "${GO_BINARY}"
                if [ $? -eq 0 ]; then
                    printf "\nDone"
                fi
            fi
        else
            printf "result: ${cfResult}"
        fi
    fi
    printf "\n"
}

function printHelp()
{
    local PROGRAM_NAME="${1}"
    printf "${PROGRAM_NAME} [<command> [<options>]]\n"
    printf "\n"
    printf "<options> may be one of the following:\n\n"
    printf "    build           only compile the software\n"
    printf "    format          only apply the formatters\n"
    printf "    help            show this screen\n"
    printf "    install         install tooling\n"
    printf "    integration     only run the integration tests\n"
    printf "    lint            only run the linters\n"
    printf "    test            only run the unit tests"
    printf "\n\n"
    printf "By default all functionality is run in the following order:\n"
    printf "  1. linters\n"
    printf "  2. formatters\n"
    printf "  3. builds\n"
    printf "  4. unit tests\n"
    printf "\n"
    return 0
}

COMMAND="${1}"
shift
case "${COMMAND}" in

"build")
    doBuilds "${GO_BINARY}"
    printf "\n"
    ;;

"clean")
    doCleanDisk
    ;;

"coverage")
    ${GO_BINARY} tool cover -html=coverage.txt
    ;;

"format")
    checkFormat
    ;;

"help")
    printHelp "${0}"
    ;;

"install")
    runInstallTools "${GO_BINARY}" ${@}
    ;;

"integration")
    runIntegrationTests "${0}" "${GO_BINARY}" ${@}
    ;;

"lint")
    runLinters
    printf "\n"
    ;;

"test")
    runUnitTests "${GO_BINARY}"
    exit $?
    ;;

*)
    main
    ;;

esac
