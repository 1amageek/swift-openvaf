#!/usr/bin/env perl
use strict;
use warnings;
use POSIX qw(WNOHANG);
use Time::HiRes qw(time);

if (@ARGV < 2) {
    print STDERR "usage: $0 <seconds> <command> [args...]\n";
    exit 64;
}

my $timeout_seconds = shift @ARGV;
if ($timeout_seconds !~ /\A[0-9]+(?:\.[0-9]+)?\z/ || $timeout_seconds <= 0) {
    print STDERR "timeout must be a positive number of seconds\n";
    exit 64;
}

my $child_pid = fork();
die "fork failed: $!\n" unless defined $child_pid;

if ($child_pid == 0) {
    setpgrp(0, 0) or die "setpgrp failed: $!\n";
    exec @ARGV;
    die "exec failed: $!\n";
}

my $deadline = time() + $timeout_seconds;

while (1) {
    my $finished = waitpid($child_pid, WNOHANG);
    if ($finished == $child_pid) {
        exit exit_code($?);
    }
    if ($finished == -1) {
        exit 1;
    }

    if (time() >= $deadline) {
        terminate_process_group($child_pid, "TERM");
        sleep 2;
        terminate_process_group($child_pid, "KILL");
        waitpid($child_pid, 0);
        exit 124;
    }

    select undef, undef, undef, 0.05;
}

sub terminate_process_group {
    my ($process_group_id, $signal) = @_;
    kill $signal, -$process_group_id;
}

sub exit_code {
    my ($status) = @_;
    my $signal = $status & 127;
    return 128 + $signal if $signal != 0;
    return ($status >> 8) & 255;
}
