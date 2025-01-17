# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2012-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
package Foswiki::Plugins::SolrPlugin::Crawler;

use strict;
use warnings;

use File::Basename ();
use Error qw(:try);

use Foswiki::Plugins::SolrPlugin::Base ();
our @ISA = qw( Foswiki::Plugins::SolrPlugin::Base );

use constant TRACE => 0;

################################################################################
sub new {
  my $class = shift;
  my $session = shift;

  my $this = $class->SUPER::new($session, @_);

  $this->init;

  # trap SIGINT
  $SIG{INT} = sub {
    $this->log("got interrupted ... finishing work");
    $this->{_trappedSignal} = 1; # will be detected by loops further down
  };

  return $this;
}

################################################################################
sub init {
  my $this = shift;

  $this->log("ERROR: cannot connect solr daemon") unless $this->connect;
}

################################################################################
sub finish {
  my $this = shift;

  $this->log("... finishing ".__PACKAGE__) if TRACE;

  undef $this->{_searcher};
  undef $this->{_timestamps};
}

################################################################################
sub crawl {
  die "crawl not implemented";
}

################################################################################
sub getIndexTime {
  my ($this, $id) = @_;

  my $ts = $this->getTimestamps();
  return 0 unless $ts && $ts->{$id};
  return $ts->{$id};
}

################################################################################
sub getTimestamps {
  my $this = shift;

  unless (defined $this->{_timestamps}) {
    $this->log("fetching timestamps for $this->{source}") if TRACE;

    $this->{_timestamps} = ();

    # get all timestamps for this web
    $this->getSearcher->iterate({
       q => "source:\"$this->{source}\"", 
       fl => "id,timestamp", 
      },
      sub {
        my $doc = shift;
        my $id = $doc->value_for("id");
        $this->{_timestamps}{$id} = $doc->value_for("timestamp");
        #$this->log("... found $id, time=$time") if TRACE;
        return 0 if $this->{_trappedSignal};
      }
    );
  }

  return $this->{_timestamps};
}

################################################################################
sub getSearcher {
  my $this = shift;

  unless (defined $this->{_searcher}) {
    $this->{_searcher} = Foswiki::Plugins::SolrPlugin::getSearcher();
  }

  return $this->{_searcher};
}

################################################################################
sub getWikiName {
  my ($this, $id) = @_;

  return unless defined $id;
  $id =~ s/^.*\.//;

  $id = "admin" if $id eq 'root'; # TODO: add mapping 

  my $wikiName = Foswiki::Func::getWikiName($id);
  if ($wikiName && $wikiName ne $id) {
    return $wikiName;
  } 

  $this->log("... unknown user $id") if TRACE;

  return;
}

################################################################################
sub getGrantedUsers {
  die "getGrantedUsers not implemented";
}

################################################################################
sub getAclFields {
  my $this = shift;

  my $viewUsers = $this->getGrantedUsers(@_, 'VIEW');
  my $editUsers = $this->getGrantedUsers(@_, 'CHANGE');

  my @fields = ();
  push @fields, "access_granted" => $viewUsers if $viewUsers;
  push @fields, "edit_granted" => $editUsers if $editUsers;

  return @fields;
}

################################################################################
sub getFileUrl {
  my ($this, $filePath) = @_;

  my $format = $this->{urlTemplate} || 'file:/$filePath';

  $format =~ s/\$filePath\b/$filePath/g;

  return $format;
}

################################################################################
sub parsePath {
  my ($this, $path) = @_;

  my ($fileName, $dirName, $extension) = File::Basename::fileparse($path, qr/\.([^.]*)$/);
  $extension =~ s/^\.//;
  $extension = lc($extension);

  # SMELL: move mapping somewhere else?
  $extension = 'jpeg' if $extension =~ /^jpe?g$/i;
  $extension = 'html' if $extension =~ /^html?$/i;
  $extension = 'cert' if $extension =~ /^ce?rt?$/i;
  $extension = 'tgz' if $path =~ /^tar\.gz$/i;

  return ($fileName, $dirName, $extension);
}

1;

