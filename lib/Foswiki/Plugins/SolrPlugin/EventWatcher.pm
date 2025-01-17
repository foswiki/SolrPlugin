# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2020-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Foswiki::Plugins::SolrPlugin::EventWatcher;

use strict;
use warnings;

use Linux::Inotify2;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use Fcntl qw(SEEK_SET SEEK_END);
use POSIX ":sys_wait_h"; 

use constant {
  FMASK => IN_CLOSE_WRITE | IN_MOVE_SELF,
  DMASK => IN_CREATE | IN_MOVED_FROM | IN_MOVED_TO,
};

sub new {
  my $class = shift;

  require "LocalSite.cfg";

  my $this = bless({
      debug => 0,
      vhosting => 0,
      throttle => 1,
      foswikiRoot => $ENV{FOSWIKI_ROOT},
      throttle => 0,
      parallel => 1,
      files => [],
      skipWebs => $Foswiki::cfg{SolrPlugin}{SkipWebs}  // '',
      skipTopics => $Foswiki::cfg{SolrPlugin}{SkipTopics}  // '',
      @_
    },
    $class
  );

  foreach my $web (split(/\s*,\s*/, $this->{skipWebs})) {
    $web =~ s/\//\./g;
    $this->{_skippedWebs}{$web} = 1;
  }
  foreach my $topic (split(/\s*,\s*/, $this->{skipTopics})) {
    $this->{_skippedTopics}{$topic} = 1;
  }

  die "no files" unless scalar(@{$this->{files}});

  return $this;
}

sub start {
  my $this = shift;

  $this->writeDebug("start");

  $this->init();

  while (!$this->{signalTrapped}) {
    $this->writeDebug("polling...");
    $this->inotify->poll();
    $this->spawnWorkers();
  }
}

sub spawnWorkers {
  my $this = shift;

  my $numProcs = scalar(keys %{$this->{pids}});
  foreach my $key (keys %{$this->{queue}}) {
    last if $numProcs >= $this->{parallel};
    last if $this->{signalTrapped};

    my $job = $this->{queue}{$key};
    next unless $job;

    my $cmd;
    if ($this->{vhosting}) {
      $cmd = "$this->{solrIndex} verbose=off host=$job->{host} topic=$job->{web}.$job->{topic}";
    } else {
      $cmd = "$this->{solrIndex} topic=$job->{web}.$job->{topic}";
    }
    #$this->writeDebug("cmd=$cmd");

    #$this->writeDebug("forking indexer for $job->{web}.$job->{topic}...");
    my $pid = fork();
    unless ($pid) {
      if ($this->{throttle}) {
        $this->writeDebug("throttling process ... ");
        sleep $this->{throttle};
      }
      $this->writeDebug("... starting process");
      exec($cmd) or die "cannot exec command";
      exit 0; # never reach
    } 

    $this->{pids}{$pid} = $key;
    $numProcs++;
    $this->{workInProgress}{$key} = $job;
    delete $this->{queue}{$key};
  }
}

sub init {
  my $this = shift;

  return if $this->{inited};
  $this->{inited} = 1;

  $this->{signalTrapped} = 0;

  my $toolsDir = "$this->{foswikiRoot}/tools";
  chdir($toolsDir) or die "ERROR: directory not found $toolsDir";

  $this->{solrIndex} = $toolsDir . '/' . ($this->{vhosting} ? "virtualhosts-solrindex" : "solrindex");

  die "ERROR: solrindex command not found: $this->{solrIndex}" unless -e $this->{solrIndex};

  $this->{queue} = {};
  $this->{pids} = {};
  $this->{workInProgress} = {};

  $SIG{INT} = sub {
    $this->writeDebug("got interrupted ... finishing work");
    $this->{signalTrapped} = 1;
  };

  $SIG{CHLD} = sub {
    local ($!, $?);
    while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
      $this->writeDebug("process $pid terminated");
      my $key = delete $this->{pids}{$pid};
      delete $this->{workInProgress}{$key};
      $this->spawnWorkers;
    }
  };

  $this->watchFiles;
}

sub inotify {
  my $this = shift;

  unless ($this->{inotify}) {
    $this->{inotify} = Linux::Inotify2->new() or die "ERROR: unable to create new inotify object: $!";
  }

  return $this->{inotify};
}

sub watchFiles {
  my $this = shift;

  foreach my $file (@{$this->{files}}) {
    my $absFile = abs_path($file);
    $this->watchFile($absFile);
    $this->watchDir($absFile);
  }
}

sub watchFile {
  my ($this, $file) = @_;

  $this->writeDebug("watchFile($file)");

  my $size = _fileSize($file);
  $this->{curPos}{$file} = $size;

  $this->inotify->watch($file, FMASK, sub {
    return $this->processEvent(@_);    
  });
}

sub watchDir {
  my ($this, $file) = @_;

  my $dir = dirname($file);
  $this->writeDebug("watchDir($dir)");

  $this->inotify->watch($dir, DMASK, sub {
    my $event = shift;

    return unless $event->fullname eq $file;

    if (($event->IN_CREATE || $event->IN_MOVED_TO)) {
      $this->{curPos}{$file} = _fileSize($file);
      $this->watchFile($file);
    }
  });
}

sub processEvent {
  my ($this, $event) = @_;

  my $file = $event->fullname;

  if ($event->IN_CLOSE_WRITE) {
    open my $fh, '<', $file or die "ERROR: Cannot open $file: $!";
    seek $fh, $this->{curPos}{$file}, SEEK_SET;

    while (<$fh>) {
      $this->processLine($file, $_);
    }

    $this->{curPos}{$file} = tell $fh;
    close $fh or die "ERROR: Cannot close $file: $!";
  }

  if ($event->IN_MOVE_SELF) {
    $event->w->cancel;
  }
}

sub processLine {
  my ($this, $file, $line) = @_;

  return unless defined $line;

  $line =~ s/^\s+//;
  $line =~ s/\s+$//;

  $this->writeDebug("processLine($line)");

  my $host;

  if ($this->{vhosting}) {
    if ($file =~ /\/([^\/]+)\/working/) {
      $host = $1;
      $this->writeDebug("host=$host");
    }
  }

  # save
  if ($line =~ /\|\s*save\s*\|\s*(.*?)\s*\|/) {
    $this->writeDebug("found save");
    $this->addToQueue($1, $host);
    return;
  }

  # upload
  if ($line =~ /\|\s*upload\s*\|\s*(.*?)\s*\|/) {
    $this->writeDebug("found upload");
    $this->addToQueue($1, $host);
    return;
  }

  # rename topic
  if ($line =~ /\|\s*rename\s*\|\s*(.*?)\s*\|\s*[Mm]oved to\s*(.*?)\s*\|/) {
    $this->writeDebug("found rename");
    $this->addToQueue($1, $host);
    $this->addToQueue($2, $host);
    return;
  }

  # move attachment
  # SMELL: fails when attachment has dots in its name
  if ($line =~ /\|\s*move\s*\|\s*(.*?)\.\w+\.\w+\s*\|\s*[Mm]oved to\s*(.*?)\.\w+\.\w+\s*\|/) {
    $this->writeDebug("found move");
    $this->addToQueue($1, $host);
    $this->addToQueue($2, $host);
    return;
  }

  $this->writeDebug("nothing found");
}

sub addToQueue {
  my ($this, $item, $host) = @_;

  $this->writeDebug("addToQueue($item, ".($host//'undef').")");
  my ($web, $topic) = _normalizeWebTopicName(undef, $item);
  
  my $key = defined($host)?"$host - $web - $topic":"$web - $topic";

  if (exists $this->{workInProgress}{$key}) {
    $this->writeDebug("not adding job '$key' as it is work in progress");
    return;
  } 

  if (exists $this->{queue}{$key}) {
    $this->writeDebug("not adding job '$key' as it has already been queued");
    return;
  }

  next if $this->{_skippedWebs}{$web};
  next if $this->{_skippedTopics}{$topic};

  $this->writeDebug("adding job '$key'");


  my $job = $this->{queue}{$key} = {
    key => $key,
    host => $host,
    web => $web,
    topic => $topic,
  };

  return $job;
}

sub writeDebug {
  my ($this, $msg) = @_;

  return unless $this->{debug};

  print STDERR "EventWatcher - $msg\n";
}

sub _fileSize {
  my $file = shift;

  return (stat $file)[7];
}

sub _normalizeWebTopicName {
  my ($web, $topic) = @_;

  if (defined $topic && $topic =~ m{^(.*)(?:\.|/)(.*?)$}) {
    $web = $1;
    $topic = $2;
  }
  $web ||= "Main";
  $topic ||= "WebHome";

  $web =~ s/\//./g;

  return ($web, $topic);
}

1;
