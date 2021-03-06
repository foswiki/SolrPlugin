# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2019 Michael Daum http://michaeldaumconsulting.com
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
use Cache::FileCache ();
use Foswiki::Contrib::Stringifier ();
use Digest::MD5 ();
use Encode ();

use constant TRACE => 0;    # toggle me
use constant VERBOSE => 1;  # toggle me
use constant PROFILE => 0;  # toggle me
use constant MAX_STRING_LENGTH => 30000; 

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
    $this->log("ERROR: can't conect solr daemon");
  }

  # trap SIGINT
  $SIG{INT} = sub {
    $this->log("got interrupted ... finishing work");
    $this->{_trappedSignal} = 1; # will be detected by loops further down
  };

  # TODO: trap SIGALARM
  # let the indexer run for a maximum timespan, then flag a signal for it
  # to bail out from work done so far

  $this->{workArea} = Foswiki::Func::getWorkArea('SolrPlugin');

  return $this;
}

################################################################################
sub finish {
  my $this = shift;

  undef $this->{_knownUsers};
  undef $this->{_groupCache};
  undef $this->{_webACLCache};
}

################################################################################
# entry point to either update one topic or a complete web
sub index {
  my $this = shift;

  # exclusively lock the indexer to prevent a delta and a full index
  # mode to run in parallel

  try {

    my $query = Foswiki::Func::getRequestObject();
    my $web = $query->param('web') || 'all';
    my $topic = $query->param('topic');
    my $mode = $query->param('mode') || 'delta';
    my $optimize = Foswiki::Func::isTrue($query->param('optimize'));

    if ($topic) {
      $web = $this->{session}->{webName} if !$web || $web eq 'all';

      $this->log("doing a topic index $web.$topic") if TRACE;
      $this->updateTopic($web, $topic);
    } else {

      $this->log("doing a web index in $mode mode") if TRACE;
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

  # remove non-existing webs
  my @webs = $searcher->getListOfWebs();
  foreach my $thisWeb (@webs) {
    next if Foswiki::Func::webExists($thisWeb);
    $this->log("$thisWeb doesn't exist anymore ... deleting");
    $this->deleteWeb($thisWeb);
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

  # TODO: check the list of webs we had the last time we did a full index
  # of all webs; then possibly delete them

  foreach my $web (@webs) {

    my $origWeb = $web;
    $origWeb =~ s/\./\//g;
    $web =~ s/\//./g;

    if ($this->isSkippedWeb($web)) {
      #$this->log("Skipping web $web");
      next;
    }

    # remove all non-existing topics
    foreach my $topic ($searcher->getListOfTopics($web)) {
      next if Foswiki::Func::topicExists($web, $topic);
      $this->log("$web.$topic gone ... deleting");
      $this->deleteTopic($web, $topic);
    }

    my $found = 0;
    if ($mode eq 'full') {
      foreach my $topic (Foswiki::Func::getTopicList($web)) {
        $this->deleteTopic($web, $topic);
        next if $this->isSkippedTopic($web, $topic);
        $this->indexTopic($web, $topic);
        $found = 1;
        last if $this->{_trappedSignal};
      }
    } else {

      my %timeStamps = ();

      # get all timestamps for this web
      $searcher->iterate({
         q => "web:$web type:topic", 
         fl => "topic,timestamp", 
        },
        sub {
          my $doc = shift;
          my $topic = $doc->value_for("topic");
          my $time = $doc->value_for("timestamp");
          $time =~ s/\.\d+Z$/Z/g; # remove miliseconds as that's incompatible with perl
          $time = int(Foswiki::Time::parseTime($time));
          $timeStamps{$topic} = $time;
        }
      );

      # delta
      my @topics = Foswiki::Func::getTopicList($web);
      foreach my $topic (@topics) {
        next if $this->isSkippedTopic($web, $topic);

        my $changed;
        if ($Foswiki::Plugins::SESSION->can('getApproxRevTime')) {
          $changed = $this->{session}->getApproxRevTime($origWeb, $topic);
        } else {

          # This is here for old engines
          $changed = $this->{session}->{store}->getTopicLatestRevTime($origWeb, $topic);
        }

        my $topicTime = $timeStamps{$topic} || 0;
        next if $topicTime > $changed;

        $this->indexTopic($web, $topic);

        $found = 1;
        last if $this->{_trappedSignal};
      }
    }
    last if $this->{_trappedSignal};
  }
}

################################################################################
# update one specific topic; deletes the topic from the index before updating it again
sub updateTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  $this->deleteTopic($web, $topic);

  return if $this->isSkippedWeb($web);
  return if $this->isSkippedTopic($web, $topic);

  if (Foswiki::Func::topicExists($web, $topic)) {
    $this->indexTopic($web, $topic, $meta, $text);
  } else {
    $this->log("... topic $web.$topic does not exist") if TRACE;
  }
}

################################################################################
# work horse: index one topic and all attachments
sub indexTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  my %outgoingLinks = ();
  my %macros = ();

  my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

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
  $this->extractMacros($text, \%macros);
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
  my ($date, undef, $rev) = $this->getRevisionInfo($web, $topic);
  $date ||= 0;    # prevent formatTime to crap out
  $date = Foswiki::Func::formatTime($date, 'iso', 'gmtime');

  unless ($rev && $rev =~ /^\d+$/) {
    $rev //= 'undef';
    $this->log("WARNING: invalid version '$rev' of $web.$topic");
    $rev = 1;
  }

  # get create date
  my ($createDate) = $this->getRevisionInfo($web, $topic, 1);
  $createDate ||= 0;    # prevent formatTime to crap out
  $createDate = Foswiki::Func::formatTime($createDate, 'iso', 'gmtime');

  #print STDERR "createDate=$createDate\n";

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
    title => Foswiki::Func::getTopicTitle($web, $topic, $meta),
    text => $text,
    summary => $this->getTopicSummary($web, $topic, $meta, $origText),
    author => $author,
    author_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $author),
    date => $date,
    version => $rev,
    createauthor => $createAuthor,
    createauthor_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $createAuthor),
    createdate => $createDate,
    type => 'topic',
    container_id => $web . '.'. $Foswiki::cfg{HomeTopicName},
    container_web => $web,
    container_topic => $Foswiki::cfg{HomeTopicName},
    container_url => $this->getScriptUrlPath($web, $Foswiki::cfg{HomeTopicName}, "view"),
    container_title => Foswiki::Func::getTopicTitle($web, $Foswiki::cfg{HomeTopicName}),
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
  $this->log("... found macros ".join(", ", sort keys %macros)) if TRACE;

  # all prefs are of type _t
  # TODO it may pay off to detect floats and ints
  my @prefs = $meta->find('PREFERENCE');
  my $foundWorkflow = 0;
  if (@prefs) {
    foreach my $pref (@prefs) {
      my $name = $pref->{name};
      my $value = $pref->{value};
      $doc->add_fields(
        'preference_' . $name . '_s' => $value,
        'preference' => $name,
      );
      $foundWorkflow = 1 if $name eq 'WORKFLOW' and $value ne '';
    }
  }

  # add support for WorkflowPlugin 
  if ($foundWorkflow) {
    my $workflow = $meta->get('WORKFLOW');
    if ($workflow) {
      $doc->add_fields(
        state => $workflow->{name},
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

  my $t1 = [Time::HiRes::gettimeofday] if PROFILE;
  my @aclFields = $this->getAclFields($web, $topic, $meta);
  $doc->add_fields(@aclFields) if @aclFields;

  if (PROFILE) {
    my $elapsed = int(Time::HiRes::tv_interval($t1) * 1000);
    $this->log("took $elapsed ms to get the extra fields from $web.$topic");
    $t1 = [Time::HiRes::gettimeofday];
  }

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
      if ($name =~ /\.(png|jpe?g|gif|bmp|svg)$/i) {
        $firstImage = $name unless defined $firstImage;
      }

      # then index each of them
      $this->indexAttachment($web, $topic, $attachment, \@aclFields);
    }

    # take the first image attachment when no thumbnail was specified explicitly
    $thumbnail = $firstImage if !defined($thumbnail) && defined($firstImage);
    $doc->add_fields('thumbnail' => $thumbnail) if defined $thumbnail;
  }

  if (PROFILE) {
    my $elapsed = int(Time::HiRes::tv_interval($t1) * 1000);
    $this->log("took $elapsed ms to index all attachments at $web.$topic");
    $t1 = [Time::HiRes::gettimeofday];
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
    $t0 = [Time::HiRes::gettimeofday];
  }

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
  my $isUserProfile = ($formName =~ /$personDataFormPattern/x) ? 1 : 0;

  my %seenFields = ();
  my $formFields = $formDef->getFields();
  if ($formFields) {
    my $foundTopicType = 0;
    foreach my $fieldDef (@{$formFields}) {
      my $name = $fieldDef->{name};
      my $field = $meta->get('FIELD', $name);

      next if !defined($field) || ($isUserProfile && $name eq 'Email');

      $foundTopicType = 1 if $name eq 'TopicType';

      # prevent from mall-formed formDefinitions
      if ($seenFields{$name}) {
        $this->log("WARNING: malformed form definition for $web.$formName - field $name appear twice must be unique");
        next;
      }
      $seenFields{$name} = 1;

      # special handling for user profile's email: get it from the user mapper in case there is none in the form
      if ($name eq 'Email' && $isUserProfile && !$field->{value}) {
        my @emails = Foswiki::Func::wikinameToEmails($topic);
        $field->{value} = $emails[0] if @emails;
      }

      $this->indexFormField($web, $topic, $fieldDef, $field->{value}, $doc, $outgoingLinks, $macros);
    }

    # map form name to TopicType if not found otherwise
    unless ($foundTopicType) {
      my $topicType = $formName;
      $topicType =~ s/^.*\.(.*?)$/$1/;
      $doc->add_fields('field_TopicType_lst' => $topicType,);
    }
  }
}

################################################################################
# index a single formfield of a topic
sub indexFormField {
  my ($this, $web, $topic, $fieldDef, $value, $doc, $outgoingLinks, $macros) = @_;

  my $name = $fieldDef->{name};
  my $type = $fieldDef->{type};

  unless ($type) {
    $this->log("WARNING: unknown type for formfield '$name' at $web.$topic");
    return;
  }

  my $isMultiValued = $fieldDef->isMultiValued;
  my $isValueMapped = $fieldDef->can("isValueMapped") && $fieldDef->isValueMapped;

  if ($isValueMapped) {

    # get mapped value
    if ($fieldDef->can('getDisplayValue')) {
      $value = $fieldDef->getDisplayValue($value);
    } else {

      # backwards compatibility
      $fieldDef->getOptions();    # load value map
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
  $this->extractMacros($value, $macros);

  # bit of cleanup
  $value =~ s/<!--.*?-->//gs;

  # create a dynamic field indicating the field type to solr

  # date
  if ($type =~ /^date/) {
    try {
      my $epoch = $value;
      $epoch = Foswiki::Time::parseTime($value) unless $epoch =~ /^\-?\d+$/;

      # only index dates that properly parse into epoch
      if ($epoch) { 
        $value = Foswiki::Time::formatTime($epoch, 'iso', 'gmtime');
        $doc->add_fields('field_' . $name . '_dt' => $value,);
      }
    }
    catch Error::Simple with {
      $this->log("WARNING: malformed date value '$value'");
    };
  }

  # multi-valued types
  elsif ($isMultiValued || $name =~ /TopicType/ || $type eq 'radio') {    # TODO: make this configurable
    my $fieldName = 'field_' . $name;
    $fieldName =~ s/(_(?:i|s|l|t|b|f|dt|lst))$//;

    $doc->add_fields($fieldName . '_lst' => [split(/\s*,\s*/, $value)]);
  }

  # finally make it a non-list field as well
  {
    my $fieldName = 'field_' . $name;
    my $fieldType = '_s';

    # is there an explicit type info part of the formfield name?
    if ($fieldName =~ s/(_(?:i|s|l|t|b|f|dt|lst))$//) {
      $fieldType = $1;
    }

    # add an extra check for floats
    if ($fieldType eq '_f') {
      if ($value =~ /^\s*([\-\+]?\d+(\.\d+)?)\s*$/) {
        $value = $1;
      } else {
        $this->log("WARNING: malformed float value '$value' in field $fieldName");
        return;
      }
    }

    # add an extra treatment for booleans
    elsif ($fieldType eq '_b') {
      $value = Foswiki::Func::isTrue($value, 0);
    }

    # for explicit _s fields apply a full plainify
    elsif ($fieldType eq '_s') {

      # note this might alter the content too much in some cases.
      # so we try to remove only those characters that break the json parser
      #$value = $this->plainify($value, $web, $topic);
      $value =~ s/<!--.*?-->//gs;    # remove all HTML comments
      $value =~ s/<[^>]*>/ /g;       # remove all HTML tags
      $value = $this->discardIllegalChars($value);    # remove illegal characters
    }

    # truncate field value to MAX_STRING_LENGTH
    if (length($value) > MAX_STRING_LENGTH) {
      $this->log("WARNING: value of field '$name' exceeds maximum string length ... shortening");
      $value = substr($value, 0, MAX_STRING_LENGTH);
    }

    $doc->add_fields($fieldName . $fieldType => $value) if defined $value && $value ne '';
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

  return unless $text;

  sub _process {
    my ($macro, $params) = @_;

    my $remain = "";

    $macros->{$macro} = 1 if defined $macro;

    my %attrs = Foswiki::Func::extractParameters($params);
    foreach my $val (values %attrs) {
      $val = Foswiki::Func::decodeFormatTokens($val);
      $this->extractMacros($val, $macros);
    }

    $remain = $attrs{_DEFAULT} if $macro =~ /TRANSLATE|MAKETEXT/;

    return $remain;
  }

  while ($text =~ s/(?:%|\$perce?nt)($Foswiki::regex{tagNameRegex})(?:\{(.*?)\})?(?:%|\$perce?nt)/_process($1, $2)/ges) {
    # nop
  };
}

################################################################################
sub extractOutgoingLinks {
  my ($this, $web, $topic, $text, $outgoingLinks) = @_;

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
  if ($name =~ /^(.+)\.(\w+?)$/) {
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
  push @types, $extension if $extension;
  push @types, $mappedType if $mappedType && $mappedType ne $extension;

  my $attText = '';
  $attText = $this->getStringifiedVersion($web, $topic, $name);
  if ($attText ne '') {
    $attText = $this->plainify($attText, $web, $topic);
  } else {
    #$this->log("WARNING: attachment $name at $web.$topic has got zero length ... maybe stringifier failed?")
  }

  my $doc = $this->newDocument();

  my $comment = $attachment->{'comment'} || '';
  my $size = $attachment->{'size'} || 0;
  my $date = $attachment->{'date'} || 0;
  $date = Foswiki::Func::formatTime($date, 'iso', 'gmtime');
  my $rev = $attachment->{'version'} || 1;
  my $author = getWikiName($attachment->{user});

  unless ($rev =~ /^\d+$/) {
    $this->log("WARNING: invalid version '$rev' of attachment $name in $web.$topic");
    $rev = 1;
  }

  # get summary
  my $summary = "";#substr($attText, 0, 300);

  # get image info
  if ($name =~ /\.(png|jpe?g|gif|bmp|svg)$/i) {
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
  my ($createDate) = $this->getRevisionInfo($web, $topic, 1, $attachment);
  $createDate ||= 0;    # prevent formatTime to crap out
  $createDate = Foswiki::Func::formatTime($createDate, 'iso', 'gmtime');

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

  $doc->add_fields(
    # common fields
    id => $id,
    url => $Foswiki::cfg{PubUrlPath}.'/'.$webDir.'/'.$topic.'/'.$name,
    web => $web,
    webcat => [@webCats],
    topic => $topic,
    webtopic => "$web.$topic",
    title => $title,
    type => \@types,
    text => $attText,
    summary => $summary,
    author => $author,
    author_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $author),
    date => $date,
    version => $rev,
    createauthor => $createAuthor,
    createauthor_title => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $createAuthor),
    createdate => $createDate,

    # attachment fields
    name => $name,
    comment => $comment,
    size => $size,
    icon => $this->mapToIconFileName($extension),
    container_id => $web . '.' . $topic,
    container_web => $web,
    container_topic => $topic,
    container_url => $this->getScriptUrlPath($web, $topic, "view"),
    container_title => Foswiki::Func::getTopicTitle($web, $topic),
  );

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
# add a document to the index
sub add {
  my ($this, $doc) = @_;

  #my ($package, $file, $line) = caller;
  #print STDERR "called add from $package:$line\n";

  return unless $this->{solr};
  return $this->{solr}->add($doc);
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
sub newDocument {

  #my $this = shift;

  return WebService::Solr::Document->new;
}

################################################################################
sub deleteTopic {
  my ($this, $web, $topic) = @_;

  $this->deleteByQuery("web:\"$web\" topic:\"$topic\"");
}

################################################################################
sub deleteWeb {
  my ($this, $web) = @_;

  $web =~ s/\//./g;
  $this->deleteByQuery("web:\"$web\"");
}

################################################################################
sub deleteByQuery {
  my ($this, $query) = @_;

  return unless $query;

  #$this->log("Deleting documents by query $query") if VERBOSE;

  my $success;
  try {
    $success = $this->{solr}->delete_by_query($query);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

  return $success;
}

################################################################################
sub deleteDocument {
  my ($this, $web, $topic, $attachment) = @_;

  $web =~ s/\//\./g;
  my $id = "$web.$topic";
  $id .= ".$attachment" if $attachment;

  #$this->log("Deleting document $id");

  try {
    $this->{solr}->delete_by_id($id);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

}


################################################################################
sub cache {
  my $this = shift;

  unless ($this->{cache}) {
    $this->{cache} = new Cache::FileCache({
        'cache_root' => $this->{workArea}.'/stringifier_cache',
        'default_expires_in' => '7 d',
        'directory_umask' => 077,
      }
    );
  }

  return $this->{cache};
}

sub _getPathOfAttachment {
  my ($web, $topic, $attachment) = @_;

  my $pubDir = Foswiki::Func::getPubDir();

  $web =~ s/\./\//g;
  return "$pubDir/$web/$topic/$attachment";
}

################################################################################
sub getStringifiedVersion {
  my ($this, $web, $topic, $attachment) = @_;

  my $filename = _getPathOfAttachment($web, $topic, $attachment);

  $web =~ s/\//\./g;

  # untaint..
  $filename =~ /(.*)/;
  $filename = $1;

#  unless (-e $filename) {
#    $this->log("WARNING: can't find file $filename");
#    return "";
#  }

  #$this->log("get stringified version of $filename") if VERBOSE;

  my $attText = Foswiki::Contrib::Stringifier->stringFor($filename) || '';
  my $fileDate = modificationTime($filename);

  # prevent wide char in subroutine
  my $encFileName = $Foswiki::UNICODE?Encode::encode_utf8($filename):$filename;

  my $key = Digest::MD5::md5_base64($encFileName);
  my $cacheDate = 0;
  my $obj = $this->cache->get_object($key);
  $cacheDate = $obj->get_created_at() if $obj;

  if ($fileDate > $cacheDate) {
    #$this->log("caching stringified version of $attachment");
    $attText = Foswiki::Contrib::Stringifier->stringFor($filename) || '';
    $this->cache->set($key, $attText);
  } else {
    #$this->log("found stringified version of $attachment in cache");
    $attText = $this->cache->get($key) || '';
  }

  # only cache the first 10MB at most, TODO: make size configurable
  if (length($attText) > 1014*1000*10) { 
    $this->log("WARNING: ignoring attachment $attachment at $web.$topic larger than 10MB");
    $attText = '';
  }

  return $attText;
}

################################################################################
sub modificationTime {
  my $filename = shift;

  my @stat = stat($filename);
  return $stat[9] || $stat[10] || 0;
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

  # only take the top 10; extracting revinfo takes too long otherwise :(
  $maxRev = 10 if $maxRev > 10;

  for (my $i = $maxRev; $i > 0; $i--) {
    my (undef, $user, $rev) = $this->getRevisionInfo($web, $topic, $i, $attachment, $maxRev);
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
  my ($this, $web, $topic, $meta, $text) = @_;

  my %grantedUsers;
  my $forbiddenUsers;

  my $allow = $this->getACL($meta, 'ALLOWTOPICVIEW');
  my $deny = $this->getACL($meta, 'DENYTOPICVIEW');

  if (TRACE) {
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

        if (defined $forbiddenUsers) {
          delete $grantedUsers{$_} foreach @$forbiddenUsers;
        }
        my @grantedUsers = keys %grantedUsers;

        $this->log("(1) granting access for @grantedUsers") if TRACE;

        # A non-empty ALLOW is final
        return \@grantedUsers;
      }
    }
  }

  # use cache if possible (no topic-level perms set)
  if (!defined($deny) && exists $this->{_webACLCache}{$web}) {
    #$this->log("found in acl cache ".join(", ", sort @{$this->{_webACLCache}{$web}})) if TRACE;
    return $this->{_webACLCache}{$web};
  }

  my $webMeta = $meta->getContainer;
  my $webAllow = $this->getACL($webMeta, 'ALLOWWEBVIEW');
  my $webDeny = $this->getACL($webMeta, 'DENYWEBVIEW');

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
    }
  } elsif (!defined($deny) && !defined($webDeny)) {

    $this->log("no denies, no allows -> grant all access") if TRACE;

    # No denies, no allows -> open door policy
    $this->{_webACLCache}{$web} = ['all'];
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
  $this->{_webACLCache}{$web} = \@grantedUsers unless defined($deny);

  $this->log("(2) granting access for ".scalar(@grantedUsers)." users") if TRACE;

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
    s/^($Foswiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
    $_
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
sub getField {
  my ($this, $doc, $name) = @_;

  foreach my $field ($doc->fields) {
    if ($field->name eq $name) {
      return $field;
    }
  }

  return;
}

################################################################################
sub getAclFields {
  my $this = shift;

  my $grantedUsers = $this->getGrantedUsers(@_);
  return () unless $grantedUsers;
  return ('access_granted' => $grantedUsers);
}

################################################################################
sub mage {
  my $this = shift;

  unless ($this->{mage}) {

    my $impl =
         $Foswiki::cfg{ImagePlugin}{Impl}
      || $Foswiki::cfg{ImageGalleryPlugin}{Impl}
      || 'Image::Magick';

    eval "require $impl";
    die $@ if $@;
    $this->{mage} = $impl->new();
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

1;

