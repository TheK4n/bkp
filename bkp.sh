#!/usr/bin/env bash

BACKUP_DIR="$HOME"/.backup
BACKUP_DIR_1="$BACKUP_DIR"/1  # local file system
GPG_ID="$BACKUP_DIR"/.gpg-id

BACKUP_FILE="$BACKUP_DIR/backup.conf"
LOG_FILE="$BACKUP_DIR/backup.log"

SCRIPT_NAME="$(basename "$0")"


die() {
    echo "$SCRIPT_NAME: Error: $1" >&2
    exit 1
}

yesno() {
    [[ -t 0 ]] || return 0
    local response
    read -r -p "$1 [y/N] " response
    [[ $response == [yY] ]] || exit 1
}

log_msg() {
    echo "$SCRIPT_NAME: $(date +"%d-%m-%Y %T"): $1" >> "$LOG_FILE"
}

log_error() {
    log_msg "Error: $1"
}

get_filesystems() {
    find -L "$BACKUP_DIR" -maxdepth 1 -type d | grep -vE "^$BACKUP_DIR$" | sort
}

cmd_init() {

    test -z "$(gpg -k | grep "$1")" && die "No public key '$1'"
    test -z "$(gpg -K | grep "$1")" && die "No private key '$1'"

    mkdir -p "$BACKUP_DIR"/1 || true
    touch "$LOG_FILE"
    touch "$BACKUP_FILE"
    echo "$1" > "$GPG_ID"
}

rsync_with() {
    rsync -ra "$BACKUP_DIR_1"/* "$1" && rsync -ra "$1"/* "$BACKUP_DIR_1"
}

cmd_rsync_all() {
    for i in $(get_filesystems)
    do
        rsync_with "$i"
    done
}

cmd_insert() {
    test -e "$1" || die "not exists"
    test -d "$1" && die "only files, not directory"

    _path="$BACKUP_DIR_1/$(basename "$1")/$(date +"%d-%m-%y")"
    file_name="$_path/$(date +"%H:%M:%S")"

    test -f "$file_name" && die "'$(basename "$1")' already exists"

    mkdir -pv "$_path"
    gpg -e -R "$(cat "$GPG_ID")" -o "$file_name" "$1"
    cmd_rsync_all
}

delete_if_exists() {
    if [ -d "$1" ]; then
        rm -r "$1"
    elif [ -f "$1" ]; then
        rm "$1"
    else
        return 1
    fi
}

cmd_delete() {
    yesno "Remove '$1'?"
    for i in $(get_filesystems)
    do
        _file="$i"/"$1"
        delete_if_exists "$_file" && echo "$SCRIPT_NAME: '$_file' Removed"
    done
}

cmd_show() {
    echo "Backup"
    tree -L 1 "$BACKUP_DIR_1" | tail -n +2 | head -n -2  # tree exclude first and last lines
}

cmd_restore() {
    test -e "$1" && die "'$1' exists in current directory"
    file_name="$(basename "$1")"

    # get last saved file by time
    last_sub_dir="$(ls -t "$BACKUP_DIR_1"/"$file_name" | head -n 1)"
    last_file="$BACKUP_DIR_1"/"$file_name"/"$last_sub_dir"/"$(ls -t "$BACKUP_DIR_1"/"$file_name"/"$last_sub_dir" | head -n 1)"

    # restore last saved file
    test -e "$last_file" && gpg -d -o "$file_name" "$last_file"
}

cmd_diskusage() {
    for i in $(get_filesystems)
    do
        du -hs "$i"/"$1"
    done
}

cmd_register() {
    if [ -f "$1" ]; then
        realpath "$1" >> "$BACKUP_FILE"
        log_msg "Register '$(realpath "$1")'"
        sort "$BACKUP_FILE" | uniq > "$BACKUP_DIR"/.tmp  # delete duplicates
        cat "$BACKUP_DIR"/.tmp > "$BACKUP_FILE"
    else
        log_error "'$1' not a file"
    fi
}

cmd_registered() {
    cat "$BACKUP_FILE"
}

cmd_cron() {
    for i in $(tr '\n' ' ' < "$BACKUP_FILE");
    do
        if [ -f "$i" ] 
        then
            cmd_insert "$i" > /dev/null
            log_msg "Backup '$i'"
        else
            log_error "'$i' not exists"
        fi
    done
}

cmd_regedit() {
    $EDITOR "$BACKUP_FILE"
}

cmd_log() {
    cat "$LOG_FILE"
}


case "$1" in
    init) shift;			          cmd_init    "$@" ;;
    #help|--help) shift;		     cmd_usage   "$@" ;;
    #version|--version) shift;	 cmd_version "$@" ;;
    show|ls|list) shift;		    cmd_show    "$@" ;;
    insert|add) shift;		      cmd_insert  "$@" ;;
    sync) shift;                cmd_rsync_all   "$@" ;;
    restore) shift;             cmd_restore "$@" ;;
    delete|rm|remove) shift;   	cmd_delete  "$@" ;;
    du) shift;	                cmd_diskusage  "$@" ;;
    register|reg) shift;        cmd_register "$@" ;;
    registered) shift;          cmd_registered "$@" ;;
    regedit) shift;             cmd_regedit "$@" ;;
    cron) shift;                cmd_cron     "$@" ;;
    log) shift;                 cmd_log      "$@" ;;

    *)				                  cmd_show    "$@" ;;
esac
exit 0
