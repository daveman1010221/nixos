#!/run/current-system/sw/bin/bash

set -euo pipefail  # Safer script execution
shopt -s lastpipe
export LC_ALL=C

[[ "${DRY_RUN:-0}" == "1" ]] && echo -e "\033[1;33m[DRY-RUN]\033[0m No changes will be made."

# ---------------------------------------------------------------

### FUNCTIONS
# Prompt the operator for explicit confirmation before proceeding.
# Usage: confirm "Message about what you're about to do"
# Requires an exact "YES" (all caps, no spaces). Anything else aborts.
confirm() {
    local msg="${1:-Proceed with potentially destructive action?}"

    echo -e "\n\033[1;33m[WARNING]\033[0m $msg"
    read -r -p "Type 'YES' to proceed: " response

    if [[ "$response" != "YES" ]]; then
        echo -e "\033[1;31m[ABORT]\033[0m User declined (typed: ${response:-<empty>})"
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────
# NVMe SED helper functions (no heredocs; inline expect)
# ────────────────────────────────────────────────────────────────

# Initialize Opal on a namespace using the per-controller SID derived earlier.
# Preconditions:
#   - Run as root (EUID==0)
#   - $dev is a namespace (/dev/nvmeXnY)
#   - sed_load_key_by_serial <serial> already works (creates/loads $SED_KEY)
# Behavior:
#   - Never logs the SID; logs only lengths and tool output.
#   - Returns the exit status of `nvme sed initialize`.
sed_initialize() {
    local dev="$1"
    echo "dev: ${dev}"

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        local serial; serial="$(ctrl_serial_for_dev "$dev")" || return 1
        echo "[DRY] nvme sed initialize $dev (serial=$serial)"
        return 0
    fi

    # 1) Basic validation
    if [[ -z "$dev" || ! -e "$dev" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_initialize: device not found: $dev" >&2
        return 2
    fi
    if [[ ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_initialize: expected NVMe *namespace* (/dev/nvmeXnY), got: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_initialize: must run as root (avoid sudo prompts inside expect)" >&2
        return 2
    fi

    # 2) Map namespace -> controller serial and load the per-drive key
    local serial
    serial="$(ctrl_serial_for_dev "$dev")" || return 1

    sed_load_key_by_serial "$serial" || return 1

    # 3) Enforce firmware-safe SID policy *before* we hit the tool
    if ! validate_sid "$SED_KEY"; then
        echo -e "\033[1;31m[ERR]\033[0m sed_initialize: SED_KEY fails policy (8–32 chars, A–Z0–9_.:@#-). Check derivation." >&2
        return 3
    fi

    # 4) Log setup (private file)
    local log_dir="${SED_LOG_DIR:-/tmp/sed-debug}"
    local log="${log_dir}/initialize-$(basename "$dev").log"
    mkdir -p "$log_dir"
    : > "$log" && chmod 0600 "$log"
    SED_LAST_INIT_LOG="$log"

    echo -e "\033[1;34m[INFO]\033[0m Initializing Opal on ${dev}… (log: $log)"

    # 5) Expect script (balanced braces; rc=98 Host Not Authorized/BLOCKSID, rc=97 Authority Locked Out)
    DEV="$dev" SED_KEY="$SED_KEY" LOG_FILE="$log" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
        # Strict-ish expect harness
        if {[info exists env(SED_INIT_TIMEOUT)]} {
            set timeout [expr {int($env(SED_INIT_TIMEOUT))}]
        } else {
            set timeout 120
        }
        proc safe_send {s} { send -- $s }

        set dev   $env(DEV)
        send_user "DBG_INIT: dev: $dev\n"
        set pw    $env(SED_KEY)
        set logf  $env(LOG_FILE)

        if {[catch {log_file -a $logf} err]} { send_user "DBG_INIT: cannot log to $logf: $err\n" }
        log_user 1

        # Track special failures we care about at the call-site
        set hostna 0
        set alock  0

        # Pre-discover for context (ignore failures)
        send_user "DBG_INIT: discover(before)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} pre
        if {[string length $pre] > 0} { send_user "$pre\n" }

        # Spawn initialize
        if {[catch {spawn $env(NVME_BIN) sed initialize $dev} err]} {
            send_user "DBG_INIT: spawn failed: $err\n"; exit 1
        }

        # Drive the prompts
        expect {
          -re {(?i)new.*pass(word)?|new.*key.*:} {
              send_user "DBG_INIT: NEW prompt -> sending (len=[string length $pw])\n"
              safe_send "$pw\r"
              exp_continue
          }
          -re {(?i)re-?enter.*pass(word)?|re-?enter.*key.*:} {
              send_user "DBG_INIT: RE-ENTER prompt -> sending\n"
              safe_send "$pw\r"
              exp_continue
          }
          -re {(?i)pass(word)?|key.*:} {
              send_user "DBG_INIT: generic pass/key prompt -> sending\n"
              safe_send "$pw\r"
              exp_continue
          }
          -re {(?i)(not supported|No such file|Operation not permitted|Permission denied|invalid argument)} {
              send_user "DBG_INIT: ERROR from tool matched; continuing to EOF for rc\n"
              exp_continue
          }
          -re {(?i)host[^a-z]+not[^a-z]+authorized} {
              # Refused "take ownership" (BlockSID/prior owner)
              send_user "DBG_INIT: HOST NOT AUTHORIZED detected\n"
              set hostna 1
              exp_continue
          }
          -re {(?i)authority[[:space:]]+locked[[:space:]]+out} {
              send_user "DBG_INIT: AUTHORITY LOCKED OUT detected\n"
              set alock 1
              exp_continue
          }
          -re {(?i)block[- ]?sid} {
              send_user "DBG_INIT: BLOCKSID hint detected\n"
              set hostna 1
              exp_continue
          }
          timeout {
              send_user "DBG_INIT: TIMEOUT during initialize\n"
          }
          eof {
              # fallthrough; we will read rc next
          }
        }

        # Child exit code
        set rc [lindex [wait] 3]

        # Post-discover for verification context
        send_user "DBG_INIT: discover(after)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} post
        if {[string length $post] > 0} { send_user "$post\n" }

        if {$hostna} {
            send_user "DBG_INIT: rc=$rc (override -> 98 due to HOST NOT AUTHORIZED)\n"
            exit 98
        } elseif {$alock} {
            send_user "DBG_INIT: rc=$rc (override -> 97 due to AUTHORITY LOCKED OUT)\n"
            exit 97
        } else {
            send_user "DBG_INIT: rc=$rc\n"
            exit $rc
        }
    '
    rc=$?
    make_log_user_readable "$log"
    return $rc
}

# If initialize fails with "Host Not Authorized", do a PSID revert (ERASES ALL DATA) then instruct a full power-cycle.
# Preconditions:
#   - Run as root
#   - $dev is a namespace (/dev/nvmeXnY)
sed_psid_revert_then_die() {
    local dev="$1"

    # 1) Validate device & privileges
    if [[ -z "$dev" || ! -e "$dev" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m PSID revert: device not found: $dev" >&2
        exit 2
    fi
    if [[ ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m PSID revert: expected NVMe *namespace* (/dev/nvmeXnY), got: $dev" >&2
        exit 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m PSID revert: must run as root." >&2
        exit 2
    fi

    # Map namespace -> controller serial (helps match physical label)
    local serial="(unknown)"
    serial="$(ctrl_serial_for_dev "$dev" 2>/dev/null || true)"; [[ -n "$serial" ]] || serial="(unknown)"

    echo -e "\033[1;33m[WARN]\033[0m initialize failed with authorization error on ${dev} (controller serial: \033[1;36m${serial}\033[0m)."
    echo -e "\033[1;33m[WARN]\033[0m A PSID revert will \033[1;31mERASE ALL DATA\033[0m on this drive."
    local PSID RAW
    while :; do
        read -rsp "Enter PSID for ${dev} [serial: ${serial}] (uppercase, no dashes/spaces): " RAW; echo

        # Normalize: strip spaces and force uppercase; then validate.
        PSID="$(printf '%s' "$RAW" | tr -d '[:space:]')"

        # Policy: A–Z/0–9, len 8..64 (most are 32–34)
        if [[ "$PSID" =~ ^[A-Za-z0-9]{8,64}$ ]]; then
            break
        fi

        read -rsp "Enter PSID for ${dev} [serial: ${serial}] (case-sensitive, no dashes/spaces): " RAW; echo

        echo -e "\033[1;31m[ERR]\033[0m PSID format looks wrong. Use A–Z/a–z/0–9, no separators."
    done

    # 3) Private log
    local log_dir="${SED_LOG_DIR:-/tmp/sed-debug}"
    local log="${log_dir}/revert-psid-$(basename "$dev").log"
    mkdir -p "$log_dir"
    : > "$log" && chmod 0600 "$log"

    echo -e "\033[1;33m[WARN]\033[0m Reverting ${dev} via PSID… (log: $log)"

    DEV="$dev" PSID="$PSID" LOG_FILE="$log" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
        set timeout 120
        set dev   $env(DEV)
        set psid  $env(PSID)
        set logf  $env(LOG_FILE)

        if {[catch {log_file -a $logf} err]} { send_user "DBG_PSID: cannot log to $logf: $err\n" }
        log_user 1

        # Optional: show discover (ignore failures)
        send_user "DBG_PSID: discover(before)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} pre
        if {[string length $pre] > 0} { send_user "$pre\n" }

        # Spawn revert --psid (tool will prompt for PSID)
        if {[catch {spawn $env(NVME_BIN) sed revert $dev --psid} err]} {
            send_user "DBG_PSID: spawn failed: $err\n"; exit 1
        }

        expect {
          -re {(?i)psid.*:} {
              send_user "DBG_PSID: PSID prompt detected -> sending (not echoed)\n"
              send -- "$psid\r"; exp_continue
          }
          -re {(?i)(not supported|No such file|invalid argument|Operation not permitted|Permission denied)} {
              send_user "DBG_PSID: ERROR from tool; aborting\n"
              # Let child exit; we still capture rc below
              exp_continue
          }
          timeout {
              send_user "DBG_PSID: TIMEOUT during revert\n"
          }
          eof {}
        }

        set rc [lindex [wait] 3]
        send_user "DBG_PSID: rc=$rc\n"
        exit $rc
    '
    rc=$?
    make_log_user_readable "$log"

    if [[ $rc -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m PSID revert failed for ${dev} (rc=$rc). Check the PSID and logs: $log" >&2
        exit $rc
    fi

    # Mark and return (do NOT exit mid-run). Final summary/exit happens after all drives.
    PSID_REVERTED_DEVICES+=("${dev}${serial:+ (serial: $serial)}")
    NEED_POWER_CYCLE=1
    return 90
}

# Revert a drive out of Opal state.
# mode: 'normal' | 'destructive' | 'psid'
# Env (optional):
#   SED_LOG_DIR           (default: /tmp/sed-debug)
#   SED_REVERT_TIMEOUT_S  (default: 600)  # overall deadline for 'destructive'
sed_revert() {
    local dev="$1"
    local mode="$2"

    echo "sed_revert::dev: $dev"

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        echo "[DRY] nvme sed revert $dev --${mode}"
        return 0
    fi

    local logdir="${SED_LOG_DIR:-/tmp/sed-debug}"

    # Default the destructive revert watchdog to something sane (overridable)
    local deadline="${SED_REVERT_TIMEOUT_S:-30}"

    # Sanity: force integer >= 0
    if ! [[ "$deadline" =~ ^[0-9]+$ ]]; then deadline=30; fi

    # --- guardrails ---
    if [[ -z "$dev" || -z "$mode" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_revert: usage sed_revert /dev/nvmeXnY <normal|destructive|psid>" >&2
        return 2
    fi
    if [[ ! -e "$dev" || ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_revert: expected NVMe *namespace* (/dev/nvmeXnY), got: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_revert: must run as root (no sudo inside expect)" >&2
        return 2
    fi

    mkdir -p "$logdir" 2>/dev/null || true
    local log="$logdir/revert-${mode}-$(basename "$dev").log"
    if ! : > "$log" 2>/dev/null; then
        echo -e "\033[1;33m[WARN]\033[0m $logdir not writable; logging to stderr."
        log="/dev/stderr"
    else
        chmod 0600 "$log" || true
    fi

    echo -e "\033[1;33m[WARN]\033[0m Reverting ${dev} from Opal state (mode=${mode})… (log: $log)"

    case "$mode" in
      normal)
        DEV="$dev" LOG_FILE="$log" DEADLINE="$deadline" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
            # Respect DEADLINE (seconds). 0 means "no timeout" (not recommended).
            if {[info exists env(DEADLINE)]} {
              set t [expr {int($env(DEADLINE))}]
              if {$t < 0} { set t 0 }
              set timeout $t
            } else {
              set timeout 30
            }
            set dev   $env(DEV)
            set logf  $env(LOG_FILE)
            if {[catch {log_file -a $logf} err]} { send_user "DBG_REV(normal): cannot open $logf: $err\n" }
            log_user 1

            send_user "DBG_REV(normal): discover(before)\n"
            catch {exec $env(NVME_BIN) sed discover $dev} pre
            if {[string length $pre] > 0} { send_user "$pre\n" }

            if {[catch {spawn $env(NVME_BIN) sed revert $dev} err]} {
              send_user "DBG_REV(normal): spawn failed: $err\n"; exit 1
            }
            send_user "DBG_REV(normal): timeout=${timeout}s\n"

            expect {
              -re {(?i)continue.*\\(y/n\\)\\?}       { send_user "DBG_REV(normal): Continue? -> y\n"; send -- "y\r"; exp_continue }
              -re {(?i)are you sure.*\\(y/n\\)\\?}   { send_user "DBG_REV(normal): Are you sure? -> y\n"; send -- "y\r"; exp_continue }
              -re {(?i)pass(word)?|key.*:} {
                  set sendpw ""
                  if {[info exists env(SED_KEY)] && [string length $env(SED_KEY)]>0} {
                      set sendpw $env(SED_KEY)
                  }
                  send_user "DBG_REV(normal): password/key prompt -> sending [expr {[string length $sendpw]>0 ? "SED_KEY" : "<blank>"}]\n"
                  send -- "$sendpw\r"; exp_continue
              }
              -re {(?i)(not supported|No such file|invalid argument|Operation not permitted|Permission denied)} {
                                                     send_user "DBG_REV(normal): ERROR from tool; aborting\n"; exp_continue }
              timeout                                { send_user "DBG_REV(normal): TIMEOUT\n"; exit 124 }
              eof {}
            }

            set rc [lindex [wait] 3]
            send_user "DBG_REV(normal): rc=$rc\n"
            exit $rc
        '
        make_log_user_readable "$log"
        return $? ;;

      destructive)
        DEV="$dev" LOG_FILE="$log" DEADLINE="$deadline" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
            set timeout 0 ;# we manage time manually
            set dev      $env(DEV)
            set logf     $env(LOG_FILE)
            set deadline [expr {int($env(DEADLINE))}]

            if {[catch {log_file -a $logf} err]} { send_user "DBG_REV(destructive): cannot open $logf: $err\n" }
            log_user 1

            send_user "DBG_REV(destructive): discover(before)\n"
            send_user "DBG_REV(destructive): dev: $dev\n"
            catch {exec $env(NVME_BIN) sed discover $dev} pre
            if {[string length $pre] > 0} { send_user "$pre\n" }

            if {[catch {spawn $env(NVME_BIN) sed revert $dev --destructive} err]} {
              send_user "DBG_REV(destructive): spawn failed: $err\n"; exit 1
            }
            set pid [exp_pid]
            set t0 [clock seconds]
            send_user "DBG_REV(destructive): spawned pid=$pid, deadline=${deadline}s\n"

            while {1} {
              set now [clock seconds]
              if {$deadline > 0 && ($now - $t0) >= $deadline} {
                send_user "DBG_REV(destructive): deadline reached, sending INT to $pid\n"
                catch {exec kill -INT $pid}
                after 3000
                catch {exec kill -KILL $pid}
                exit 124
              }
              expect {
                -re {(?i)continue.*\\(y/n\\)\\?}       { send_user "DBG_REV(destructive): Continue? -> y\n"; send -- "y\r"; exp_continue }
                -re {(?i)are you sure.*\\(y/n\\)\\?}   { send_user "DBG_REV(destructive): Are you sure? -> y\n"; send -- "y\r"; exp_continue }
                -re {(?i)pass(word)?|key.*:}           { send_user "DBG_REV(destructive): password/key prompt -> <blank>\n"; send -- "\r"; exp_continue }
                -re {(?i)(not supported|No such file|invalid argument|Operation not permitted|Permission denied)} {
                                                       send_user "DBG_REV(destructive): ERROR from tool; aborting\n"; exp_continue }
                timeout                                { after 3000; }
                eof                                    { break }
              }
            }

            set rc [lindex [wait] 3]
            send_user "DBG_REV(destructive): rc=$rc\n"
            exit $rc
        '
        make_log_user_readable "$log"
        return $? ;;

      psid)
          # Helpful: show controller serial in the prompt
          local serial="(unknown)"
          serial="$(ctrl_serial_for_dev "$dev" 2>/dev/null || true)"; [[ -n "$serial" ]] || serial="(unknown)"
          local PSID RAW
          while :; do
            read -rsp "Enter PSID for ${dev} [serial: ${serial}] (case-sensitive, no dashes/spaces): " RAW; echo
            # Keep exact case; just strip whitespace
            PSID="$(printf '%s' "$RAW" | tr -d '[:space:]')"
            [[ "$PSID" =~ ^[A-Za-z0-9]{8,64}$ ]] && break
            echo -e "\033[1;31m[ERR]\033[0m PSID format looks wrong. Use A–Z/a–z/0–9, no separators."
          done

          # Final sanity
          if ! [[ "$PSID" =~ ^[A-Za-z0-9]{8,64}$ ]]; then
            echo -e "\033[1;31m[ERR]\033[0m PSID format invalid (expect [A-Za-z0-9], length 8..64)."
            return 2
          fi

          # PSID path: some firmwares show *two* confirmations before PSID prompt.
          # Provide shorter default timeout; let env override via SED_PSID_TIMEOUT_S.
          DEV="$dev" PSID="$PSID" LOG_FILE="$log" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
              if {[info exists env(SED_PSID_TIMEOUT_S)]} { set timeout [expr {int($env(SED_PSID_TIMEOUT_S))}] } else { set timeout 120 }
              set dev  $env(DEV)
              set psid $env(PSID)
              set logf $env(LOG_FILE)
              if {[catch {log_file -a $logf} err]} { send_user "DBG_PSID: cannot open $logf: $err\n" }
              log_user 1

              send_user "DBG_PSID: discover(before)\n"
              catch {exec $env(NVME_BIN) sed discover $dev} pre
              if {[string length $pre] > 0} { send_user "$pre\n" }

              if {[catch {spawn $env(NVME_BIN) sed revert $dev --psid} err]} {
                send_user "DBG_PSID: spawn failed: $err\n"; exit 1
              }
              expect {
                -re {(?i)destructive.*continue.*\\(y/n\\)\\?} { send_user "DBG_PSID: confirm#1 -> y\n"; send -- "y\r"; exp_continue }
                -re {(?i)are you sure.*\\(y/n\\)\\?}          { send_user "DBG_PSID: confirm#2 -> y\n"; send -- "y\r"; exp_continue }
                -re {(?i)psid.*:}                             { send_user "DBG_PSID: PSID prompt -> sending (not echoed)\n"; send -- "$psid\r"; exp_continue }
                -re {(?i)(not supported|No such file|invalid argument|Operation not permitted|Permission denied)} {
                                                               send_user "DBG_PSID: ERROR from tool; continuing to EOF\n"; exp_continue }
                timeout                                       { send_user "DBG_PSID: TIMEOUT during revert\n" }
                eof {}
              }
              set rc [lindex [wait] 3]
              send_user "DBG_PSID: rc=$rc\n"
              exit $rc
          '
          make_log_user_readable "$log"
          return $? ;;
    esac
}

# Unlock (needs existing password on the controller owning this namespace)
sed_unlock() {
    local dev="$1"

    [[ "${DRY_RUN:-0}" == "1" ]] && { echo "[DRY] nvme sed unlock $dev"; return 0; }

    # 1) Guardrails
    if [[ -z "$dev" || ! -e "$dev" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_unlock: device not found: $dev" >&2
        return 2
    fi
    if [[ ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_unlock: expected NVMe *namespace* (/dev/nvmeXnY), got: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_unlock: must run as root (avoid sudo prompts in expect)" >&2
        return 2
    fi

    # 2) Load per-drive SID by controller serial
    local serial
    serial="$(ctrl_serial_for_dev "$dev")" || return 1
    sed_load_key_by_serial "$serial" || return 1
    if ! validate_sid "$SED_KEY"; then
        echo -e "\033[1;31m[ERR]\033[0m sed_unlock: SED_KEY fails policy (8–32, A–Z0–9_.:@#-)" >&2
        return 3
    fi

    # 3) Log file (private)
    local log_dir="${SED_LOG_DIR:-/tmp/sed-debug}"
    local log="${log_dir}/unlock-$(basename "$dev").log"
    mkdir -p "$log_dir" || true
    : > "$log" 2>/dev/null && chmod 0600 "$log" || log="/dev/stderr"

    echo -e "\033[1;34m[INFO]\033[0m Unlocking ${dev}… (log: $log)"

    # 4) Expect harness
    DEV="$dev" SED_KEY="$SED_KEY" LOG_FILE="$log" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
        set timeout 60
        set dev   $env(DEV)
        set pw    $env(SED_KEY)
        set logf  $env(LOG_FILE)

        if {[catch {log_file -a $logf} err]} { send_user "DBG_UNLOCK: cannot log to $logf: $err\n" }
        log_user 1

        # Optional pre-discover (ignore failures)
        send_user "DBG_UNLOCK: discover(before)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} pre
        if {[string length $pre] > 0} { send_user "$pre\n" }

        if {[catch {spawn $env(NVME_BIN) sed unlock $dev --ask-key} err]} {
            send_user "DBG_UNLOCK: spawn failed: $err\n"; exit 1
        }

        expect {
          -re {(?i)pass(word)?|key.*:} {
              send_user "DBG_UNLOCK: key prompt -> sending (len=[string length $pw])\n"
              send -- "$pw\r"; exp_continue
          }
          -re {(?i)(not supported|No such file|invalid argument|Operation not permitted|Permission denied)} {
              send_user "DBG_UNLOCK: ERROR from tool; aborting\n"; exp_continue
          }
          timeout { send_user "DBG_UNLOCK: TIMEOUT during unlock\n"; exit 124 }
          eof {}
        }

        set rc [lindex [wait] 3]

        # Optional post-discover
        send_user "DBG_UNLOCK: discover(after)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} post
        if {[string length $post] > 0} { send_user "$post\n" }

        send_user "DBG_UNLOCK: rc=$rc\n"
        exit $rc
    '

    make_log_user_readable "$log"
    return $?
}

# Lock the drive (requires current password on the controller owning this namespace)
sed_lock() {
    local dev="$1"

    [[ "${DRY_RUN:-0}" == "1" ]] && { echo "[DRY] nvme sed lock $dev"; return 0; }

    # 1) Guardrails
    if [[ -z "$dev" || ! -e "$dev" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_lock: device not found: $dev" >&2
        return 2
    fi
    if [[ ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_lock: expected NVMe *namespace* (/dev/nvmeXnY), got: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_lock: must run as root (avoid sudo prompts in expect)" >&2
        return 2
    fi

    # 2) Load per-drive SID by controller serial
    local serial
    serial="$(ctrl_serial_for_dev "$dev")" || return 1
    sed_load_key_by_serial "$serial" || return 1
    if ! validate_sid "$SED_KEY"; then
        echo -e "\033[1;31m[ERR]\033[0m sed_lock: SED_KEY fails policy (8–32, A–Z0–9_.:@#-)" >&2
        return 3
    fi

    # 3) Log file (private)
    local log_dir="${SED_LOG_DIR:-/tmp/sed-debug}"
    local log="${log_dir}/lock-$(basename "$dev").log"
    mkdir -p "$log_dir" || true
    : > "$log" 2>/dev/null && chmod 0600 "$log" || log="/dev/stderr"

    echo -e "\033[1;34m[INFO]\033[0m Locking ${dev}… (log: $log)"

    # 4) Expect harness
    DEV="$dev" SED_KEY="$SED_KEY" LOG_FILE="$log" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
        set timeout 60
        set dev   $env(DEV)
        set pw    $env(SED_KEY)
        set logf  $env(LOG_FILE)

        if {[catch {log_file -a $logf} err]} { send_user "DBG_LOCK: cannot log to $logf: $err\n" }
        log_user 1

        # Optional pre-discover (ignore failures)
        send_user "DBG_LOCK: discover(before)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} pre
        if {[string length $pre] > 0} { send_user "$pre\n" }

        if {[catch {spawn $env(NVME_BIN) sed lock $dev --ask-key} err]} {
            send_user "DBG_LOCK: spawn failed: $err\n"; exit 1
        }

        expect {
          -re {(?i)pass(word)?|key.*:} {
              send_user "DBG_LOCK: key prompt -> sending (len=[string length $pw])\n"
              send -- "$pw\r"; exp_continue
          }
          -re {(?i)(not supported|No such file|invalid argument|Operation not permitted|Permission denied)} {
              send_user "DBG_LOCK: ERROR from tool; aborting\n"; exp_continue
          }
          timeout { send_user "DBG_LOCK: TIMEOUT during lock\n"; exit 124 }
          eof {}
        }

        set rc [lindex [wait] 3]

        # Optional post-discover
        send_user "DBG_LOCK: discover(after)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} post
        if {[string length $post] > 0} { send_user "$post\n" }

        send_user "DBG_LOCK: rc=$rc\n"
        exit $rc
    '
    make_log_user_readable "$log"
    return $?
}

# Change Opal password (old -> new) for a namespace with nvme-cli 2.11-style prompts.
# Requires helpers you already have:
#   - ctrl_serial_for_dev
#   - sed_load_key_by_serial (loads current into $SED_KEY)
#   - sed_load_next_key_by_serial (loads desired new into $SED_KEY_NEW)
#   - validate_sid
sed_change_password() {
    local dev="$1"

    [[ "${DRY_RUN:-0}" == "1" ]] && { echo "[DRY] nvme sed password $dev"; return 0; }

    if [[ -z "$dev" || ! -e "$dev" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_change_password: device not found: $dev" >&2
        return 2
    fi
    if [[ ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_change_password: expected NVMe namespace (/dev/nvmeXnY), got: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_change_password: must run as root" >&2
        return 2
    fi

    local serial
    serial="$(ctrl_serial_for_dev "$dev")" || return 1

    sed_load_key_by_serial "$serial" || return 1
    local OLD_KEY="$SED_KEY"
    if ! validate_sid "$OLD_KEY"; then
        echo -e "\033[1;31m[ERR]\033[0m sed_change_password: current key fails policy" >&2
        return 3
    fi
    sed_load_next_key_by_serial "$serial" || return 1
    local NEW_KEY="$SED_KEY_NEW"
    if ! validate_sid "$NEW_KEY"; then
        echo -e "\033[1;31m[ERR]\033[0m sed_change_password: new key fails policy" >&2
        return 3
    fi

    local log_dir="${SED_LOG_DIR:-/tmp/sed-debug}"
    local log="${log_dir}/password-$(basename "$dev").log"
    mkdir -p "$log_dir" || true
    : > "$log" 2>/dev/null && chmod 0600 "$log" || log="/dev/stderr"

    DEV="$dev" OLD_KEY="$OLD_KEY" NEW_KEY="$NEW_KEY" LOG_FILE="$log" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
        set timeout 90
        set dev  $env(DEV)
        set old  $env(OLD_KEY)
        set new  $env(NEW_KEY)
        set logf $env(LOG_FILE)

        if {[catch {log_file -a $logf} err]} { send_user "DBG_PW: cannot log to $logf: $err\n" }
        log_user 1

        send_user "DBG_PW: discover(before)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} pre
        if {[string length $pre] > 0} { send_user "$pre\n" }

        if {[catch {spawn $env(NVME_BIN) sed password $dev} err]} {
            send_user "DBG_PW: spawn failed: $err\n"; exit 1
        }

        expect {
          -re {(?i)old.*pass(word)?|old.*key.*:} {
             send_user "DBG_PW: OLD prompt -> sending\n"
             send -- "$old\r"; exp_continue
          }
          -re {(?i)new.*pass(word)?|new.*key.*:} {
             send_user "DBG_PW: NEW prompt -> sending\n"
             send -- "$new\r"; exp_continue
          }
          -re {(?i)re-?enter.*pass(word)?|re-?enter.*key.*:} {
             send_user "DBG_PW: RE-ENTER prompt -> sending\n"
             send -- "$new\r"; exp_continue
          }
          timeout { send_user "DBG_PW: TIMEOUT\n"; exit 124 }
          eof {}
        }

        set rc [lindex [wait] 3]

        send_user "DBG_PW: discover(after)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} post
        if {[string length $post] > 0} { send_user "$post\n" }

        send_user "DBG_PW: rc=$rc\n"
        exit $rc
    '

    make_log_user_readable "$log"
    return $?
}

# PSID revert (interactive) for a namespace device.
# Usage: sed_psid_revert /dev/nvmeXnY "<PSID-STRING>"
# Notes:
#   * Always targets the namespace node (nvmeXnY), as required by nvme sed.
#   * Drives "Destructive revert … Continue (y/n)?", "Are you sure (y/n)?", then "PSID:".
sed_psid_revert() {
    local dev="$1"
    local psid="$2"

    if [[ -z "$dev" || ! -e "$dev" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_psid_revert: device not found: $dev" >&2
        return 2
    fi
    if [[ ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_psid_revert: expected NVMe namespace (/dev/nvmeXnY), got: $dev" >&2
        return 2
    fi
    if [[ -z "$psid" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_psid_revert: PSID is empty" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_psid_revert: must run as root" >&2
        return 2
    fi

    local log_dir="${SED_LOG_DIR:-/tmp/sed-debug}"
    local log="${log_dir}/psid-revert-$(basename "$dev").log"
    mkdir -p "$log_dir" || true
    : > "$log" 2>/dev/null && chmod 0600 "$log" || log="/dev/stderr"

    DEV="$dev" PSID="$psid" LOG_FILE="$log" NVME_BIN="${NVME_BIN:-nvme}" "${EXPECT_BIN:-expect}" -c '
        set timeout 90
        set dev   $env(DEV)
        set psid  $env(PSID)
        set logf  $env(LOG_FILE)

        if {[catch {log_file -a $logf} err]} { send_user "DBG_PSID: cannot log to $logf: $err\n" }
        log_user 1

        send_user "DBG_PSID: discover(before)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} pre
        if {[string length $pre] > 0} { send_user "$pre\n" }

        if {[catch {spawn $env(NVME_BIN) sed revert $dev --psid} err]} {
            send_user "DBG_PSID: spawn failed: $err\n"; exit 1
        }

        expect {
          -re {(?i)destructive.*continue.*\\(y/n\\)\\?} {
              send_user "DBG_PSID: first confirm -> y\n"
              send -- "y\r"; exp_continue
          }
          -re {(?i)are you sure.*\\(y/n\\)\\?} {
              send_user "DBG_PSID: second confirm -> y\n"
              send -- "y\r"; exp_continue
          }
          -re {(?i)^psid:} {
              send_user "DBG_PSID: PSID prompt -> sending ([string length $psid] chars)\n"
              send -- "$psid\r"; exp_continue
          }
          timeout { send_user "DBG_PSID: TIMEOUT\n"; exit 124 }
          eof {}
        }

        set rc [lindex [wait] 3]

        send_user "DBG_PSID: discover(after)\n"
        catch {exec $env(NVME_BIN) sed discover $dev} post
        if {[string length $post] > 0} { send_user "$post\n" }

        send_user "DBG_PSID: rc=$rc\n"
        exit $rc
    '

    make_log_user_readable "$log"
    return $?
}

# Minimal runtime cleanup so kernel state is sane before/after SED ops
# - Root only (no sudo here)
# - Only touches stacks built on nvme namespaces we care about
# - Unmounts deepest first, swapoff, closes dm, stops md, partprobe, settle
runtime_sanity() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "\033[1;31m[ERR]\033[0m runtime_sanity: must run as root" >&2
    return 2
  fi

  echo -e "\033[1;34m[INFO]\033[0m Preparing runtime state (swapoff, unmounts, md/dm cleanup)…"

  # Discover NVMe namespaces present (adjust filter if you only want specific ones)
  mapfile -t NVME_NODES < <(lsblk -rno NAME,TYPE | awk '$2=="disk"||$2=="part"{print "/dev/"$1}' | grep -E '^/dev/nvme[0-9]+n[0-9]+$' || true)
  [[ ${#NVME_NODES[@]} -eq 0 ]] && { echo "[INFO] No NVMe namespaces found; nothing to do."; return 0; }

  # Collect all block devices (and dm/md layers) that sit on top of the NVMe namespaces
  # Columns: NAME TYPE MOUNTPOINT PKNAME
  mapfile -t STACK < <(lsblk -rno NAME,TYPE,MOUNTPOINT,PKNAME | sed 's/  */ /g')
  # Determine which names are in-scope by walking parents
  declare -A INSCOPE=()
  for n in "${NVME_NODES[@]}"; do
    INSCOPE["${n#/dev/}"]=1
  done
  # Propagate in-scope to children whose PKNAME chain leads to our nvmes
  changed=1
  while (( changed )); do
    changed=0
    for line in "${STACK[@]}"; do
      name=$(awk '{print $1}' <<<"$line")
      pk=$(awk '{print $4}' <<<"$line")
      if [[ -n "$pk" && ${INSCOPE[$pk]+y} && -z ${INSCOPE[$name]+x} ]]; then
        INSCOPE[$name]=1; changed=1
      fi
    done
  done

  # 1) Unmount filesystems on our stack, deepest mountpoints first
  mapfile -t MOUNTS < <(
    for line in "${STACK[@]}"; do
      mp=$(awk '{print $3}' <<<"$line")
      name=$(awk '{print $1}' <<<"$line")
      [[ -n "$mp" && ${INSCOPE[$name]+y} ]] && printf '%06d %s %s\n' "$(echo -n "$mp" | wc -c)" "$mp" "$name"
    done | sort -r
  )
  for entry in "${MOUNTS[@]}"; do
    mp=$(awk '{print $2}' <<<"$entry")
    if mountpoint -q -- "$mp"; then
      umount -R -- "$mp" 2>/dev/null || umount -lR -- "$mp" 2>/dev/null || true
    fi
  done
  # Also clean standard installer mounts if hanging around
  umount -R /mnt 2>/dev/null || umount -lR /mnt 2>/dev/null || true
  umount /mnt/boot/EFI 2>/dev/null || true
  umount /mnt/boot 2>/dev/null || true

  # 2) Swapoff any swap devices in our stack (plus zram as a courtesy)
  swapoff -a 2>/dev/null || true
  for line in "${STACK[@]}"; do
    name=$(awk '{print $1}' <<<"$line")
    if [[ ${INSCOPE[$name]+y} && -e "/dev/$name" ]]; then
      swapoff "/dev/$name" 2>/dev/null || true
    fi
  done
  # zram if present
  for z in /dev/zram*; do [[ -b "$z" ]] && swapoff "$z" 2>/dev/null || true; done

  # 3) Close LUKS/dm-crypt mappings that sit on our devices
  # Identify dm names whose parents are in-scope
  mapfile -t DM_NAMES < <(
    for line in "${STACK[@]}"; do
      name=$(awk '{print $1}' <<<"$line")
      type=$(awk '{print $2}' <<<"$line")
      pk=$(awk '{print $4}' <<<"$line")
      if [[ "$type" == "crypt" || "$type" == "dm" ]] && [[ ${INSCOPE[$name]+y} || ${INSCOPE[$pk]+y} ]]; then
        echo "$name"
      fi
    done | sort -u
  )
  for dm in "${DM_NAMES[@]}"; do
    # Try cryptsetup close first (if it’s a crypt target), then dmsetup remove
    cryptsetup close "$dm" 2>/dev/null || true
    dmsetup remove -f "$dm" 2>/dev/null || true
  done

  # 4) Stop mdraid arrays that include our devices
  # First, a general stop/scan (idempotent)
  mdadm --stop --scan 2>/dev/null || true
  # Then, any residual md devices whose components are in-scope
  for md in /dev/md/* /dev/md*; do
    [[ -b "$md" ]] || continue
    # If any child of this md maps to our stack, stop/remove
    if lsblk -rno NAME,PKNAME "$md" | awk '{print $2}' | grep -Eq "$(printf '%s|' "${!INSCOPE[@]}" | sed 's/|$//')" 2>/dev/null; then
      mdadm --stop "$md" 2>/dev/null || true
      mdadm --remove "$md" 2>/dev/null || true
    fi
  done

  # 5) Final DM sweep for any stragglers tied to our nvmes
  while read -r mapname _; do
    [[ -n "$mapname" ]] || continue
    # Check if this map sits on top of our stack
    if lsblk -rno NAME,PKNAME "/dev/mapper/$mapname" 2>/dev/null | awk '{print $2}' \
        | grep -Eq "$(printf '%s|' "${!INSCOPE[@]}" | sed 's/|$//')" 2>/dev/null; then
      dmsetup remove -f "$mapname" 2>/dev/null || true
    fi
  done < <(dmsetup ls 2>/dev/null || true)

  # 6) Partitions re-read for the specific namespaces we’re working with
  for nv in "${NVME_NODES[@]}"; do
    partprobe "$nv" 2>/dev/null || true
  done

  # 7) Udev settle
  udevadm settle || true

  echo -e "\033[1;32m[OK]\033[0m Runtime state cleaned."
}

# Robust reset of storage stack built on top of target NVMe namespaces.
# Usage:
#   robust_storage_reset             # auto-detect all /dev/nvmeXnY
#   robust_storage_reset /dev/nvme0n1 /dev/nvme1n1  # explicit
robust_storage_reset() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "\033[1;31m[ERR]\033[0m robust_storage_reset: must run as root" >&2
    return 2
  fi

  echo -e "\033[1;34m[INFO]\033[0m Nuking stale mounts, LVM, md, dm-crypt…"

  local targets=()
  if [[ $# -gt 0 ]]; then
    for d in "$@"; do
      [[ -e "$d" ]] || { echo "[ERR] no such device: $d" >&2; return 2; }
      [[ "$d" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]] || { echo "[ERR] not an NVMe namespace: $d" >&2; return 2; }
      targets+=("$d")
    done
  else
    mapfile -t targets < <(list_nvme_namespaces)
  fi
  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "[INFO] No NVMe namespaces found; nothing to do."
    return 0
  fi

  # Build block stack once
  mapfile -t STACK < <(lsblk -rno NAME,TYPE,MOUNTPOINT,PKNAME | sed 's/  */ /g')

  # Mark devices in-scope: every node whose PKNAME chain leads to a target
  declare -A IN
  for t in "${targets[@]}"; do IN["${t#/dev/}"]=1; done
  local changed=1 name pk
  while (( changed )); do
    changed=0
    for line in "${STACK[@]}"; do
      name=$(awk '{print $1}' <<<"$line")
      pk=$(awk '{print $4}' <<<"$line")
      if [[ -n "$pk" && ${IN[$pk]+y} && -z ${IN[$name]+x} ]]; then
        IN[$name]=1; changed=1
      fi
    done
  done

  # 1) Unmount deepest mountpoints first (only in-scope)
  mapfile -t MOUNTS < <(
    for line in "${STACK[@]}"; do
      mp=$(awk '{print $3}' <<<"$line")
      name=$(awk '{print $1}' <<<"$line")
      [[ -n "$mp" && ${IN[$name]+y} ]] && printf '%06d %s %s\n' "$(echo -n "$mp" | wc -c)" "$mp" "$name"
    done | sort -r
  )
  for entry in "${MOUNTS[@]}"; do
    mp=$(awk '{print $2}' <<<"$entry")
    if mountpoint -q -- "$mp"; then
      do_or_echo umount -R -- "$mp" || do_or_echo umount -lR -- "$mp"
    fi
  done
  # Installer-common mounts, if still lingering
  do_or_echo umount -R /mnt 2>/dev/null || do_or_echo umount -lR /mnt 2>/dev/null || true
  do_or_echo umount /mnt/boot/EFI || true
  do_or_echo umount /mnt/boot     || true
  do_or_echo umount /mnt/secrets  || true

  # 2) Swapoff
  do_or_echo swapoff -a || true
  for name in "${!IN[@]}"; do
    [[ -e "/dev/$name" ]] && do_or_echo swapoff "/dev/$name" || true
  done
  for z in /dev/zram*; do [[ -b "$z" ]] && do_or_echo swapoff "$z" || true; done

  # 3) Close crypt targets (dm-crypt) that are in-scope
  mapfile -t DM_CRYPT < <(
    for line in "${STACK[@]}"; do
      name=$(awk '{print $1}' <<<"$line")
      type=$(awk '{print $2}' <<<"$line")
      pk=$(awk '{print $4}' <<<"$line")
      if [[ "$type" == "crypt" || "$type" == "dm" ]] && [[ ${IN[$name]+y} || ${IN[$pk]+y} ]]; then
        echo "$name"
      fi
    done | sort -u
  )
  for dm in "${DM_CRYPT[@]}"; do
    do_or_echo cryptsetup close "$dm" || true
    do_or_echo dmsetup remove -f "$dm" || true
  done

  # 4) Stop md arrays that include our devices; zero superblocks later
  if command -v mdadm >/dev/null 2>&1; then
    do_or_echo mdadm --stop --scan || true
    for md in /dev/md/* /dev/md*; do
      [[ -b "$md" ]] || continue
      if lsblk -rno NAME,PKNAME "$md" | awk '{print $2}' \
           | grep -Eq "$(printf '%s|' "${!IN[@]}" | sed 's/|$//')" 2>/dev/null; then
        do_or_echo mdadm --stop "$md"   || true
        do_or_echo mdadm --remove "$md" || true
      fi
    done
  fi

  # 5) Deactivate/remove LVM objects that sit on our stack
  if command -v lvs >/dev/null 2>&1; then
    mapfile -t LVS < <(lvs --noheadings -o lv_name,vg_name,lv_path 2>/dev/null | sed 's/^[[:space:]]*//')
    local lvname vgname lvpath
    for line in "${LVS[@]}"; do
      lvname=$(awk '{print $1}' <<<"$line")
      vgname=$(awk '{print $2}' <<<"$line")
      lvpath=$(awk '{print $3}' <<<"$line")
      if pvs --noheadings -o pv_name,vg_name 2>/dev/null | awk -v vg="$vgname" '$2==vg{print $1}' \
          | sed 's|^/dev/||' | grep -Eq "$(printf '%s|' "${!IN[@]}" | sed 's/|$//')" 2>/dev/null ; then
        do_or_echo lvchange -an "$lvpath" || true
        do_or_echo lvremove -fy "$lvpath" || true
      fi
    done
    if command -v vgs >/dev/null 2>&1; then
      mapfile -t VGS < <(vgs --noheadings -o vg_name 2>/dev/null | awk '{print $1}')
      local vg
      for vg in "${VGS[@]}"; do
        if pvs --noheadings -o pv_name,vg_name 2>/dev/null | awk -v vg="$vg" '$2==vg{print $1}' \
            | sed 's|^/dev/||' | grep -Egq "$(printf '%s|' "${!IN[@]}" | sed 's/|$//')" 2>/dev/null ; then
          do_or_echo vgchange -an "$vg" || true
          do_or_echo vgremove -fy "$vg" || true
        fi
      done
    fi
    if command -v pvremove >/dev/null 2>&1; then
      local t
      for t in "${targets[@]}"; do
        do_or_echo pvremove -ff "$t" || true
      done
    fi
  fi

  # 6) Wipefs + zero md superblocks on our raw *targets* only
  for t in "${targets[@]}"; do
    if command -v mdadm >/dev/null 2>&1; then
      do_or_echo mdadm --zero-superblock "$t" || true
    fi
    do_or_echo wipefs -af "$t" || true
  done

  # 7) Partitions re-read + settle (only our targets)
  for t in "${targets[@]}"; do
    do_or_echo partprobe "$t" || true
  done
  udevadm settle || true

  echo -e "\033[1;32m[OK]\033[0m Storage stack reset for: ${targets[*]}"
}

# Assert Opal Locking is enabled and the drive is currently *unlocked* on a given namespace.
# Returns 0 if OK, non-zero otherwise. Does not exit the script.
sed_assert_enabled_unlocked() {
    local dev="$1"

    # Guardrails
    if [[ -z "$dev" || ! -e "$dev" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_assert_enabled_unlocked: device not found: $dev" >&2
        return 2
    fi
    if [[ ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_assert_enabled_unlocked: expected NVMe *namespace* (/dev/nvmeXnY), got: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_assert_enabled_unlocked: must run as root" >&2
        return 2
    fi

    # Discover output
    local out rc
    if ! out="$("${NVME_BIN:-nvme}" sed discover "$dev" 2>/dev/null)"; then
        rc=$?
        echo -e "\033[1;31m[ERR]\033[0m ${dev}: 'nvme sed discover' failed (rc=$rc)" >&2
        return $rc
    fi
    [[ -n "$out" ]] || { echo -e "\033[1;31m[ERR]\033[0m ${dev}: empty discover output" >&2; return 1; }

    # Parse (case/space tolerant)
    # Examples we expect to match:
    #   "Locking Feature Enabled: Yes"
    #   "Locked: No"
    local enabled locked
    enabled="$(
        printf '%s\n' "$out" \
        | awk -F: 'tolower($1) ~ /locking[[:space:]]+feature[[:space:]]+enabled/ {
            gsub(/^[ \t]+|[ \t]+$/,"",$2); print tolower($2)
        }'
    )"
    locked="$(
        printf '%s\n' "$out" \
        | awk -F: 'tolower($1) ~ /^[ \t]*locked/ {
            gsub(/^[ \t]+|[ \t]+$/,"",$2); print tolower($2)
        }'
    )"

    if [[ "$enabled" != "yes" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m ${dev}: Locking Feature Enabled != Yes (got: ${enabled:-<missing>})" >&2
        # Helpful context dump
        printf '%s\n' "$out" | sed -n '1,120p' >&2
        return 1
    fi
    if [[ "$locked" != "no" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m ${dev}: drive reports Locked != No (got: ${locked:-<missing>})" >&2
        printf '%s\n' "$out" | sed -n '1,120p' >&2
        return 1
    fi

    echo -e "\033[1;32m[OK]\033[0m ${dev}: Opal enabled and currently unlocked"
    return 0
}

# Return 'Yes' or 'No' if the Locking Feature is enabled on a namespace.
# Returns empty on parse failure.
sed_enabled() {
    local dev="$1"

    # Guardrails
    if [[ -z "$dev" || ! -e "$dev" || ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo "[ERR] sed_enabled: bad device: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo "[ERR] sed_enabled: must run as root" >&2
        return 2
    fi

    local out
    out="$("${NVME_BIN:-nvme}" sed discover "$dev" 2>/dev/null || true)"
    [[ -z "$out" ]] && return 1

    printf '%s\n' "$out" \
      | awk -F: 'tolower($1) ~ /locking[[:space:]]+feature[[:space:]]+enabled/ {
            gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit
        }'
}

# Return 'Yes' or 'No' if the drive is currently locked.
# Returns empty on parse failure.
sed_locked() {
    local dev="$1"

    # Guardrails
    if [[ -z "$dev" || ! -e "$dev" || ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo "[ERR] sed_locked: bad device: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo "[ERR] sed_locked: must run as root" >&2
        return 2
    fi

    local out
    out="$("${NVME_BIN:-nvme}" sed discover "$dev" 2>/dev/null || true)"
    [[ -z "$out" ]] && return 1

    printf '%s\n' "$out" \
      | awk -F: 'tolower($1) ~ /^[ \t]*locked/ {
            gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit
        }'
}

# Return 0 if a revert should be attempted (Opal enabled or drive locked), 1 otherwise.
sed_should_revert() {
  local dev="$1"
  local en locked
  en="$(sed_enabled "$dev" || true)"
  locked="$(sed_locked "$dev" || true)"

  # If we can tell it's locked, revert. Otherwise require Enabled=Yes.
  if [[ "$locked" == "Yes" ]]; then
    return 0
  fi
  if [[ -z "$en" ]]; then
    echo "[WARN] sed_should_revert: could not parse 'Enabled' for $dev; skipping revert." >&2
    return 1
  fi
  [[ "$en" == "Yes" ]]
}

# Full flow: conditional revert -> initialize -> verify lock/unlock
sed_reset_and_init() {
    local dev="$1"

    # Guardrails
    if [[ -z "$dev" || ! -e "$dev" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_reset_and_init: device not found: $dev" >&2
        return 2
    fi
    if [[ ! "$dev" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_reset_and_init: expected NVMe *namespace* (/dev/nvmeXnY), got: $dev" >&2
        return 2
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31m[ERR]\033[0m sed_reset_and_init: must run as root" >&2
        return 2
    fi

    # Map to controller serial and load/derive the per-drive key (idempotent)
    local serial
    serial="$(ctrl_serial_for_dev "$dev")" || { echo "[ERR] cannot read controller serial for $dev"; return 2; }
    if ! sed_load_key_by_serial "$serial"; then
      echo -e "\033[1;31m[ERR]\033[0m could not obtain SED key for serial ${serial}" >&2
      return 2
    fi

    # Snapshot pre-state (tolerate parse failures)
    local en before_locked
    en="$(sed_enabled "$dev" || true)"
    before_locked="$(sed_locked "$dev" || true)"
    echo -e "\033[1;34m[INFO]\033[0m ${dev} pre-state: Enabled=${en:-<unknown>}, Locked=${before_locked:-<unknown>}"

    # Fast idempotency paths:
    #  - Enabled=Yes, Locked=No -> we likely already own it: verify lock/unlock and exit OK.
    #  - Enabled=Yes, Locked=Yes -> try to unlock with our key before anything destructive.
    if [[ "$en" == "Yes" && "$before_locked" == "No" ]]; then
      echo -e "\033[1;34m[INFO]\033[0m ${dev}: Opal enabled & unlocked; verifying lock/unlock and skipping initialize."
      if ! sed_lock "$dev"; then
        echo -e "\033[1;33m[WARN]\033[0m Lock attempt failed; short retry…" ; sleep 1 ; sed_lock "$dev" || { echo -e "\033[1;31m[ERR]\033[0m lock failed on ${dev}"; return 1; }
      fi
      sleep 1
      if ! sed_unlock "$dev"; then
        echo -e "\033[1;33m[WARN]\033[0m Unlock attempt failed; short retry…" ; sleep 1 ; sed_unlock "$dev" || { echo -e "\033[1;31m[ERR]\033[0m unlock failed on ${dev}"; return 1; }
      fi
      echo -e "\033[1;32m[OK]\033[0m ${dev} already initialized; ownership verified."
      return 0
    fi
    if [[ "$en" == "Yes" && "$before_locked" == "Yes" ]]; then
      echo -e "\033[1;34m[INFO]\033[0m ${dev}: Opal enabled & LOCKED; attempting unlock with current key."
      if sed_unlock "$dev"; then
        echo -e "\033[1;32m[OK]\033[0m ${dev} unlocked with current key; skipping re-initialize."
        return 0
      fi
      echo -e "\033[1;33m[WARN]\033[0m ${dev}: unlock with current key failed; will consider revert paths."
    fi
    # Else: looks factory-ish (Enabled=No), proceed to initialize first.
    if [[ "$en" != "Yes" && "$before_locked" != "Yes" ]]; then
      echo -e "\033[1;34m[INFO]\033[0m ${dev}: Opal not enabled and not locked; trying initialize without revert."
    fi

    # Initialize (sets the new SID/Admin and enables Locking SP)
    local init_ok=0
    if ! sed_initialize "$dev"; then
        rc=$?
        if [[ $rc -eq 98 || $rc -eq 97 ]]; then
            echo -e "\033[1;33m[WARN]\033[0m ${dev}: Initialize failed with '$( [[ $rc -eq 98 ]] && echo Host Not Authorized || echo Authority Locked Out )'."
            if [[ "${FORCE_PSID:-1}" == "1" ]]; then
                echo -e "\033[1;34m[INFO]\033[0m Falling back to PSID revert for ${dev}…"
                sed_psid_revert_then_die "$dev"   # exits 90
                return 90
            else
                echo -e "\033[1;33m[WARN]\033[0m FORCE_PSID=0 -> not reverting automatically for ${dev}."
                echo -e "\033[1;33m[HINT]\033[0m Re-run with FORCE_PSID=1 to PSID revert on this condition."
                return 1
            fi
        fi

        echo -e "\033[1;33m[WARN]\033[0m initialize failed; will try *destructive* revert, reset controller, and retry once."
        if ! sed_revert "$dev" destructive; then
          echo -e "\033[1;33m[WARN]\033[0m Destructive revert failed on ${dev}."
          if [[ "${FORCE_PSID:-0}" == "1" ]]; then
            sed_psid_revert_then_die "$dev"; return 90
          fi
          return 1
        fi

        # Controller reset and settle
        local ctrl=""
        ctrl="$(ctrl_node_for_dev "$dev" 2>/dev/null || true)"
        if [[ -n "$ctrl" && -e "$ctrl" ]]; then
          do_or_echo "${NVME_BIN:-nvme}" reset "$ctrl" || true
        else
          echo -e "\033[1;33m[WARN]\033[0m Could not derive controller node from ${dev}; skipping nvme reset."
        fi
        partprobe "$dev" 2>/dev/null || true
        udevadm settle || true
        sleep 1
        echo -e "\033[1;34m[INFO]\033[0m Retrying initialize on ${dev} after revert/reset…"
        if ! sed_initialize "$dev"; then
          if [[ "${FORCE_PSID:-0}" == "1" ]]; then
            echo -e "\033[1;34m[INFO]\033[0m Falling back to PSID revert for ${dev}…"
            sed_psid_revert_then_die "$dev"; return 90
          fi
          echo -e "\033[1;31m[ERR]\033[0m initialize retry failed."
          return 1
        fi
        init_ok=1
    else
        init_ok=1
    fi

    # Give firmware a moment, then verify state
    udevadm settle || true
    sleep 1

    if ! sed_assert_enabled_unlocked "$dev"; then
        local en_after="$(sed_enabled "$dev" || true)"
        local locked_after="$(sed_locked "$dev" || true)"
        echo -e "\033[1;31m[ERR]\033[0m ${dev}: unexpected state after initialize (Enabled=${en_after:-<unknown>}, Locked=${locked_after:-<unknown>})"
        return 1
    fi

    # Exercise lock/unlock once (with tiny backoff)
    echo -e "\033[1;34m[INFO]\033[0m Verifying lock/unlock on ${dev}…"
    if ! sed_lock "$dev"; then
        echo -e "\033[1;33m[WARN]\033[0m Lock attempt failed; short retry…"
        sleep 1
        sed_lock "$dev" || { echo -e "\033[1;31m[ERR]\033[0m lock failed on ${dev}"; return 1; }
    fi
    sleep 1
    if ! sed_unlock "$dev"; then
        echo -e "\033[1;33m[WARN]\033[0m Unlock attempt failed; short retry…"
        sleep 1
        sed_unlock "$dev" || { echo -e "\033[1;31m[ERR]\033[0m unlock failed on ${dev}"; return 1; }
    fi

    echo -e "\033[1;32m[OK]\033[0m ${dev} initialized, Opal enabled, and unlock verified."
    return 0
}

# Ensure a required command exists in PATH.
# Usage: check_command <cmd>
# Returns 0 if present, exits/returns non-zero otherwise.
check_command() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m check_command: no command name provided" >&2
        return 2
    fi
    if ! command -v -- "$cmd" >/dev/null 2>&1; then
        echo -e "\033[1;31m[ERR]\033[0m Required command '${cmd}' not found in PATH" >&2
        exit 1   # change to 'return 1' if you want softer failure
    fi
}

# Prompt once for the SED master secret if not already set in the environment.
# The secret is exported so that child processes (expect, nvme, etc.) can see it.
prompt_master_secret() {
    if [[ -z "${SED_MASTER_SECRET:-}" ]]; then
        local secret
        while :; do
            read -rsp "SED Master Secret: " secret
            echo
            if [[ -z "$secret" ]]; then
                echo -e "\033[1;31m[ERR]\033[0m Master secret cannot be empty." >&2
                continue
            fi
            # Optional: enforce minimum length for sanity
            if (( ${#secret} < 8 )); then
                echo -e "\033[1;33m[WARN]\033[0m Master secret is very short (<8 chars)." >&2
                # break here if you want to allow short secrets, or continue to reprompt
                # continue
            fi
            break
        done
        export SED_MASTER_SECRET="$secret"
    fi
}

# Derive a firmware-safe SID from (MASTER, SERIAL).
# HMAC-SHA256(master, serial) → Base32 (no '='), UPPERCASE, length-limited.
# Emits only A–Z2–7, which is firmware-friendly ASCII.
derive_sed_sid() {
  local master="$1" serial="$2" n="${3:-30}"
  # Guardrails
  if [[ -z "$master" || -z "$serial" ]]; then
    echo "[ERR] derive_sed_sid: missing args" >&2
    return 1
  fi
  # Trim whitespace just in case
  serial="$(printf '%s' "$serial" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  # Clamp length to 8..32
  if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 8 || n > 32 )); then
    echo "[ERR] derive_sed_sid: length must be 8..32 (got: $n)" >&2
    return 1
  fi
  # Dependencies
  command -v openssl >/dev/null 2>&1 || { echo "[ERR] derive_sed_sid: openssl not found" >&2; return 1; }
  local have_basenc= have_base32=
  command -v basenc  >/dev/null 2>&1 && have_basenc=1
  command -v base32  >/dev/null 2>&1 && have_base32=1
  if [[ -z "$have_basenc$have_base32" ]]; then
    echo "[ERR] derive_sed_sid: need either 'basenc' or 'base32'" >&2
    return 1
  fi

  # Force C locale so [:lower:]/[:upper:] behave predictably
  local out
  if [[ -n "$have_basenc" ]]; then
    out="$(
      LC_ALL=C printf '%s' "$serial" \
        | openssl dgst -sha256 -mac HMAC -macopt "key:$master" -binary \
        | basenc --base32 \
        | tr -d '=' \
        | tr '[:lower:]' '[:upper:]' \
        | tr -d '\n' \
        | cut -c1-"$n"
    )"
  else
    out="$(
      LC_ALL=C printf '%s' "$serial" \
        | openssl dgst -sha256 -mac HMAC -macopt "key:$master" -binary \
        | base32 \
        | tr -d '=' \
        | tr '[:lower:]' '[:upper:]' \
        | tr -d '\n' \
        | cut -c1-"$n"
    )"
  fi

  if [[ -z "$out" ]]; then
    echo "[ERR] derive_sed_sid: empty output (unexpected)" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

# Validate a firmware-safe SID:
# - length 8..32
# - chars limited to A–Z, 0–9, and _ . : @ # -
# Returns 0 if valid, 1 otherwise. Silent (no output).
validate_sid() {
  local s="$1"
  # Fast length check first
  [[ -n "$s" ]] || return 1
  local len=${#s}
  (( len >= 8 && len <= 32 )) || return 1
  # Force C locale so character classes behave predictably (works with [[...]])
  local LC_ALL=C
  if [[ "$s" =~ ^[A-Z0-9_.:@#-]{8,32}$ ]]; then
    return 0
  fi
  return 1
}

# Deterministic per-drive key from MASTER_SECRET and controller serial
# Output: upper-hex trimmed to SED_KEY_LEN (default 30)
derive_sid_from_master() {
  local secret="$1" serial="$2" n="${SED_KEY_LEN:-30}"
  [[ -n "$secret" && -n "$serial" ]] || return 2
  # Use sha256(secret||serial), upper-hex, trim length
  local hex
  hex="$(printf '%s' "${secret}::${serial}" | sha256sum | awk '{print $1}' | tr 'a-f' 'A-F')"
  printf '%s' "${hex:0:${n}}"
}

# Map /dev/nvmeXnY (or partition /dev/nvmeXnYpZ) -> controller serial via sysfs.
# Prints the serial on success; returns non-zero on failure.
ctrl_serial_for_dev() {
  local dev="$1"
  [[ -n "$dev" ]] || { echo "[ERR] ctrl_serial_for_dev: no device arg" >&2; return 1; }
  [[ -e "$dev" ]] || { echo "[ERR] ctrl_serial_for_dev: no such device: $dev" >&2; return 1; }

  # Normalize to namespace/controller base name:
  #   nvme0n1p3 -> nvme0   (strip shortest suffix matching 'n*')
  #   nvme0n1   -> nvme0
  #   (Reject controller nodes explicitly; this helper expects a namespace/partition.)
  local base ctrl_name
  base="$(basename -- "$dev")"
  if [[ "$base" =~ ^nvme[0-9]+$ ]]; then
    echo "[ERR] ctrl_serial_for_dev: controller node given, expected namespace (/dev/nvmeXnY): $dev" >&2
    return 1
  fi
  ctrl_name="${base%n*}"
  [[ "$ctrl_name" =~ ^nvme[0-9]+$ ]] || { echo "[ERR] ctrl_serial_for_dev: cannot derive controller from: $dev" >&2; return 1; }

  local ctrl_sys="/sys/class/nvme/${ctrl_name}"
  local serial_file="${ctrl_sys}/serial"
  [[ -r "$serial_file" ]] || { echo "[ERR] ctrl_serial_for_dev: cannot read ${serial_file}" >&2; return 1; }

  # Trim any stray whitespace just in case
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' < "$serial_file"
}

# Map /dev/nvmeXnY (or /dev/nvmeXnYpZ) -> controller node /dev/nvmeX.
# Usage: ctrl_node_for_dev /dev/nvme0n1[px]
# Returns /dev/nvmeX on stdout; non-zero on failure.
ctrl_node_for_dev() {
  local dev="$1"
  [[ -n "$dev" && -e "$dev" ]] || { echo "[ERR] ctrl_node_for_dev: no such device: $dev" >&2; return 1; }
  local base; base="$(basename -- "$dev")"

  # Accept nvmeXnY and nvmeXnYpZ forms
  if [[ "$base" =~ ^(nvme[0-9]+)n[0-9]+(p[0-9]+)?$ ]]; then
    # Capture the controller (nvmeX) and print /dev/nvmeX
    printf '/dev/%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  # If a controller node was (incorrectly) passed in, just echo it back
  if [[ "$base" =~ ^nvme[0-9]+$ ]]; then
    printf '/dev/%s\n' "$base"
    return 0
  fi
  echo "[ERR] ctrl_node_for_dev: not an NVMe namespace: $dev" >&2; return 1
}

# Ensure per-drive key files exist for a list of SERIALs.
# - Prompts for master secret if needed
# - Creates ${KEYS_DIR}/nvme-<SERIAL>.key with 0400 perms (root-only)
# - Never prints the SID; logs minimal info (optionally a hash if available)
ensure_sed_keys_for_serials() {
  # Guardrails
  if [[ $EUID -ne 0 ]]; then
    echo "[ERR] ensure_sed_keys_for_serials: must run as root" >&2
    return 2
  fi
  if [[ $# -eq 0 ]]; then
    echo "[ERR] ensure_sed_keys_for_serials: no serials provided" >&2
    return 2
  fi

  # Directories / perms
  : "${KEYS_DIR:=${SECRETS_MOUNT:-/run/secrets}/keys}"
  mkdir -p -- "$KEYS_DIR" || { echo "[ERR] cannot create $KEYS_DIR" >&2; return 1; }
  chmod 0700 -- "$KEYS_DIR" 2>/dev/null || true

  prompt_master_secret || return 1
  local um_old
  um_old=$(umask)
  umask 077  # new files: owner-only

  local rc=0
  for s in "$@"; do
    # Trim serial, basic sanity
    local serial="${s#"${s%%[![:space:]]*}"}"; serial="${serial%"${serial##*[![:space:]]}"}"
    [[ -n "$serial" ]] || { echo "[ERR] empty serial in list; skipping" >&2; rc=1; continue; }

    local keyfile="${KEYS_DIR}/nvme-${serial}.key"

    if [[ -s "$keyfile" ]]; then
      # Validate existing key and fix perms quietly
      local existing
      existing="$(head -n1 -- "$keyfile" 2>/dev/null || true)"
      if [[ -z "$existing" ]] || ! validate_sid "$existing"; then
        echo "[WARN] $keyfile exists but is invalid; refusing to overwrite automatically." >&2
        echo "[WARN] Remove it manually to regenerate: rm -f -- '$keyfile'" >&2
        rc=1; continue
      fi
      chmod 0400 -- "$keyfile" 2>/dev/null || true
      echo "[INFO] Reusing existing ${keyfile}"
      continue
    fi

    # Derive new SID
    local sid
    sid="$(derive_sed_sid "$SED_MASTER_SECRET" "$serial" "${SED_SID_LEN:-30}")" \
      || { echo "[ERR] derive failed for serial $serial" >&2; rc=1; continue; }
    if ! validate_sid "$sid"; then
      echo "[ERR] Derived SID failed policy for serial $serial" >&2
      rc=1; continue
    fi

    # Atomic write: temp file then mv
    local tmp
    tmp="$(mktemp --tmpdir="$KEYS_DIR" ".nvme-${serial}.key.tmp.XXXXXX")" \
      || { echo "[ERR] mktemp failed in $KEYS_DIR" >&2; rc=1; continue; }
    printf '%s\n' "$sid" >"$tmp" 2>/dev/null \
      && chmod 0400 -- "$tmp" \
      && mv -f -- "$tmp" "$keyfile" \
      || { echo "[ERR] failed writing $keyfile" >&2; rm -f -- "$tmp"; rc=1; continue; }

    # Optional: log a non-secret fingerprint if available
    if command -v sha256sum >/dev/null 2>&1; then
      local fp
      fp="$(printf '%s' "$sid" | sha256sum | awk '{print $1}')" || fp="(unavailable)"
      echo "[INFO] Created ${keyfile} (sha256 of SID: ${fp})"
    else
      echo "[INFO] Created ${keyfile}"
    fi
  done

  umask "$um_old"
  return $rc
}

# Load SED_KEY for a given SERIAL (export for expect).
# Strategy:
#   1) If MASTER_SECRET is set (or after prompting), derive key deterministically.
#   2) Otherwise, try existing key file: ${KEYS_DIR}/nvme-<SERIAL>.key
#   3) If SED_WRITE_KEYS=1, write the derived key to that path (optional).
sed_load_key_by_serial() {
  local s="$1"
  if [[ -z "$s" ]]; then
    echo "[ERR] sed_load_key_by_serial: missing serial" >&2
    return 2
  fi
  : "${KEYS_DIR:=${SECRETS_MOUNT:-/run/secrets}/keys}"
  local f="${KEYS_DIR}/nvme-${s}.key"

  # 1) Derive from MASTER_SECRET if provided
  if [[ -n "${MASTER_SECRET}" ]]; then
    SED_KEY="$(derive_sid_from_master "${MASTER_SECRET}" "${s}")" || return 1
    if ! validate_sid "$SED_KEY"; then
      echo "[ERR] derived SID fails policy; adjust SED_KEY_LEN or MASTER_SECRET." >&2
      return 3
    fi
    export SED_KEY SED_KEY_SOURCE="derived"
    if [[ "${SED_WRITE_KEYS:-0}" == "1" ]]; then
      # Writing requires root; keep non-fatal if not.
      if [[ $EUID -eq 0 ]]; then
        mkdir -p "$KEYS_DIR" && chmod 0700 "$KEYS_DIR" || true
        printf '%s' "$SED_KEY" > "$f" && chmod 0600 "$f" || true
      else
        echo "[WARN] not root; skipping write of $f" >&2
      fi
    fi
    return 0
  fi

  # 2) Attempt to read an existing key file
  if [[ -r "$f" ]]; then
    # Reading a file doesn’t strictly require root, but you likely run as root anyway.
    local key
    key="$(head -n1 -- "$f" 2>/dev/null || true)"
    if [[ -z "$key" ]]; then
      echo "[ERR] empty key in $f" >&2
      return 1
    fi
    if ! validate_sid "$key"; then
      echo "[ERR] key in $f fails policy (expect A–Z0–9_.:@#- length 8..32)" >&2
      return 1
    fi
    SED_KEY="$key"
    export SED_KEY SED_KEY_SOURCE="file:$f"
    return 0
  fi

  # 3) Prompt MASTER_SECRET once, then derive
  read -rsp "SED Master Secret (won't be stored): " MASTER_SECRET; echo
  if [[ -z "${MASTER_SECRET}" ]]; then
    echo "[ERR] MASTER_SECRET empty; cannot derive key." >&2
    return 2
  fi
  SED_KEY="$(derive_sid_from_master "${MASTER_SECRET}" "${s}")" || return 1
  if ! validate_sid "$SED_KEY"; then
    echo "[ERR] derived SID fails policy; adjust SED_KEY_LEN or MASTER_SECRET." >&2
    return 3
  fi
  export SED_KEY SED_KEY_SOURCE="derived"
  if [[ "${SED_WRITE_KEYS:-0}" == "1" ]]; then
    if [[ $EUID -eq 0 ]]; then
      mkdir -p "$KEYS_DIR" && chmod 0700 "$KEYS_DIR" || true
      printf '%s' "$SED_KEY" > "$f" && chmod 0600 "$f" || true
    else
      echo "[WARN] not root; skipping write of $f" >&2
    fi
  fi
  return 0
}

# Convenience: ensure keys for all present controllers (nvme0, nvme1, …)
ensure_keys_for_present_controllers() {
  if [[ $EUID -ne 0 ]]; then
    echo "[ERR] ensure_keys_for_present_controllers: must run as root" >&2
    return 2
  fi

  # Collect controller serials from sysfs; handle no matches, trim, dedupe
  local ctrl serial
  local serials=()
  declare -A seen=()

  shopt -s nullglob
  for ctrl in /sys/class/nvme/nvme*; do
    [[ -r "$ctrl/serial" ]] || continue
    serial="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' < "$ctrl/serial")"
    [[ -n "$serial" ]] || continue
    if [[ -z "${seen[$serial]:-}" ]]; then
      serials+=("$serial")
      seen[$serial]=1
    fi
  done
  shopt -u nullglob

  if [[ ${#serials[@]} -eq 0 ]]; then
    echo "[INFO] No NVMe controllers with readable serials found; skipping key creation."
    return 0
  fi

  ensure_sed_keys_for_serials "${serials[@]}"
}

# Check that a given value is non-empty and present in a target file.
# Usage: check_value "<value>" "<name>" [path]
# - Increments global MISSING_VALUES on failure (keeps your current behavior)
# - Returns:
#     0 = found
#     1 = value empty
#     2 = file missing/unreadable
#     3 = not found in file
check_value() {
    local value="$1"
    local name="$2"
    local path="${3:-$HWC_PATH}"

    # arg sanity
    if [[ -z "$name" ]]; then
        echo -e "\033[1;31m[ERR]\033[0m check_value: missing <name> label" >&2
        MISSING_VALUES=$((MISSING_VALUES + 1))
        return 1
    fi

    # empty value
    if [[ -z "$value" ]]; then
        echo -e "\033[1;31m[ERROR]\033[0m $name is empty; device may not be ready or blkid needed root."
        MISSING_VALUES=$((MISSING_VALUES + 1))
        return 1
    fi

    # file sanity
    if [[ -z "$path" || ! -r "$path" ]]; then
        echo -e "\033[1;31m[ERROR]\033[0m $name check failed: target file unreadable: ${path:-<unset>}"
        MISSING_VALUES=$((MISSING_VALUES + 1))
        return 2
    fi

    # search (fixed string). If you need exact-line match, use: grep -Fxq -- "$value" "$path"
    if grep -Fq -- "$value" -- "$path"; then
        echo -e "\033[1;32m[OK]\033[0m Found $name ($value) in $path."
        return 0
    else
        echo -e "\033[1;31m[ERROR]\033[0m Expected $name ($value) not found in $path!"
        MISSING_VALUES=$((MISSING_VALUES + 1))
        return 3
    fi
}

# Get the filesystem UUID for a block device (namespace or partition).
# Usage: get_uuid /dev/nvmeXnY[pZ]
# - Forces blkid cache refresh, probes the device, trims output
# - Retries briefly if the UUID isn’t visible yet (fresh mkfs/udev)
# Returns 0 with UUID on stdout, non-zero otherwise.
get_uuid() {
  local dev="$1"
  local tries="${2:-8}"  # optional: retry count
  local sleep_s="${3:-0.5}"

  # Guardrails
  if [[ -z "$dev" || ! -e "$dev" ]]; then
    echo "[ERR] get_uuid: device not found: $dev" >&2
    return 2
  fi
  if [[ $EUID -ne 0 ]]; then
    echo "[ERR] get_uuid: must run as root" >&2
    return 2
  fi
  command -v blkid >/dev/null 2>&1 || { echo "[ERR] get_uuid: blkid not found" >&2; return 2; }

  # Resolve symlinks (e.g., /dev/disk/by-id/*) to keep blkid happy
  local node; node="$(readlink -f -- "$dev" 2>/dev/null || printf '%s' "$dev")"

  # Refresh blkid cache; ignore errors
  blkid -g >/dev/null 2>&1 || true

  local out= rc=1
  for ((i=0; i<tries; i++)); do
    # Probe only; output the value; suppress noise
    out="$(blkid -p -o value -s UUID -- "$node" 2>/dev/null | tr -d '\n' || true)"
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      rc=0
      break
    fi
    # Give udev a beat if just formatted/created
    udevadm settle 2>/dev/null || true
    sleep "$sleep_s"
  done

  return $rc
}

# List NVMe namespaces (/dev/nvmeXnY), one per line.
# Be tolerant of kernels that expose nvmeXnY as TYPE=disk (no partitions yet)
# and exclude partition nodes like nvmeXnYpZ.
list_nvme_namespaces() {
  shopt -s nullglob
  local nodes=()
  # Fast path: glob actual block nodes
  for n in /dev/nvme*n*; do
    [[ -b "$n" ]] || continue
    [[ "$n" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]] && nodes+=("$n")
  done
  shopt -u nullglob
  if (( ${#nodes[@]} == 0 )); then
    # Fallback via lsblk without TYPE filtering (some ISOs report nvmeXnY as "disk")
    mapfile -t nodes < <(lsblk -dn -o NAME | grep -E '^nvme[0-9]+n[0-9]+$' | sed 's|^|/dev/|') || true
  fi
  printf '%s\n' "${nodes[@]}"
}

# If DRY_RUN=1, just print the command. Otherwise execute it.
do_or_echo() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[DRY] $*"
    return 0
  fi
  "$@"
}

# Make sure log dir exists and is owned by the invoking user if running under sudo.
init_log_dir() {
  mkdir -p -- "$SED_LOG_DIR" || return
  chmod 0700 -- "$SED_LOG_DIR" 2>/dev/null || true
  if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$SED_LOG_DIR" 2>/dev/null || true
  fi
}

# After creating/append to a log file, flip ownership so the user can read it.
make_log_user_readable() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  chmod 0640 -- "$f" 2>/dev/null || true
  if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$f" 2>/dev/null || true
  fi
}

# ── sane defaults for -u and logs ───────────────────────────────
: "${SED_LOG_DIR:=/tmp/sed-debug}"
: "${SED_DEBUG:=1}"
: "${SUDO_BIN:=sudo}"
: "${NVME_BIN:=nvme}"
: "${EXPECT_BIN:=expect}"

# SED master secret:
#   Provide via env MASTER_SECRET (recommended), or the script will prompt once.
#   Keys are derived per-drive from MASTER_SECRET + controller serial.
: "${MASTER_SECRET:=}"

# Write materialized key files? 0 = no (default; keys are derived), 1 = yes.
: "${SED_WRITE_KEYS:=0}"

# Key length policy (nvme-cli allows 8..32 for Opal). We use 30 by default.
: "${SED_KEY_LEN:=30}"

# Expect timeouts (seconds). You can override at runtime:
#   SED_REVERT_TIMEOUT=30 SED_INIT_TIMEOUT=90 ./setup.sh

: "${SED_INIT_TIMEOUT:=90}"
: "${SED_REVERT_TIMEOUT:=30}"

# Auto-PSID fallback on initialize failure ("Host Not Authorized")
: "${FORCE_PSID:=1}"

# Track PSID reverts performed in this run (to summarize once, at the end)
declare -a PSID_REVERTED_DEVICES=(); NEED_POWER_CYCLE=0

# ── SED master-secret driven per-drive SIDs ─────────────────────
# Always prompt unless SED_MASTER_SECRET is already exported.
: "${SED_SID_LEN:=30}"    # 8..32; keep ≤32 for Opal firmware sanity
: "${SECRETS_MOUNT:=/run/secrets}"
: "${KEYS_DIR:=${SECRETS_MOUNT}/keys}"

# ensure log dir exists and is writable by current user (not root leftovers)
init_log_dir

if [[ $EUID -ne 0 ]]; then
  echo -e "\033[1;31m[ERROR]\033[0m This script must be run as root."
  exit 1
fi

### IDENTIFY TARGET DRIVE ###
# Make sure stale /secrets isn't influencing detection
do_or_echo umount /mnt/secrets 2>/dev/null || do_or_echo umount -l /mnt/secrets 2>/dev/null || true
if do_or_echo cryptsetup status secrets_crypt &>/dev/null; then
  do_or_echo cryptsetup luksClose secrets_crypt 2>/dev/null || true
fi

echo -e "\033[1;34m[INFO]\033[0m Detecting available disks..."
lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINT

# Filter out nvme, and loop devices to avoid picking them accidentally
DEFAULT_BOOT=$(
  lsblk -dno NAME,TYPE,SIZE,TRAN \
  | awk '$2=="disk" && $4!="nvme"{print "/dev/"$1, $3}' \
  | sort -h -k2 \
  | head -n1 \
  | awk '{print $1}'
)

if [[ -z "$DEFAULT_BOOT" ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Could not detect a valid boot drive!"
    exit 1
fi

echo -e "\n\033[1;33m[WARNING]\033[0m The target boot drive is set to: \033[1;36m${DEFAULT_BOOT}\033[0m"
echo "Detected details:"

# Run fdisk safely outside a pipe to avoid -e/pipefail killing the script on 0B/quirky devices.
{ FD_OUT="$(fdisk -l "${DEFAULT_BOOT}" 2>/dev/null || true)"; } || true
if [[ -n "$FD_OUT" ]]; then
  printf '%s\n' "$FD_OUT" | awk -v d="${DEFAULT_BOOT}" '$0 ~ ("^Disk " d) {print}' || true
else
  echo "(fdisk provided no details; device may report 0B or not support geometry queries)"
fi

confirm "Is this the correct drive? This will ERASE and REINSTALL your system! Type 'YES' to proceed."; rc=$?; ((rc==0)) || exit 1

BOOT_MOUNT="/mnt/boot"
SECRETS_MOUNT="/mnt/secrets"
EFI_PARTITION="${DEFAULT_BOOT}1"
BOOT_PARTITION="${DEFAULT_BOOT}2"
SECRETS_PARTITION="${DEFAULT_BOOT}3"
DATA_PARTITION="${DEFAULT_BOOT}4"

# keys will live on the encrypted /secrets partition
KEYS_DIR="${SECRETS_MOUNT}/keys"

cleanup() {
  set +e
  umount "${SECRETS_MOUNT:-/mnt/secrets}" 2>/dev/null || true
  cryptsetup luksClose secrets_crypt 2>/dev/null || true
  umount "${BOOT_MOUNT:-/mnt/boot}/EFI" 2>/dev/null || true
  umount "${BOOT_MOUNT:-/mnt/boot}" 2>/dev/null || true
}
trap cleanup EXIT

# Ensure OpenSSL is installed
if ! command -v openssl &>/dev/null; then
    echo -e "\033[1;34m[INFO]\033[0m Installing OpenSSL..."
    if ! nix profile install nixpkgs#openssl --extra-experimental-features nix-command --extra-experimental-features flakes; then
        echo -e "\033[1;31m[ERROR]\033[0m Failed to install OpenSSL! Check your Nix setup."
        exit 1
    fi
fi

# Ensure Expect is installed (used to drive nvme-cli prompts)
if ! command -v expect &>/dev/null; then
    echo -e "\033[1;34m[INFO]\033[0m Installing Expect..."
    if ! nix profile install nixpkgs#expect --extra-experimental-features nix-command --extra-experimental-features flakes; then
        echo -e "\033[1;31m[ERROR]\033[0m Failed to install Expect (package 'expect')."
        echo "Install it manually (e.g., 'nix profile install nixpkgs#expect') and re-run."
        exit 1
    fi
fi

# Resolve EXPECT_BIN (works even if PATH wasn’t updated yet)
EXPECT_BIN="$(command -v expect || true)"
: "${EXPECT_BIN:=expect}"

### PRE-FLIGHT CHECKS
echo -e "\033[1;34m[INFO]\033[0m Checking required commands..."
for cmd in \
  openssl expect parted mdadm pvcreate vgcreate lvcreate lvs vgs pvs \
  mkfs.ext4 mkfs.f2fs mkfs.vfat findmnt git nvme dmsetup nixos-install cryptsetup; do
  check_command "$cmd"
done

# Verify nvme sed subcommands are present
if ! "${NVME_BIN:-nvme}" sed help 2>&1 | grep -qi 'initialize'; then
  echo -e "\033[1;31m[ERROR]\033[0m nvme-cli is present but lacks SED/Opal support."
  echo "Expected subcommands: discover, initialize, revert, lock, unlock."
  exit 1
fi

### RUNTIME SANITY (compact) ###
runtime_sanity
robust_storage_reset

echo -e "\033[1;34m[INFO]\033[0m Proceeding with SED hardware crypto-wipe & init before provisioning…"

# ── Make 100% sure the installer/GUI hasn't mounted the target USB ────────────
echo -e "\033[1;34m[INFO]\033[0m Releasing any mounts on ${DEFAULT_BOOT}…"

# Unmount any mountpoints whose SOURCE begins with the target disk (/dev/sdX1, /dev/sdX2, …)
mapfile -t _BOOT_MPS < <(findmnt -rn -S "^${DEFAULT_BOOT}.*" -o TARGET 2>/dev/null || true)
for mp in "${_BOOT_MPS[@]}"; do
  echo "  - umount $mp"
  umount -R -- "$mp" 2>/dev/null || umount -lR -- "$mp" 2>/dev/null || true
done

# Give udev a moment to settle device state
udevadm settle 2>/dev/null || true

### PARTITIONING ###
echo -e "\033[1;34m[INFO]\033[0m Partitioning ${DEFAULT_BOOT}..."
do_or_echo parted -s ${DEFAULT_BOOT} mklabel gpt

# 1  ESP    512 MiB
do_or_echo parted -s ${DEFAULT_BOOT} mkpart ESP fat32     1MiB  551MiB
do_or_echo parted -s ${DEFAULT_BOOT} set   1 esp on

# 2  /boot  2 GiB
do_or_echo parted -s ${DEFAULT_BOOT} mkpart BOOT ext4    551MiB 2599MiB

# 3  /secrets 256 MiB (will be LUKS2 → ext4)
do_or_echo parted -s ${DEFAULT_BOOT} mkpart SECRETS ext4 2599MiB 2855MiB

# 4  /data  remainder of the stick
do_or_echo parted -s ${DEFAULT_BOOT} mkpart DATA ext4    2855MiB 100%

### FORMATTING EFI ###
echo -e "\033[1;34m[INFO]\033[0m Formatting EFI partition..."
do_or_echo mkfs.vfat -v -F 32 ${EFI_PARTITION}

### FORMATTING & MOUNTING /BOOT ###
echo -e "\033[1;34m[INFO]\033[0m Formatting and mounting /boot..."
do_or_echo mkfs.ext4 ${BOOT_PARTITION}
do_or_echo mkdir -p ${BOOT_MOUNT}
do_or_echo mount ${BOOT_PARTITION} ${BOOT_MOUNT}
do_or_echo mkdir -p ${BOOT_MOUNT}/EFI
do_or_echo mount ${EFI_PARTITION} ${BOOT_MOUNT}/EFI

# create & unlock the **LUKS2 /secrets** slice
echo -e "\033[1;34m[INFO]\033[0m Creating encrypted /secrets partition (you’ll be prompted once)..."
do_or_echo cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 ${SECRETS_PARTITION}
do_or_echo cryptsetup luksOpen ${SECRETS_PARTITION} secrets_crypt
do_or_echo mkfs.ext4  /dev/mapper/secrets_crypt
do_or_echo mkdir -p   ${SECRETS_MOUNT}
do_or_echo mount      /dev/mapper/secrets_crypt ${SECRETS_MOUNT}

# ────────────────────────────────────────────────────────────────
# Create/keep SED passphrase & (optionally) reset pre-encrypted drives
# ────────────────────────────────────────────────────────────────
do_or_echo mkdir -p "${KEYS_DIR}"

# Ensure per-controller SID key files exist (prompts once for SED_MASTER_SECRET)
ensure_keys_for_present_controllers

# Hardware crypto-wipe + initialize + verify lock/unlock on all namespaces
echo -e "\033[1;34m[INFO]\033[0m Proceeding with SED hardware crypto-wipe & init before provisioning…"
set +e
overall_fail=0
for dev in $(list_nvme_namespaces); do
  echo "dev: ${dev}"
  sed_reset_and_init "$dev"
  rc=$?
  case "$rc" in
    0)  ;;                       # ok
    90) ;;                       # PSID revert recorded inside sed_psid_revert_then_die
    *)  overall_fail=1 ;;        # other failure
  esac
done
set -e

if (( NEED_POWER_CYCLE )); then
  echo -e "\n\033[1;33m[ACTION REQUIRED]\033[0m A PSID revert was performed on the following device(s):"
  for d in "${PSID_REVERTED_DEVICES[@]}"; do
    echo "  - $d"
  done
  echo
  echo "Perform a full power cycle now:"
  echo "  1) Shut the machine down completely."
  echo "  2) Remove power for ~10 seconds."
  echo "  3) Boot and re-run this script; it will skip reverts and go straight to initialize."
  exit 90
fi

if (( overall_fail )); then
  echo -e "\033[1;31m[ERR]\033[0m One or more drives failed SED setup; check logs in ${SED_LOG_DIR}."
  exit 1
fi

### CREATING RAID-0 ###

echo -e "\033[1;34m[INFO]\033[0m Ensuring no stale md0 is present..."
do_or_echo mdadm --stop /dev/md0 || true
do_or_echo mdadm --remove /dev/md0 || true

for i in {1..5}; do
    if [ -e /dev/md0 ]; then
        echo -e "\033[1;33m[WAITING]\033[0m md0 still present... waiting 1s"
        sleep 1
    else
        break
    fi
done

echo -e "\033[1;34m[INFO]\033[0m Creating RAID-0 array..."

mapfile -t NVME_NS < <(list_nvme_namespaces)
echo -e "\033[1;34m[INFO]\033[0m NVMe namespaces detected: ${NVME_NS[*]:-(none)}"
if (( ${#NVME_NS[@]} < 2 )); then
  echo -e "\033[1;31m[ERROR]\033[0m Need at least two NVMe namespaces for RAID-0."
  exit 1
fi
BLOCK_01="$(basename "${NVME_NS[0]}")"
BLOCK_02="$(basename "${NVME_NS[1]}")"
echo -e "\033[1;36m[PLAN]\033[0m RAID0: /dev/${BLOCK_01} + /dev/${BLOCK_02}"

do_or_echo mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 --chunk=512K --force /dev/${BLOCK_01} /dev/${BLOCK_02}

### CREATING LVM ###
echo -e "\033[1;34m[INFO]\033[0m Creating LVM structure..."

do_or_echo wipefs -af /dev/md0 2>/dev/null || true

# 1️⃣  Create the Physical Volume
do_or_echo pvcreate -ff -y /dev/md0 || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create Physical Volume!"; exit 1; }

# 2️⃣  Create the Volume Group
do_or_echo vgcreate -s 16M nix /dev/md0 || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create Volume Group!"; exit 1; }

# 3️⃣  Create Logical Volumes
do_or_echo lvcreate -L 96G  -n swap nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create swap LV!"; exit 1; }
do_or_echo lvcreate -L 80G  -n tmp  nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create tmp LV!"; exit 1; }
do_or_echo lvcreate -L 80G  -n var  nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create var LV!"; exit 1; }
do_or_echo lvcreate -L 200G -n root nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create root LV!"; exit 1; }
do_or_echo lvcreate -L 500G -n home nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create home LV!"; exit 1; }

# 4️⃣  Verify LVM setup
echo -e "\033[1;34m[INFO]\033[0m Verifying LVM setup..."
do_or_echo vgdisplay nix
do_or_echo lvdisplay nix

# 5️⃣  Format Logical Volumes with F2FS
echo -e "\033[1;34m[INFO]\033[0m Formatting Logical Volumes with F2FS..."
do_or_echo mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr -z 512 /dev/nix/tmp  || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format tmp LV!"; exit 1; }
do_or_echo mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr -z 512 /dev/nix/var  || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format var LV!"; exit 1; }
do_or_echo mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr -z 512 /dev/nix/root || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format root LV!"; exit 1; }
do_or_echo mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr -z 512 /dev/nix/home || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format home LV!"; exit 1; }

# 6️⃣  Configure Swap
echo -e "\033[1;34m[INFO]\033[0m Configuring Swap..."
do_or_echo mkswap /dev/nix/swap
do_or_echo swapon /dev/nix/swap

# 6.5 Unmount Boot and EFI (First step)
echo -e "\033[1;34m[INFO]\033[0m Unmounting Boot and EFI..."
do_or_echo umount ${BOOT_MOUNT}/EFI || true
do_or_echo umount ${BOOT_MOUNT} || true
do_or_echo umount ${SECRETS_MOUNT}  || true
do_or_echo cryptsetup luksClose secrets_crypt || true

# 7️⃣  Mount Logical Volumes
echo -e "\033[1;34m[INFO]\033[0m Mounting Logical Volumes..."
do_or_echo mount /dev/nix/root /mnt || { echo -e "\033[1;31m[ERROR]\033[0m Failed to mount root!"; exit 1; }
do_or_echo mkdir -p /mnt/tmp  && do_or_echo mount /dev/nix/tmp  /mnt/tmp
do_or_echo mkdir -p /mnt/var  && do_or_echo mount /dev/nix/var  /mnt/var
do_or_echo mkdir -p /mnt/home && do_or_echo mount /dev/nix/home /mnt/home

# 8️⃣  Remount Boot and EFI
echo -e "\033[1;34m[INFO]\033[0m Remounting Boot and EFI..."
do_or_echo mkdir -p ${BOOT_MOUNT} && do_or_echo mount ${BOOT_PARTITION} ${BOOT_MOUNT}
do_or_echo mkdir -p ${BOOT_MOUNT}/EFI && do_or_echo mount ${EFI_PARTITION} ${BOOT_MOUNT}/EFI

# remount secrets for the copy-to-nixos step
do_or_echo mkdir -p ${SECRETS_MOUNT}
do_or_echo cryptsetup luksOpen ${SECRETS_PARTITION} secrets_crypt
do_or_echo mount /dev/mapper/secrets_crypt ${SECRETS_MOUNT}

echo -e "\033[1;34m[INFO]\033[0m Verifying that all devices and filesystems are correctly set up..."

# Check RAID status
if ! grep -q "md0" /proc/mdstat; then
    echo -e "\033[1;31m[ERROR]\033[0m RAID array /dev/md0 is NOT active!"
    exit 1
else
    echo -e "\033[1;32m[OK]\033[0m RAID array /dev/md0 is active."
fi

# Check if LVM volumes exist
for lv in root var home tmp swap; do
    if [ ! -e "/dev/nix/$lv" ]; then
        echo -e "\033[1;31m[ERROR]\033[0m LVM volume nix/$lv does NOT exist!"
        exit 1
    else
        echo -e "\033[1;32m[OK]\033[0m LVM volume nix/$lv exists."
    fi
done

echo -e "\033[1;34m[INFO]\033[0m Waiting for all LVM volumes to settle..."
REQUIRED_MOUNTS=("tmp" "var" "home" "boot" "boot/EFI")

# Wait for up to 10 seconds for all required mounts
for i in {1..10}; do
    MISSING_MOUNTS=()

    for mountpoint in "${REQUIRED_MOUNTS[@]}"; do
        if ! findmnt -r "/mnt/$mountpoint" &>/dev/null; then
            MISSING_MOUNTS+=("$mountpoint")
        fi
    done

    if [ ${#MISSING_MOUNTS[@]} -eq 0 ]; then
        echo -e "\033[1;32m[OK]\033[0m All required filesystems are mounted."
        break
    fi

    echo -e "\033[1;33m[WAITING]\033[0m Still waiting for: ${MISSING_MOUNTS[*]}... retrying in 1 second."
    sleep 1
done

# Final hard check to fail if any mounts are still missing
MISSING_FINAL=()
for mountpoint in "${REQUIRED_MOUNTS[@]}"; do
    if ! findmnt -r "/mnt/$mountpoint" &>/dev/null; then
        MISSING_FINAL+=("$mountpoint")
    fi
done

if [ ${#MISSING_FINAL[@]} -ne 0 ]; then
    echo -e "\033[1;31m[ERROR]\033[0m The following mount points are still missing: ${MISSING_FINAL[*]}"
    exit 1
fi

echo -e "\033[1;34m[INFO]\033[0m All devices, filesystems, and mounts are correctly set up."

do_or_echo umount ${SECRETS_MOUNT}
do_or_echo cryptsetup luksClose secrets_crypt

### CLONING NIXOS CONFIG FROM GIT ###
echo -e "\033[1;34m[INFO]\033[0m Generating initial hardware configuration..."
do_or_echo nixos-generate-config --root /mnt  # <-- Creates initial /mnt/etc/* files

### ASK USER FOR HOSTNAME ###
echo -e "\033[1;34m[INFO]\033[0m Please enter the hostname for this system:"
read -p "Hostname: " HOSTNAME

# Ensure it's a valid hostname (no spaces or special characters)
if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Invalid hostname. Use only letters, numbers, dots, hyphens, and underscores."
    exit 1
fi

echo -e "\033[1;34m[INFO]\033[0m Copying NixOS flake repo to its official destination..."
do_or_echo cp -r /home/nixos/nixos /mnt/etc

do_or_echo chown -R nixos:users /mnt/etc/nixos

# do_or_echo git config --system --add safe.directory /mnt/etc/nixos

echo -e "\033[1;34m[INFO]\033[0m Moving the hardware configuration to the host-specific path in the repo..."
do_or_echo mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/$HOSTNAME/hardware-configuration.nix

HWC_PATH="/mnt/etc/nixos/hosts/$HOSTNAME/hardware-configuration.nix"

# Strip out availableKernelModules block entirely from hardware-configuration.nix
sed -i '/boot\.initrd\.availableKernelModules = \[/,/];/d' "$HWC_PATH"

# Remove kernelModules block
sed -i '/boot\.initrd\.kernelModules = \[/,/];/d' "$HWC_PATH"

# Remove luks.cryptoModules block
sed -i '/boot\.initrd\.luks\.cryptoModules = \[/,/];/d' "$HWC_PATH"

do_or_echo mv /mnt/etc/nixos/configuration.nix /mnt/etc/nixos/configuration.nix.installer

echo -e "\033[1;34m[INFO]\033[0m Extracting hardware-specific details for flake configuration..."

# Get UUIDs for devices and filesystems
boot_fs_uuid=$(get_uuid "$BOOT_PARTITION")     # ext4 /boot
efi_fs_uuid=$(get_uuid "$EFI_PARTITION")       # vfat /boot/EFI

root_fs_uuid=$(findmnt -no UUID /mnt)
var_fs_uuid=$(findmnt -no UUID /mnt/var)
tmp_fs_uuid=$(findmnt -no UUID /mnt/tmp)
home_fs_uuid=$(findmnt -no UUID /mnt/home)

# If anything is empty, settle udev and retry once
if [[ -z "$efi_fs_uuid" || -z "$boot_fs_uuid" ]]; then
do_or_echo udevadm settle || true
  [[ -z "$boot_fs_uuid" ]] && boot_fs_uuid=$(get_uuid "$BOOT_PARTITION")
  [[ -z "$efi_fs_uuid"  ]] && efi_fs_uuid=$(get_uuid "$EFI_PARTITION")
fi

# (Optional) if you still want a separate “boot_uuid”, make it the same source:
boot_uuid="$boot_fs_uuid"

# UUID of the *unencrypted* mapper device
#secrets_fs_uuid=$(blkid -s UUID -o value /dev/mapper/secrets_crypt)

# --- compute stable device symlinks ----------------------------------------
# LUKS container (encrypted) device path for /secrets
secrets_path="$(
  for f in /dev/disk/by-id/*; do
    [[ -e "$f" ]] || continue
    [[ "$(readlink -f "$f")" == "$SECRETS_PARTITION" ]] && { echo "$f"; break; }
  done
)"

# Get persistent device paths
nvme0_path="$(
  for f in /dev/disk/by-id/nvme-*; do
    [[ -e "$f" ]] || continue
    [[ "$(readlink -f "$f")" == /dev/nvme0n1 ]] && { echo "$f"; break; }
  done
)"
nvme1_path="$(
  for f in /dev/disk/by-id/nvme-*; do
    [[ -e "$f" ]] || continue
    [[ "$(readlink -f "$f")" == /dev/nvme1n1 ]] && { echo "$f"; break; }
  done
)"

if [[ -z "$nvme0_path" || -z "$nvme1_path" ]]; then
    # Fall back to raw nodes if by-id symlinks aren’t present
    : "${nvme0_path:=/dev/nvme0n1}"
    : "${nvme1_path:=/dev/nvme1n1}"
fi
if [[ ! -e "$nvme0_path" || ! -e "$nvme1_path" ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Failed to determine NVMe device paths!"
    echo "Check your system's device list manually and update flake.nix as needed."
    exit 1
fi

# Validate extracted values against hardware-configuration.nix
echo -e "\033[1;34m[INFO]\033[0m Verifying extracted values exist in hardware.nix..."

MISSING_VALUES=0
check_value "$boot_uuid" "Boot UUID"
check_value "$boot_fs_uuid" "Boot Filesystem UUID"
check_value "$efi_fs_uuid" "EFI Filesystem UUID"
#check_value "$secrets_fs_uuid"  "Secrets Filesystem UUID"

if [[ $MISSING_VALUES -gt 0 ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Some expected values were not found in hardware-configuration.nix!"
    echo "Please check hardware-configuration.nix and ensure all required values are present."
    exit 1
fi

# 🧼 Remove /secrets mount entry to avoid early-stage mount issues
#echo -e "\033[1;34m[INFO]\033[0m Removing /secrets filesystem entry from hardware.nix..."

# delete the luks.devices line
#sed -i '/^[[:space:]]*boot\.initrd\.luks\.devices\."secrets_crypt"\.device[[:space:]]*=/d' "$HWC_PATH"

# delete the /secrets filesystem block
#sed -i '/^[[:space:]]*fileSystems\."\/secrets"[[:space:]]*=/,/^[[:space:]]*};[[:space:]]*$/d' "$HWC_PATH"

echo -e "\033[1;34m[INFO]\033[0m Writing ${BOOT_MOUNT}/secrets/flakey.json ..."

# ensure the directory exists on the *boot* filesystem
do_or_echo mkdir -p "${BOOT_MOUNT}/secrets"

do_or_echo tee "${BOOT_MOUNT}/secrets/flakey.json" >/dev/null <<EOF
{
  "PLACEHOLDER_NVME0":  "${nvme0_path}",
  "PLACEHOLDER_NVME1":  "${nvme1_path}",

  "PLACEHOLDER_BOOT_FS_UUID":   "/dev/disk/by-uuid/${boot_fs_uuid}",
  "PLACEHOLDER_EFI_FS_UUID":    "/dev/disk/by-uuid/${efi_fs_uuid}",

  "PLACEHOLDER_ROOT":  "/dev/disk/by-uuid/${root_fs_uuid}",
  "PLACEHOLDER_VAR":   "/dev/disk/by-uuid/${var_fs_uuid}",
  "PLACEHOLDER_TMP":   "/dev/disk/by-uuid/${tmp_fs_uuid}",
  "PLACEHOLDER_HOME":  "/dev/disk/by-uuid/${home_fs_uuid}",
  "PLACEHOLDER_SECRETS": "${secrets_path}",

  "GIT_SMTP_PASS": "mlucmulyvpqlfprb"
}
EOF
# "PLACEHOLDER_SECRETS": "/dev/disk/by-uuid/${secrets_fs_uuid}",
do_or_echo chmod 600 "${BOOT_MOUNT}/secrets/flakey.json"

### APPLYING SYSTEM CONFIGURATION ###

echo -e "\033[1;34m[INFO]\033[0m Installing NixOS from flake..."
nixos-install \
  --flake /mnt/etc/nixos#${HOSTNAME} \
  --override-input secrets-empty path:${BOOT_MOUNT}/secrets/flakey.json

#do_or_echo umount ${SECRETS_MOUNT}
#do_or_echo cryptsetup luksClose secrets_crypt
#do_or_echo umount "${BOOT_MOUNT}/EFI"
#do_or_echo umount "${BOOT_MOUNT}"

echo -e "\033[1;32m[SUCCESS]\033[0m Installation complete! Reboot when ready."
