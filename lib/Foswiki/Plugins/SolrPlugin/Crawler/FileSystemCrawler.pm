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
package Foswiki::Plugins::SolrPlugin::Crawler::FileSystemCrawler;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::SolrPlugin::Crawler ();
use Foswiki::Contrib::Stringifier ();

use Encode ();
use File::Spec ();
use Error qw(:try);
use User::grent;

our @ISA = qw( Foswiki::Plugins::SolrPlugin::Crawler );

use constant TRACE => 0;

################################################################################
sub init {
  my $this = shift;

  $this->SUPER::init();

  $this->{_currentDepth} = 0;
  $this->{depth} ||= 0;
  $this->{_seen} = {};
}

################################################################################
sub finish {
  my $this = shift;

  $this->SUPER::finish();

  $this->log("... finish ".__PACKAGE__) if TRACE;

  undef $this->{_seen};
  undef $this->{_currentDepth};
}

################################################################################
sub crawl {
  my ($this, $mode) = @_;

  $mode //= 'delta';

  # remove all non-existing files
  my $timestamps = $this->getTimestamps();
  foreach my $id (keys %$timestamps) {
    my $path;
    if ($id =~ /^$this->{source}::(.*)$/) {
      $path = $1;

      next if -e $path 
           && (!$this->{excludePath} || $path !~ /$this->{excludePath}/)
           && (!$this->{includePath} || $path =~ /$this->{includePath}/);

      $this->log("Deleting file $id");
    } else {
      $this->log("WARNING: found invalid id '$id' for source '$this->{source}'");
    }
    $this->deleteById($id);
  }

  $this->crawlPath($mode, $this->{path});
}

################################################################################
sub crawlPath {
  my ($this, $mode, $path) = @_;

  return if $this->{_trappedSignal};

  # protect against infinite recursion 
  return if $this->{_seen}{$path};
  $this->{_seen}{$path} = 1;

  return if $this->{excludePath} && $path =~ /$this->{excludePath}/;
  return if $this->{includePath} && $path !~ /$this->{includePath}/;

  #$this->log("... path=$path") if TRACE;

  if (-d $path) {
    if ($this->{depth} && $this->{_currentDepth} > $this->{depth}) {
      $this->log("... pruning off at depth $this->{_currentDepth}") if TRACE;
      return;
    }

    if (opendir(my $dirh, $path)) {

      $this->{_currentDepth}++;

      foreach my $entry (readdir $dirh) {
	next if $entry eq '.' || $entry =~ /^\.\./;
	$entry = Encode::encode_utf8($entry);
        my $entry = File::Spec->catfile($path, $entry);
        $this->crawlPath($mode, $entry);
	last if $this->{_trappedSignal};
      }

      closedir $dirh;
    }
  } elsif(($this->{followSymLinks} && -l $path) || -f $path) {

    my $mtime = $this->getModificationTime($path);
    my $itime = $this->getIndexTime($path);

    #$this->log("... mtime=$mtime, itime=$itime") if TRACE;

    $this->indexFile($path)
      if -r $path && ($mode eq 'full' || $mtime > $itime);

  } else {
    return; # not a file type we are interested in
  }

  sleep($this->{throttle}) if $this->{throttle};
}

################################################################################
sub getIndexTime {
  my ($this, $path) = @_;

  return $this->SUPER::getIndexTime($this->{source} . '::'. $path);
}

################################################################################
sub getOwnership {
  my ($this, $path) = @_;

  my @stat = stat($path);
  my $user = getpwuid($stat[4]);
  my $group = getgrgid($stat[5]);

  return ($user, $group);
}

################################################################################
sub getFileSize {
  my ($this, $path) = @_;

  my @stat = stat($path);

  return $stat[7] || 0;
}

################################################################################
sub getModificationTime {
  my ($this, $path) = @_;

  my @stat = stat($path);

  return $stat[9] || $stat[10] || 0;
}

################################################################################
sub getGrantedUsers {
  my ($this, $path) = @_;

  my ($user, $group) = $this->getOwnership($path);

  my %members = ();
  my $groupName = $group->name;
  %members = map {$_ => 1} @{$group->members};
  $members{$user} = 1;

  my @wikiNames = ();
  foreach my $id (keys %members) {
    my $wikiName = $this->getWikiName($id);
    push @wikiNames, $wikiName if $wikiName;
  }

  $this->log("... owned by $user/$groupName, members=@wikiNames") if TRACE;

  return \@wikiNames;
}

################################################################################
sub indexFile {
  my ($this, $path) = @_;

  $this->log("Indexing file $path");

  unless (-r $path) {
    $this->log("ERROR: cannot read $path");
    return;
  }

  #$this->log("... reading $path") if TRACE;

  my $doc = $this->newDocument();
  my $text = $this->getStringifiedVersion($path) || '';
  $text = $this->plainify($text);

  my ($fileName, $dirName, $extension) = $this->parsePath($path);
  my $title = $fileName;
  $title =~ s/_+/ /g;
  $fileName .= ".$extension" if defined $extension;

  # get file types
  my @types = ();
  my ($mappedType) = $this->getMappedMimeType($fileName);
  push @types, 'file';
  push @types, $mappedType if $mappedType;

  $this->log("... type=@types") if TRACE;

  # get author
  my ($author) = $this->getWikiName($this->getOwnership($path)) || 'UnknownUser';
  my $epoch = $this->getModificationTime($path);
  my $date = Foswiki::Func::formatTime($epoch, 'iso', 'gmtime');
  my $dateString = Foswiki::Func::formatTime($epoch);

  my @aclFields = $this->getAclFields($path);
  $doc->add_fields(@aclFields) if @aclFields;

  my $fileId = $this->{source} . '::' . $path;

  $doc->add_fields(
    id => $fileId,
    name => $fileName,
    url => $this->getFileUrl($path),
    title => $title,
    text => $text,
    source => $this->{source},
    type => \@types,
    author => $author,
    contributor => $author,
    author_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $author),
    date => $date,
    date_s => $dateString,
    container_id => $dirName,
    container_url => $this->getFileUrl($dirName),
    container_title => $dirName,
    icon => $this->mapToIconFileName($extension),
    size => $this->getFileSize($path),
    version => 1, # is this usefull on some filesystems?
  );

  # add the document to the index
  try {
    $this->add($doc);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };
}

1;
