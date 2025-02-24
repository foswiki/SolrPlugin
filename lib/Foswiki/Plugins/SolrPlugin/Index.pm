# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
package Foswiki::Plugins::SolrPlugin::Index;

use strict;
use warnings;

use Foswiki::Plugins::SolrPlugin::Base ();
our @ISA = qw( Foswiki::Plugins::SolrPlugin::Base );

use Error qw( :try );
use Fcntl qw( :flock );
use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::SolrPlugin ();
use Foswiki::Form ();
use Foswiki::OopsException ();
use Foswiki::Time ();
use Foswiki::Contrib::Stringifier ();
use Encode ();

use constant TRACE => 0;    # toggle me
use constant VERBOSE => 1;  # toggle me
use constant MAX_STRING_LENGTH => 32000;

use constant PROFILE => 0;  # toggle me
#use Time::HiRes (); # enable this too when profiling

##############################################################################
sub new {
  my ($class, $session) = @_;

  my $this = $class->SUPER::new($session);

  $this->{url} = $Foswiki::cfg{SolrPlugin}{UpdateUrl} || $Foswiki::cfg{SolrPlugin}{Url};

  $this->{_groupCache} = {};
  $this->{_webACLCache} = {};

  throw Error::Simple("no solr url defined") unless defined $this->{url};

  # Compared to the Search constructor there's no autostarting here
  # to prevent any indexer to accidentally create a solrindex lock and further
  # java inheriting it. So we simply test for connectivity and barf if that fails.
  $this->connect();

  unless ($this->{solr}) {
    $this->log("ERROR: can't connect solr daemon");
  }

  # trap SIGINT
  $SIG{INT} = sub {
    $this->log("got interrupted ... finishing work");
    $this->{_trappedSignal} = 1; # will be detected by loops further down
  };

  # TODO: trap SIGALARM
  # let the indexer run for a maximum timespan, then flag a signal for it
  # to bail out from work done so far

  return $this;
}

################################################################################
sub finish {
  my $this = shift;

  undef $this->{_knownUsers};
  undef $this->{_groupCache};
  undef $this->{_webACLCache};
  undef $SIG{INT};
}

################################################################################
# entry point to either update one topic or a complete web
sub index {
  my $this = shift;

  # exclusively lock the indexer to prevent a delta and a full index
  # mode to run in parallel

  try {

    my $request = Foswiki::Func::getRequestObject();
    my $web = $request->param('web') || 'all';
    my $topic = $request->param('topic');
    my $mode = $request->param('mode') || 'delta';
    my $optimize = Foswiki::Func::isTrue($request->param('optimize'));

    # SMELL: why do we have to decode this here?
    $web = Encode::decode_utf8($web);
    $topic = Encode::decode_utf8($topic);

    if ($topic) {
      $web = $this->{session}->{webName} if !$web || $web eq 'all';

      $this->log("doing a topic index $web.$topic") if TRACE;
      $this->updateTopic($web, $topic);
    } else {

      $this->log("doing a web index in $mode mode") if TRACE;
      $this->{_count} = 0;
      $this->update($web, $mode);
    }

    $this->optimize() if $optimize;
  }

  catch Error::Simple with {
    my $error = shift;
    print STDERR "ERROR: " . $error->{-text} . "\n";
  };

}

################################################################################
sub afterSaveHandler {
  my $this = shift;

  return unless $this->{solr};

  $this->updateTopic(@_);
}

################################################################################
sub afterRenameHandler {
  my ($this, $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  return unless $this->{solr};

  $this->updateTopic($oldWeb, $oldTopic);
  $this->updateTopic($newWeb, $newTopic);
}

################################################################################
sub afterUploadHandler {
  my ($this, $attachment, $meta) = @_;

  return unless $this->{solr};

  my $web = $meta->web;
  my $topic = $meta->topic;

  # SMELL: make sure meta is loaded
  $meta = $meta->load() unless $meta->latestIsLoaded();

  my @aclFields = $this->getAclFields($web, $topic, $meta);

  $this->indexAttachment($web, $topic, $attachment, \@aclFields);
}

################################################################################
# update documents of a web - either in fully or incremental
# on a full update, the complete web is removed from the index prior to updating it;
# this calls updateTopic for each topic to be updated
sub update {
  my ($this, $web, $mode) = @_;

  $mode ||= 'full';

  my $searcher = Foswiki::Plugins::SolrPlugin::getSearcher();

  my @webs = $searcher->getListOfWebs();
  foreach my $thisWeb (@webs) {
    # remove non-existing webs
    if (!Foswiki::Func::webExists($thisWeb)) {
      $this->log("$thisWeb doesn't exist anymore ... deleting");
      $this->deleteWeb($thisWeb);
      next;
    }

    # remove skipped webs
    if ($this->isSkippedWeb($web)) {
      $this->deleteWeb($web);
      next;
    }
  }

  if (!defined($web) || $web eq 'all') {
    @webs = Foswiki::Func::getListOfWebs("user");
  } else {
    @webs = ();
    foreach my $item (split(/\s*,\s*/, $web)) {
      push @webs, $item;
      push @webs, Foswiki::Func::getListOfWebs("user", $item);
    }
  }

  foreach my $web (@webs) {
    $web = Encode::encode_utf8($web);

    my $origWeb = $web;
    $origWeb =~ s/\./\//g;
    $web =~ s/\//./g;

    next if $this->isSkippedWeb($web);

    my %timeStamps = ();

    # get all timestamps for this web 
    # SMELL: this could run for a long time ... :(
    $searcher->iterate({
       q => "web:$web type:topic", 
       fl => "topic,timestamp", 
      },
      sub {
        my $doc = shift;
        my $topic = $doc->value_for("topic");
        $timeStamps{$topic} = $doc->value_for("timestamp");
      }
    );

    # remove all non-existing topics
    foreach my $topic (keys %timeStamps) {
      next if Foswiki::Func::topicExists($web, $topic);
      $this->deleteTopic($web, $topic);
    }

    my $found = 0;
    if ($mode eq 'full') {
      # SMELL: do we need to delete all of the web? can't we do more precise updates
      $this->deleteWeb($web); 

      foreach my $topic (Foswiki::Func::getTopicList($web)) {
        next if $this->isSkippedTopic($web, $topic);
        try {
          $this->indexTopic($web, $topic);
        } catch Error with {
          my $e = shift;
          print STDERR "ERROR: $e\n";
        };
        $found = 1;
        last if $this->{_trappedSignal};
      }
    } else {

      # delta
      my @topics = Foswiki::Func::getTopicList($web);
      foreach my $topic (@topics) {
        my $topicTime = $timeStamps{$topic} || 0;

        if ($this->isSkippedTopic($web, $topic)) {
          $this->deleteTopic($web, $topic) if $topicTime;
          next;
        }

        my $changed;
        if ($Foswiki::Plugins::SESSION->can('getApproxRevTime')) {
          $changed = $this->{session}->getApproxRevTime($origWeb, $topic);
        } else {

          # This is here for old engines
          $changed = $this->{session}->{store}->getTopicLatestRevTime($origWeb, $topic);
        }

        next if $topicTime > $changed;

        try {
          $this->indexTopic($web, $topic);
        } catch Error with {
          my $e = shift;
          print STDERR "ERROR: $e\n";
        };

        $found = 1;
        last if $this->{_trappedSignal};
      }
    }

    # unload DBCache to lower the memory footprint
    if (Foswiki::Func::getContext()->{DBCachePluginEnabled}) {
      require Foswiki::Plugins::DBCachePlugin;
      Foswiki::Plugins::DBCachePlugin::unloadDB($web);
    }

    last if $this->{_trappedSignal};
  }
}

################################################################################
# update one specific topic; deletes the topic from the index before updating it again
sub updateTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  return if $this->isSkippedWeb($web);
  return if $this->isSkippedTopic($web, $topic);

  $this->deleteTopic($web, $topic);

  if (Foswiki::Func::topicExists($web, $topic)) {
    try {
      $this->indexTopic($web, $topic, $meta, $text);
    } catch Error with {
      my $e = shift;
      print STDERR "ERROR: $e\n";
    };
  }
}

################################################################################
# work horse: index one topic and all attachments
sub indexTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  $this->{_count}++;

  Foswiki::Func::pushTopicContext($web, $topic);

  my %outgoingLinks = ();
  my %macros = ();

  my $t0;
  $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  # normalize web name
  $web =~ s/\//\./g;

  if (VERBOSE) {
    $this->log("Indexing topic $web.$topic");
  } else {

    #$this->log(".", 1);
  }

  # new solr document for the current topic
  my $doc = $this->newDocument();

  unless (defined $meta && defined $text) {
    ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  }

  $text = $this->entityDecode($text);

  # Eliminate Topic Makup Language elements and newlines.
  my $origText = $text;

  # get all outgoing links from topic text
  $this->extractOutgoingLinks($web, $topic, $origText, \%outgoingLinks);

  # get macro occurence
  $text = $this->extractMacros($text, \%macros);
  $text = $this->plainify($text, $web, $topic);

  # parent data
  my $parent = $meta->getParent();
  my $parentWeb;
  my $parentTopic;
  if ($parent) {
    ($parentWeb, $parentTopic) = $this->normalizeWebTopicName($web, $parent);
    $this->_addLink(\%outgoingLinks, $web, $topic, $parentWeb, $parentTopic);
  }

  # all webs

  # get date
  my ($epoch, undef, $rev) = $this->getRevisionInfo($web, $topic);
  $epoch ||= 0;    # prevent formatTime to crap out
  my $date = Foswiki::Func::formatTime($epoch, 'iso', 'gmtime');
  my $dateString = Foswiki::Func::formatTime($epoch);

  unless ($rev && $rev =~ /^\d+$/) {
    $rev //= 'undef';
    $this->log("WARNING: invalid version '$rev' of $web.$topic");
    $rev = 1;
  }

  # get create date
  ($epoch) = $this->getRevisionInfo($web, $topic, 1);
  $epoch ||= 0;    # prevent formatTime to crap out
  my $createDate = Foswiki::Func::formatTime($epoch, 'iso', 'gmtime');
  my $createString = Foswiki::Func::formatTime($epoch);

  #print STDERR "createDate=$createDate\n";

  # get the web change date
  # SMELL: as per solr-5 we only record this to WebHome, later on we will update 
  # the webchange_date on any topic change in a web, not only WebHome
  # if ($topic eq $Foswiki::cfg{HomeTopicName}) {
  #   my $webChangeDate = $this->getWebChangeDate($web);
  #   $doc->add_fields(field_WebChangeDate_dt => $webChangeDate);
  # }

  # get contributor and most recent author
  my @contributors = $this->getContributors($web, $topic);
  my %contributors = map {$_ => 1} @contributors;
  $doc->add_fields(contributor => [keys %contributors]);

  my $author = $contributors[0] || 'UnknownUser';
  my $createAuthor = $contributors[ scalar(@contributors) - 1 ] || $author;

  # gather all webs and parent webs
  my @webCats = ();
  my @prefix = ();
  foreach my $component (split(/\./, $web)) {
    push @prefix, $component;
    push @webCats, join(".", @prefix);
  }

  $doc->add_fields(

    # common fields
    id => "$web.$topic",
    url => $this->getScriptUrlPath($web, $topic, "view"),
    topic => $topic,
    web => $web,
    webcat => [@webCats],
    webtopic => "$web.$topic",
    title => $this->plainify(Foswiki::Func::getTopicTitle($web, $topic, undef, $meta)),
    text => $text,
    summary => $this->getTopicSummary($web, $topic, $meta, $origText),
    author => $author,
    author_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $author),
    date => $date,
    date_s => $dateString,
    version => $rev,
    createauthor => $createAuthor,
    createauthor_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $createAuthor),
    createdate => $createDate,
    createdate_s => $createString,
    source => 'wiki', # name of crawler
    type => 'topic',
    container_id => $web . '.'. $Foswiki::cfg{HomeTopicName},
    container_web => $web,
    container_topic => $Foswiki::cfg{HomeTopicName},
    container_url => $this->getScriptUrlPath($web, $Foswiki::cfg{HomeTopicName}, "view"),
    container_title => $this->plainify(Foswiki::Func::getTopicTitle($web, $Foswiki::cfg{HomeTopicName})),
    icon => $this->mapToIconFileName('topic'),

    # topic specific
  );

  $doc->add_fields(parent => "$parentWeb.$parentTopic") if $parent;

  # tag and analyze language
  my $contentLanguage = $this->getContentLanguage($web, $topic);
  if (defined $contentLanguage && $contentLanguage ne 'detect') {
    $doc->add_fields(
      language => $contentLanguage,
      'text_' . $contentLanguage => $text,
    );
  }

  # process form
  my $formName = $meta->getFormName();
  if ($formName) {

    # read form definition to add field type hints
    my $formDef;
    try {
      $formDef = new Foswiki::Form($this->{session}, $web, $formName);
    }
    catch Foswiki::OopsException with {

      # Form definition not found, ignore
      my $e = shift;
      $this->log("ERROR: can't read form definition for $formName");
    };

    if ($formDef) {    # form definition found, if not the formfields aren't indexed

      $formName =~ s/\//\./g;
      $doc->add_fields(form => $formName);

      $this->indexFormFields($web, $topic, $meta, $formDef, $doc, \%outgoingLinks, \%macros);
    }
  }

  # store all outgoing links collected so far
  foreach my $link (keys %outgoingLinks) {
    next if $link eq "$web.$topic";    # self link is not an outgoing link
    $doc->add_fields(outgoing => $link);
  }

  # store all macros
  $doc->add_fields(macro => [keys %macros]);
  #$this->log("... found macros ".join(", ", sort keys %macros)) if TRACE;

  # all prefs are of type _t
  # TODO it may pay off to detect floats and ints
  my @prefs = $meta->find('PREFERENCE');
  if (@prefs) {
    foreach my $pref (@prefs) {
      my $name = $pref->{name};
      my $value = $pref->{value};
      $doc->add_fields(
        'preference_' . $name . '_s' => $value,
        'preference' => $name,
      );
    }
  }

  # call index topic handlers
  my %seen;
  foreach my $sub (@Foswiki::Plugins::SolrPlugin::knownIndexTopicHandler) {
    next if $seen{$sub};
    try {
      &$sub($this, $doc, $web, $topic, $meta, $text);
      $seen{$sub} = 1;
    }
    catch Foswiki::OopsException with {
      my $e = shift;
      $this->log("ERROR: while calling indexTopicHandler: " . $e->stringify());
    };
  }

  # get extra fields like acls and other properties

  my $t1;
  $t1 = [Time::HiRes::gettimeofday] if PROFILE;

  my @aclFields = $this->getAclFields($web, $topic, $meta);
  $doc->add_fields(@aclFields) if @aclFields;

  #if (PROFILE) {
  #  my $elapsed = int(Time::HiRes::tv_interval($t1) * 1000);
  #  $this->log("took $elapsed ms to get the extra fields from $web.$topic");
  #  $t1 = [Time::HiRes::gettimeofday];
  #}

  # attachments
  my @attachments = $meta->find('FILEATTACHMENT');
  if (@attachments) {
    my $thumbnail;
    my $firstImage;
    my %sorting = map { $_ => lc($_->{comment} || $_->{name}) } @attachments;
    foreach my $attachment (sort { $sorting{$a} cmp $sorting{$b} } @attachments) {

      my $name = $attachment->{'name'} || '';

      # test for existence
      unless (Foswiki::Func::attachmentExists($web, $topic, $name)) {
        $this->log("WARNING: can't find attachment '$name' at $web.$topic ... invalid meta data");
        next;
      }

      # is the attachment is the skip list?
      if ($this->isSkippedAttachment($web, $topic, $name)) {
        $this->log("Skipping attachment $web.$topic.$name");
        next;
      }

      # add attachment names to the topic doc
      $doc->add_fields('attachment' => $name);

      # decide on thumbnail
      if (!defined $thumbnail && $attachment->{attr} && $attachment->{attr} =~ /t/) {
        $thumbnail = $name;
      }
      if ($this->isImage($name)) {
        $firstImage = $name unless defined $firstImage;
      }

      # then index each of them
      $this->indexAttachment($web, $topic, $attachment, \@aclFields);
      last if $this->{_trappedSignal};
    }

    # take the first image attachment when no thumbnail was specified explicitly
    unless ($this->getField($doc, "thumbnail")) {
      $thumbnail = $firstImage if !defined($thumbnail) && defined($firstImage);
      $doc->add_fields('thumbnail' => $thumbnail) if defined $thumbnail;
    }

    #if (PROFILE) {
    #  my $elapsed = int(Time::HiRes::tv_interval($t1) * 1000);
    #  $this->log("took $elapsed ms to index all attachments at $web.$topic");
    #}
  }

  # add the document to the index
  try {
    $this->add($doc);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

  if (PROFILE) {
    my $elapsed = int(Time::HiRes::tv_interval($t0) * 1000);
    $this->log("took $elapsed ms to index topic $web.$topic");
    #$this->log("$topic;$this->{_count};$elapsed");
  }

  Foswiki::Func::popTopicContext();
}

################################################################################
# index all formfields of a topic
sub indexFormFields {
  my ($this, $web, $topic, $meta, $formDef, $doc, $outgoingLinks, $macros) = @_;

  # check whether we are indexing a user profile
  my $personDataFormPattern = $Foswiki::cfg{SolrPlugin}{PersonDataForm} || '*UserForm';
  $personDataFormPattern =~ s/\*/.*/g;
  $personDataFormPattern =~ s/OR/|/g;

  my $formName = $meta->getFormName();
  my ($formWeb, $formTopic) = Foswiki::Func::normalizeWebTopicName(undef, $formName);
  my $isUserProfile = ($formName =~ /$personDataFormPattern/x) ? 1 : 0;
  my %seenFields = ();
  my $formFields = $formDef->getFields();
  my $state;

  if ($formFields) {
    my $topicType;
    foreach my $fieldDef (@{$formFields}) {
      my $name = $fieldDef->{name};
      next unless $name; # dummy fields

      my $field = $meta->get('FIELD', $name);

      my $val = defined $field ? $field->{value} : undef;
      $val = $fieldDef->getDefaultValue($web, $topic) unless defined($val) && $val ne "";

      $topicType = $val if $name eq 'TopicType';

      # prevent from mall-formed formDefinitions
      if ($seenFields{$name}) {
        $this->log("WARNING: malformed form definition for $formWeb.$formTopic - field '$name' appear twice must be unique");
        next;
      }
      $seenFields{$name} = 1;

      # special handling for user profile's email: get it from the user mapper in case there is none in the form
      if ($isUserProfile) {
        if ($name eq 'Email' && !$val) {
          my @emails = Foswiki::Func::wikinameToEmails($topic);
          $val = $emails[0] if @emails;
        }

        # special handling of state formfield
        if ($name eq 'Status') {
          $state = Foswiki::Func::isTrue($val, 1);
        }

        # special handling of LastName
        if ($name eq 'LastName' && $val ne "") {
          $doc->add_fields('LastName_first_letter' => $val);
        }
      }

      $this->indexFormField($web, $topic, $fieldDef, $val, $doc, $outgoingLinks, $macros);
    }

    # map form name to TopicType if not found otherwise
    unless ($topicType) {
      $doc->add_fields('field_TopicType_lst' => $formTopic);
      $topicType = $formTopic;
    }

    # add most significant topicType
    if ($topicType && $topicType ne "") {

      $topicType =~ s/^\s+//;
      $topicType =~ s/\s+$//;

      my @topicTypes = split(/\s*,\s*/, $topicType);
      $topicType = shift @topicTypes;

      $doc->add_fields('field_TopicType_first_s' => $topicType);
    }
  }

  if ($isUserProfile) {
    unless (defined $state) {
      my $loginName = Foswiki::Func::wikiToUserName($topic);
      $state = $loginName ? 1: 0;
    }

    $this->log("... user $topic is disabled") unless $state;
    $doc->add_fields('state' => $state ? 'enabled' : 'disabled');
  }
}

################################################################################
# normalize to _s
sub _stringFieldName {
  my $fieldName = shift;
  
  $fieldName =~ s/^field_//;
  $fieldName = 'field_'.$fieldName;
  $fieldName =~ s/_(?:[a-z]+)$//;
  $fieldName .= '_s';

  return $fieldName;
}

################################################################################
# index a single formfield of a topic
sub indexFormField {
  my ($this, $web, $topic, $fieldDef, $value, $doc, $outgoingLinks, $macros) = @_;

  my $name = $fieldDef->{name};
  my $type = $fieldDef->{type};

  return if $type && $type eq "qmworkflow"; # will be indexed in QMPlugin

  unless ($type) {
    $this->log("WARNING: unknown type for formfield '$name' at $web.$topic");
    return;
  }

  if ($type eq "autofill") {
    my $casted = $fieldDef->param("type");
    if ($casted) {
      $type = $casted;
      $fieldDef = $fieldDef->createField($type);
    }
  }

  my $isValueMapped = $fieldDef->can("isValueMapped") ? $fieldDef->isValueMapped(): $type =~ /\+values/;
  $isValueMapped = 0 if $type eq 'cat'; # SMELL

  if ($isValueMapped) {

    # get mapped value
    if ($fieldDef->can('getDisplayValue')) {
      $value = $fieldDef->getDisplayValue($value, $web, $topic);
    } else {

      # backwards compatibility
      $fieldDef->getOptions($web, $topic);    # load value map
      if (defined $fieldDef->{valueMap}) {
        my @values = ();
        foreach my $v (split(/\s*,\s*/, $value)) {
          if (defined $fieldDef->{valueMap}{$v}) {
            push @values, $fieldDef->{valueMap}{$v};
          } else {
            push @values, $v;
          }
        }
        $value = join(", ", @values);
      }
    }
  }

  # extract outgoing links for formfield values
  $this->extractOutgoingLinks($web, $topic, $value, $outgoingLinks)
    if defined $outgoingLinks;

  # get macro occurence
  $value = $this->extractMacros($value, $macros);

  # bit of cleanup
  $value =~ s/<!--.*?-->//gs;

  # normalize user and group fields stripping off any leading web part
  my $origValue = $value;
  if ($type =~ /^(user|group)/) {
    my @nvals = ();
    foreach my $item (split(/\s*,\s*/, $value)) {
      $item =~ s/^$Foswiki::cfg{UsersWebName}\.//;
      push @nvals, $item;
    }
    $value = join(", ", @nvals);
  }

  # create a dynamic field indicating the field type to solr
  my $fieldName = $this->getSolrFieldNameOfFormfield($fieldDef);

  # multi-valued types
  if ($fieldDef->isMultiValued || $name =~ /TopicType/) {    # TODO: make this configurable
    $doc->add_fields($fieldName => [split(/\s*,\s*/, $value)]);

    $fieldName = _stringFieldName($fieldName);
  }

  # date
  if ($type =~ /^date/) {
    try {
      my $epoch = $value;
      $epoch = Foswiki::Time::parseTime($value) unless $epoch =~ /^\-?\d+$/;

      # only index dates that properly parse into epoch
      if ($epoch) { 

        my $isoDate = Foswiki::Time::formatTime($epoch, 'iso', 'gmtime');
        #print STDERR "... adding $fieldName=$isoDate\n";

        my $epochFieldName = $fieldName;
        $epochFieldName =~ s/_dt$/_l/;

        $doc->add_fields(
          $fieldName => $isoDate,
          $epochFieldName => $epoch
        );

        # reformat in human readable way
        $value = Foswiki::Time::formatTime($epoch);
      }
    }
    catch Error::Simple with {
      $this->log("WARNING: malformed date value '$value'");
    };

    $fieldName = _stringFieldName($fieldName);
  }

  # floating numbers
  elsif ($type =~ /^(number|percent|currency|rating)/) {
    if ($value =~ /^\s*[+-]?(\d*\.)?\d+\s*$/) {
      #print STDERR "... adding $fieldName=$value\n";
      $doc->add_fields($fieldName => $value,);
    } else {
      #print STDERR "... NOT adding $fieldName=$value\n";
    }

    $fieldName = _stringFieldName($fieldName);
  }

  # integers 
  elsif ($type =~ /^bytes/) {
    #print STDERR "... adding $fieldName=$value\n";
    $doc->add_fields($fieldName => $value) if $value ne '';

    $fieldName = _stringFieldName($fieldName);
  }

  # topic links
  elsif ($type =~ /^(topic|user|group)/ && $value ne "") {
    my $titleFieldName = $fieldName;
    if ($fieldDef->isMultiValued) {
      my @topicTitles = ();
      my $web = $fieldDef->getWeb();
      foreach (split(/\s*,\s*/, $origValue)) {
        push @topicTitles, Foswiki::Func::getTopicTitle($web, $_);
      }
      my $topicTitle = join(", ", @topicTitles);

      
      #print STDERR "... adding $titleFieldName=$topicTitle\n";
      $titleFieldName =~ s/_s$/_title_s/;
      $doc->add_fields($titleFieldName => $topicTitle);

      #print STDERR "... adding $titleFieldName=@topicTitles\n";
      $titleFieldName =~ s/_title_s$/_title_lst/;
      $doc->add_fields($titleFieldName => \@topicTitles);

    } else {
      my $topicTitle = Foswiki::Func::getTopicTitle($web, $origValue);
      $titleFieldName =~ s/_s/_title_s/;

      #print STDERR "... adding $titleFieldName=$topicTitle\n";
      $doc->add_fields($titleFieldName => $topicTitle);
    }


    $fieldName = _stringFieldName($fieldName);
  }

  # finally make it a non-list field as well

  # add an extra check for floats
  if ($fieldName =~ /_(f|d)$/) {
    if ($value =~ /^\s*([\-\+]?\d+(\.\d+)?)?\s*$/) {
      $value = $1 || 0;
    } else {
      $this->log("WARNING: malformed float value '$value' in field $fieldName");
      return;
    }
  }

  # add an extra check for integers
  elsif ($fieldName =~ /_(l|i)$/) {
    if ($value =~ /^\s*([\-\+]?\d+)?\s*$/) {
      $value = $1 || 0;
    } else {
      $this->log("WARNING: malformed integer value '$value' in field $fieldName");
      return;
    }
  }

  # add an extra treatment for booleans
  elsif ($fieldName =~ /_b$/) {
    $value = Foswiki::Func::isTrue($value, 0);
  }

  # for explicit _s fields apply a full plainify
  elsif ($fieldName =~ /_s$/) {

    # note this might alter the content too much in some cases.
    # so we try to remove only those characters that break the json parser
    #$value = $this->plainify($value, $web, $topic);
    $value =~ s/<!--.*?-->//gs;    # remove all HTML comments
    $value =~ s/<[^>]*>/ /g;       # remove all HTML tags
    $value = $this->discardIllegalChars($value);    # remove illegal characters

    # truncate field value to MAX_STRING_LENGTH
    if (length($value) > MAX_STRING_LENGTH) {
      $this->log("WARNING: value of field '$name' exceeds maximum string length ... shortening");
      $value = substr($value, 0, MAX_STRING_LENGTH);
    }
  }

  if (defined $value && $value ne '') {
    #print STDERR "... adding $fieldName=$value\n";
    $doc->add_fields($fieldName => $value);
  } else {
    #print STDERR "... NOT adding $fieldName=$value\n";
  }
}

################################################################################
# returns one of the SupportedLanguages or undef if not found
sub getContentLanguage {
  my ($this, $web, $topic) = @_;

  unless (defined $Foswiki::cfg{SolrPlugin}{SupportedLanguages}) {
    Foswiki::Func::writeWarning("{SolrPlugin}{SupportedLanguages} not defined. Please run configure.");
    return;
  }

  my $donePush = 0;
  if ($web ne $this->{session}{webName} || $topic ne $this->{session}{topicName}) {
    Foswiki::Func::pushTopicContext($web, $topic);
    $donePush = 1;
  }

  my $prefsLanguage = Foswiki::Func::getPreferencesValue('CONTENT_LANGUAGE') || '';
  my $contentLanguage = $Foswiki::cfg{SolrPlugin}{SupportedLanguages}{$prefsLanguage};

  #$this->log("contentLanguage=$contentLanguage") if TRACE;

  Foswiki::Func::popTopicContext() if $donePush;

  return $contentLanguage;
}

################################################################################
# rough macro extraction; it does not find every macro as the foswiki parser does
sub extractMacros {
  our ($this, $text, $macros) = @_;

  return "" unless $text;

  while ($text =~ s/(%|\$perce?nt)($Foswiki::regex{tagNameRegex})(?:\{(.*?)\})?\1/$this->_processMacro($2, $macros, $3)/ges) {
    # nop
  };


  return $text;
}

sub _processMacro {
  my ($this, $macro, $macros, $params) = @_;

  $this->log("... found macro $macro") if TRACE;

  $macros->{$macro} = 1 if defined $macro;

  # some macros don't need to be depuzzled
  return "" if $macro =~ /^(STARTSECTION|ENDSECTION)$/;

  my $remain = "";
  my %attrs = Foswiki::Func::extractParameters($params);
  foreach my $val (values %attrs) {
    $val = Foswiki::Func::decodeFormatTokens($val);
    $remain .= " " . $this->extractMacros($val, $macros);
  }

  #$remain = $attrs{_DEFAULT} || ''; # only keep the default param

  return $remain;
}


################################################################################
sub extractOutgoingLinks {
  my ($this, $web, $topic, $text, $outgoingLinks) = @_;

  return unless $text;
  my $removed = {};

  # normal wikiwords
  $text = $this->takeOutBlocks($text, 'noautolink', $removed);
  $text =~ s#(?:($Foswiki::regex{webNameRegex})\.)?($Foswiki::regex{wikiWordRegex}|$Foswiki::regex{abbrevRegex})#$this->_addLink($outgoingLinks, $web, $topic, $1, $2)#gexm;
  $this->putBackBlocks(\$text, $removed, 'noautolink');

  # square brackets
  $text =~ s#\[\[([^\]\[\n]+)\]\]#$this->_addLink($outgoingLinks, $web, $topic, undef, $1)#ge;
  $text =~ s#\[\[([^\]\[\n]+)\]\[([^\]\n]+)\]\]#$this->_addLink($outgoingLinks, $web, $topic, undef, $1)#ge;

}

sub _addLink {
  my ($this, $links, $baseWeb, $baseTopic, $web, $topic) = @_;

  $web ||= $baseWeb;
  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  my $link = $web . "." . $topic;
  return '' if $link =~ /^http|ftp/;    # don't index external links
  return '' unless Foswiki::Func::topicExists($web, $topic);

  $link =~ s/\%SCRIPTURL(?:PATH)?(?:\{.*?\})?\%\///g;
  $link =~ s/%(?:BASE)?WEB%/$baseWeb/g;
  $link =~ s/%(?:BASE)?TOPIC%/$baseTopic/g;

  #print STDERR "link=$link\n" unless defined $links->{$link};

  $links->{$link} = 1;

  return $link;
}

################################################################################
# add the given attachment to the index.
sub indexAttachment {
  my ($this, $web, $topic, $attachment, $commonFields) = @_;

  #my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  my $name = $attachment->{'name'} || '';

  $this->log("Indexing attachment $web.$topic.$name") if VERBOSE;

  # the attachment extension has to be checked
  my $extension = '';
  my $title = $name;
  if ($name =~ /^(.+?)\.([^\.]+?)(?:\.\d+)?$/) {
    $title = $1;
    $extension = lc($2);
  }
  $title =~ s/_+/ /g;

  # fix some extension naming
  $extension = 'jpeg' if $extension =~ /jpe?g/i;
  $extension = 'html' if $extension =~ /html?/i;
  $extension = 'tgz' if $name =~ /\.tar\.gz$/i;

  # get file types
  my @types = ();
  my ($mappedType) = $this->getMappedMimeType($name);
  push @types, 'attachment';
  push @types, $mappedType if $mappedType;

  my $attText = $this->getStringifiedVersion($web, $topic, $name) || '';
  $attText = $this->plainify($attText, $web, $topic);

  my $doc = $this->newDocument();

  my $comment = $attachment->{'comment'} || '';
  my $size = $attachment->{'size'} || 0;
  my $rev = $attachment->{'version'} || 1;
  my $author = getWikiName($attachment->{user});

  my $epoch = $attachment->{'date'} || 0;
  my $date = Foswiki::Func::formatTime($epoch, 'iso', 'gmtime');
  my $dateString = Foswiki::Func::formatTime($epoch);

  unless ($rev =~ /^\d+$/) {
    $this->log("WARNING: invalid version '$rev' of attachment $name in $web.$topic");
    $rev = 1;
  }

  # get image info
  if ($name !~ /\.svgz?$/ && $this->isImage($name)) {
    my ($width, $height) = $this->pingImage(_getPathOfAttachment($web, $topic, $name));
    if (defined $width && defined $height) {
      $doc->add_fields('width' => $width, 'height' => $height);
    }
  }

  # get contributor and most recent author
  my @contributors = $this->getContributors($web, $topic, $attachment);
  my %contributors = map {$_ => 1} @contributors;
  $doc->add_fields(contributor => [keys %contributors]);

  my $createAuthor = $contributors[ scalar(@contributors) - 1 ] || $author;
  my ($createEpoch) = $this->getRevisionInfo($web, $topic, 1, $attachment);
  $createEpoch ||= 0;    # prevent formatTime to crap out
  my $createDate = Foswiki::Func::formatTime($createEpoch, 'iso', 'gmtime');
  my $createString = Foswiki::Func::formatTime($createEpoch);

  # normalize web name
  $web =~ s/\//\./g;
  my $id = "$web.$topic.$name";

  # view url
  #my $url = $this->getScriptUrlPath($web, $topic, 'viewfile', filename => $name);
  my $webDir = $web;
  $webDir =~ s/\./\//g;

  # gather all webs and parent webs
  my @webCats = ();
  my @prefix = ();
  foreach my $component (split(/\./, $web)) {
    push @prefix, $component;
    push @webCats, join(".", @prefix);
  }

  my $containerTitle = Foswiki::Func::getTopicTitle($web, $topic);
  $containerTitle = $this->plainify($containerTitle);

  $doc->add_fields(
    # common fields
    id => $id,
    url => $Foswiki::cfg{PubUrlPath}.'/'.$webDir.'/'.$topic.'/'.$name,
    web => $web,
    webcat => [@webCats],
    topic => $topic,
    webtopic => "$web.$topic",
    title => $title,
    source => 'wiki', # name of crawler
    type => \@types,
    text => $attText,
    author => $author,
    author_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $author),
    date => $date,
    date_s => $dateString,
    version => $rev,
    createauthor => $createAuthor,
    createauthor_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $createAuthor),
    createdate => $createDate,
    createdate_s => $createString,

    # attachment fields
    name => $name,
    comment => $comment,
    hidden => $attachment->{attr} =~ /h/ ? 1:0,
    size => $size,
    icon => $this->mapToIconFileName($extension),
    container_id => $web . '.' . $topic,
    container_web => $web,
    container_topic => $topic,
    container_url => $this->getScriptUrlPath($web, $topic, "view"),
    container_title => $containerTitle,

    'field_TopicType_lst' => 'Attachment',
  );

  $doc->add_fields(thumbnail => $name) if $this->isImage($name);

  # tag and analyze language
  # SMELL: silently assumes all attachments to a topic are the same langauge
  my $contentLanguage = $this->getContentLanguage($web, $topic);
  if (defined $contentLanguage && $contentLanguage ne 'detect') {
    $doc->add_fields(
      language => $contentLanguage,
      'text_' . $contentLanguage => $attText,
    );
  }

  # add extra fields, i.e. ACLs
  $doc->add_fields(@$commonFields) if $commonFields;

  # call index attachment handlers
  my %seen;
  foreach my $sub (@Foswiki::Plugins::SolrPlugin::knownIndexAttachmentHandler) {
    next if $seen{$sub};
    &$sub($this, $doc, $web, $topic, $attachment);
    $seen{$sub} = 1;
  }

  # add the document to the index
  try {
    $this->add($doc);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

  #if (PROFILE) {
  #  my $elapsed = int(Time::HiRes::tv_interval($t0) * 1000);
  #  $this->log("took $elapsed ms to index attachment $web.$topic.$name");
  #}

}

################################################################################
# optimize index
sub optimize {
  my $this = shift;

  return unless $this->{solr};
  return if $this->{_trappedSignal};

  # temporarily set a different timeout for this operation
  my $agent = $this->{solr}->agent();
  my $oldTimeout = $agent->timeout();

  $agent->timeout($this->{optimizeTimeout});  

  $this->log("Optimizing index");
  $this->{solr}->optimize({
    waitSearcher => "true",
    softCommit => "true",
  });

  $agent->timeout($oldTimeout);
}

################################################################################
sub commit {
  my ($this, $force) = @_;

  return unless $this->{solr};

  $this->log("Committing index") if VERBOSE;
  $this->{solr}->commit({
      waitSearcher => "true",
      softCommit => "true",
  });

  # invalidate page cache for all search interfaces
  if ($Foswiki::cfg{Cache}{Enabled} && $this->{session}{cache}) {
    my @webs = Foswiki::Func::getListOfWebs("user, public");
    foreach my $web (@webs) {
      next if $web eq $Foswiki::cfg{TrashWebName};

      #$this->log("firing dependencies in $web");
      $this->{session}->{cache}->fireDependency($web, "WebSearch");

      # SMELL: should record all topics a SOLRSEARCH is on, outside of a dirtyarea
    }
  }
}

################################################################################
sub deleteTopic {
  my ($this, $web, $topic) = @_;

  $this->log("Deleting topic $web.$topic");
  $this->deleteByQuery("web:\"$web\" AND topic:\"$topic\"");
}

################################################################################
sub deleteWeb {
  my ($this, $web) = @_;

  $web =~ s/\//./g;
  $this->log("Deleting web $web");
  $this->deleteByQuery("web:\"$web\"");
}

################################################################################
sub deleteDocument {
  my ($this, $web, $topic, $attachment) = @_;

  $web =~ s/\//\./g;
  my $id = "$web.$topic";
  $id .= ".$attachment" if $attachment;

  #$this->log("Deleting document $id");

  $this->deleteById($id);
}

################################################################################
sub getStringifiedVersion {
  my ($this, $web, $topic, $attachment) = @_;

  my $filename = _getPathOfAttachment($web, $topic, $attachment);
  return $this->SUPER::getStringifiedVersion($filename);
}

################################################################################
sub nrKnownUsers {
  my ($this, $id) = @_;

  $this->getListOfUsers();
  return $this->{_nrKnownUsers};
}

################################################################################
sub isKnownUser {
  my ($this, $id) = @_;

  $this->getListOfUsers();
  return (exists $this->{_knownUsers}{$id}?1:0);
}

################################################################################
# Get a list of all registered users
sub getListOfUsers {
  my $this = shift;

  unless (defined $this->{_knownUsers}) {

    my $it = Foswiki::Func::eachUser();
    while ($it->hasNext()) {
      my $user = $it->next();
      next if $user eq 'UnknownUser';
      $this->{_knownUsers}{$user} = 1;# if Foswiki::Func::topicExists($Foswiki::cfg{UsersWebName}, $user);
    }

    #$this->log("known users=".join(", ", sort keys %{$this->{_knownUsers}})) if TRACE;
    $this->{_nrKnownUsers} = scalar(keys %{ $this->{_knownUsers} });

    #$this->log("found ".$this->{_nrKnownUsers}." users");
  }

  return $this->{_knownUsers};
}

################################################################################
sub getContributors {
  my ($this, $web, $topic, $attachment) = @_;

  #my $t0 = [Time::HiRes::gettimeofday] if PROFILE;
  my $maxRev;
  try {
    (undef, undef, $maxRev) = $this->getRevisionInfo($web, $topic, undef, $attachment);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };
  return () unless defined $maxRev;

  $maxRev =~ s/r?1\.//g;    # cut 'r' and major

  my %contributors = ();

  # get most recent
  my (undef, $user, $rev) = $this->getRevisionInfo($web, $topic, $maxRev, $attachment, $maxRev);
  my $mostRecent = getWikiName($user);
  $contributors{$mostRecent} = 1;

  # get creator
  (undef, $user, $rev) = $this->getRevisionInfo($web, $topic, 1, $attachment, $maxRev);
  my $creator = getWikiName($user);
  $contributors{$creator} = 1;

  return ($mostRecent, $creator) if $Foswiki::cfg{SolrPlugin}{SimpleContributors};

  # only take the top 10; extracting revinfo takes too long otherwise :(
  $maxRev = 10 if $maxRev > 10;

  for (my $i = $maxRev; $i > 0; $i--) {
    (undef, $user, $rev) = $this->getRevisionInfo($web, $topic, $i, $attachment, $maxRev);
    my $wikiName = getWikiName($user);
    $contributors{$wikiName} = 1;
  }

  #if (PROFILE) {
  #  my $elapsed = int(Time::HiRes::tv_interval($t0) * 1000);
  #  $this->log("took $elapsed ms to get contributors of $web.$topic".($attachment?'.'.$attachment->{name}:''));
  #}

  delete $contributors{$mostRecent};
  delete $contributors{$creator};

  my @contributors = ($mostRecent, keys %contributors, $creator);
  return @contributors;
}

################################################################################
sub getWikiName {
  my $user = shift;

  my $wikiName = Foswiki::Func::getWikiName($user) || 'UnknownUser';
  $wikiName = 'UnknownUser' unless Foswiki::Func::isValidWikiWord($wikiName);    # weed out some strangers

  return $wikiName;
}

################################################################################
# wrapper around original getRevisionInfo which
# can't deal with dots in the webname
sub getRevisionInfo {
  my ($this, $web, $topic, $rev, $attachment, $maxRev) = @_;

  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  if (!defined($rev) || (defined($maxRev) && $rev == $maxRev)) {
    if ($attachment) {
      return ($attachment->{date}, $attachment->{author} || $attachment->{user}, $attachment->{version} || $maxRev);
    } else {
      my ($meta) = Foswiki::Func::readTopic($web, $topic); 
      my $topicInfo = $meta->get('TOPICINFO');
      return ($topicInfo->{date}, $topicInfo->{author}, $topicInfo->{version});
    }
  }

  # fall back to store means
  return Foswiki::Func::getRevisionInfo($web, $topic, $rev, $attachment);
}

################################################################################
# returns the list of users granted view access, or "all" if all users have got view access
sub getGrantedUsers {
  my ($this, $web, $topic, $meta, $type) = @_;

  $type //= 'VIEW';
  $type = uc($type);

  my %grantedUsers;
  my $forbiddenUsers;

  my $allow = $this->getACL($meta, 'ALLOWTOPIC'.$type);
  my $deny = $this->getACL($meta, 'DENYTOPIC'.$type);

  if (TRACE) {
    $this->log("called getGrantedUsers(web=$web, topic=$topic, type=$type)");
    $this->log("topicAllow=@$allow") if defined $allow;
    $this->log("topicDeny=@$deny") if defined $deny;
  }

  my $isDeprecatedEmptyDeny =
    !defined($Foswiki::cfg{AccessControlACL}{EnableDeprecatedEmptyDeny}) || $Foswiki::cfg{AccessControlACL}{EnableDeprecatedEmptyDeny};

  # Check DENYTOPIC
  if (defined $deny) {
    if (scalar(@$deny)) {
      if (grep {/^\*$/} @$deny) {
        $forbiddenUsers = [keys %{$this->getListOfUsers()}];
      } else {
        $forbiddenUsers = $this->expandUserList(@$deny);
      }
    } else {

      if ($isDeprecatedEmptyDeny) {
        $this->log("empty deny -> grant all access") if TRACE;

        # Empty deny
        return ['all'];
      } else {
        $deny = undef;
      }
    }
  }
  $this->log("(1) forbiddenUsers=@$forbiddenUsers") if TRACE && defined $forbiddenUsers;

  # Check ALLOWTOPIC
  if (defined($allow)) {
    if (scalar(@$allow)) {
      if (!$isDeprecatedEmptyDeny && grep {/^\*$/} @$allow) {
        $this->log("access * -> grant all access") if TRACE;

        # Empty deny
        return ['all'];
      } else {
      
        $grantedUsers{$_} = 1 foreach grep {!/^UnknownUser/} @{$this->expandUserList(@$allow)};
	$grantedUsers{$Foswiki::cfg{AdminUserWikiName}} = 1;

        if (defined $forbiddenUsers) {
          delete $grantedUsers{$_} foreach @$forbiddenUsers;
        }
        my @grantedUsers = keys %grantedUsers;

	$this->log("(2) granting access for ".scalar(@grantedUsers)." users: ".join(", ", sort @grantedUsers)) if TRACE;

        # A non-empty ALLOW is final
        return \@grantedUsers;
      }
    }
  }

  # use cache if possible (no topic-level perms set)
  if (!defined($deny) && exists $this->{_webACLCache}{$type}{$web}) {
    #$this->log("found in acl cache ".join(", ", sort @{$this->{_webACLCache}{$type}{$web}})) if TRACE;
    return $this->{_webACLCache}{$type}{$web};
  }

  my $webMeta = $meta->getContainer;
  my $webAllow = $this->getACL($webMeta, 'ALLOWWEB'.$type);
  my $webDeny = $this->getACL($webMeta, 'DENYWEB'.$type);

  if (TRACE) {
    $this->log("webAllow=@$webAllow") if defined $webAllow;
    $this->log("webDeny=@$webDeny") if defined $webDeny;
  }

  # Check DENYWEB, but only if DENYTOPIC is not set 
  if (!defined($deny) && defined($webDeny) && scalar(@$webDeny)) {
    push @{$forbiddenUsers}, @{$this->expandUserList(@$webDeny)};
  }
  $this->log("(2) forbiddenUsers=@$forbiddenUsers") if TRACE && defined $forbiddenUsers;

  if (defined($webAllow) && scalar(@$webAllow)) {
    if (grep {/^\*$/} @$webAllow) {
      %grantedUsers = %{$this->getListOfUsers()};
    } else {
      $grantedUsers{$_} = 1 foreach grep {!/^UnknownUser/} @{$this->expandUserList(@$webAllow)};
      $grantedUsers{$Foswiki::cfg{AdminUserWikiName}} = 1;
    }
  } elsif (!defined($deny) && !defined($webDeny)) {

    $this->log("no denies, no allows -> grant all access") if TRACE;

    # No denies, no allows -> open door policy
    $this->{_webACLCache}{$type}{$web} = ['all'];
    return ['all'];

  } else {
    %grantedUsers = %{$this->getListOfUsers()};
  }

  if (defined $forbiddenUsers) {
    delete $grantedUsers{$_} foreach @$forbiddenUsers;
  }

  # get list of users granted access that actually still exist
  foreach my $user (keys %grantedUsers) {
    $grantedUsers{$user}++ if defined $this->isKnownUser($user);
  }

  my @grantedUsers = ();
  foreach my $user (keys %grantedUsers) {
    push @grantedUsers, $user if $grantedUsers{$user} > 1;
  }

  $this->log("nr granted users=".scalar(@grantedUsers).", nr known users=".$this->nrKnownUsers) if TRACE;
  @grantedUsers = ('all') if scalar(@grantedUsers) == $this->nrKnownUsers;

  #$this->log("grantedUsers=@grantedUsers") if TRACE;

  # can't cache when there are topic-level perms 
  $this->{_webACLCache}{$type}{$web} = \@grantedUsers unless defined($deny);

  $this->log("(2) granting access for ".scalar(@grantedUsers)." users: ".join(", ", sort @grantedUsers)) if TRACE;

  return \@grantedUsers;
}

################################################################################
# SMELL: coppied from core; only works with topic-based ACLs
sub getACL {
  my ($this, $meta, $mode) = @_;

  if (defined $meta->{_topic} && !defined $meta->{_loadedRev}) {
    # Lazy load the latest version.
    $meta->loadVersion();
  }

  my $text = $meta->getPreference($mode);
  return unless defined $text;

  # Remove HTML tags (compatibility, inherited from Users.pm
  $text =~ s/(<[^>]*>)//g;

  # Dump the users web specifier if userweb
  my @list = grep { /\S/ } map { 
    my $tmp = $_;
    $tmp =~ s/^($Foswiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
    $tmp
  } split(/[,\s]+/, $text);

  #print STDERR "getACL($mode): ".join(', ', @list)."\n";

  return \@list;
}

################################################################################
sub expandUserList {
  my ($this, @users) = @_;

  my %result = ();

  foreach my $id (@users) {
    $id =~ s/(<[^>]*>)//g;
    $id =~ s/^($Foswiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
    next unless $id;

    if (Foswiki::Func::isGroup($id)) {
      $result{$_} = 1 foreach @{$this->_expandGroup($id)};
    } else {
      $result{getWikiName($id)} = 1;
    }
  }

  return [keys %result];
}

sub _expandGroup {
  my ($this, $group) = @_;

  return $this->{_groupCache}{$group} if exists $this->{_groupCache}{$group};

  my %result = ();

  my $it = Foswiki::Func::eachGroupMember($group);

  while ($it->hasNext) {
    my $id = $it->next;

    if (Foswiki::Func::isGroup($id)) {
      $result{$_} = 1 foreach @{$this->_expandGroup($id)};
    } else {
      $result{getWikiName($id)} = 1;
    }
  }

  $this->{_groupCache}{$group} = [keys %result];

  return [keys %result];
}

################################################################################
sub getAclFields {
  my $this = shift;

  my $viewUsers = $this->getGrantedUsers(@_, 'VIEW');
  my $editUsers = $this->getGrantedUsers(@_, 'CHANGE');

  my @fields = ();
  push @fields, ("access_granted" => $viewUsers) if $viewUsers;
  push @fields, ("edit_granted" => $editUsers) if $editUsers;

  return @fields;
}

################################################################################
sub mage {
  my $this = shift;

  unless ($this->{mage}) {
    require Image::Magick;
    $this->{mage} = Image::Magick->new();
  }

  return $this->{mage};
}

################################################################################
sub pingImage {
  my ($this, $path) = @_;

  #print STDERR "pinging $path\n";

  my ($width, $height, $filesize, $format) = $this->mage->Ping($path);
  $width ||= 0;
  $height ||= 0;

  return ($width, $height, $filesize, $format);
}

################################################################################
sub _getPathOfAttachment {
  my ($web, $topic, $attachment) = @_;

  my $pubDir = Foswiki::Func::getPubDir();

  $web =~ s/\./\//g;
  return "$pubDir/$web/$topic/$attachment";
}

1;
